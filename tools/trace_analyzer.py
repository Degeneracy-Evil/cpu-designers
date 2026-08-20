#!/usr/bin/env python3
"""Trace log analyzer for RISC-V CPU simulation debug.

Parses instruction trace logs, compares with Spike ISA simulator,
locates failure points, and generates statistics.

Usage:
    python -m tools.trace_analyzer parse instr_trace.log
    python -m tools.trace_analyzer diff instr_trace.log spike_commit.log
    python -m tools.trace_analyzer find-fail instr_trace.log
    python -m tools.trace_analyzer stats instr_trace.log
"""
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class TraceEntry:
    cycle: int
    time: str
    pc: int
    inst: int
    event: str
    rd: str
    rd_val: str

    @property
    def rd_num(self) -> int | None:
        if self.rd == "---":
            return None
        val = self.rd.lstrip("x")
        try:
            return int(val)
        except ValueError:
            return None

    @property
    def rd_val_int(self) -> int | None:
        if self.rd_val == "--------":
            return None
        return int(self.rd_val, 16)


@dataclass
class SpikeEntry:
    priv: int
    pc: int
    inst: int
    rd: str
    rd_val: str


@dataclass
class ParseResult:
    entries: list[TraceEntry] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)


def parse_trace_log(path: str | Path) -> ParseResult:
    result = ParseResult()
    p = Path(path)
    if not p.exists():
        result.errors.append(f"File not found: {path}")
        return result

    with p.open("r", encoding="utf-8", errors="replace") as f:
        for line_no, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 7:
                result.errors.append(f"L{line_no}: malformed line ({len(parts)} fields): {line}")
                continue
            try:
                entry = TraceEntry(
                    cycle=int(parts[0]),
                    time=parts[1],
                    pc=int(parts[2], 16),
                    inst=int(parts[3], 16),
                    event=parts[4].strip(),
                    rd=parts[5].strip(),
                    rd_val=parts[6].strip(),
                )
                result.entries.append(entry)
            except (ValueError, IndexError):
                result.errors.append(f"L{line_no}: parse error: {line}")

    return result


def parse_spike_log(path: str | Path) -> list[SpikeEntry]:
    entries: list[SpikeEntry] = []
    p = Path(path)
    if not p.exists():
        print(f"ERROR: File not found: {path}", file=sys.stderr)
        return entries

    pattern = re.compile(
        r"(\d+)\s+0x([0-9a-fA-F]+)\s+\(0x([0-9a-fA-F]+)\)"
        r"(?:\s+(x\d+)\s+0x([0-9a-fA-F]+))?"
    )

    with p.open("r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            m = pattern.match(line)
            if m:
                entries.append(SpikeEntry(
                    priv=int(m.group(1)),
                    pc=int(m.group(2), 16),
                    inst=int(m.group(3), 16),
                    rd=m.group(4) or "---",
                    rd_val=m.group(5) or "--------",
                ))

    return entries


def cmd_parse(args: argparse.Namespace) -> int:
    result = parse_trace_log(args.log_file)
    if result.errors:
        print(f"Parse errors: {len(result.errors)}")
        for e in result.errors[:10]:
            print(f"  {e}")
        if len(result.errors) > 10:
            print(f"  ... and {len(result.errors) - 10} more")

    print(f"Entries: {len(result.entries)}")
    if args.limit:
        for e in result.entries[:args.limit]:
            print(f"  #{e.cycle:6d}  t={e.time:>10s}  PC=0x{e.pc:08x}  INST=0x{e.inst:08x}  {e.event}  {e.rd}={e.rd_val}")
    elif args.pc:
        target_pc = int(args.pc, 16)
        for e in result.entries:
            if e.pc == target_pc:
                print(f"  #{e.cycle:6d}  t={e.time:>10s}  PC=0x{e.pc:08x}  INST=0x{e.inst:08x}  {e.event}  {e.rd}={e.rd_val}")
    elif args.cycle_range:
        lo, hi = map(int, args.cycle_range.split(":"))
        for e in result.entries:
            if lo <= e.cycle <= hi:
                print(f"  #{e.cycle:6d}  t={e.time:>10s}  PC=0x{e.pc:08x}  INST=0x{e.inst:08x}  {e.event}  {e.rd}={e.rd_val}")
    else:
        for e in result.entries[:20]:
            print(f"  #{e.cycle:6d}  t={e.time:>10s}  PC=0x{e.pc:08x}  INST=0x{e.inst:08x}  {e.event}  {e.rd}={e.rd_val}")
        if len(result.entries) > 20:
            print(f"  ... ({len(result.entries) - 20} more entries)")

    return 0


def cmd_diff(args: argparse.Namespace) -> int:
    trace = parse_trace_log(args.trace_log)
    spike = parse_spike_log(args.spike_log)

    if not trace.entries:
        print("ERROR: No trace entries found", file=sys.stderr)
        return 1
    if not spike:
        print("ERROR: No Spike entries found", file=sys.stderr)
        return 1

    mismatches = 0
    max_compare = min(len(trace.entries), len(spike))
    first_mismatch = None

    for i in range(max_compare):
        t = trace.entries[i]
        s = spike[i]
        pc_match = t.pc == s.pc
        inst_match = t.inst == s.inst

        rd_match = True
        if s.rd != "---" and t.rd != "---":
            if t.rd_num is not None and s.rd.startswith("x"):
                spike_rd_num = int(s.rd[1:])
                if t.rd_num != spike_rd_num:
                    rd_match = False
                elif t.rd_val_int is not None and s.rd_val != "--------":
                    spike_val = int(s.rd_val, 16)
                    if t.rd_val_int != spike_val:
                        rd_match = False

        if not (pc_match and inst_match and rd_match):
            mismatches += 1
            if first_mismatch is None:
                first_mismatch = i
            if mismatches <= 10:
                print(f"MISMATCH #{i}:")
                print(f"  Trace: PC=0x{t.pc:08x} INST=0x{t.inst:08x} {t.rd}={t.rd_val}")
                print(f"  Spike: PC=0x{s.pc:08x} INST=0x{s.inst:08x} {s.rd}={s.rd_val}")

    if mismatches == 0:
        print(f"OK: {max_compare} instructions match perfectly")
    else:
        print(f"FAIL: {mismatches}/{max_compare} mismatches (first at instruction #{first_mismatch})")

    return 1 if mismatches else 0


def cmd_find_fail(args: argparse.Namespace) -> int:
    result = parse_trace_log(args.log_file)
    if not result.entries:
        print("ERROR: No trace entries found", file=sys.stderr)
        return 1

    issues: list[str] = []
    prev_pc = 0

    for i, e in enumerate(result.entries):
        if e.event == "BR":
            continue
        if i > 0 and e.pc != prev_pc + 4 and e.event not in ("BR", "TR", "MR"):
            issues.append(
                f"#{e.cycle}: PC gap 0x{prev_pc:08x} -> 0x{e.pc:08x} (expected 0x{prev_pc + 4:08x})"
            )

        prev_pc = e.pc

    if not issues:
        print(f"OK: No PC discontinuities in {len(result.entries)} instructions")
        return 0

    print(f"Found {len(issues)} potential issues:")
    for issue in issues[:20]:
        print(f"  {issue}")
    if len(issues) > 20:
        print(f"  ... ({len(issues) - 20} more)")

    return 1


def cmd_stats(args: argparse.Namespace) -> int:
    result = parse_trace_log(args.log_file)
    if not result.entries:
        print("ERROR: No trace entries found", file=sys.stderr)
        return 1

    total = len(result.entries)
    branches = sum(1 for e in result.entries if e.event == "BR")
    traps = sum(1 for e in result.entries if e.event == "TR")
    mrets = sum(1 for e in result.entries if e.event == "MR")
    normal = total - branches - traps - mrets
    reg_writes = sum(1 for e in result.entries if e.rd != "---")

    pcs = [e.pc for e in result.entries]
    unique_pcs = len(set(pcs))

    print(f"Total instructions:  {total}")
    print(f"  Normal:            {normal} ({normal * 100 / total:.1f}%)")
    print(f"  Branches:          {branches} ({branches * 100 / total:.1f}%)")
    print(f"  Traps:             {traps} ({traps * 100 / total:.1f}%)")
    print(f"  MRET:              {mrets} ({mrets * 100 / total:.1f}%)")
    print(f"  Register writes:   {reg_writes}")
    print(f"  Unique PCs:        {unique_pcs}")
    print(f"  PC range:          0x{min(pcs):08x} - 0x{max(pcs):08x}")
    print(f"  Cycle range:       1 - {result.entries[-1].cycle}")

    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="trace_analyzer",
        description="RISC-V CPU simulation trace log analyzer",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # parse
    p_parse = sub.add_parser("parse", help="Parse and display trace log entries")
    p_parse.add_argument("log_file", help="Path to instr_trace.log")
    p_parse.add_argument("--limit", type=int, help="Max entries to display")
    p_parse.add_argument("--pc", metavar="HEX", help="Filter by PC (hex)")
    p_parse.add_argument("--cycle-range", metavar="LO:HI", help="Filter by cycle range")

    # diff
    p_diff = sub.add_parser("diff", help="Compare trace log with Spike commit log")
    p_diff.add_argument("trace_log", help="Path to instr_trace.log")
    p_diff.add_argument("spike_log", help="Path to spike_commit.log")

    # find-fail
    p_fail = sub.add_parser("find-fail", help="Locate PC discontinuities (potential failures)")
    p_fail.add_argument("log_file", help="Path to instr_trace.log")

    # stats
    p_stats = sub.add_parser("stats", help="Generate trace statistics")
    p_stats.add_argument("log_file", help="Path to instr_trace.log")

    args = parser.parse_args(argv)

    if args.command == "parse":
        return cmd_parse(args)
    elif args.command == "diff":
        return cmd_diff(args)
    elif args.command == "find-fail":
        return cmd_find_fail(args)
    elif args.command == "stats":
        return cmd_stats(args)
    else:
        parser.print_help()
        return 1


if __name__ == "__main__":
    sys.exit(main())
