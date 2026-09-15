#!/bin/sh
set -eu

# Deliberately fixed to this project's isolated test simulator.
SIFT_TEST_UDID=34C20ACC-6657-467B-BAF1-CF34097AE244
SIFT_PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SIFT_MEDIA_DIR="$SIFT_PROJECT_ROOT/test-support/media"

if [ ! -f "$SIFT_MEDIA_DIR/manifest.json" ]; then
    printf '%s\n' 'Generate the disposable media before seeding.' >&2
    exit 1
fi

xcrun simctl bootstatus "$SIFT_TEST_UDID" -b
xcrun simctl addmedia "$SIFT_TEST_UDID" "$SIFT_MEDIA_DIR"/*.jpg "$SIFT_MEDIA_DIR"/*.png "$SIFT_MEDIA_DIR"/*.mov
printf '%s\n' "Imported disposable media into $SIFT_TEST_UDID."
