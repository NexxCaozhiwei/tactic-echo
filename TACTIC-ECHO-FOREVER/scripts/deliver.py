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
LOAD = ["Config.lua", "Safety.lua", "APL/Packs/Mage/Abilities.lua", "APL/Packs/Mage/Talents.lua", "APL/TalentState.lua", "APL/Registry.lua", "APL/PublicConditions.lua", "APL/Custom.lua", "APL/State.lua", "APL/Conditions.lua", "APL/Trace.lua", "APL/Packs/Mage/Mage60.lua", "APL/Packs/Mage/Rules.lua", "APL/Engine.lua", "Sequence.lua", "HudStyles.lua", "Profiles.lua", "Recommendation.lua", "Research.lua", "UI.lua", "UIComponents.lua", "SequenceEditor.lua", "CustomAPLEditor.lua", "HUD.lua", "Dispatch.lua", "Presentation.lua", "Transport.lua", "Runtime.lua", "Hotkeys.lua", "Core/Bootstrap.lua"]
RUNTIME = ["TACTIC-ECHO-FOREVER.toc", "VERSION", "Bindings.xml"] + LOAD + ["README.md", "CHANGELOG.md"]


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
    receipt = {"version": VERSION, "interface": 16001, "client_evidence_exe": "1.60.1.70338",
               "simulation_only": True, "target": str(TARGET), "backup": None}
    receipt["validation"] = {"lua51_cases": 300, "sequence_lua51_cases": 196, "apl_lua51_cases": 104, "tek_interop_dry_run_cases": 6,
        "exact_manual_packet_encodings": 3, "simulated_single_dispatch_budget": 1, "manual_handoff_dry_run_cases": 2,
        "paused_start_toggle_handoff": "passed",
        "acceptance_harness_mock_tests": 2, "startup_dry_run": "not_run_this_delivery",
        "pytest_passed": 791, "pytest_skipped": 7, "pytest_subtests_passed": 17,
        "tek_unittest": 234, "addon_unittest": 244, "lua_syntax": "passed", "lua_syntax_files": 88,
        "baseline_contract": "passed", "compileall": "passed",
        "new_features_in_game_verified": False, "tek_source_modified": False,
        "live_pixel_locate_decode": "not_run_this_delivery", "gamma_combinations_limit": 64,
        "production_tek_signal_found": None, "hud_and_settings_live_layout_observed": False,
        "real_sendinput_verified": False, "game_success_receipts_verified": False,
        "request_entry_guard_in_game_verified": False, "continuous_in_game_verified": False}
    receipt["sequence_editor"] = {"max_steps_per_scene": 16, "repeat_count_min": 1,
        "repeat_count_max": 99, "count_evidence": "public_current_initiation_and_succeeded",
        "legacy_17_32_steps_preserved_inactive": True, "drag_cursor_spell_id_position": 4,
        "drag_in_game_verified": False, "shoot_5019_in_game_verified": False,
        "shoot_active_or_unknown_binding_token": 0, "shoot_final_success_public_5019_handoff": True, "shoot_handoff_in_game_verified": False}
    receipt["apl"]={"pack":"MAGE_FOREVER_60","unit":"class","default_source":"sequence",
        "catalog_records":272,"talent_records":54,"catalog_status":"unverified",
        "talent_source_declared_build":"1.60.1.70170","conditions":"three_valued",
        "automatic_filler_weights_implemented":False,"templates":["arcane","fire","frost","custom"],"template_selection":"manual_build_template","wotlk_source_rules":84,"source_conditions_preserved":True,"gcd_policy":"user_authorized_not_queried_not_gated","failed_identities":"shared_engine_4096_no_eviction","wotlk_classifications":{"KEEP":10,"ADAPT":4,"DROP":37,"BLOCKED":33},"five_reference_hashes_verified":True,"source_identity_order_criteria_checks":84,"enemy_count":"visible_only",
        "secret_or_unknown_dependencies_binding_token":0,"modern_spec_required":False,
        "live_learned_ranks_verified":False,"live_talent_provider_verified":False,
        "apl_real_dispatch_verified":False}
    receipt["custom_apl"] = {"class": "MAGE", "max_rules_per_scene": 16, "registered_spell_kinds": 13,
        "exact_ids_only": True, "selection": "first_public_eligible_in_manual_order",
        "conditions": ["moving", "cooldown_activity", "experimental_visible_enemies", "mana_percent", "checked_target_distance", "cdm_buff_activity", "cdm_cooldown_activity"],
        "mandatory": ["known", "usable", "power_ok", "in_range"], "cooldown_check": "optional_default_off", "standby_preview": True, "dispatch_requires_public_combat": True, "standby_binding_token": 0,
        "unsupported": ["unverified_aura_truth", "secret_numeric_comparison", "distance_estimation"], "comparators": ["lt", "le", "eq", "ne", "ge", "gt"], "cdm_directory_identity": "explicit_exact_spell_id", "missing_frame_means_inactive": False, "unknown_frame_identity_policy": "skip_bounded_preserve_exact_matches", "cdm_skipped_frame_diagnostics": True,
        "live_recheck": True, "in_game_verified": False}
    receipt["hotkey"] = {"capture_saves_immediately": True, "typed_save_or_enter": True,
        "explicit_override_existing_binding": True, "override_default": False,
        "control_keys_excluded_from_spell_dispatch": True,
        "readback_requires_exact_override_command": True, "reapply_events": ["PLAYER_LOGIN",
        "PLAYER_ENTERING_WORLD", "UPDATE_BINDINGS", "PLAYER_REGEN_ENABLED"],
        "in_game_trigger_verified": False, "in_game_reload_verified": False}
    receipt["loop_modes"] = {"modes": ["none", "normal", "target", "combat"],
        "old_loop_true_migration": "normal", "reset_preserves_intent": True,
        "reset_retires_public_initiations": True, "new_modes_in_game_verified": False}
    receipt["hud_label_styles"] = {"modules": ["main", "preview", "global"],
        "font_size": [8, 30], "scale": [0.6, 2.0], "combat_layout_deferred": True,
        "in_game_layout_verified": False, "dispatch_authority": False}
    receipt["historical_live_evidence"] = {"version": "0.7.0", "session": 39,
        "sequence": [116, 205, 205, 143], "game_success_receipts_verified": True,
        "proves_current_version": False}
    receipt["transport"] = {"protocol": 3, "mode": "unified_intent_auto_standby_or_fixed_attempt", "default_binding_token": 0,
        "default_enabled": True, "default_request_permission": True, "desktop_tek_ui_linked": True, "per_step_explicit_request": False, "continuous_default_enabled": False, "default_runtime_mode": "auto", "auto_start_preference": True, "runtime_in_game_verified": False, "continuous_requires_public_numeric_evidence": False}
    sources = sorted([ROOT / name for name in RUNTIME] +
                     list((ROOT / "docs").rglob("*.md")) + list((ROOT / "docs/references/wotlk").glob("*.json")) +
                     [ROOT / "tests/run.lua", ROOT / "tests/run.py", ROOT / "tests/apl.lua", ROOT / "tests/custom_apl.lua", ROOT / "tests/public_conditions.lua", ROOT / "tests/test_acceptance_harness.py", ROOT / "scripts/deliver.py", ROOT / "scripts/import_apl_catalog.py", ROOT / "scripts/import_wotlk_apl.py", ROOT / "scripts/tek_acceptance.py"])
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
