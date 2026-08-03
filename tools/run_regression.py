#!/usr/bin/env python3
"""run_regression.py — 全测试回归运行器

构建所有测试程序并使用 Vivado Orchestrator 批量仿真，
收集并汇总结果。

用法:
    python tools/run_regression.py                          # 全回归 (构建+仿真)
    python tools/run_regression.py --category mmu           # 仅 MMU 类别
    python tools/run_regression.py --sim-only               # 仅仿真 (跳过构建)
    python tools/run_regression.py --build-only             # 仅构建 (跳过仿真)
    python tools/run_regression.py --verbose                # 详细输出
    python tools/run_regression.py --dry-run                # 仅列计划不执行
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
BUILD_YAML = REPO_ROOT / "src" / "program_source" / "build.yaml"
TEST_BUILDER = REPO_ROOT / "tools" / "test_builder.py"
VIVADO_CLI = REPO_ROOT / "tools" / "vivado_cli.py"


def load_categories() -> list[str]:
    """从 build.yaml 读取所有类别名。"""
    with open(BUILD_YAML, encoding="utf-8") as f:
        config = yaml.safe_load(f)
    return list(config.get("categories", {}).keys())


def build_tests(category: str | None = None, verbose: bool = False) -> bool:
    """调用 test_builder.py 构建测试。"""
    cmd = [sys.executable, str(TEST_BUILDER)]
    if category:
        cmd.extend(["--category", category])
    if verbose:
        cmd.append("--verbose")

    print(f"[BUILD] {'all' if category is None else category} ...")
    result = subprocess.run(cmd, capture_output=not verbose, text=True)
    if result.returncode != 0 and not verbose:
        print(result.stderr or result.stdout)
    return result.returncode == 0


def sim_category(category: str) -> bool:
    """使用 vivado_cli batch 模式仿真一个类别。"""
    task_pattern = f"{category}_*"

    cmd = [
        sys.executable,
        "-m", "tools.vivado_cli",
        "-batch", task_pattern,
        "-create", "-sim",
        "--on-error", "continue",
        "--max-parallel", "2",
    ]

    print(f"\n[SIM] {category} (pattern: {task_pattern}) ...")
    start = time.time()
    result = subprocess.run(cmd, capture_output=True, text=True)
    elapsed = time.time() - start

    # 提取汇总行
    summary_lines = []
    for line in result.stdout.splitlines():
        if "PASS" in line or "FAIL" in line or "Total" in line or "Succeeded" in line:
            summary_lines.append(line.strip())

    if summary_lines:
        print("\n".join(summary_lines))
    print(f"  elapsed: {elapsed:.1f}s")

    return result.returncode == 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Full regression runner for the test system.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--category",
        help="Run regression for a single category only",
    )
    parser.add_argument(
        "--sim-only",
        action="store_true",
        help="Skip build, only run simulations",
    )
    parser.add_argument(
        "--build-only",
        action="store_true",
        help="Only build, skip simulations",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Verbose output",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print plan without executing",
    )
    args = parser.parse_args()

    categories = load_categories()
    if args.category:
        if args.category not in categories:
            print(f"[ERROR] Unknown category: {args.category}", file=sys.stderr)
            print(f"  Available: {', '.join(categories)}", file=sys.stderr)
            return 1
        categories = [args.category]

    if args.dry_run:
        print(f"[DRY-RUN] Categories: {', '.join(categories)}")
        print(f"[DRY-RUN] Build: {not args.sim_only}")
        print(f"[DRY-RUN] Sim:   {not args.build_only}")
        return 0

    all_ok = True

    # ── Phase 1: Build ──
    if not args.sim_only:
        print("=" * 60)
        print("PHASE 1: Build")
        print("=" * 60)
        for cat in categories:
            ok = build_tests(cat, args.verbose)
            if not ok:
                print(f"[FAIL] Build failed for {cat}")
                all_ok = False
            else:
                print(f"[OK]   Build {cat}")

    # ── Phase 2: Sim ──
    if not args.build_only:
        print("\n" + "=" * 60)
        print("PHASE 2: Simulation")
        print("=" * 60)
        for cat in categories:
            ok = sim_category(cat)
            if not ok:
                print(f"[FAIL] Sim failed for {cat}")
                all_ok = False
            else:
                print(f"[OK]   Sim {cat}")

    print("\n" + "=" * 60)
    print("REGRESSION COMPLETE")
    print(f"Result: {'ALL PASS' if all_ok else 'SOME FAILURES'}")
    print("=" * 60)

    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
