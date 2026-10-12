# Local project split — 2026-10-12

Split date: 2026-10-12 (Asia/Shanghai).
Source commit: `3e57b9d1713ad3c9d821b416dc073452289c2691`.
Original shared repository / remaining Retail TE: `G:\Desktop\CODES\tactic-echo`.
New local sibling TEF: `G:\Desktop\CODES\Tactic Echo Forever`. These are documentation paths only.

Rollback: pre-te-tef-split; full dirty-worktree backup:
`G:\Desktop\CODES\_project-split-backups\tactic-echo-20261012-084826`.
1,310 backup files checked by SHA256. 31 modified/untracked source files were
copied to the independent TEF clone before removal from TE.

TE scope: Retail addon/!TacticEcho, own tek/, tests/unit, Retail tools/docs.
Retired reaction/control/defensive/survival modules remain retired. No Retail
AddOn runtime code was changed by this split. Version remains 1.5.12.
TEF scope: Forever/Infinite, Classic60, class/talents/learned exact ranks,
APL/Secret Value, fixed sequence and own TEF TEK; version remains 1.0.1.

TEK was copied into both projects at the split point.
From this point forward, TE TEK and TEF TEK may evolve independently.
No automatic code synchronization; no shared directories, submodules,
symlinks or junctions. Both projects work without the sibling checkout.

TEK config/identity: TE remains %LOCALAPPDATA%/TacticEcho and TEK.exe;
TEF uses %LOCALAPPDATA%/TacticEchoForever, TEF TEK title, TEK-TEF.exe,
TEF trace/status/build metadata and safe read-only settings/profile migration.
CLI lifecycle scripts match only their own managed checkout paths; ambiguous
bare module processes are left untouched rather than stopping the other host.
No existing executable was stopped/replaced; builds output to isolated dist.

Protocol: namespaces TE / TEF documented. TEAP v3 wire unchanged and not
project-identifying; only one AddOn signal source should be enabled at a time.
No new input channel or authorization bypass. SavedVariables stay distinct:
TacticEchoDB versus TEF_DB. No game/WTF data was modified.

Removal: 140 TEF-only source/doc/script paths, including
135 tracked files; remaining untracked source and old TEF packages were moved
to the backup after the verified TEF commit. TEF copy removed370 Retail-only
files. Gamma/CRC codec tests are actually shared and were preserved here under
test_colour_transport_compat.py; they do not import either AddOn. Classification
is in split-file-classification.json. UNRESOLVED_SHARED_FILES: none.

README declares Retail-only scope. AGENTS removes Classic60/APL constraints
and retains existing Retail safety/scope. CI: no .github workflows existed.
Retail packaging/test discovery no longer includes the independent project.
Both source histories/branches/tags are retained; no filter-repo/filter-branch.
TE origin is unchanged. TEF origin was renamed source with disabled push URL.

No remote push was performed.

## Retail validation after removal

PASS: baseline; 614 pytest cases (182 environment skips, 17 subtests); 234 TEK
unittest cases; 244 AddOn unittest cases (4 skipped); compileall; 54 Lua5.1
syntax files. A temporary isolated copy with no sibling and no PYTHONPATH also
passed baseline and the same full pytest suite. PASS: isolated TEK.exe build.
Retail AddOn files and the pre-existing dist/TEK.exe match the safety backup
byte for byte. NOT_RUN: executable startup smoke and live Windows/game input.
