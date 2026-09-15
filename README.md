# Photo Tinder

A native iPhone photo cleanup app. Shuffle your library or choose a category, swipe left to queue an item, swipe right to keep it, then explicitly confirm deletion in Review. Swipes never delete from Photos.

Open `PhotoTinder.xcodeproj` in Xcode. Select the `PhotoTinder` scheme and an iPhone simulator. The project targets iOS 26 and uses Swift 6 with complete concurrency checking. No packages or server setup are required. Physical-device builds need your own signing team.

## Run and test

The verified destination is **Photo Tinder Disposable QA**, an iPhone 17 Pro on iOS 26.5:

```sh
xcodebuild -project PhotoTinder.xcodeproj -scheme PhotoTinder \
  -destination 'platform=iOS Simulator,id=34C20ACC-6657-467B-BAF1-CF34097AE244' \
  -derivedDataPath build build CODE_SIGNING_ALLOWED=NO

xcrun simctl install 34C20ACC-6657-467B-BAF1-CF34097AE244 \
  build/Build/Products/Debug-iphonesimulator/PhotoTinder.app
xcrun simctl launch 34C20ACC-6657-467B-BAF1-CF34097AE244 org.local.PhotoTinder
```

Run the deterministic tests on any compatible simulator:

```sh
xcodebuild -project PhotoTinder.xcodeproj -scheme PhotoTinder \
  -destination 'platform=iOS Simulator,id=34C20ACC-6657-467B-BAF1-CF34097AE244' \
  -parallel-testing-enabled NO -derivedDataPath build \
  -only-testing:PhotoTinderTests \
  -skip-testing:PhotoTinderTests/PhotoKitIntegrationTests \
  test CODE_SIGNING_ALLOWED=NO
```

UI and real PhotoKit tests are guarded to the exact disposable simulator UUID above. They skip on other simulators and physical devices. UI tests intentionally delete disposable library items, never use a personal or iCloud-synced device. The initial empty-library test is a separate check for the simulator's original sample library, before importing fixtures.

Disposable fixtures have already been imported into the delivered simulator. For a new test environment, see [fixture generation and import](test-support/README.md). Do not rerun the import on the existing simulator unless you want duplicate fixtures. Core UI tests use a separate local review file, but the Photos assets themselves are real simulator assets.

```sh
xcodebuild -project PhotoTinder.xcodeproj -scheme PhotoTinder \
  -destination 'platform=iOS Simulator,id=34C20ACC-6657-467B-BAF1-CF34097AE244' \
  -parallel-testing-enabled NO -derivedDataPath build \
  -only-testing:PhotoTinderUITests \
  -skip-testing:PhotoTinderUITests/PhotoTinderUITests/testEmptyLibraryAfterDeletingDisposableSamples \
  test CODE_SIGNING_ALLOWED=NO
```

Photos permission can reset when Xcode replaces an unsigned simulator app with a newly built binary. Real PhotoKit integration tests require full access on that installed binary; use the app's permission flow, then `test-without-building` for the integration target. The verification report records actual results, including any skipped preliminary runs.

After building the tests, this sequence grants access through the actual system dialog and then runs the 39 Swift Testing tests and six read-only PhotoKit checks without replacing the app binary:

```sh
xcodebuild -project PhotoTinder.xcodeproj -scheme PhotoTinder \
  -destination 'platform=iOS Simulator,id=34C20ACC-6657-467B-BAF1-CF34097AE244' \
  -parallel-testing-enabled NO -derivedDataPath build \
  -only-testing:PhotoTinderUITests/PhotoTinderUITests/testPermissionFull \
  test-without-building CODE_SIGNING_ALLOWED=NO

xcodebuild -project PhotoTinder.xcodeproj -scheme PhotoTinder \
  -destination 'platform=iOS Simulator,id=34C20ACC-6657-467B-BAF1-CF34097AE244' \
  -parallel-testing-enabled NO -derivedDataPath build \
  -only-testing:PhotoTinderTests test-without-building CODE_SIGNING_ALLOWED=NO
```

## Project layout

- `PhotoTinder/Core`: metadata categories, persistent review state, session order, undo, and atomic actor-owned storage.
- `PhotoTinder/Library`: PhotoKit authorization, smart albums, metadata scanning, change observation, caching, image/Live Photo/video requests, and deletion.
- `PhotoTinder/App`: observable UI state, saved progress, and deletion transaction coordination.
- `PhotoTinder/Views`: native Clean and Review tabs, swipe session, inspection, places, and Settings.
- `PhotoTinderTests`: Swift Testing domain/store/transaction suites and guarded read-only PhotoKit integration tests.
- `PhotoTinderUITests`: native XCUITest interactions and retained screenshots.
- `evidence`: build/test logs, result bundles, and simulator screenshots.

Kept, unreviewed, and pending-deletion state is shared across every category. Skips remain unreviewed for another pass. Favorites are protected by default. Locations use approximate coordinate groups from existing photo metadata; no current-location permission or reverse geocoding is used.

Review is an app-local queue. Deleted media can be recovered in Photos' Recently Deleted for up to 30 days. iCloud Photos synchronizes deletion across devices. App Undo cannot restore a completed library deletion. The app has no accounts, analytics, uploads, or storage-savings estimates.

See [skills actually used](SKILLS_USED.md) and [verification evidence](VERIFICATION.md).
