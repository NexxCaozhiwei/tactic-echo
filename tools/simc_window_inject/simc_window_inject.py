#!/usr/bin/env python3
"""Command-line entry point for the SimC Window / Inject review-data generator."""

from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import sys
import tempfile
from urllib.error import URLError
from urllib.request import urlopen
from zipfile import ZipFile
from io import BytesIO

try:
    from .core import DEFAULT_REF, SimcParserError, run_parser
except ImportError:  # Direct execution: python tools/.../simc_window_inject.py
    from core import DEFAULT_REF, SimcParserError, run_parser


OFFICIAL_ARCHIVE_URL = "https://github.com/simulationcraft/simc/archive/refs/heads/{ref}.zip"


def _download_simc_archive(cache_dir: Path, ref: str) -> Path:
    """Download the official SimC archive only when requested explicitly.

    The archive is extracted into a temporary sibling directory and promoted only
    after the expected ActionPriorityLists tree exists.  A failed download cannot
    leave a partial cache that later looks valid.
    """

    if not ref or any(char not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-/" for char in ref):
        raise SimcParserError("--ref 只允许字母、数字、.、_、-、/。")
    cache_dir.mkdir(parents=True, exist_ok=True)
    destination = cache_dir / f"simc-{ref.replace('/', '_')}"
    expected_apl = destination / "ActionPriorityLists"
    if expected_apl.is_dir():
        return destination

    url = OFFICIAL_ARCHIVE_URL.format(ref=ref)
    try:
        with urlopen(url, timeout=30) as response:  # nosec B310: fixed official GitHub URL
            payload = response.read()
    except URLError as exc:
        raise SimcParserError(f"无法从 SimulationCraft 官方仓库下载 '{url}': {exc}") from exc

    temp_dir = Path(tempfile.mkdtemp(prefix=".simc-download-", dir=str(cache_dir)))
    try:
        try:
            with ZipFile(BytesIO(payload)) as archive:
                members = [member for member in archive.namelist() if member and not member.endswith("/")]
                top_levels = {member.split("/", 1)[0] for member in members if "/" in member}
                if len(top_levels) != 1:
                    raise SimcParserError("SimulationCraft 下载包结构异常，拒绝解压。")
                source_prefix = next(iter(top_levels)) + "/"
                for member in members:
                    if not member.startswith(source_prefix):
                        raise SimcParserError("SimulationCraft 下载包包含异常路径，拒绝解压。")
                    relative = Path(member[len(source_prefix):])
                    if relative.is_absolute() or ".." in relative.parts:
                        raise SimcParserError("SimulationCraft 下载包包含危险路径，拒绝解压。")
                    target = temp_dir / relative
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with archive.open(member) as source, target.open("wb") as sink:
                        shutil.copyfileobj(source, sink)
        except SimcParserError:
            raise
        except Exception as exc:  # zipfile raises multiple implementation-specific errors.
            raise SimcParserError(f"无法解压 SimulationCraft 下载包: {exc}") from exc

        if not (temp_dir / "ActionPriorityLists").is_dir():
            raise SimcParserError("下载完成后未找到 ActionPriorityLists，拒绝继续。")
        if destination.exists():
            shutil.rmtree(destination)
        temp_dir.replace(destination)
        return destination
    except Exception:
        if temp_dir.exists():
            shutil.rmtree(temp_dir, ignore_errors=True)
        raise


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="从 SimulationCraft APL 生成 Tactic Echo Window / Inject 审核数据。",
    )
    source_group = parser.add_mutually_exclusive_group(required=True)
    source_group.add_argument(
        "--simc-root",
        help="SimulationCraft 仓库根目录、ActionPriorityLists 目录，或其 default/assisted_combat 子目录。",
    )
    source_group.add_argument(
        "--download",
        action="store_true",
        help="从 SimulationCraft 官方 GitHub 仓库下载指定分支到本地缓存后解析。",
    )
    parser.add_argument(
        "--ref",
        default=DEFAULT_REF,
        help=f"--download 使用的官方分支，默认 {DEFAULT_REF}。",
    )
    parser.add_argument(
        "--cache-dir",
        default=str(Path(__file__).resolve().parent / "_cache"),
        help="--download 的本地缓存目录。",
    )
    parser.add_argument(
        "--out-dir",
        required=True,
        help="输出目录。将生成 JSON、TXT、Lua 审核种子、overrides 模板与来源哈希清单。",
    )
    parser.add_argument(
        "--spec",
        action="append",
        default=[],
        help="仅处理指定 spec 文件名，可重复或以逗号分隔，例如 paladin_retribution,mage_fire。",
    )
    parser.add_argument(
        "--overrides",
        help="可选 JSON 覆盖文件，用于确认 include/exclude 与前置/后置 pairs。",
    )
    return parser.parse_args(argv)


def _normalize_specs(raw_values: list[str]) -> list[str]:
    result: list[str] = []
    for raw in raw_values:
        result.extend(piece.strip().lower() for piece in raw.split(",") if piece.strip())
    return result


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv or sys.argv[1:])
    try:
        simc_root = (
            _download_simc_archive(Path(args.cache_dir), args.ref)
            if args.download
            else Path(args.simc_root)
        )
        outputs = run_parser(
            simc_root,
            Path(args.out_dir),
            selected_specs=_normalize_specs(args.spec),
            overrides_path=args.overrides,
        )
    except SimcParserError as exc:
        print(f"[SimC Parser] 失败: {exc}", file=sys.stderr)
        return 2

    print("[SimC Parser] 完成。")
    for name, path in outputs.items():
        print(f"  {name}: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
