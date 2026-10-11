"""Developer-only Lua 5.1 and TOC checks; never loaded by WoW."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def main():
    from lupa.lua51 import LuaRuntime

    toc = (ROOT / "TACTIC-ECHO-FOREVER.toc").read_text(encoding="utf-8")
    entries = [line.strip() for line in toc.splitlines() if line.strip() and not line.startswith("#")]
    assert entries == ["Config.lua", "Safety.lua", "Sequence.lua", "HudStyles.lua", "Profiles.lua", "Recommendation.lua", "Research.lua", "UI.lua", "UIComponents.lua", "SequenceEditor.lua", "HUD.lua", "Dispatch.lua", "Presentation.lua", "Transport.lua", "Runtime.lua", "Hotkeys.lua", "Core/Bootstrap.lua", "Bindings.xml"]
    assert "## Interface: 16001" in toc and "## SavedVariables: TEF_DB" in toc
    version = (ROOT / "VERSION").read_text().strip()
    assert version == "0.10.1" and f"## Version: {version}" in toc
    assert f'local VERSION = "{version}"' in (ROOT / "Core/Bootstrap.lua").read_text(encoding="utf-8")
    baseline = ROOT / f"docs/baselines/BASELINE_{version}.md"
    if not baseline.is_file():
        baseline = ROOT.parent / f"docs/baselines/tef/BASELINE_{version}.md"
    assert baseline.is_file()
    assert version in (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    lua = LuaRuntime(unpack_returned_tuples=True)
    assert lua.eval("_VERSION") == "Lua 5.1"
    for entry in entries:
        assert (ROOT / entry).is_file()
        if entry.endswith(".xml"):
            import xml.etree.ElementTree as ET
            tree=ET.parse(ROOT/entry)
            assert len(list(tree.getroot()))==6
            public = [b for b in tree.getroot() if b.attrib.get("header")=="TEF"]
            assert len(public)==1 and public[0].attrib["name"]=="TEF_TOGGLE_DISPATCH"
            assert "TEF_ToggleDispatchIntent()" in public[0].text
            continue
        lua.execute("assert(loadfile(...))", str(ROOT / entry))
        code = (ROOT / entry).read_text(encoding="utf-8")
        # Forbidden runtime dependencies/inputs and asynchronous advancement.
        assert not re.search(r"TacticEchoDB|TEProbeDB|C_Timer|CastSpell|RunMacro|SetCVar|TargetUnit|SendInput", code)
        if entry in ("UI.lua","UIComponents.lua","SequenceEditor.lua","HUD.lua","Dispatch.lua","Transport.lua","Core/Bootstrap.lua"):
            assert not re.search(r"(?:engine|self\.e|e)\.running\s*=", code)
            assert not re.search(r"Runtime\.intent\s*=", code)
        if entry=="HUD.lua":
            assert not re.search(r"Dispatch:Request|SecureActionButton|UseAction",code)
        if entry not in ("Transport.lua","HUD.lua"):
            assert "OnUpdate" not in code
    lua.globals().arg = lua.table_from([ROOT.as_posix()])
    lua.execute((ROOT / "tests/run.lua").read_text(encoding="utf-8"))
    # Independent TEK decoder/gate checks use its current unmodified source.
    if not (ROOT.parent / "tek/src/teap.py").is_file():
        print("Lua 5.1/TOC passed; TEK interoperability checks skipped outside TE workspace")
        return
    import sys
    sys.path.insert(0,str(ROOT.parent))
    from tek.src.teap import decode_fields, encode_fields_v3
    from tek.src.safety_gate import SafetyGate, SafetyContext
    from tek.src.action_catalog import RETRIBUTION_V2
    from tek.src.binding_tokens import encode_binding_token
    from tek.src.engine import TEKEngine
    from tek.src.profile_resolver import ProfileResolver
    protocol = LuaRuntime(unpack_returned_tuples=True)
    tef = protocol.table()
    protocol.execute((ROOT / "Transport.lua").read_text(encoding="utf-8"), "TEF", tef)
    for session,sequence,freshness in [(1,1,1),(65535,65535,65535),(24,257,513)]:
        fields=tef.Transport.Encode(session,sequence,freshness,0)
        raw=tuple(fields[i] for i in range(1,21))
        frame=decode_fields(raw)
        assert raw==encode_fields_v3(state="waiting",session_epoch=session,sequence=sequence,
            frame_freshness_counter=freshness,action_code=0,catalog_version=0,
            catalog_fingerprint=0,binding_token=0,in_combat=False,observation_only=True)
        allowed,reason=SafetyGate().evaluate(frame,SafetyContext(tek_armed=True),send_input=True)
        assert not allowed and reason=="observation_frame"
    # Existing TE uses ActionCode=0 for uncatalogued bound spells. Verify
    # this transport envelope with the existing engine and DRY RUN only.
    example = ROOT.parent / "examples/profiles/laptop.json"
    for binding in ["1","SHIFT-1","CTRL-Q"]:
        token=encode_binding_token(binding)
        fields=tef.Transport.Encode(91,10,11,1,token)
        assert tuple(fields[i] for i in range(1,21))==encode_fields_v3(state="armed",session_epoch=91,sequence=10,
            frame_freshness_counter=11,action_code=0,catalog_version=2,catalog_fingerprint=25732,binding_token=token,in_combat=False)
        frame=decode_fields(encode_fields_v3(state="armed",session_epoch=91,sequence=10,
            frame_freshness_counter=11,action_code=0,catalog_version=RETRIBUTION_V2.version,
            catalog_fingerprint=RETRIBUTION_V2.fingerprint16,binding_token=encode_binding_token(binding)))
        engine=TEKEngine(RETRIBUTION_V2,ProfileResolver.from_file(example))
        trace=engine.process_frame(frame,SafetyContext(bootstrapped=True))
        assert trace.accepted and trace.gatePassed and not trace.inputSent
        assert trace.action_id is None and trace.binding_token==frame.binding_token
        assert trace.dispatcher_backend=="dry_run"
    gate=SafetyGate(catalog=RETRIBUTION_V2,profile=ProfileResolver.from_file(example).profile)
    context=SafetyContext(bootstrapped=True,dispatch_budget=1)
    allowed,reason=gate.evaluate(frame,context,send_input=True)
    assert allowed,reason
    gate.mark_dispatched(frame,context,sent=True)
    following=decode_fields(encode_fields_v3(state="armed",session_epoch=91,sequence=11,
        frame_freshness_counter=12,action_code=0,catalog_version=2,catalog_fingerprint=25732,binding_token=token))
    allowed,reason=gate.evaluate(following,context,send_input=True)
    assert not allowed and reason=="dispatch_budget_exhausted"
    paused=tef.Transport.Encode(91,1,1,2)
    paused_frame=decode_fields(tuple(paused[i] for i in range(1,21)))
    context=SafetyContext(bootstrapped=True,dispatch_budget=1,require_start_toggle=True)
    allowed,reason=gate.evaluate(paused_frame,context,send_input=True)
    assert not allowed and reason=="frame_state_paused" and context.start_toggle_seen_disarmed
    allowed,reason=gate.evaluate(frame,context,send_input=True)
    assert allowed,reason
    from tek.src.physical_input import PhysicalInputPause
    from tek.src.dispatch_rate_limiter import DispatchRateLimiter
    for held_key in ("Q", "SHIFT"):
        now=[100.0]
        guard=PhysicalInputPause(profile="balanced",clock=lambda:now[0])
        engine=TEKEngine(RETRIBUTION_V2,ProfileResolver.from_file(example),physical_input_guard=guard,
            rate_limiter=DispatchRateLimiter(clock=lambda:now[0]))
        context=SafetyContext(bootstrapped=True)
        def process(seq):
            fields=tef.Transport.Encode(92,seq,seq,1,encode_binding_token("1"),True)
            return engine.process_frame(decode_fields(tuple(fields[i] for i in range(1,21))),context)
        initial=process(1)
        assert initial.gatePassed and not initial.inputSent
        guard.note_auto_dispatch(encode_binding_token("1"),1)
        guard.begin_manual_hold(held_key)
        held=process(2)
        assert held.reason=="manual_input_held" and not held.inputSent
        guard.end_manual_hold(held_key)
        now[0]+=.01
        assert process(3).reason=="manual_release_delay"
        now[0]+=.04
        assert process(4).reason=="manual_wait_freshness"
        now[0]+=.05
        recovered=process(5)
        assert recovered.gatePassed and not recovered.inputSent and recovered.dispatcher_backend=="dry_run"
        assert context.tek_armed and context.state!="ErrorLocked"
    print("Lua 5.1/TOC; 6 TEK decoder/dry-run cases, 3 exact packet encodings, 1 simulated budget and 2 manual-handoff cases passed")


if __name__ == "__main__":
    main()
