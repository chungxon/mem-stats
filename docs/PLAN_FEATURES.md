# MemStats Feature Plan: Support Us, Theme, Languages and Glass

This plan replaces the removed implementation and is intentionally split into four reviewable
tasks. No task should be marked complete until its code, tests and documentation are reviewed.

## Product decisions

| Feature | Location | Default / options |
| --- | --- | --- |
| Support Us | Context menu and Settings | Opens the GitHub Sponsors page |
| Theme | Settings | `System`, `Light`, `Dark`; default `System` |
| Language | Settings | System plus common languages; applies without restart |
| Glass background | Settings | Off by default; On uses a visibly translucent background |

Shared rules:

- Keep the existing native macOS layout and solid-color path as the fallback.
- Do not add gradients or an in-app payment flow.
- Preserve process names, user names, paths, versions and system values exactly as collected.
- Each task gets its own commit and review gate. Do not stage unrelated task changes.
- Run Swift format lint, build and relevant tests for every changed Swift file before the review.

## Feature Task 1 - Support Us

Objective:

- Add a Support Us action that opens the exact GitHub Sponsors page:
  `https://github.com/chungxon/MemStats/`.

Placement:

- Add `Support Us…` to the context menu near Settings/About.
- Add a Support Us section and `Sponsor this project` action in Settings.

Implementation:

- Add `AppLinks.sponsorURL` and reuse the existing `NSWorkspace` or SwiftUI `openURL` path.
- Keep the action independent of theme, language and sampling state.
- Keep the UI usable when the default browser cannot open the URL.
- Use the current English strings for this first task; Task 3 owns localization of all visible
  copy, including Support Us.

TODO:

- [x] Add the exact Sponsor URL to `AppLinks`.
- [x] Add the context-menu action.
- [x] Add the Settings section and action.
- [x] Add the URL test and verify both action wiring.
- [x] Update the feature plan and relevant product documentation.

Acceptance criteria:

- Support Us is discoverable in both required locations.
- Both actions open the exact Sponsor URL.
- No payment SDK, network client or account flow is added.

Suggested commit:

`feat(settings): add support us sponsor link`

Review gate: stop for review before Feature Task 2.

## Feature Task 2 - Theme

Objective:

- Add `System`, `Light` and `Dark` theme selection in Settings and apply it immediately.

Implementation:

- Add a typed, persisted `AppTheme` setting with `System` as the default.
- Map the setting through one shared appearance helper to SwiftUI and AppKit.
- `System` must remove the explicit override and follow the current macOS appearance.
- Update an already-open popover and Settings window without relaunching.
- Keep menu-bar pressure colors and status text behavior unchanged.

TODO:

- [x] Add and validate the persisted theme setting.
- [x] Add the Settings picker.
- [x] Apply the theme to the popover and self-managed Settings window.
- [x] Add focused mapping and persistence tests.
- [ ] Verify readable controls, charts, menus and alerts in all three modes.

Acceptance criteria:

- Theme changes are visible immediately.
- Relaunch restores the chosen theme.
- Invalid stored values fall back to `System`.
- System mode tracks macOS appearance changes.

Suggested commit:

`feat(theme): add system light and dark themes`

Review gate: stop for review before Feature Task 3.

## Feature Task 3 - Common languages

Objective:

- Add an in-app language picker whose selection updates the app immediately without restart.

Supported choices:

- `System`, `English`, `Tiếng Việt`, `简体中文`, `日本語`, `한국어`, `Español`, `Français`,
  `Deutsch`.

Implementation:

- Add a typed, persisted `AppLanguage` setting with `System` as the default.
- Use an Apple String Catalog with English source strings and the initial common-language
  translations.
- Inject the selected locale into Settings and the popover. Rebuild AppKit menus, alerts,
  tooltips and accessibility labels using the current selection.
- `System` follows the macOS preferred language. Missing translations fall back to English.
- Never translate process names, users, paths, versions or system values.
- Support Us copy from Task 1 must be localized here.

TODO:

- [x] Add and validate the persisted language setting.
- [x] Add the picker with native language names.
- [x] Add the String Catalog and common-language translations.
- [x] Localize SwiftUI and AppKit visible copy, dynamic formats and accessibility text.
- [x] Re-render cached errors and status text when the language changes.
- [x] Add tests for persistence, locale selection and live updates.
- [x] Verify long translations and fallback behavior.

Acceptance criteria:

- Changing language updates an open Settings window and popover immediately.
- Newly opened menus and alerts use the selected language.
- No restart is required.
- Missing entries safely show English.

Suggested commit:

`feat(localization): add live common-language selection`

Review gate: stop for review before Feature Task 4.

## Feature Task 4 - Glass background

Objective:

- Add a real translucent Glass background that visibly reveals the desktop or window content
  behind the app, while preserving a readable solid fallback.

Implementation requirements:

- Add an independent persisted Glass toggle in Settings, default Off.
- Target macOS 14 with `NSVisualEffectView`, not `.glassEffect`.
- Use a true behind-window effect: the popover and Settings window backgrounds must be clear or
  non-opaque where the material is applied, and the visual effect must use an appropriate
  `blendingMode` such as `.behindWindow`.
- Keep charts, tables, controls and status badges on readable native surfaces instead of
  stacking opaque cards over the material.
- Turning Glass Off must restore the existing solid background with no layout change.
- Respect Accessibility Reduce Transparency by using the solid fallback even when the preference
  remains enabled.
- Verify the effect in both System/Light/Dark themes and on a desktop with a visible wallpaper.

TODO:

- [x] Add and validate the persisted Glass setting.
- [x] Add the Settings toggle and explanatory copy.
- [x] Implement a reusable AppKit/SwiftUI translucent background wrapper.
- [x] Make the popover and Settings window backgrounds actually transparent for the Glass path.
- [x] Reduce popup card opacity when Glass is enabled so the material remains visible.
- [x] Add a persisted Glass opacity control that applies immediately to both surfaces.
- [x] Apply the latest published Glass and opacity values on every toggle, including Off → On.
- [x] Use a frosted popover material instead of the more transparent under-window material.
- [x] Replace the nested NSPopover backgrounds with one window-level native blur surface.
- [x] Keep Settings readable with native blur and adjustable tint instead of using opacity alone.
- [x] Lighten the tint and popup card surfaces further at the same saved slider value.
- [x] Blend a small amount of the unblurred backdrop through the native material in both windows.
- [x] Add Reduce Transparency fallback and tests for the resolver.
- [x] Keep popup cards and chart overlays on solid surfaces when Reduce Transparency is enabled.
- [x] Resolve Glass tint and solid fallback in the window's selected Light or Dark appearance.
- [ ] Verify the desktop is visibly seen through both windows and readability is preserved on-device.

Acceptance criteria:

- Glass On visibly shows content behind the popover and Settings window.
- Glass Off is visually solid and keeps the same layout.
- Reduce Transparency never forces a translucent surface.
- No opaque root background silently hides the material effect.

Suggested commit:

`feat(ui): add true translucent glass background`

Review gate: stop for final QA and documentation review.

## Feature task checklist

- [x] Feature Task 1 - Support Us
- [x] Feature Task 2 - Theme
- [x] Feature Task 3 - Common languages
- [ ] Feature Task 4 - Glass background
