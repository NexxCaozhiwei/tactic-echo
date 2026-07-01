#!/usr/bin/env python3
"""Static baseline contract checks for Tactic Echo.

This verifier intentionally has no runtime dependency outside the Python
standard library. It validates repository structure and source archives; it
never imports TEK runtime modules or edits files.
"""
from __future__ import annotations

import argparse
import re
import sys
import zipfile
from pathlib import Path, PurePosixPath

FORBIDDEN_ARCHIVE_PARTS = {
    ".git", ".pytest_cache", "__pycache__", "build", "dist", "logs", "trace", "release",
}
FORBIDDEN_ARCHIVE_SUFFIXES = {".exe", ".pyc", ".pyo", ".log", ".jsonl", ".zip"}
FORBIDDEN_ARCHIVE_NAMES = {"settings.json", "TacticEcho.lua"}
DIRECT_EVENT_CALL = re.compile(r"\b\w+\s*:\s*RegisterEvent\s*\(")
TOC_VERSION = re.compile(r"^## Version:\s*(.+)$", re.MULTILINE)
BOOTSTRAP_VERSION = re.compile(r'TE\.version\s*=\s*"([^"\n]+)"')


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _read_version(root: Path) -> str:
    value = _read_text(root / "VERSION").strip()
    if not value:
        raise ValueError("VERSION is empty")
    return value


def _toc_lua_paths(toc_text: str) -> list[str]:
    paths: list[str] = []
    for raw in toc_text.splitlines():
        line = raw.strip()
        if not line or line.startswith("##") or line.startswith("#"):
            continue
        if line.lower().endswith(".lua"):
            paths.append(line)
    return paths


def verify_repository(root: Path) -> list[str]:
    errors: list[str] = []
    addon = root / "addon" / "!TacticEcho"
    toc_path = addon / "!TacticEcho.toc"
    bootstrap_path = addon / "Core" / "Bootstrap.lua"

    for required in (root / "VERSION", toc_path, bootstrap_path, root / "TEKEXEBUILD.CMD"):
        if not required.is_file():
            errors.append(f"required file missing: {required.relative_to(root)}")
    if errors:
        return errors

    try:
        root_version = _read_version(root)
    except (OSError, ValueError) as exc:
        return [str(exc)]

    toc_text = _read_text(toc_path)
    bootstrap_text = _read_text(bootstrap_path)
    toc_match = TOC_VERSION.search(toc_text)
    bootstrap_match = BOOTSTRAP_VERSION.search(bootstrap_text)
    if not toc_match:
        errors.append("missing ## Version in addon/!TacticEcho/!TacticEcho.toc")
    if not bootstrap_match:
        errors.append("missing TE.version assignment in addon/!TacticEcho/Core/Bootstrap.lua")
    if toc_match and toc_match.group(1).strip() != root_version:
        errors.append(f"TOC version {toc_match.group(1).strip()!r} != VERSION {root_version!r}")
    if bootstrap_match and bootstrap_match.group(1) != root_version:
        errors.append(f"Bootstrap version {bootstrap_match.group(1)!r} != VERSION {root_version!r}")

    for relative in _toc_lua_paths(toc_text):
        candidate = addon.joinpath(*relative.replace("\\", "/").split("/"))
        if not candidate.is_file():
            errors.append(f"TOC Lua path missing: addon/!TacticEcho/{relative}")

    for lua_path in sorted(addon.rglob("*.lua")):
        if lua_path == bootstrap_path:
            continue
        if DIRECT_EVENT_CALL.search(_read_text(lua_path)):
            errors.append(f"direct RegisterEvent outside Bootstrap: {lua_path.relative_to(root)}")

    return errors


def verify_archive(archive: Path, expected_root: str | None, release_package: bool) -> list[str]:
    errors: list[str] = []
    if not archive.is_file():
        return [f"archive missing: {archive}"]

    with zipfile.ZipFile(archive) as bundle:
        members = [name for name in bundle.namelist() if name and not name.endswith("/")]
        if not members:
            return ["archive has no files"]
        roots = {PurePosixPath(name).parts[0] for name in members if PurePosixPath(name).parts}
        if len(roots) != 1:
            errors.append(f"archive must have one top-level root, found: {sorted(roots)}")
        root_name = next(iter(roots)) if len(roots) == 1 else None
        if expected_root and root_name != expected_root:
            errors.append(f"archive root {root_name!r} != expected {expected_root!r}")

        for name in members:
            path = PurePosixPath(name)
            parts = set(path.parts[1:]) if len(path.parts) > 1 else set()
            if parts & FORBIDDEN_ARCHIVE_PARTS:
                errors.append(f"forbidden generated path in archive: {name}")
            allow_release_exe = release_package and root_name and name == f"{root_name}/TEK.exe"
            if path.suffix.lower() in FORBIDDEN_ARCHIVE_SUFFIXES and not allow_release_exe:
                errors.append(f"forbidden generated suffix in archive: {name}")
            if path.name in FORBIDDEN_ARCHIVE_NAMES:
                errors.append(f"forbidden local file in archive: {name}")

        if root_name:
            required = (
                {
                    f"{root_name}/TEK.exe",
                    f"{root_name}/!TacticEcho/!TacticEcho.toc",
                    f"{root_name}/!TacticEcho/Core/Bootstrap.lua",
                }
                if release_package
                else {
                    f"{root_name}/VERSION",
                    f"{root_name}/TEKEXEBUILD.CMD",
                    f"{root_name}/addon/!TacticEcho/!TacticEcho.toc",
                    f"{root_name}/addon/!TacticEcho/Core/Bootstrap.lua",
                }
            )
            absent = sorted(required - set(members))
            errors.extend(f"required archive member missing: {name}" for name in absent)

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify Tactic Echo baseline structure and source archive hygiene.")
    parser.add_argument("--repo-root", type=Path, help="Repository root to verify.")
    parser.add_argument("--archive", type=Path, help="Source archive to verify.")
    parser.add_argument("--expect-root", help="Expected single top-level archive root.")
    parser.add_argument("--release-package", action="store_true", help="Allow the single release executable at <root>/TEK.exe.")
    args = parser.parse_args()

    if not args.repo_root and not args.archive:
        parser.error("provide --repo-root and/or --archive")

    errors: list[str] = []
    if args.repo_root:
        errors.extend(verify_repository(args.repo_root.resolve()))
    if args.archive:
        errors.extend(verify_archive(args.archive.resolve(), args.expect_root, args.release_package))

    if errors:
        print("Baseline contract failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print("Baseline contract passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
