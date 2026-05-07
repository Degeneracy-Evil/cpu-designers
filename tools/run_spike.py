#!/usr/bin/env python3
import argparse
import subprocess
import os
import sys

def main():
    parser = argparse.ArgumentParser(description="Run a RISC-V program with Spike and capture state.")
    parser.add_argument("program", help="The ELF executable to run")
    parser.add_argument("--out-prefix", default="spike_out", help="Prefix for output files")
    parser.add_argument("--max-insns", type=int, default=100000, help="Max instructions to run before halting")
    parser.add_argument("--memory", default="0x0:0x20000", help="Memory definition (base:size). E.g. 0x0:0x20000 or 0x80000000:0x20000")
    
    args = parser.parse_args()

    cmd_file = args.out_prefix + "_cmds.txt"
    with open(cmd_file, "w") as f:
        f.write(f"rs {args.max_insns}\n")
        f.write("reg 0\n")
        f.write("dump\n")
        f.write("q\n")

    print(f"Running spike on {args.program}...")
    
    command = [
        "spike", 
        f"-m{args.memory}", 
        "--isa=rv32im_zicsr_zifencei", 
        "-d", 
        f"--debug-cmd={cmd_file}", 
        args.program
    ]

    try:
        result = subprocess.run(command, capture_output=True, text=True)
    except FileNotFoundError:
        print("Error: spike not found in PATH.")
        sys.exit(1)

    reg_out_file = args.out_prefix + "_regs.txt"
    with open(reg_out_file, "w") as f:
        f.write(result.stdout)
        f.write("\n")
        f.write(result.stderr)
    
    print(f"Registers captured in {reg_out_file}")
    mem_base = args.memory.split(':')[0]
    print(f"Memory dumped in current directory as mem.{mem_base}.bin")
    
    if os.path.exists(cmd_file):
        os.remove(cmd_file)

if __name__ == "__main__":
    main()
