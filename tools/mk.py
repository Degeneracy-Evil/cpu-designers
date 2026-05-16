#!/usr/bin/env python3
"""[DEPRECATED] Simple Verilog build runner for this repository.

**此脚本已弃用。** 项目已迁移至 SystemVerilog，仿真请使用 Vivado TCL:
    vivado.bat -mode tcl
    source vivado_sim.tcl
    vivado_sim -tb <testbench_name>

Features:
- Use command line arguments to choose top Verilog file.
- Auto-resolve dependent design files by parsing module instantiations.
- Compile with iverilog and run with vvp.
- Keep generated artifacts in build/.
"""

from __future__ import annotations

import argparse
import re
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Set


VERILOG_SUFFIXES = (".v", ".sv", ".vh", ".svh")
KEYWORDS = {
    "module",
    "endmodule",
    "input",
    "output",
    "inout",
    "wire",
    "reg",
    "logic",
    "assign",
    "if",
    "else",
    "for",
    "while",
    "case",
    "endcase",
    "always",
    "always_ff",
    "always_comb",
    "always_latch",
    "initial",
    "begin",
    "end",
    "function",
    "endfunction",
    "task",
    "endtask",
    "generate",
    "endgenerate",
    "genvar",
    "parameter",
    "localparam",
    "typedef",
    "struct",
    "union",
    "packed",
    "signed",
    "unsigned",
    "import",
    "export",
    "class",
    "endclass",
    "interface",
    "endinterface",
    "program",
    "endprogram",
}


def strip_comments(src: str) -> str:
    src = re.sub(r"//.*?$", "", src, flags=re.MULTILINE)
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.DOTALL)
    return src


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore")


def find_module_defs(src: str) -> List[str]:
    text = strip_comments(src)
    return re.findall(r"(?m)^\s*module\s+([A-Za-z_]\w*)\b", text)


def find_instantiated_modules(src: str) -> Set[str]:
    text = strip_comments(src)
    pattern = re.compile(
        r"(?m)^\s*"
        r"([A-Za-z_]\w*)"
        r"\s*(?:#\s*\([^;]*?\))?"
        r"\s+"
        r"(?:[A-Za-z_]\w*|\[[^\]]+\])"
        r"\s*\(",
        re.DOTALL,
    )
    modules: Set[str] = set()
    for module_name in pattern.findall(text):
        if module_name not in KEYWORDS:
            modules.add(module_name)
    return modules


def collect_verilog_files(
    search_roots: Iterable[Path], build_dir: Path, exclude_patterns: Iterable[str] = ()
) -> List[Path]:
    files: List[Path] = []
    build_dir_resolved = build_dir.resolve()
    for root in search_roots:
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if not path.is_file() or path.suffix.lower() not in VERILOG_SUFFIXES:
                continue
            try:
                if path.resolve().is_relative_to(build_dir_resolved):
                    continue
            except Exception:
                pass
            skip = False
            for pat in exclude_patterns:
                if pat in str(path):
                    skip = True
                    break
            if skip:
                continue
            files.append(path.resolve())
    return sorted(set(files))


def build_module_map(verilog_files: Iterable[Path]) -> Dict[str, Path]:
    module_map: Dict[str, Path] = {}
    for vf in verilog_files:
        try:
            src = read_text(vf)
        except OSError:
            continue
        for module_name in find_module_defs(src):
            module_map.setdefault(module_name, vf)
    return module_map


def resolve_dependency_files(top_file: Path, module_map: Dict[str, Path]) -> List[Path]:
    resolved: List[Path] = []
    visited_files: Set[Path] = set()
    queue: List[Path] = [top_file.resolve()]

    while queue:
        cur = queue.pop(0)
        cur = cur.resolve()
        if cur in visited_files:
            continue
        visited_files.add(cur)
        resolved.append(cur)

        try:
            src = read_text(cur)
        except OSError:
            continue

        for submodule in find_instantiated_modules(src):
            dep = module_map.get(submodule)
            if dep is not None and dep.resolve() not in visited_files:
                queue.append(dep.resolve())

    return resolved


def run_cmd(cmd: List[str], cwd: Path | None = None, tee_log: Path | None = None) -> int:
    process = subprocess.Popen(
        cmd,
        cwd=str(cwd) if cwd else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
    )

    log_fp = None
    if tee_log is not None:
        tee_log.parent.mkdir(parents=True, exist_ok=True)
        log_fp = tee_log.open("w", encoding="utf-8")

    assert process.stdout is not None
    for line in process.stdout:
        sys.stdout.write(line)
        if log_fp:
            log_fp.write(line)

    process.wait()
    if log_fp:
        log_fp.close()
    return process.returncode


def to_shell_line(parts: List[str]) -> str:
    return " ".join(shlex.quote(p) for p in parts)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compile and run Verilog with auto dependency discovery.",
        formatter_class=argparse.RawTextHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python mk.py --top dev/tb/ALU/tb_alu_cpu_integration.v\n"
            "  python mk.py --top dev/tb/ALU/tb_alu_cpu_integration.v --top-module tb_alu_cpu_integration\n"
            "  python mk.py --top dev/rtl/ALU/alu_32bit.v --compile-only\n"
        ),
    )

    parser.add_argument("--top", required=True, help="Top Verilog file path (.v/.sv).")
    parser.add_argument("--top-module", help="Top module name for iverilog -s.")
    parser.add_argument(
        "--search-root",
        action="append",
        default=["."],
        help="Search roots for Verilog files. Can be used multiple times.",
    )
    parser.add_argument(
        "--exclude",
        action="append",
        default=["Reference"],
        help="Substring pattern to exclude from file search. Can be used multiple times. Default: Reference",
    )
    parser.add_argument(
        "--build-dir",
        default="build",
        help="Build output directory. Default: build",
    )
    parser.add_argument(
        "--output",
        help="Output vvp filename (without path). Default: <top_stem>.vvp",
    )
    parser.add_argument(
        "--extra-file",
        action="append",
        default=[],
        help="Extra source file to force include. Can be used multiple times.",
    )
    parser.add_argument(
        "--include-dir",
        action="append",
        default=[],
        help="Extra include directory (-I). Can be used multiple times.",
    )
    parser.add_argument(
        "--define",
        action="append",
        default=[],
        help="Macro define in form NAME or NAME=VALUE. Can be used multiple times.",
    )
    parser.add_argument("--iverilog", default="iverilog", help="iverilog executable name/path.")
    parser.add_argument("--vvp", default="vvp", help="vvp executable name/path.")
    parser.add_argument(
        "--iverilog-flag",
        action="append",
        default=["-g2005-sv"],
        help="Extra flag for iverilog. Can be used multiple times. Default: -g2005-sv",
    )
    parser.add_argument("--compile-only", action="store_true", help="Only compile, do not run.")
    parser.add_argument("--run-only", action="store_true", help="Only run existing vvp output.")
    parser.add_argument("--dry-run", action="store_true", help="Print commands only.")

    return parser.parse_args()


def main() -> int:
    args = parse_args()
    # Use the shell's current working directory as the base path.
    workspace = Path.cwd().resolve()
    build_dir = (workspace / args.build_dir).resolve()
    build_dir.mkdir(parents=True, exist_ok=True)

    top_file = (workspace / args.top).resolve()
    if not top_file.exists():
        print(f"[ERROR] Top file not found: {top_file}")
        return 2

    output_name = args.output if args.output else f"{top_file.stem}.vvp"
    output_path = build_dir / output_name

    if args.compile_only and args.run_only:
        print("[ERROR] --compile-only and --run-only cannot be used together.")
        return 2

    compile_log = build_dir / f"{Path(output_name).stem}.compile.log"
    run_log = build_dir / f"{Path(output_name).stem}.run.log"
    filelist_txt = build_dir / f"{Path(output_name).stem}.filelist.txt"

    do_compile = not args.run_only
    do_run = not args.compile_only

    if do_compile:
        search_roots = [(workspace / p).resolve() for p in args.search_root]
        all_verilog_files = collect_verilog_files(search_roots, build_dir, args.exclude)
        module_map = build_module_map(all_verilog_files)

        resolved = resolve_dependency_files(top_file, module_map)

        for ef in args.extra_file:
            ef_path = (workspace / ef).resolve()
            if ef_path.exists() and ef_path not in resolved:
                resolved.append(ef_path)

        resolved = sorted(set(resolved))

        include_dirs = {str(p.parent) for p in resolved}
        for vf in all_verilog_files:
            if vf.suffix.lower() in (".vh", ".svh"):
                include_dirs.add(str(vf.parent))
        include_dirs.update(str((workspace / p).resolve()) for p in args.include_dir)

        compile_cmd: List[str] = [args.iverilog, "-Wall"] + args.iverilog_flag
        if args.top_module:
            compile_cmd.extend(["-s", args.top_module])
        for macro in args.define:
            compile_cmd.extend(["-D", macro])
        for inc in sorted(include_dirs):
            compile_cmd.extend(["-I", inc])
        compile_cmd.extend(["-o", str(output_path)])
        compile_cmd.extend(str(p) for p in resolved)

        filelist_txt.write_text("\n".join(str(p) for p in resolved) + "\n", encoding="utf-8")

        print(f"[INFO] Top file: {top_file}")
        print(f"[INFO] Resolved {len(resolved)} source files.")
        print(f"[INFO] Build dir: {build_dir}")
        print(f"[CMD ] {to_shell_line(compile_cmd)}")

        if not args.dry_run:
            rc = run_cmd(compile_cmd, cwd=workspace, tee_log=compile_log)
            if rc != 0:
                print(f"[ERROR] Compile failed with code {rc}.")
                return rc
            print(f"[INFO] Compile success. Log: {compile_log}")

    if do_run:
        run_cmdline = [args.vvp, str(output_path)]
        print(f"[CMD ] {to_shell_line(run_cmdline)}")

        if not args.dry_run:
            rc = run_cmd(run_cmdline, cwd=workspace, tee_log=run_log)
            if rc != 0:
                print(f"[ERROR] Simulation failed with code {rc}.")
                return rc
            print(f"[INFO] Simulation success. Log: {run_log}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
