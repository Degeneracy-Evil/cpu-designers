#!/usr/bin/env python3
"""test_builder.py — 测试程序构建管理

读取 src/program_source/build.yaml，调用 rv2coe.py 编译测试程序和应用。

 用法:
     python tools/test_builder.py                          # 构建全部
     python tools/test_builder.py --category isa           # 仅构建 ISA 测试
     python tools/test_builder.py --category mmu           # 仅构建 MMU 测试
     python tools/test_builder.py --test isa/alu           # 构建单个测试
     python tools/test_builder.py --app led_marquee        # 构建单个应用
     python tools/test_builder.py --clean                  # 清理产物
     python tools/test_builder.py --list                   # 列出所有测试
     python tools/test_builder.py --gen-tasks              # 生成 tasks.yaml 任务条目
     python tools/test_builder.py --dry-run                # 仅打印命令不执行
     python tools/test_builder.py --verbose                # 详细输出
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

import yaml


# ── 路径常量 ──

# 项目根目录 (repo checkout root)
REPO_ROOT = Path(__file__).resolve().parent.parent

# src/program_source/ 基目录
PROG_SRC = REPO_ROOT / "src" / "program_source"

# 测试源码基目录
TEST_SRC = PROG_SRC / "test"

# 应用源码基目录
APP_SRC = PROG_SRC / "app"

# 产物根目录 (build/program/) — 镜像 program_source 的相对结构。
# 编译产物 (.hex/.coe) 一律落在 build/ 下, 不入版本库。
PROG_BUILD = REPO_ROOT / "build" / "program"
TEST_BUILD = PROG_BUILD / "test"
APP_BUILD = PROG_BUILD / "app"

# build.yaml 路径（统一编译配置：测试 + 应用）
BUILD_YAML = PROG_SRC / "build.yaml"

# tasks.yaml 路径
TASKS_YAML = REPO_ROOT / "config" / "tasks.yaml"

# rv2coe.py 路径
RV2COE = REPO_ROOT / "tools" / "rv2coe.py"


APP_TARGETS: dict[str, dict[str, Any]] = {}  # populated from build.yaml at load time


# ── 运行时映射 ──

RUNTIME_MAP: dict[str, str] = {
    "isa":        "5ms",
    "exception":  "5ms",
    "privilege":  "20ms",
    "mmu":        "20ms",
    "cache":      "10ms",
    "cache_mmu":  "20ms",
    "mmio":       "10ms",
    "regression": "20ms",
    "integration":"10ms",
}


# ── YAML 加载 ──

def load_build_config() -> dict[str, Any]:
    """加载 build.yaml 统一编译配置。"""
    with open(BUILD_YAML, encoding="utf-8") as f:
        return yaml.safe_load(f)


def _resolve_app_targets(config: dict) -> None:
    """从 build.yaml 的 apps 段填充 APP_TARGETS。

    路径相对于 src/program_source/ 解析；未指定字段继承 defaults。
    """
    global APP_TARGETS

    defaults = config.get("defaults", {})
    apps_section = config.get("apps", {})

    resolved: dict[str, dict[str, Any]] = {}
    for name, app_cfg in apps_section.items():
        src_files = [PROG_SRC / f for f in app_cfg.get("src_files", [])]
        include_dirs = [PROG_SRC / d for d in app_cfg.get("include_dirs", [])]

        linker_val = app_cfg.get("linker_script", defaults.get("linker_script"))
        linker_script = PROG_SRC / linker_val if linker_val else None

        resolved[name] = {
            "src_files": src_files,
            "arch": app_cfg.get("arch", defaults.get("arch", "rv32im_zicsr_zifencei")),
            "abi": app_cfg.get("abi", defaults.get("abi", "ilp32")),
            "linker_script": linker_script,
            "include_dirs": include_dirs,
            "depth": app_cfg.get("depth", defaults.get("depth", 8192)),
        }

    APP_TARGETS = resolved


# ── 测试发现 ──

def discover_all_tests(config: dict) -> list[dict]:
    """从 build.yaml 解析所有测试条目。

    Returns:
        list of dicts, each with keys:
            name: str         e.g. "isa/alu"
            category: str     e.g. "isa"
            src_file: Path    e.g. src/program_source/test/isa/alu.s
            framework: list[str]  framework files to include
            arch: str
            abi: str
            linker_script: Path
            depth: int
    """
    framework_defs = config.get("framework", {})
    defaults = config.get("defaults", {})
    categories = config.get("categories", {})

    all_tests = []
    for cat_name, cat_config in categories.items():
        fw_name = cat_config.get("framework", "common")
        if isinstance(fw_name, list):
            # 直接指定的框架文件列表
            fw_files = fw_name
        else:
            fw_files = framework_defs.get(fw_name, [])

        test_names = cat_config.get("tests", [])
        for test_name in test_names:
            all_tests.append({
                "name": test_name,
                "category": cat_name,
                "src_file": TEST_SRC / f"{test_name}.s",
                "framework": [PROG_SRC / f for f in fw_files],
                "arch": cat_config.get("arch", defaults.get("arch", "rv32im_zicsr_zifencei")),
                "abi": cat_config.get("abi", defaults.get("abi", "ilp32")),
                "linker_script": PROG_SRC / defaults.get("linker_script", "link.ld"),
                "depth": defaults.get("depth", 8192),
                "output_dir": TEST_BUILD,
            })

    return all_tests


def filter_tests(
    all_tests: list[dict],
    category: str | None,
    test_name: str | None,
) -> list[dict]:
    """按类别或测试名过滤。"""
    if test_name is not None:
        matched = [t for t in all_tests if t["name"] == test_name]
        if not matched:
            print(f"[ERROR] Test '{test_name}' not found in build.yaml", file=sys.stderr)
            sys.exit(1)
        return matched

    if category is not None:
        matched = [t for t in all_tests if t["category"] == category]
        if not matched:
            print(f"[ERROR] Category '{category}' not found in build.yaml", file=sys.stderr)
            sys.exit(1)
        return matched

    return all_tests


def discover_app(app_name: str) -> dict:
    """解析单个应用构建目标。"""
    app = APP_TARGETS.get(app_name)
    if app is None:
        print(f"[ERROR] App '{app_name}' not found", file=sys.stderr)
        sys.exit(1)

    return {
        "name": app_name,
        "category": "app",
        "src_file": app["src_files"][0],
        "src_files": app["src_files"],
        "framework": [],
        "arch": app["arch"],
        "abi": app["abi"],
        "linker_script": app["linker_script"],
        "include_dirs": app["include_dirs"],
        "depth": app["depth"],
        "output_dir": APP_BUILD,
    }


# ── 构建逻辑 ──

def build_test(test: dict, verbose: bool, dry_run: bool) -> bool:
    """构建单个测试程序。

    Returns:
        True if build succeeded (or dry_run), False otherwise.
    """
    name = test["name"]
    src_files = test.get("src_files", [test["src_file"]])
    output_dir = test.get("output_dir", TEST_BUILD)
    hex_file = output_dir / f"{name}.hex"
    coe_file = output_dir / f"{name}.coe"

    # 检查源文件存在
    for src_file in src_files:
        if not src_file.exists():
            print(f"[SKIP] {name}: source file not found: {src_file}")
            return False

    # 组装 rv2coe.py 命令
    cmd = [
        sys.executable,
        str(RV2COE),
    ]

    # 添加框架文件
    for fw_file in test["framework"]:
        if fw_file.exists():
            cmd.extend(["-i", str(fw_file)])
        else:
            print(f"[WARN] Framework file not found: {fw_file}", file=sys.stderr)

    # 添加测试/应用源文件
    for src_file in src_files:
        cmd.extend(["-i", str(src_file)])

    for inc_dir in test.get("include_dirs", []):
        cmd.extend(["-I", str(inc_dir)])

    # 链接脚本
    linker = test["linker_script"]
    if linker is not None and linker.exists():
        cmd.extend(["--linker-script", str(linker)])

    # 架构/ABI
    cmd.extend(["--march", test["arch"], "--abi", test["abi"]])

    # 输出文件: -o for COE, --hex for hex
    cmd.extend(["-o", str(coe_file), "--hex", str(hex_file)])

    # 深度
    depth = test["depth"]
    if depth > 0:
        cmd.extend(["--depth", str(depth)])

    if verbose:
        cmd.append("-v")

    if dry_run:
        print(f"[DRY] {name}: {' '.join(cmd)}")
        return True

    # 确保输出目录存在
    hex_file.parent.mkdir(parents=True, exist_ok=True)

    print(f"[BUILD] {name} ...", end=" ", flush=True)
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
        if result.returncode == 0:
            print("OK")
            if verbose and result.stdout:
                print(result.stdout)
            return True
        else:
            print("FAIL")
            print(f"  Command: {' '.join(cmd)}")
            if result.stdout:
                print(f"  stdout: {result.stdout}")
            if result.stderr:
                print(f"  stderr: {result.stderr}")
            return False
    except Exception as e:
        print(f"ERROR: {e}")
        return False


def clean_tests(all_tests: list[dict]) -> None:
    """清理所有测试产物 (.hex, .coe)。"""
    removed = 0
    for test in all_tests:
        out_dir = test.get("output_dir", TEST_BUILD)
        for ext in (".hex", ".coe"):
            f = out_dir / f"{test['name']}{ext}"
            if f.exists():
                f.unlink()
                removed += 1
    print(f"[CLEAN] Removed {removed} files")


def clean_app(app: dict) -> None:
    """清理单个应用产物 (.hex, .coe)。"""
    removed = 0
    out_dir = app.get("output_dir", APP_BUILD)
    for ext in (".hex", ".coe"):
        f = out_dir / f"{app['name']}{ext}"
        if f.exists():
            f.unlink()
            removed += 1
    print(f"[CLEAN] Removed {removed} files for app {app['name']}")


def list_tests(all_tests: list[dict]) -> None:
    """列出所有测试。"""
    # 按类别分组
    by_category: dict[str, list[dict]] = {}
    for t in all_tests:
        by_category.setdefault(t["category"], []).append(t)

    for cat, tests in sorted(by_category.items()):
        print(f"\n[{cat}] ({len(tests)} tests)")
        for t in tests:
            exists = "OK" if t["src_file"].exists() else "MISS"
            print(f"  {exists} {t['name']}")


def gen_tasks(all_tests: list[dict]) -> int:
    """生成 tasks.yaml 条目并打印到标准输出。

    生成的 YAML 可直接复制粘贴到 tasks.yaml 的 ``tasks:`` 段中。
    使用 ``--gen-tasks --output-file tasks.yaml`` 可直接追加到文件。
    """
    output_lines = []
    output_lines.append("# === AUTO-GENERATED test tasks (begin) ===")
    output_lines.append("# Generated by: python tools/test_builder.py --gen-tasks")
    output_lines.append("")

    for t in all_tests:
        name = t["name"]
        task_name = name.replace("/", "_")
        tb_name = f"tb_{task_name}"
        blcoe_path = f"test/{name}.coe"
        runtime = RUNTIME_MAP.get(t["category"], "10ms")

        output_lines.append(f"  {task_name}:")
        output_lines.append(f"    tb: {tb_name}")
        output_lines.append(f"    blcoe: {blcoe_path}")
        output_lines.append(f"    runtime: {runtime}")
        output_lines.append("")

    output_lines.append("# === AUTO-GENERATED test tasks (end) ===")
    print("\n".join(output_lines))
    return 0


# ── 主入口 ──

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build test programs for the embedded CPU project.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--category",
        help="Build only tests in this category (isa, mmu, cache, ...)",
    )
    parser.add_argument(
        "--test",
        help="Build a single test by name (e.g. isa/alu)",
    )
    parser.add_argument(
        "--app",
        help="Build a single app by name (e.g. led_marquee)",
    )
    parser.add_argument(
        "--clean",
        action="store_true",
        help="Remove all generated .hex/.coe files",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List all registered tests",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print commands without executing",
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Verbose output",
    )
    parser.add_argument(
        "--gen-tasks",
        action="store_true",
        help="Generate tasks.yaml entries from build.yaml and print to stdout",
    )
    args = parser.parse_args()

    # 加载配置
    if not BUILD_YAML.exists():
        print(f"[ERROR] build.yaml not found: {BUILD_YAML}", file=sys.stderr)
        return 1

    config = load_build_config()
    _resolve_app_targets(config)
    all_tests = discover_all_tests(config)

    if args.app:
        app = discover_app(args.app)
        if args.clean:
            clean_app(app)
            return 0
        ok = build_test(app, args.verbose, args.dry_run)
        return 0 if ok else 1

    # --list
    if args.list:
        list_tests(all_tests)
        return 0

    # --gen-tasks
    if args.gen_tasks:
        return gen_tasks(all_tests)

    # --clean
    if args.clean:
        clean_tests(all_tests)
        return 0

    # 过滤测试
    selected = filter_tests(all_tests, args.category, args.test)

    if not selected:
        print("[ERROR] No tests selected", file=sys.stderr)
        return 1

    print(f"[INFO] Building {len(selected)} test(s) ...")

    # 构建
    ok = 0
    fail = 0
    skip = 0
    for test in selected:
        if not test["src_file"].exists():
            print(f"[SKIP] {test['name']}: source not found")
            skip += 1
            continue
        if build_test(test, args.verbose, args.dry_run):
            ok += 1
        else:
            fail += 1

    # 汇总
    print(f"\n[SUMMARY] {ok} built, {fail} failed, {skip} skipped")
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
