# WindowRanger agent instructions

These instructions apply to the entire repository.

## Sources of truth

Read the smallest relevant set before making changes:

- `README.md` — current product behaviour, setup, and documented limits.
- `TODO.md` — canonical work queue and evidence status.
- `ARCHITECTURE.md` — module boundaries, data ownership, and safety invariants.
- `CONTRIBUTING.md` — development setup, implementation principles, test isolation, and review
  requirements.
- `docs/release-channels-and-branching.md` — Stable, Beta, and Dev channel contract, branch bases,
  versioning, and promotion flow.
- `docs/first-github-release.md` — authoritative first-release build, notarization, artifact, tag,
  and draft-publication sequence.
- `docs/daily-development-workflow.md` — safe handoff between the installed daily copy and Xcode's
  development build on one Mac.
- `docs/permissions-and-privacy.md` — Accessibility and privacy boundaries.
- `SECURITY.md` — vulnerability-reporting rules; never put a suspected vulnerability in an issue.
- `docs/release-checklist.md` — release gates; checklist items do not authorise release actions.

When these documents disagree, preserve the safer behaviour and update the stale documentation as
part of the same scoped change. Do not create a second roadmap, contributor guide, or architecture
source of truth.

## Canonical work queue

`TODO.md` is the canonical queue for bugs, features, changes, validation, research, and release
work.

Before starting work:

1. Read `TODO.md` and the documentation linked by the relevant queue item.
2. Check whether the request already has a `WR-###` entry. Update that entry instead of creating a
   duplicate.
3. Preserve the distinction between implementation, automated verification, live validation, and
   completion.

While working:

- Capture newly reported work in **Inbox** when it is not part of the active request.
- Use the next unused `WR-###` identifier for a new entry.
- Record bugs as **User-observed** until they are reproduced or supported by diagnostics. Include
  observed behavior, expected behavior, reproduction context, and the evidence level.
- Give features and changes a smallest useful outcome and a concrete acceptance boundary.
- Update an item's scope when investigation materially changes what is known; do not silently grow
  implementation beyond the user's request.
- Treat **Needs decision** entries as research only. They are not approved for implementation.
- Treat **Held** release entries as non-authorizing. Do not publish, deploy, notarize, or change a
  shared/release environment without explicit maintainer approval.

Before handing off:

1. Update the relevant queue entry with its truthful status and current evidence.
2. If code is implemented and automated tests pass but signed-app/manual behavior remains untested,
   move or keep the item in **Live validation** rather than **Done**.
3. Mark an item **Done** only when its stated acceptance boundary is satisfied. Keep a short result
   in `TODO.md` and put durable implementation detail in the relevant design or architecture doc.
4. Mention any newly discovered follow-up, blocker, or human-validation boundary in the queue.

Keep `README.md`, relevant design docs, and `TODO.md` consistent about what is implemented, tested,
live-validated, deferred, or research-only.

## Git and branches

- `main` is the Stable branch. `develop` is the Dev integration branch and the normal base and target
  for new work. Follow `docs/release-channels-and-branching.md` for release and hotfix promotion.
- When an agent is asked to create an ordinary branch, start from `develop` and use
  `codex/<work-item>-<short-topic>` in lowercase kebab-case, for example
  `codex/wr-011-project-hygiene`. If no work item exists, use `codex/<short-topic>`.
- For release or hotfix work, use the base and target required by the release-channel document; keep
  the `codex/` prefix for an agent-owned auxiliary branch rather than impersonating a maintainer-owned
  `release/*` or `hotfix/*` branch.
- Human topic branches should use `fix/`, `feature/`, `docs/`, or `chore/` followed by an optional
  `wr-###-` and a short lowercase kebab-case topic. Ordinary human topic branches also start from
  and merge into `develop`.
- Do not create or switch branches, commit, stage, push, open a pull request, or alter repository
  settings unless the active request includes that action.
- Never stage or rewrite unrelated user-owned changes. Inspect `git status` and the targeted diff
  before and after editing.
- Keep commits to one logical checkpoint. Use an imperative summary that describes the outcome;
  include the `WR-###` identifier when there is one.
- Do not amend, rebase, force-push, delete branches, or rewrite history unless explicitly requested.

## Error handling

Do not fight repeated errors. When the same error occurs twice, research the web and identify three
to five plausible fixes. Choose the most efficient suitable solution, implement it, and record any
remaining blocker or follow-up in `TODO.md`.

## Repository safety

- Preserve user-owned and unrelated working-tree changes.
- Do not launch, stop, replace, or automate the user's running WindowRanger during background
  verification.
- Follow the live-window and test-isolation boundaries in `CONTRIBUTING.md`.
- Prefer deterministic, non-hosted tests. Live Accessibility, display, focus, and input behavior
  remains a separate human-validation boundary.
- Use `apply_patch` for hand-authored file edits. Regenerate `WindowRanger.xcodeproj` from
  `project.yml` only when project membership or build settings change; do not hand-edit generated
  project output.
- Never publish, deploy, notarise, sign a distributable build, change a shared/release environment,
  or use production credentials without explicit maintainer authorisation.
- Do not add Sparkle, appcasts, update keys, channel settings, or release automation until an active
  request explicitly moves that held work into scope.
- `scripts/install-daily.sh` is never a distribution path. Public artifacts must come from
  `scripts/build-distribution.sh` and pass the release runbook.
- Never run the credentialed distribution or GitHub-release scripts, create/push a release tag,
  change repository visibility, or publish a draft without explicit maintainer authorization for
  that release checkpoint.
