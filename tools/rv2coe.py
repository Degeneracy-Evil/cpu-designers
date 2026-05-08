#!/usr/bin/env python3
"""Compile RISC-V ASM/C source into Xilinx COE instruction/data images.

Default target matches this repository's embedded CPU project:
- ISA: rv32i_zicsr_zifencei
- ABI: ilp32
- COE format: memory_initialization_radix=16 + 32-bit words

Supports separate instruction (.text) and data (.data/.rodata) output
for Harvard-architecture CPUs with split instruction/data memories.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Dict, FrozenSet, List, Sequence

_RV32I_BASE: FrozenSet[str] = frozenset({
    "add",
    "sub",
    "sll",
    "slt",
    "sltu",
    "xor",
    "srl",
    "sra",
    "or",
    "and",
    "addi",
    "slti",
    "sltiu",
    "xori",
    "ori",
    "andi",
    "slli",
    "srli",
    "srai",
    "lb",
    "lh",
    "lw",
    "lbu",
    "lhu",
    "sb",
    "sh",
    "sw",
    "beq",
    "bne",
    "blt",
    "bge",
    "bltu",
    "bgeu",
    "jal",
    "jalr",
    "lui",
    "auipc",
    "ecall",
    "ebreak",
    "fence",
})

_RV32I_ZICSR: FrozenSet[str] = _RV32I_BASE | frozenset({
    "csrrw",
    "csrrs",
    "csrrc",
    "csrrwi",
    "csrrsi",
    "csrrci",
    "mret",
    "sret",
})

_RV32I_ZIFENCEI: FrozenSet[str] = _RV32I_ZICSR | frozenset({"fence.i"})

_RV32IM_EXT: FrozenSet[str] = frozenset({
    "mul",
    "mulh",
    "mulhsu",
    "mulhu",
    "div",
    "divu",
    "rem",
    "remu",
})

_RV32IA_EXT: FrozenSet[str] = frozenset({
    "lr.w",
    "sc.w",
    "amoswap.w",
    "amoadd.w",
    "amoxor.w",
    "amoand.w",
    "amoor.w",
    "amomin.w",
    "amomax.w",
    "amominu.w",
    "amomaxu.w",
})

_RV32IC_EXT: FrozenSet[str] = frozenset({
    "c.ebreak",
    "c.jr",
    "c.jalr",
    "c.j",
    "c.jal",
    "c.beqz",
    "c.bnez",
    "c.li",
    "c.lui",
    "c.addi",
    "c.addi16sp",
    "c.addi4spn",
    "c.slli",
    "c.srli",
    "c.srai",
    "c.andi",
    "c.mv",
    "c.add",
    "c.sub",
    "c.xor",
    "c.or",
    "c.and",
    "c.lw",
    "c.sw",
    "c.lwsp",
    "c.swsp",
    "c.nop",
})

_RV32IF_EXT: FrozenSet[str] = frozenset({
    "flw",
    "fsw",
    "fmadd.s",
    "fmsub.s",
    "fnmsub.s",
    "fnmadd.s",
    "fadd.s",
    "fsub.s",
    "fmul.s",
    "fdiv.s",
    "fsqrt.s",
    "fsgnj.s",
    "fsgnjn.s",
    "fsgnjx.s",
    "fmin.s",
    "fmax.s",
    "fcvt.w.s",
    "fcvt.wu.s",
    "fmv.x.w",
    "feq.s",
    "flt.s",
    "fle.s",
    "fclass.s",
    "fcvt.s.w",
    "fcvt.s.wu",
    "fmv.w.x",
})

ISA_PROFILES: Dict[str, FrozenSet[str]] = {
    "rv32i": _RV32I_BASE,
    "rv32i_zicsr": _RV32I_ZICSR,
    "rv32i_zicsr_zifencei": _RV32I_ZIFENCEI,
    "rv32im": _RV32I_BASE | _RV32IM_EXT,
    "rv32im_zicsr": _RV32I_ZICSR | _RV32IM_EXT,
    "rv32im_zicsr_zifencei": _RV32I_ZIFENCEI | _RV32IM_EXT,
    "rv32imc": _RV32I_BASE | _RV32IM_EXT | _RV32IC_EXT,
    "rv32imc_zicsr": _RV32I_ZICSR | _RV32IM_EXT | _RV32IC_EXT,
    "rv32imc_zicsr_zifencei": _RV32I_ZIFENCEI | _RV32IM_EXT | _RV32IC_EXT,
    "rv32imac": _RV32I_BASE | _RV32IM_EXT | _RV32IA_EXT | _RV32IC_EXT,
    "rv32imac_zicsr": _RV32I_ZICSR | _RV32IM_EXT | _RV32IA_EXT | _RV32IC_EXT,
    "rv32imac_zicsr_zifencei": _RV32I_ZIFENCEI | _RV32IM_EXT | _RV32IA_EXT | _RV32IC_EXT,
    "rv32if": _RV32I_BASE | _RV32IF_EXT,
    "rv32if_zicsr": _RV32I_ZICSR | _RV32IF_EXT,
    "rv32if_zicsr_zifencei": _RV32I_ZIFENCEI | _RV32IF_EXT,
    "rv32imaf": _RV32I_BASE | _RV32IM_EXT | _RV32IF_EXT,
    "rv32imaf_zicsr": _RV32I_ZICSR | _RV32IM_EXT | _RV32IF_EXT,
    "rv32imaf_zicsr_zifencei": _RV32I_ZIFENCEI | _RV32IM_EXT | _RV32IF_EXT,
}

DEFAULT_MARCH = "rv32im_zicsr_zifencei"


def resolve_isa_profile(march: str) -> FrozenSet[str] | None:
    normalized = march.lower().replace("_", "_")
    if normalized in ISA_PROFILES:
        return ISA_PROFILES[normalized]
    base = normalized.split("_")[0]
    if base in ISA_PROFILES:
        return ISA_PROFILES[base]
    return None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compile RISC-V ASM/C into COE/hex/bin for instruction/data memories.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("-i", "--input", required=True, help="Input source file (.S/.s/.asm/.c)")
    parser.add_argument("-o", "--output", default="", help="Output .coe file (unified .text)")
    parser.add_argument(
        "--lang",
        choices=["auto", "asm", "c"],
        default="auto",
        help="Input language",
    )
    parser.add_argument("--entry", default="_start", help="Link entry symbol")
    parser.add_argument(
        "--march",
        default=DEFAULT_MARCH,
        help="-march passed to GCC and ISA check profile (e.g. rv32i, rv32im_zicsr_zifencei, rv32imc)",
    )
    parser.add_argument("--abi", default="ilp32", help="-mabi passed to GCC")
    parser.add_argument("--gcc", default="riscv64-unknown-elf-gcc", help="RISC-V GCC executable")
    parser.add_argument("--objcopy", default="riscv64-unknown-elf-objcopy", help="RISC-V objcopy executable")
    parser.add_argument("--objdump", default="riscv64-unknown-elf-objdump", help="RISC-V objdump executable")
    check_group = parser.add_mutually_exclusive_group()
    check_group.add_argument(
        "--check-isa",
        dest="check_isa",
        action="store_true",
        help="Check instructions against ISA profile derived from --march",
    )
    check_group.add_argument(
        "--no-check-isa",
        dest="check_isa",
        action="store_false",
        help="Skip ISA whitelist check",
    )
    parser.set_defaults(check_isa=True)
    parser.add_argument(
        "--depth",
        type=int,
        default=0,
        help="Pad instruction words to fixed depth (0 means no padding)",
    )
    parser.add_argument(
        "--data-depth",
        type=int,
        default=0,
        help="Pad data words to fixed depth (0 means no padding)",
    )
    parser.add_argument(
        "--hex",
        default="",
        help="Also output a plain hex file for $readmemh (one word per line)",
    )
    sep_group = parser.add_argument_group("separate inst/data output", "For Harvard-architecture CPUs with split memories")
    sep_group.add_argument("--inst-coe", default="", help="Instruction COE file (.text section only)")
    sep_group.add_argument("--inst-hex", default="", help="Instruction hex file for $readmemh")
    sep_group.add_argument("--inst-bin", default="", help="Instruction raw binary file (.inst.bin)")
    sep_group.add_argument("--data-coe", default="", help="Data COE file (.data+.rodata sections)")
    sep_group.add_argument("--data-hex", default="", help="Data hex file for $readmemh")
    sep_group.add_argument("--data-bin", default="", help="Data raw binary file (.data.bin)")
    parser.add_argument("--keep-temp", action="store_true", help="Keep intermediate files")
    parser.add_argument("-v", "--verbose", action="store_true", help="Print full tool commands")
    return parser.parse_args()


def detect_lang(input_path: Path, lang_arg: str) -> str:
    if lang_arg != "auto":
        return lang_arg

    suffix = input_path.suffix.lower()
    if suffix == ".c":
        return "c"
    if suffix in {".s", ".asm"} or input_path.suffix == ".S":
        return "asm"
    return "asm"


def ensure_tool(tool_name: str) -> None:
    if shutil.which(tool_name) is None:
        raise RuntimeError(f"Required tool not found in PATH: {tool_name}")


def run_cmd(cmd: Sequence[str], verbose: bool) -> str:
    if verbose:
        print("[CMD ]", " ".join(cmd))
    proc = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if proc.returncode != 0:
        out = proc.stdout.rstrip()
        if out:
            raise RuntimeError(f"Command failed ({proc.returncode}): {' '.join(cmd)}\n{out}")
        raise RuntimeError(f"Command failed ({proc.returncode}): {' '.join(cmd)}")
    return proc.stdout


def compile_to_elf(
    args: argparse.Namespace,
    src_path: Path,
    src_kind: str,
    elf_path: Path,
) -> None:
    cmd: List[str] = [
        args.gcc,
        f"-march={args.march}",
        f"-mabi={args.abi}",
        "-nostdlib",
        "-nostartfiles",
        "-Wl,-Ttext=0x0",
        "-Wl,--no-relax",
        "-Wl,--build-id=none",
        f"-Wl,-e,{args.entry}",
    ]

    if src_kind == "asm":
        cmd.extend(["-x", "assembler-with-cpp"])
    else:
        cmd.extend(
            [
                "-x",
                "c",
                "-ffreestanding",
                "-fno-builtin",
                "-fno-stack-protector",
                "-fno-pic",
                "-fno-pie",
                "-fno-unwind-tables",
                "-fno-asynchronous-unwind-tables",
            ]
        )

    cmd.extend([str(src_path), "-o", str(elf_path)])
    run_cmd(cmd, args.verbose)


def check_isa_whitelist(args: argparse.Namespace, elf_path: Path) -> None:
    allowed = resolve_isa_profile(args.march)
    if allowed is None:
        print(
            f"[WARN] No ISA profile for --march={args.march}, skipping check. "
            f"Available: {', '.join(sorted(ISA_PROFILES.keys()))}",
            file=sys.stderr,
        )
        return

    output = run_cmd([args.objdump, "-d", "-M", "no-aliases", str(elf_path)], args.verbose)

    addr_re = re.compile(r"^\s*[0-9a-fA-F]+:\s*$")
    bytes_re = re.compile(r"^[0-9a-fA-F ]+$")
    invalid = []

    for line in output.splitlines():
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        if not addr_re.match(parts[0]):
            continue
        if not bytes_re.match(parts[1].strip()):
            continue

        mnemonic = parts[2].strip().split()[0].lower()
        if re.match(r"^(0x[0-9a-f]+|unknown|<unknown>|\.word|\.byte|\.half|\.short|\.long|\.dword|\.quad)$", mnemonic):
            continue
        if mnemonic not in allowed:
            addr = parts[0].strip().rstrip(":")
            invalid.append((addr, mnemonic))

    if invalid:
        details = "\n".join(f"  0x{addr}: {mnemonic}" for addr, mnemonic in invalid[:20])
        more = "" if len(invalid) <= 20 else f"\n  ... and {len(invalid) - 20} more"
        raise RuntimeError(
            f"Instruction(s) outside ISA profile '{args.march}' detected:\n"
            f"{details}{more}\n"
            f"Expected {args.march} instructions only."
        )


def elf_text_to_bin(args: argparse.Namespace, elf_path: Path, bin_path: Path) -> None:
    run_cmd(
        [args.objcopy, "-O", "binary", "--only-section=.text", str(elf_path), str(bin_path)],
        args.verbose,
    )


def elf_data_to_bin(args: argparse.Namespace, elf_path: Path, bin_path: Path) -> None:
    run_cmd(
        [
            args.objcopy,
            "-O",
            "binary",
            "--only-section=.data",
            "--only-section=.rodata",
            "--only-section=.sdata",
            str(elf_path),
            str(bin_path),
        ],
        args.verbose,
    )


def bin_to_words(bin_path: Path, allow_empty: bool = False) -> List[str]:
    data = bin_path.read_bytes()
    if not data:
        if allow_empty:
            return []
        raise RuntimeError(".text section is empty, nothing to write into COE")
    padded_len = (len(data) + 3) & ~3
    if padded_len != len(data):
        data = data + b"\x00" * (padded_len - len(data))

    words = []
    for idx in range(0, len(data), 4):
        word = int.from_bytes(data[idx : idx + 4], byteorder="little", signed=False)
        words.append(f"{word:08x}")
    return words


def apply_depth(words: List[str], depth: int) -> List[str]:
    if depth <= 0:
        return words
    if len(words) > depth:
        raise RuntimeError(f"Program has {len(words)} words, exceeds --depth {depth}")
    return words + ["00000013"] * (depth - len(words))


def write_coe(words: Sequence[str], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)

    lines = ["memory_initialization_radix=16;", "memory_initialization_vector="]
    for i, word in enumerate(words):
        suffix = ";" if i == len(words) - 1 else ","
        lines.append(f"{word}{suffix}")

    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_hex(words: Sequence[str], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(words) + "\n", encoding="utf-8")


def write_bin(bin_path_src: Path, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    data = bin_path_src.read_bytes()
    output_path.write_bytes(data)


def main() -> int:
    args = parse_args()

    src_path = Path(args.input).resolve()
    if not src_path.exists():
        print(f"[ERROR] Input file not found: {src_path}", file=sys.stderr)
        return 2

    has_unified = bool(args.output)
    has_inst = bool(args.inst_coe or args.inst_hex or args.inst_bin)
    has_data = bool(args.data_coe or args.data_hex or args.data_bin)
    if not has_unified and not has_inst and not has_data:
        print("[ERROR] No output specified. Use -o, --inst-coe/hex/bin, or --data-coe/hex/bin.", file=sys.stderr)
        return 2

    try:
        ensure_tool(args.gcc)
        ensure_tool(args.objcopy)
        if args.check_isa:
            ensure_tool(args.objdump)

        src_kind = detect_lang(src_path, args.lang)

        if args.keep_temp:
            tmp_root = Path(tempfile.mkdtemp(prefix="rv2coe_"))
            print(f"[INFO] Keeping temporary files in: {tmp_root}")
            cleanup_tmp = False
        else:
            tmp_obj = tempfile.TemporaryDirectory(prefix="rv2coe_")
            tmp_root = Path(tmp_obj.name)
            cleanup_tmp = True

        elf_path = tmp_root / "prog.elf"
        inst_bin_path = tmp_root / "prog.inst.bin"
        data_bin_path = tmp_root / "prog.data.bin"

        compile_to_elf(args, src_path, src_kind, elf_path)
        if args.check_isa:
            check_isa_whitelist(args, elf_path)

        if has_unified or has_inst:
            elf_text_to_bin(args, elf_path, inst_bin_path)
        if has_data:
            elf_data_to_bin(args, elf_path, data_bin_path)

        if has_unified:
            output_path = Path(args.output).resolve()
            words = bin_to_words(inst_bin_path)
            words = apply_depth(words, args.depth)
            write_coe(words, output_path)
            print(f"[INFO] Input : {src_path}")
            print(f"[INFO] Lang  : {src_kind}")
            print(f"[INFO] Words : {len(words)}")
            print(f"[INFO] Output: {output_path}")
            if args.hex:
                hex_path = Path(args.hex).resolve()
                write_hex(words, hex_path)
                print(f"[INFO] Hex   : {hex_path}")

        if has_inst:
            inst_words = bin_to_words(inst_bin_path)
            inst_words = apply_depth(inst_words, args.depth)
            if args.inst_coe:
                p = Path(args.inst_coe).resolve()
                write_coe(inst_words, p)
                print(f"[INFO] Inst COE : {p} ({len(inst_words)} words)")
            if args.inst_hex:
                p = Path(args.inst_hex).resolve()
                write_hex(inst_words, p)
                print(f"[INFO] Inst HEX : {p} ({len(inst_words)} words)")
            if args.inst_bin:
                p = Path(args.inst_bin).resolve()
                write_bin(inst_bin_path, p)
                print(f"[INFO] Inst BIN : {p} ({inst_bin_path.stat().st_size} bytes)")

        if has_data:
            data_words = bin_to_words(data_bin_path, allow_empty=True)
            data_words = apply_depth(data_words, args.data_depth)
            if args.data_coe:
                p = Path(args.data_coe).resolve()
                if data_words:
                    write_coe(data_words, p)
                    print(f"[INFO] Data COE : {p} ({len(data_words)} words)")
                else:
                    print("[WARN] No data sections (.data/.rodata/.sdata) found, skipping --data-coe", file=sys.stderr)
            if args.data_hex:
                p = Path(args.data_hex).resolve()
                if data_words:
                    write_hex(data_words, p)
                    print(f"[INFO] Data HEX : {p} ({len(data_words)} words)")
                else:
                    print("[WARN] No data sections found, skipping --data-hex", file=sys.stderr)
            if args.data_bin:
                p = Path(args.data_bin).resolve()
                if data_bin_path.stat().st_size > 0:
                    write_bin(data_bin_path, p)
                    print(f"[INFO] Data BIN : {p} ({data_bin_path.stat().st_size} bytes)")
                else:
                    print("[WARN] No data sections found, skipping --data-bin", file=sys.stderr)

        if not has_unified:
            print(f"[INFO] Input : {src_path}")
            print(f"[INFO] Lang  : {src_kind}")
            print(f"[INFO] March : {args.march}")

        if cleanup_tmp:
            tmp_obj.cleanup() # type: ignore
        return 0
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
