# Back up note directories whose paths contain spaces (#42)

`bin/sync-notes.sh` copies a notes directory into a dated backup under a backup
root and keeps the newest five backups. Users keep their notes in folders such
as `My Notes`, and the script breaks on them.

## Acceptance Criteria

1. `bin/sync-notes.sh "<source>" "<backup root>"` backs up a source directory
   whose path contains spaces.
2. A backup root whose path contains spaces works the same way.
3. Backups beyond the newest five are removed from the backup root, and
   nothing outside the backup root is removed.
