# Security policy

WindowRanger is pre-release software under active private development. There are no supported public
releases yet.

## Supported versions

| Version | Supported |
| --- | --- |
| Public releases | None published |
| Current `main` branch | Reviewed on a best-effort basis |

Once public distribution begins, the intended policy is to support the latest Stable release and
review the latest Beta on a best-effort basis. Dev builds remain unsupported. The exact support
window must be confirmed before the first public release; see the
[release-channel contract](docs/release-channels-and-branching.md).

## Reporting a vulnerability

Do not post suspected vulnerabilities, private diagnostics, or reproduction data in a public issue.

The repository is currently private and GitHub private vulnerability reporting is not enabled.
Existing collaborators should report a vulnerability to the maintainer through their established
private project channel. Before the repository is made public, maintainers must enable
[private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/working-with-repository-security-advisories/configuring-private-vulnerability-reporting-for-a-repository)
or publish another verified private contact and update this policy.

Until then, people with an existing private relationship to the maintainer should use that existing
channel and share the minimum information needed to reproduce the issue. Remove window titles,
documents, URLs, user file paths and other personal data from logs or screenshots.

## Current support boundary

Only the current development branch is examined during active work. There are no security-support
windows, signed public downloads, update feed, vulnerability bounty, or guaranteed response time.
Automated tests and code review do not substitute for later manual security and privacy review,
notarisation, and release-channel validation.

When reporting, include the affected commit or version, impact, reproduction steps, and the smallest
privacy-safe supporting material. Do not include real window titles, documents, URLs, user file
paths, credentials, or unrelated diagnostics.
