# Domain and persistence skill references

Read on September 14, 2026. The project uses Swift 6.0, complete concurrency checking, and the installed Swift 6.3.3 toolchain. The project does not enable default MainActor isolation.

- [Swift Testing README](https://github.com/AvdLee/Swift-Testing-Agent-Skill/blob/main/README.md) and [current SKILL.md](https://github.com/AvdLee/Swift-Testing-Agent-Skill/blob/main/swift-testing-expert/SKILL.md), plus `fundamentals.md`, `expectations.md`, `parallelization-and-isolation.md`, `async-testing-and-waiting.md`, and `parameterized-testing.md`. The domain suites use Swift Testing, value types with independent state, explicit expected values, and parameterized metadata cases. Persistence tests await actor calls and use a fresh temporary directory for each test. The shuffle generator and date reference are injected. No test depends on wall-clock sleeps or test ordering. XCUITest remains the UI verification mechanism.
- [Swift Concurrency README](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill/blob/main/README.md) and [current SKILL.md](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill/blob/main/skills/swift-concurrency/SKILL.md), plus `actors.md` and `sendable.md`. Media metadata, review state, and undo entries are Sendable values. A dedicated actor owns atomic disk writes; its write operation has no suspension point. Monotonic revisions reject late saves of older state. Core uses no unchecked Sendable or unsafe isolation annotations.
- Local [Unslop skill](/Users/djoshea/.codex/skills/unslop/SKILL.md). Documentation uses concrete claims and names the checks that actually ran.

The fetched repositories are preserved under `/tmp/photo-tinder-references/testing` and `/tmp/photo-tinder-references/concurrency` for this run.

Independent verification compiled the exact Core sources with Swift 6 and complete concurrency checking. An isolated SwiftPM package in `/tmp/photo-tinder-domain-tests` ran the domain, category, and persistence suites on macOS. These runs verify the value model and file store. Native iOS build and simulator tests are reported separately.
