#!/usr/bin/env python3
"""Compile RISC-V ASM/C source into Xilinx COE instruction image.

Default target matches this repository's embedded CPU project:
- ISA: rv32i_zicsr_zifencei
- ABI: ilp32
- COE format: memory_initialization_radix=16 + 32-bit words
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import List, Sequence


ALLOWED_MNEMONICS = {
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
    "fence.i",
    "csrrw",
    "csrrs",
    "csrrc",
    "csrrwi",
    "csrrsi",
    "csrrci",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compile RISC-V ASM/C into COE for instruction BRAM.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("-i", "--input", required=True, help="Input source file (.S/.s/.asm/.c)")
    parser.add_argument("-o", "--output", required=True, help="Output .coe file")
    parser.add_argument(
        "--lang",
        choices=["auto", "asm", "c"],
        default="auto",
        help="Input language",
    )
    parser.add_argument("--entry", default="_start", help="Link entry symbol")
    parser.add_argument("--march", default="rv32i_zicsr_zifencei", help="-march passed to GCC")
    parser.add_argument("--abi", default="ilp32", help="-mabi passed to GCC")
    parser.add_argument("--gcc", default="riscv64-unknown-elf-gcc", help="RISC-V GCC executable")
    parser.add_argument("--objcopy", default="riscv64-unknown-elf-objcopy", help="RISC-V objcopy executable")
    parser.add_argument("--objdump", default="riscv64-unknown-elf-objdump", help="RISC-V objdump executable")
    check_group = parser.add_mutually_exclusive_group()
    check_group.add_argument(
        "--check-isa",
        dest="check_isa",
        action="store_true",
        help="Check instructions against project ISA list",
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
        help="Pad output words to fixed depth (0 means no padding)",
    )
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
        if mnemonic not in ALLOWED_MNEMONICS:
            addr = parts[0].strip().rstrip(":")
            invalid.append((addr, mnemonic))

    if invalid:
        details = "\n".join(f"  0x{addr}: {mnemonic}" for addr, mnemonic in invalid[:20])
        more = "" if len(invalid) <= 20 else f"\n  ... and {len(invalid) - 20} more"
        raise RuntimeError(
            "Instruction(s) outside project ISA set detected:\n"
            f"{details}{more}\n"
            "Expected RV32I + Zicsr + Zifencei only."
        )


def elf_text_to_bin(args: argparse.Namespace, elf_path: Path, bin_path: Path) -> None:
    run_cmd(
        [args.objcopy, "-O", "binary", "--only-section=.text", str(elf_path), str(bin_path)],
        args.verbose,
    )


def bin_to_words(bin_path: Path) -> List[str]:
    data = bin_path.read_bytes()
    if not data:
        raise RuntimeError(".text section is empty, nothing to write into COE")
    if len(data) % 4 != 0:
        raise RuntimeError(f".text binary size {len(data)} is not a multiple of 4 bytes")

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


def main() -> int:
    args = parse_args()

    src_path = Path(args.input).resolve()
    output_path = Path(args.output).resolve()
    if not src_path.exists():
        print(f"[ERROR] Input file not found: {src_path}", file=sys.stderr)
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
        bin_path = tmp_root / "prog.bin"

        compile_to_elf(args, src_path, src_kind, elf_path)
        if args.check_isa:
            check_isa_whitelist(args, elf_path)
        elf_text_to_bin(args, elf_path, bin_path)

        words = bin_to_words(bin_path)
        words = apply_depth(words, args.depth)
        write_coe(words, output_path)

        print(f"[INFO] Input : {src_path}")
        print(f"[INFO] Lang  : {src_kind}")
        print(f"[INFO] Words : {len(words)}")
        print(f"[INFO] Output: {output_path}")

        if cleanup_tmp:
            tmp_obj.cleanup()
        return 0
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
