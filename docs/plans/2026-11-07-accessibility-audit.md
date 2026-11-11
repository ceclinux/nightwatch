# Accessibility Nutrition Labels: audit and draft answers (7 November 2026)

Owner asked for the audit and a draft, not for the declaration to be made. Nothing has been declared in App Store Connect (App Store Connect > App Accessibility
still shows "Get Started", checked 7 November 2026).

## What Apple requires (read 7 November 2026)

From Apple's [Overview of Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/)
and the [Larger Text](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/larger-text-evaluation-criteria/) and
[Reduced Motion](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/reduced-motion-evaluation-criteria/) criteria pages:

- Nine features: VoiceOver, Voice Control, Larger Text, Dark Interface, Differentiate Without Color Alone, Sufficient Contrast, Reduced Motion, Captions, Audio Descriptions.
- **Larger Text is not supported on the Mac label.**
- A feature may be claimed only if users can complete **all the common tasks** of the app with it: the primary functionality, plus first launch, login, purchase and settings.
- **Per device.** Assess and answer for each device the app supports (iPhone, iPad, Mac).
- The developer is responsible for accuracy (Guideline 2.3); App Review may ask for a label to be corrected. Labels are voluntary now and Apple says they will become required.
- Re-evaluate on every update (the Sufficient Contrast and Reduced Motion pages say so).
- Not read from Apple's full text (the search summary said it, the fetched page did not confirm it): that the label can be edited at any time without a new version. Check on the page when declaring.

## Common tasks for Nightwatch (the list every test below walks)

1. First launch: the welcome screen, then choosing or adding a site (use a public site such as Malham Tarn).
2. Read tonight: sky score, clear window, the night arc, the best targets.
3. Turn alerts on and change alert settings (Settings).
4. Open Tonight's plan; heart a target; take one off for tonight and put it back.
5. Browse Targets by type, open a target page, read "How to shoot this", add to tonight's plan.
6. Open the week ahead and open a night's plan.
7. Set the horizon (mark a direction, or measure from a photo).
8. Find a dark site and open it in Maps.
No login and no purchase exist in the app (no accounts, free, no in-app purchases).

## Evidence in the code, per feature

| Feature | iPhone and iPad | Mac | Evidence (found 7 November 2026) | Verdict |
|---|---|---|---|---|
| Dark Interface | yes | yes | iPhone/iPad: `UIUserInterfaceStyle: Dark` in `Phone/project.yml` and `.preferredColorScheme(.dark)` in `Theme.swift`. Mac: `.preferredColorScheme(.dark)` on Tonight, Targets, Settings, Numbers and Welcome | **Supported.** Declare after a glance at each window. |
| Reduced Motion | yes | yes | Phone: every repeating or entrance animation checks `accessibilityReduceMotion` (Backdrop timeline, Loading sweep, Components pulse and entrance, Plan and Tonight parts). Mac: the only animated scroll is guarded (`Components.swift:147`); the other `TimelineView` re-sorts a list and draws no motion | **Likely supported.** Declare after a walk through the eight tasks with Reduce Motion on, on each device. |
| VoiceOver | unproven | unproven | Phone: 21 `accessibilityLabel`, 17 grouped elements, 11 hidden decorative items. Mac: 31 labels, 17 elements, 21 hidden. Labels exist; the claim needs all eight tasks completed by VoiceOver alone | **Needs a device test.** |
| Voice Control | unproven | unproven | Standard controls with labels; custom card buttons need their spoken names to match what is on screen | **Needs a device test.** |
| Larger Text | partly | **not available** | Phone: 178 text-style fonts, `@ScaledMetric` and `dynamicTypeSize` in the hero, but caps exist: `...accessibility1` on the Tonight screen's captions and the horizon sheet, `...accessibility2` on the hero headline (AX2 is about 194% of body, just under Apple's 200%). Apple's test is body text in the primary views at 200% or the system maximum, not captions | **Needs a device test at AX3 and AX5** on Tonight, Plan, Targets and a target page. Not declarable for the Mac. |
| Differentiate Without Color Alone | unproven | unproven | Charts use different dash patterns per line (seen in the plan chart), "Clash" and "Not tonight" are words and icons; the sky-score and clear-window bars rely on shape and length; red night mode is a colour scheme, not a signal. Not every status has been checked | **Needs a review pass** of each screen for colour-only signals. |
| Sufficient Contrast | unproven | likely | `scripts/contrast.swift` measures the Mac popover's text tokens against the glass (exits 1 under 4.5:1). Increase Contrast is handled in the design (hairlines become the text colour). The phone has not been measured | **Run `scripts/contrast.swift` with the popover open** for the Mac; the phone needs a sample of screens measured. Re-do on every update. |
| Captions | n/a | n/a | No audio or video in the app | Do not declare. |
| Audio Descriptions | n/a | n/a | No audio or video in the app | Do not declare. |

## Draft answers

**Declare now, after a short on-device look** (low risk, the code is clear):
- iPhone, iPad, Mac: Dark Interface.
- iPhone, iPad, Mac: Reduced Motion (turn the setting on and walk the tasks once per device).

**Declare after a test** (do not declare on the strength of the code alone):
- VoiceOver and Voice Control: one pass per device, all eight tasks.
- Larger Text, iPhone and iPad only: the four screens at AX3 and AX5; if the caps in `TonightScreen.swift`, `TonightHeroView.swift` and `HorizonSheet.swift` are what fails, raising them is a small change that would need a new build.
- Differentiate Without Color Alone and Sufficient Contrast: one review pass and the contrast script.

**Leave undeclared:** Captions, Audio Descriptions, and Larger Text on the Mac.

## Tests, step by step

Use a public site (Malham Tarn) so nothing private is on screen. Each test is the eight common tasks above, with one setting on.

1. VoiceOver (iPhone: triple-click the side button after turning on the shortcut; iPad: the same; Mac: Cmd+F5). Complete each task without looking. Note anything that is unlabelled, read in the wrong order, or cannot be reached.
2. Voice Control (Settings > Accessibility > Voice Control; Mac the same). Say "Show numbers" and complete the tasks by speaking.
3. Larger Text (iPhone/iPad: Settings > Accessibility > Display & Text Size > Larger Text > Larger Accessibility Sizes, then the slider to the end, then one step down). Walk the four screens and look for overlapping or cut-off body text.
4. Reduced Motion (Settings > Accessibility > Motion > Reduce Motion; Mac: System Settings > Accessibility > Display > Reduce motion). Walk the tasks and look for anything that slides, drifts, pulses or spins.
5. Differentiate Without Color Alone (Settings > Accessibility > Display & Text Size > Differentiate Without Color): check that nothing depends on colour only.
6. Contrast: `swift scripts/contrast.swift` with the popover open over a white window; for the phone, Increase Contrast on, then look at each screen.

## Result record (fill in as tests are done)

| Feature | iPhone | iPad | Mac | Date and who |
|---|---|---|---|---|
| Dark Interface | | | | |
| Reduced Motion | | | | |
| VoiceOver | | | | |
| Voice Control | | | | |
| Larger Text | | | n/a | |
| Differentiate Without Color Alone | | | | |
| Sufficient Contrast | | | | |
