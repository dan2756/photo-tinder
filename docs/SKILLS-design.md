# Native design references read

Read on September 14, 2026. Axiom was retrieved under `/tmp/photo-tinder-references/axiom`; no Axiom installer or global configuration was used. The current repository is tracking OS 27 beta documentation, so implementation must use only APIs available in the installed iOS 26 SDK.

| Resource actually read | Influence on this app |
| --- | --- |
| [Axiom README](https://github.com/CharlesWiltgen/Axiom/blob/main/README.md) | Located the current grouped skill structure and noted the OS 27 beta scope. |
| [Design SKILL.md](https://github.com/CharlesWiltgen/Axiom/blob/main/.claude-plugin/plugins/axiom/skills/axiom-design/SKILL.md) | Chose native navigation, semantic text/colors, and functional controls before custom presentation. |
| [HIG guide](https://github.com/CharlesWiltgen/Axiom/blob/main/.claude-plugin/plugins/axiom/skills/axiom-design/skills/hig.md) | Keep photos visually dominant, honor system light/dark appearance, use native bottom tabs, minimum 44-point controls, and flexible layouts. The objective's explicit automatic appearance requirement takes precedence over the guide's optional permanent dark media mode. |
| [Liquid Glass guide](https://github.com/CharlesWiltgen/Axiom/blob/main/.claude-plugin/plugins/axiom/skills/axiom-design/skills/liquid-glass.md) | Native navigation/toolbars adopt glass with the new SDK. Avoid glass on category rows, image content, and nested cards. Prefer regular glass when custom control treatment is needed. |
| [Accessibility SKILL.md](https://github.com/CharlesWiltgen/Axiom/blob/main/.claude-plugin/plugins/axiom/skills/axiom-accessibility/SKILL.md) and [diagnostics](https://github.com/CharlesWiltgen/Axiom/blob/main/.claude-plugin/plugins/axiom/skills/axiom-accessibility/skills/accessibility-diag.md), sections on VoiceOver, Dynamic Type, contrast, touch targets, Reduce Motion, custom controls and announcements | Provide labeled buttons for every swipe action, non-color decision cues, explicit inspection dismissal, semantic fonts without truncating fixed frames, and reduced custom animations. Verify at accessibility text sizes and with the accessibility tree. |
| [SwiftUI gestures](https://github.com/CharlesWiltgen/Axiom/blob/main/.claude-plugin/plugins/axiom/skills/axiom-swiftui/skills/gestures.md), basic/composed gestures, transient state, velocity, accessibility, cancellation, performance and testing | Use transient drag state and disable implicit animation while following the finger. Commit only on end with horizontal intent and a threshold. Keep inspection zoom/pan separate, and route buttons and swipes to the same domain decisions. |
| [Apple Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), full Markdown document | Use standard tabs, bars, sheets, controls and spacing; test custom animations and colors with display/accessibility settings. App icon uses simple filled overlapping shapes and leaves outer masking to iOS. |
| [Unslop SKILL.md](/Users/djoshea/.codex/skills/unslop/SKILL.md) | Keep product copy and implementation notes direct, specific, and brief. |

Apple HIG, accessibility and app-icon web pages were opened but returned JavaScript shells through the web reader. Their substantive guidance here comes from Axiom's linked HIG guide and Apple's full Liquid Glass adoption article, which was fetched through its published Markdown endpoint. Do not count those empty page shells as read documentation.

The card's PhotoKit request now depends on its measured width, height, and display scale. SwiftUI can provide temporary dimensions during initial layout; restarting the request when those dimensions change fixes the undersized image that appeared as a uniform green card. Display remains a SwiftUI `Image(uiImage:)` with `resizable().scaledToFit()`, preserving the complete photo. A screenshot regression check samples the actual card's pixels for color variation using the disposable fixtures.

Recommended verification checks from this reading:

- Test the bottom decision buttons at the largest accessibility text sizes and verify no safe-area overlap.
- Use explicit Keep, Delete, Undo and Skip labels in the accessibility tree. A destructive cue needs text or a symbol in addition to red.
- Verify a cancelled drag resets and that a vertical drag does not commit a cleanup decision.
- Verify magnification and panning in full-screen inspection cannot reach the underlying cleanup gesture.
- Verify Reduce Motion changes custom card transitions, and Reduced Transparency does not make controls disappear.
- Verify the new native glass tab bar remains readable over both light and dark content.
- Verify image/video load failures retain decision state and expose Retry and Skip.

This document records research and implementation implications, not a claim that those runtime checks already passed.
