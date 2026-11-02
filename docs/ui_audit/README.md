# UI audit data

`before/report.json` is the first run of `tools/ui_overlap_check.gd` over the game as it was before the fixes; `report.json` is the latest run.
`docs/ui_audit.md` is generated from them (`python3 tools/ui_audit_report.py`).

The pictures (every state at six sizes, each problem outlined in red) are not stored in the repository. Every CI run writes them to the
`ui-overlap-pictures` artifact of the run; or make them locally: `xvfb-run -a godot --path . --rendering-driver opengl3 --script tools/ui_overlap_check.gd -- shots=<dir>`.
