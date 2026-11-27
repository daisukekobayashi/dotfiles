# Progress record: example/notes-sync#42

[scope S1] Task #42 (ISSUE.md): back up note directories whose paths contain spaces; acceptance criteria 1-3.
[decision A1] Agreed with the user: paths with spaces stay supported for both the source and the backup root, and the command-line arguments do not change.
[tier T1] Medium at head 1a2b3c4d5e6f.
[review R1] r1 full review at head 1a2b3c4d5e6f: change-review and change-adversarial-review.
[finding r1-CR1] r1 change-review, Medium, introduced, bin/sync-notes.sh:12: "`cp -R $SRC $DEST` splits a source directory whose path contains a space into two arguments, so criterion 1 fails."
[disposition D1] r1-CR1 -> fixed: quoted "$SRC" and "$DEST" at bin/sync-notes.sh:12 and added tests/sync_spaces_test.sh (a source path with a space); verified at head 7f8e9d0c1b2a.
[review R2] r2 focused follow-up at head 7f8e9d0c1b2a: change-review and change-adversarial-review.
