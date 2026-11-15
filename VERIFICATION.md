# Verification — 16 November 2026

## Commands

- `npm.cmd run build`: passed; production Vite bundle generated.
- `npm.cmd run lint`: passed with no warnings or errors.
- OpenCV video inspection and poster extraction: passed. H.264, 1920×1080, 30 fps, 8 seconds, 3,140,782 bytes. Original preserved.

## Browser checks (in-app browser)

- Visually inspected 360×800, 390×844, 768×1024, 1024×900, and 1440×1000 viewports. Measured document scroll widths were 345, 375, 753, 1009, and 1425 respectively (the difference is the vertical scrollbar). No horizontal page overflow.
- Inspected phone hero, phone stacked photo/text, tablet/laptop overlapping image/text, desktop hero, About, and insights layouts.
- Local video: decoded at 1920 pixels wide, readyState 4, muted, advancing playback. Pause and resume controls changed the actual paused state.
- Reduced-motion branch: isolated temporary browser harness simulated matchMedia returning true. Confirmed no video element, loaded 1600px poster, and static-view status. OS/browser preference itself was not changed.
- Autoplay rejection: temporary harness made play() reject with NotAllowedError. Confirmed video stayed paused, autoplay was disabled after rejection, poster loaded, retry control remained, and retry rejection produced clear accessible feedback.
- Loading error: temporary harness used a deliberately missing video source. Confirmed video element removed, poster loaded, and static-view unavailable label shown. Expected 404 belonged only to that isolated harness, not the website.
- Temporary harness files were deleted after checks.
- Desktop program dropdown and category navigation; mobile expandable program categories, selected-category navigation, automatic menu closing, and Escape dismissal: passed.
- Program category filter and search narrowed results from 6 to 2 to 1. Program dialog opened and closed with Escape. Focus restoration to its triggering button was explicitly verified after correction.
- Project category filter narrowed to one brief; sample project detail dialog opened/closed.
- Sample insight dialog opened/closed.
- FAQ expanded with correct aria-expanded state.
- Empty contact form produced validation errors; filled valid demo values produced explicit feedback that nothing was sent or stored.
- All hash links resolve to existing IDs. No broken loaded images. Three stock image files and the poster were verified locally with Pillow; browser images loaded successfully.
- Main website browser warning/error log: empty.

## Captures

- `screenshots/revised-desktop.jpg`: 1440px desktop hero.
- `screenshots/revised-overlap.jpg`: 1440px photographic overlap.
- `screenshots/revised-mobile.jpg`: 390px phone hero.
- `screenshots/revised-mobile-overlap.jpg`: 390px stacked photo/text composition.

## Limits

Single browser engine; no physical-device, network-throttling, screen-reader, or real OS reduced-motion preference testing. Glass fallback is implemented with @supports but was not tested in a browser lacking backdrop-filter. Video codec profile, audio tracks, and MP4 fast-start metadata were not inspected. Stock and video sources/limitations are documented in ASSET_SOURCES.md. No backend, external message transmission, commit, push, or deployment.
