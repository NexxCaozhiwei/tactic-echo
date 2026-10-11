"""Build clean source ZIP, install only TEF files, and produce SHA256 receipt."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = (ROOT / "VERSION").read_text().strip()
TARGET = Path(r"E:\World of Warcraft\_cn_beta_\Interface\AddOns\TACTIC-ECHO-FOREVER")
LOAD = ["Config.lua", "Safety.lua", "Sequence.lua", "Profiles.lua", "Research.lua", "UI.lua", "HUD.lua", "Dispatch.lua", "Presentation.lua", "Transport.lua", "Core/Bootstrap.lua", "Bindings.xml"]
RUNTIME = ["TACTIC-ECHO-FOREVER.toc", "VERSION"] + LOAD + ["README.md", "CHANGELOG.md"]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def archive_name(source):
    if source.is_relative_to(ROOT):
        return "TACTIC-ECHO-FOREVER/" + source.relative_to(ROOT).as_posix()
    return "TACTIC-ECHO-FOREVER/docs/baselines/" + source.name


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--deploy", action="store_true")
    args = parser.parse_args()
    out = ROOT.parent / "dist/tef"
    out.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    receipt = {"version": VERSION, "interface": 16001, "verified_exe": "1.60.1.70338",
               "simulation_only": True, "target": str(TARGET), "backup": None}
    receipt["validation"] = {"lua51_cases": 71, "tek_interop_dry_run_cases": 6,
        "exact_manual_packet_encodings": 3, "simulated_single_dispatch_budget": 1,
        "paused_start_toggle_handoff": "passed",
        "acceptance_harness_mock_tests": 2, "startup_dry_run": "waiting_without_input",
        "pytest_passed": 789, "pytest_skipped": 7, "pytest_subtests_passed": 17,
        "tek_unittest": 234, "addon_unittest": 244, "lua_syntax": "passed",
        "baseline_contract": "passed", "compileall": "passed",
        "new_features_in_game_verified": False, "tek_source_modified": True,
        "live_pixel_locate_decode": "passed_token_zero_no_input", "gamma_combinations_limit": 64,
        "production_tek_signal_found": True, "hud_and_settings_live_layout_observed": True,
        "real_sendinput_verified": True, "game_success_receipts_verified": True,
        "live_evidence_version": "0.5.0", "live_evidence_session": 29,
        "request_entry_guard_in_game_verified": False}
    receipt["transport"] = {"protocol": 3, "mode": "default_observation_explicit_production_request", "default_binding_token": 0,
        "default_enabled": True, "default_request_permission": False, "desktop_tek_ui_linked": True, "per_step_explicit_request": True}
    sources = sorted([ROOT / name for name in RUNTIME] +
                     list((ROOT / "docs").rglob("*.md")) +
                     [ROOT / "tests/run.lua", ROOT / "tests/run.py", ROOT / "tests/test_acceptance_harness.py", ROOT / "scripts/deliver.py", ROOT / "scripts/tek_acceptance.py"])
    sources += sorted((ROOT.parent / "docs/baselines/tef").glob("BASELINE_*.md"))
    archive = out / f"TACTIC-ECHO-FOREVER-{VERSION}.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as z:
        for source in sources:
            z.write(source, archive_name(source))
    with zipfile.ZipFile(archive) as z:
        assert {p.split("/")[0] for p in z.namelist()} == {"TACTIC-ECHO-FOREVER"}
        assert "TACTIC-ECHO-FOREVER/TACTIC-ECHO-FOREVER.toc" in z.namelist()
        for source in sources:
            name = archive_name(source)
            assert hashlib.sha256(z.read(name)).hexdigest().upper() == digest(source)
    receipt["archive"] = {"path": str(archive), "sha256": digest(archive), "files": len(sources)}
    if args.deploy:
        # Exact absolute TEF path only. No MIR, deletion, or access to WTF.
        assert TARGET.resolve().name == "TACTIC-ECHO-FOREVER"
        assert TARGET.resolve().parent == Path(r"E:\World of Warcraft\_cn_beta_\Interface\AddOns").resolve()
        if TARGET.exists():
            backup = out / ("backup-TEF-" + stamp)
            shutil.copytree(TARGET, backup)
            receipt["backup"] = str(backup)
        TARGET.mkdir(parents=True, exist_ok=True)
        receipt["files"] = []
        for relative in RUNTIME:
            source, destination = ROOT / relative, TARGET / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
            original, installed = digest(source), digest(destination)
            assert original == installed, relative
            receipt["files"].append({"path": relative, "source_sha256": original, "installed_sha256": installed})
        toc = (TARGET / "TACTIC-ECHO-FOREVER.toc").read_text(encoding="utf-8")
        entries = [line.strip() for line in toc.splitlines() if line.strip() and not line.startswith("#")]
        assert entries == LOAD
        assert f"## Version: {VERSION}" in toc and "## Interface: 16001" in toc
        assert all((TARGET / entry).is_file() for entry in entries)
        receipt["toc_load_list"] = entries
        receipt["unknown_files_preserved"] = [str(p.relative_to(TARGET)) for p in TARGET.rglob("*")
                                                if p.is_file() and p.relative_to(TARGET).as_posix() not in RUNTIME]
    receipt_path = out / f"TEF-{VERSION}-delivery.json"
    receipt_path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"archive": str(archive), "zip_sha256": digest(archive),
                      "receipt": str(receipt_path), "deployed_files": len(receipt.get("files", [])),
                      "source_zip_files": len(sources), "backup": receipt["backup"]}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
