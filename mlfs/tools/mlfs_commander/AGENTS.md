# MLFS Commander Agent Notes

This directory is for the planned MLFS Commander graphical file manager. See
`README.md` for the project description, architecture, and implementation
breakdown.

## Preferred Direction

- Use C++ with Qt 6 for the GUI.
- Link directly against `mlfs/lib` for raw MLFS image handling.
- Keep SDL3 out of the main application unless a future feature specifically
  needs custom realtime rendering.

## Local Constraints

- Keep `mlfs/lib` as the source of truth for image and partition operations.
- Do not duplicate MLFS on-disk parsing in the GUI unless the library lacks a
  necessary read-only inspection helper.
- Treat image writes carefully: one writer per image, explicit confirmations for
  destructive operations, and refresh views from MLFS after writes.
- Keep cli application un-touched.
