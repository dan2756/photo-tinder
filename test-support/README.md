# Disposable simulator media

This directory contains synthetic drawings and a synthetic four-second video made with native macOS APIs. Each image visibly says "DISPOSABLE FIXTURE". They are test inputs, never bundled in the production app. The video contains moving water, a moving bird, a visible time counter, and a quiet audio tone so playback and mute behavior can be checked.

Regenerate from the project root:

```sh
xcrun swiftc -parse-as-library scripts/generate-fixtures.swift -o /tmp/photo-tinder-fixtures
/tmp/photo-tinder-fixtures
```

The generator creates 12 JPEG scenic drawings, one PNG screenshot-like graphic, one playable MOV, and a JSON manifest. JPEGs have ImageIO EXIF capture dates. Eight scenic drawings have synthetic GPS coordinates in two groups. Eight scenic drawings have capture dates within the past 30 days; four are over 500 days old. The PNG and video are current. These are deliberately fictional associations, not claims about the drawn scene's real location.

The PNG looks like a screenshot but is an ordinary image. Importing it does not establish the PhotoKit screenshot subtype. Selfies, screenshot, and Live Photo category conditions require deterministic domain fixtures or genuine system-classified assets. Empty smart categories remain empty in production.

Import only into the dedicated disposable simulator:

```sh
sh scripts/seed-disposable-simulator.sh
```

The script is fixed to simulator `34C20ACC-6657-467B-BAF1-CF34097AE244`. It does not target the generic "booted" destination or any physical device. Import adds new assets each time, so call it once per clean test library. No script in this directory deletes Photos assets. Destructive integration tests must act on this simulator's disposable assets through the app's explicit review and PhotoKit confirmation flow.

`media/manifest.json` records metadata used by the generator. Verify the imported library's actual PhotoKit metadata before claiming successful Recent, Older, or Places integration checks, because a simulator import may normalize metadata.

To reproduce Review thumbnail hit testing with tall images, generate three 300-by-3000 color-band PNGs and import them once into the disposable simulator:

```sh
xcrun swift scripts/generate-tall-fixtures.swift
xcrun simctl addmedia 34C20ACC-6657-467B-BAF1-CF34097AE244 test-support/generated/tall-thumbnails/*.png
```

Run `PhotoTinderUITests/PhotoTinderUITests/testSelectAllDoesNotOpenPhoto`. It queues the accessible disposable library, taps Select All and Deselect All at their screen coordinates, then checks that tapping a thumbnail still opens inspection. It does not delete any Photos assets. The tall fixtures reproduce taps being intercepted by cropped image content before the hit-testing fix.

Regenerate the app icon separately:

```sh
xcrun swift scripts/generate-icon.swift
```

The icon is a native vector drawing of overlapping review cards with a checkmark. Both icon images are opaque 1024-pixel PNGs; iOS applies the outer mask.
