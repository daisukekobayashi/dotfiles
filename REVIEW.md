# Review Policy

This policy applies to `change-review` and `change-adversarial-review`.
`change-security-review` takes its threat model from `SECURITY.md`.

## What failure looks like

- **Public exposure:** a change that introduces an instance of an asset
  category listed in `SECURITY.md` into any tracked file is a material defect,
  in code, comments, documentation, tests, fixtures, eval files, and records
  alike. Check every commit that would be published, the branch's commits since
  the recorded base, not only the net diff. The finding closes only when none
  of those commits contains the value; a later commit that removes it does not
  close it. Closing it needs the branch history rewritten before publication,
  which needs the owner's explicit approval. An existing value that the change
  only moves is `pre-existing`.
- **Unlisted authority rule:** a change that adds or weakens a rule that
  grants, limits, or gates agent authority in a skill file that is not
  sensitive under the root `AGENTS.md` at the recorded base, because an
  `exclude` entry matches the file and no `add` entry matches it, is a
  material defect, unless the same change adds an `add` entry that matches
  the file. Authority rules are approval for commit, push, merge, cleanup, or
  remote writes; read-only limits; code execution; permission, allowlist, or
  hook rules; and the tier and security review selection.

## Focus areas

Check these in addition to the usual review focus, not instead of it:

- Recognize assets by shape, since no list of values exists: a home directory
  path with a real account name, a hostname or address that is not a
  documentation example, an employer or customer name in prose or
  configuration, credential-like strings, and pasted session logs,
  transcripts, or delivery records.
- Placeholders are acceptable: `~`, `$HOME`, `<user>`, `example.com` and other
  reserved example domains, documentation IP ranges, and clearly fake values.
- Report an exposure by its category and location; never quote the value.
