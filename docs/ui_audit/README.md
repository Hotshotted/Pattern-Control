# UI audit pictures

Every screen, panel, popup, tab and state of the game at six screen sizes, written by `tools/ui_overlap_check.gd` (see `docs/ui_audit.md`):

* `before/<size>/<screen>.jpg`: the screens that had a problem, as they were when the tool was first run, each problem outlined in red;
* `before/report.json`: the problems found then (the numbers in `docs/ui_audit.md`);
* `<size>/<screen>.jpg`: the same screens after the fixes (a red outline would be a problem still open).

Sizes are logical points: 320x568 (iPhone SE 1st gen), 375x667 (SE 2/3), 390x844 (iPhone 14), 430x932 (14 Pro Max), 768x1024 (iPad), 1280x720 (landscape web).
Pictures are scaled so that the long side is at most 640 pixels.
