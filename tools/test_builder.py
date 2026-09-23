#!/usr/bin/env python3
"""Build the bare-metal tests and applications declared in config/programs.yaml."""

from __future__ import annotations

import argparse
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "config" / "programs.yaml"
TEST_ROOT = ROOT / "test" / "program"
SOFTWARE_ROOT = ROOT / "software"
OUTPUT_ROOT = ROOT / "build" / "program"
RV2COE = ROOT / "tools" / "rv2coe.py"


@dataclass(frozen=True)
class Target:
    name: str
    kind: str
    category: str
    sources: tuple[Path, ...]
    framework: tuple[Path, ...]
    includes: tuple[Path, ...]
    linker: Path | None
    arch: str
    abi: str
    depth: int

    @property
    def output_dir(self) -> Path:
        return OUTPUT_ROOT / ("test" if self.kind == "test" else "app")


def load_targets() -> tuple[list[Target], list[Target]]:
    raw = yaml.safe_load(CONFIG.read_text(encoding="utf-8")) or {}
    defaults = raw.get("defaults", {})
    arch_default = defaults.get("arch", "rv32im_zicsr_zifencei")
    abi_default = defaults.get("abi", "ilp32")
    depth_default = int(defaults.get("depth", 8192))
    linker_default = defaults.get("linker_script", "linker/ram.ld")
    frameworks = raw.get("framework", {})

    tests: list[Target] = []
    for category, entry in raw.get("categories", {}).items():
        framework_name = entry.get("framework", "common")
        framework_files = framework_name if isinstance(framework_name, list) else frameworks.get(framework_name, [])
        for name in entry.get("tests", []):
            tests.append(Target(
                name=name,
                kind="test",
                category=category,
                sources=(TEST_ROOT / f"{name}.s",),
                framework=tuple(TEST_ROOT / path for path in framework_files),
                includes=(),
                linker=SOFTWARE_ROOT / linker_default if linker_default else None,
                arch=entry.get("arch", arch_default),
                abi=entry.get("abi", abi_default),
                depth=int(entry.get("depth", depth_default)),
            ))

    apps: list[Target] = []
    for name, entry in raw.get("apps", {}).items():
        linker_value = entry.get("linker_script", linker_default)
        apps.append(Target(
            name=name,
            kind="app",
            category="app",
            sources=tuple(SOFTWARE_ROOT / path for path in entry.get("src_files", [])),
            framework=(),
            includes=tuple(SOFTWARE_ROOT / path for path in entry.get("include_dirs", [])),
            linker=SOFTWARE_ROOT / linker_value if linker_value else None,
            arch=entry.get("arch", arch_default),
            abi=entry.get("abi", abi_default),
            depth=int(entry.get("depth", depth_default)),
        ))
    return tests, apps


def output_paths(target: Target) -> tuple[Path, Path]:
    base = target.output_dir / target.name
    return base.with_suffix(".coe"), base.with_suffix(".hex")


def build(target: Target, dry_run: bool, verbose: bool) -> bool:
    inputs = (*target.framework, *target.sources)
    missing = [path for path in inputs if not path.is_file()]
    if missing:
        print(f"ERROR {target.name}: missing {missing[0]}", file=sys.stderr)
        return False

    coe, hex_file = output_paths(target)
    command = [sys.executable, str(RV2COE)]
    for path in inputs:
        command.extend(("-i", str(path)))
    for path in target.includes:
        command.extend(("-I", str(path)))
    if target.linker is not None:
        command.extend(("--linker-script", str(target.linker)))
    command.extend((
        "--march", target.arch,
        "--abi", target.abi,
        "--depth", str(target.depth),
        "-o", str(coe),
        "--hex", str(hex_file),
    ))
    if verbose:
        command.append("-v")
    if dry_run:
        print(" ".join(command))
        return True

    coe.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(command, text=True, check=False)
    if result.returncode == 0:
        print(f"PASS {target.name}")
        return True
    print(f"FAIL {target.name}", file=sys.stderr)
    return False


def clean(targets: list[Target]) -> None:
    removed = 0
    for target in targets:
        for path in output_paths(target):
            if path.exists():
                path.unlink()
                removed += 1
    print(f"Removed {removed} generated files")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument("--test", help="test name, for example isa/alu")
    selection.add_argument("--category", help="test category")
    selection.add_argument("--app", help="application name")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--clean", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("-v", "--verbose", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    tests, apps = load_targets()

    if args.list:
        for target in (*tests, *apps):
            print(f"{target.kind:4} {target.name}")
        return 0

    if args.app:
        selected = [target for target in apps if target.name == args.app]
    elif args.test:
        selected = [target for target in tests if target.name == args.test]
    elif args.category:
        selected = [target for target in tests if target.category == args.category]
    else:
        selected = tests

    if not selected:
        print("No matching target", file=sys.stderr)
        return 1
    if args.clean:
        clean(selected if any((args.app, args.test, args.category)) else tests + apps)
        return 0

    failures = sum(not build(target, args.dry_run, args.verbose) for target in selected)
    print(f"{len(selected) - failures} passed, {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
