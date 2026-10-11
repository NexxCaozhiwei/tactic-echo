"""Read-only TEFSim import. Candidate metadata never certifies live availability."""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def literal(value):
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r') + '"'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    spell_file = args.source / "data/forever_catalog/mage_spells.json"
    talent_file = args.source / "data/talents_forever_book_0_37_1/mage_talents.json"
    spells = json.loads(spell_file.read_text(encoding="utf-8"))
    talents = json.loads(talent_file.read_text(encoding="utf-8"))
    lines = ['local _,TEF=...', 'local A=TEF.APL',
             '-- Generated candidate facts, UNVERIFIED; no effects or rank aliases.', 'A.Catalog={']
    for row in spells:
        p = row["parameters"]
        lines.append(' {id=%s,name=%s,rank=%s,learnLevel=%s},' % tuple(map(literal,
            [row["spell_id"], row["name"], p["rank"], p["learn_level"]])))
    lines += ['}', 'A.Talents={}; A.TalentNames={}; A.TalentIDs={}', 'local rows={']
    for row in talents:
        key = re.sub(r"[^a-z0-9]+", "_", row["name_en"].lower()).strip("_")
        # Stable public rule key, not a different classic talent implementation.
        if key == "winter_s_chill":
            key = "winters_chill"
        values = [key, row["name_zh_from_spell_catalog"] or row["name_en"],
                  row["name_en"], row["branch_name"].upper(), row["spell_id"],
                  row["node_id"], row["max_points"], row["passive"]]
        lines.append(' {%s},' % ','.join(map(literal, values)))
    lines += ['}', 'for _,r in ipairs(rows) do',
        ' A.Talents[r[1]]={key=r[1],name=r[2],englishName=r[3],tree=r[4],spellID=r[5],nodeID=r[6],maxRank=r[7],sourceStatus="unverified"}',
        ' A.TalentNames[r[2]]=r[1]; A.TalentNames[r[3]]=r[1]; A.TalentIDs[r[5]]=r[1]',
        ' if not A.Abilities[r[1]] then A.Abilities[r[1]]={key=r[1],name=r[2],school=r[4],type=r[8] and "passive" or "unclassified_active",unsupported="PASSIVE_OR_NEW_CAPABILITY_PENDING"} end',
        'end', 'A.CatalogSource={status="unverified",declaredTalentBuild="1.60.1.70170",spellRecords=%d,talentRecords=%d,' % (len(spells), len(talents)),
        ' spellSHA256=%s,talentSHA256=%s}' % (literal(hashlib.sha256(spell_file.read_bytes()).hexdigest()), literal(hashlib.sha256(talent_file.read_bytes()).hexdigest()))]
    (ROOT / "APL/Packs/Mage/Talents.lua").write_text('\n'.join(lines) + '\n', encoding="utf-8")
    print("Imported %d candidate spells and %d talents (unverified)" % (len(spells), len(talents)))


if __name__ == "__main__":
    main()
