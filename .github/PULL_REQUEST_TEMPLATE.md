## Summary

<!-- What problem does this solve, and what changed? -->

## Related issue

<!-- Use "Closes #123" when applicable. Explain why no issue was needed for a small change. -->

- [ ] This targets `develop`, unless it is an authorised `release/*` or `hotfix/*` promotion to
      `main`.

## Validation

<!-- List exact commands and results. Separate automated evidence from signed-app/live testing. -->

- [ ] I ran `./scripts/verify-test-isolation.sh`.
- [ ] I ran the smallest relevant tests.
- [ ] I ran the complete non-hosted suite, or explained why it is not needed.
- [ ] I described any signed-app, Accessibility, multi-display, or other live validation still needed.

## Safety and scope

- [ ] The change is focused and follows `CONTRIBUTING.md` and `ARCHITECTURE.md`.
- [ ] Tests do not launch the app, request permissions, register hotkeys, change login items, access
      iCloud, write private diagnostics, or manipulate live windows.
- [ ] Diagnostics and fixtures contain no window titles, document names, URLs, typed content, full
      user paths, credentials, or private screenshots.
- [ ] User-facing behaviour and relevant documentation are updated.
- [ ] I reviewed all submitted code, including any produced with automated or AI-assisted tools.

## Screenshots or diagnostics

<!-- Optional. Include only privacy-safe material and explain what it demonstrates. -->
