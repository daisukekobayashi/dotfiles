# Security Policy

This repository is public. Anyone can read every tracked file, its full
history, and its pull requests and issues. Removing a committed value later
needs a history rewrite and does not recall copies already made.

## Assets

These are categories. This file and the rest of the repository never list
actual values.

- Personal identifiers: real names, email addresses, phone numbers, postal
  addresses, and account or user IDs of the owner or other people.
- Employer, customer, and organization names: any organization the owner
  works for or with, other than the public vendors and projects the tooling
  already depends on.
- Internal hostnames: names, IP addresses, and URLs of private networks,
  machines, or services.
- Absolute paths that contain a real user name, such as a home directory.
- Credentials: tokens, API keys, passwords, private keys, certificates, and
  connection strings.
- Agent logs and transcripts: session logs, conversation exports, delivery and
  review records, and tool output copied from them.

## Attackers

- Public readers: anyone who reads the repository, its history, forks, pull
  requests, or issues, including crawlers and indexers. Committing an asset
  discloses it to them, even when the developer commits it.

The default attacker positions of the security review still apply.

## CI secret scan

The trusted PR scan gets its workflow, scanner, and allowlist from the same
reviewed default-branch revision and reads PR commits as Git data. In Actions,
confirm that the **Trusted PR secret scan** job ran and succeeded on a
`pull_request_target` run matching the PR number and its recorded
`baseRefOid` and `headRefOid`. A missing or skipped job leaves the range
unverified. The push scan provides advisory detection after publication. The
local staged scan checks contents before commit. See
[Testing](docs/testing.md#sensitive-changes) for event eligibility and the
Actions event policy.

## Sensitive paths

This file names no sensitive paths. The root `AGENTS.md`
`## Delivery sensitive paths` section is their single source.
