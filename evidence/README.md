# Evidence index

See [VERIFICATION.md](../VERIFICATION.md) for actual results, reruns, and limitations. Screenshots show only disposable simulator media.

| Screen | Light | Dark | Maximum text size |
| --- | --- | --- | --- |
| Clean | [View](clean.png) | [View](clean-dark.png) | [View](clean-large-light.png) |
| Swipe | [View](swipe.png) | [View](swipe-dark.png) | [Light](swipe-large-light.png), [dark](swipe-large-dark.png) |
| Review | [View](review.png) | [View](review-dark.png) | [View](review-large-light.png) |

Functional evidence: [denied access](permission-denied.png), [full access](permission-full.png), [limited access](permission-limited.png), [empty library](empty-library.png), [selected deletion](deleted-one-item.png), [cancelled deletion](delete-cancelled.png), [Places](places-metadata-session.png), [image zoom](zoomed-image.png), [video inspection](video-inspection.png), [completed-session Undo](completed-session-undo-restored.png), and [rapid-swipe Undo](rapid-swipes-restored.png).

Accessibility settings: [Reduce Motion enabled](reduce-motion-enabled.png), [Reduce Transparency enabled](reduce-transparency-enabled.png), and [the app with both enabled](reduced-motion-transparency-swipe.png).

The final [domain/PhotoKit log](test-final-domain-photokit.log), [full UI log](test-final-ui.log), [focused UI rerun](test-final-ui-rerun.log), and [Release build](build-release.log) retain their actual output. Native `.xcresult` bundles and bulk attachment exports remain locally available but are excluded from Git; named screenshots and logs are included. Earlier bundles retain the failures that prompted corrections.
