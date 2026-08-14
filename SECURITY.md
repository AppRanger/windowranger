# Security policy

WindowRanger is pre-release software. The latest Beta is reviewed on a best-effort basis; Dev
builds and arbitrary source checkpoints are unsupported.

## Supported versions

| Version | Supported |
| --- | --- |
| Latest Beta | Best-effort review |
| Stable releases | None published |
| Dev builds and source checkpoints | Unsupported |

When Stable distribution begins, the intended policy is to support the latest Stable release and
continue reviewing the latest Beta on a best-effort basis. See the
[release-channel contract](docs/release-channels-and-branching.md).

## Reporting a vulnerability

Do not post suspected vulnerabilities, private diagnostics, or reproduction data in a public issue.

Use WindowRanger's
[private vulnerability reporting form](https://github.com/AppRanger/windowranger/security/advisories/new).
The report is visible only to repository maintainers and invited collaborators. Share the minimum
information needed to reproduce the issue, and remove window titles, documents, URLs, user file
paths and other personal data from logs or screenshots.

## Current support boundary

There is no vulnerability bounty, guaranteed response time, automatic update feed, or security
support promise for Dev builds. Automated tests and code review do not substitute for manual
security and privacy review, notarisation, and release-channel validation.

When reporting, include the affected commit or version, impact, reproduction steps, and the smallest
privacy-safe supporting material. Do not include real window titles, documents, URLs, user file
paths, credentials, or unrelated diagnostics.
