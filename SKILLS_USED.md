# Skills used

Read September 14, 2026 before the corresponding implementation work. Public references were downloaded into `/tmp/photo-tinder-references` for inspection, without running installers. The source repositories contain some SDK 27 guidance; this project uses only APIs that compile with the installed iOS 26.5 SDK.

- [SwiftUI Expert README](https://github.com/AvdLee/SwiftUI-Agent-Skill/blob/main/README.md), [current skill](https://github.com/AvdLee/SwiftUI-Agent-Skill/blob/main/skills/swiftui-expert-skill/SKILL.md), and its state-management, view-structure, sheet-navigation-patterns, image-optimization, accessibility-patterns, performance-patterns, liquid-glass references; relevant latest-apis entries. Applied explicit `@MainActor @Observable` ownership, private view state, stable asset identity, native tabs/navigation/sheets, small media views, sized image requests, fit-preserving cards, gesture alternatives and system materials.
- Swift Concurrency and Axiom Photo Library, including the linked API reference and installed SDK headers. Applied separate metadata/store actors, `@Sendable` callbacks, cancellation, generation checks, bounded caching, true metadata classification, native limited selection, and exact selected-ID deletion. Exact files read and their effects are in [PhotoKit reference notes](docs/SKILLS-photokit.md).
- Swift Testing. Applied independent value-state tests, seeded randomization, fixed reference dates, isolated temporary stores, async actor tests and explicit errors. XCUITest exercises the app and system dialogs. Exact files read are in [domain reference notes](docs/SKILLS-domain.md).
- Axiom HIG, Liquid Glass, gesture and accessibility guidance, plus Apple's Liquid Glass article. Applied native chrome, semantic appearance, plain photo content, adaptable controls, explicit inspection dismissal and reduced custom motion. Exact sources and scopes are in [design reference notes](docs/SKILLS-design.md).
- The local unslop skill governed product copy and delivery notes.

Apple's [Photos deletion and recovery guidance](https://support.apple.com/104967) informed confirmation and Settings text: deleted assets can be recovered in Recently Deleted for up to 30 days, and iCloud Photos synchronizes deletion. No exact storage savings are claimed.

XcodeBuildMCP was not used. Existing Xcode MCP, xcodebuild, simctl, XCUITest and native Simulator tools were used instead.
