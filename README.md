# Slonix Solutions frontend prototype

React + Vite (JavaScript), npm, Tailwind CSS v4 with the official Vite plugin. Frontend only; no submission endpoint.

## Preview and checks

- `npm.cmd install` if dependencies are missing.
- `npm.cmd run dev` and open the URL Vite prints (normally http://localhost:5173).
- `npm.cmd run build` creates `dist`.
- `npm.cmd run preview` previews that production build.
- `npm.cmd run lint` runs the configured oxlint command.

## Editing

- `src/data.js`: company contacts, programs, illustrative briefs, sample articles, FAQs, local media paths.
- `src/index.css`: centralized brand, neutral, overlay, glass, focus, and typography tokens.
- `src/App.css`: layout, image compositions, mobile stacking, glass fallbacks.
- `src/components/VideoHero.jsx`: video lifecycle, pause/play control, poster, reduced-motion and error handling.
- `src/components/UI.jsx`: shared wordmark, section heading, accessible native dialog.
- `references/`: copies of all ten supplied screenshots, plus named copies of the overlap and photo-tile references. The supplied screen recording remains at its original user path; it is not bundled or used as website media.

## Brand and content verification

Inspected the rendered https://slonixsolutions.in/ on 16 November 2026. Its header wordmark uses `linear-gradient(135deg, rgb(241,70,37), rgb(255,140,66))`: exact accent tokens `#F14625` and `#FF8C42`. Headline text is `#111827`. The new design uses those accents with white/charcoal neutrals, and a darker derivative `#B63218` for small text and primary button contrast. No green or olive UI palette remains. This is a text wordmark, not a supplied official logo file.

Program names, practical learning direction, mission summary, email, phone, and Bengaluru address derive from Slonix. Categories are editorial groupings. Outlines are indicative, not confirmed syllabuses. Fees, schedules, duration, prerequisites, accreditation, and placement outcomes are not asserted. Projects and articles are original sample content clearly labeled in the interface. Stock photography is illustrative and never identified as Slonix staff, students, premises, or completed work.

The supplied Finulent screenshots inform the large overlapping image/text section, alternating photographic compositions, image-led category tiles, and editorial insight layout. No Finulent claims, contact details, statistics, or testimonials are reused.

## Media

See [ASSET_SOURCES.md](ASSET_SOURCES.md) for photographer credits, source pages, license, file dimensions, and video details. All website media is served locally; no external photo or font requests are needed.

The original `public/videos/construction_bg.mp4` is preserved and referenced at `/videos/construction_bg.mp4`. Its poster was extracted locally from the six-second frame with OpenCV, resized to 1600×900, and saved as `public/images/construction-poster.jpg`. The supplied video is an architectural visualization, not footage of Slonix premises. No compressed derivative was created. At 3.14 MB for 8 seconds, it is usable for this prototype; a 720p mobile derivative would reduce mobile transfer further before production. A future encode should preserve the original, strip unused audio, and enable fast-start streaming.

The video is muted, looped, autoplaying, playsInline, decorative, and cannot intercept pointer input. The pause/play button controls actual playback. Reduced motion omits the video entirely and shows the poster. Autoplay rejection leaves a static background and a retry control; source failures show the poster and a static-view label. Glass panels use a solid translucent fallback; blur is applied only when supported and only to the hero supporting panel and photographic CTA.

## Interaction and accessibility

Program search and category filtering, native modal details, project filters, FAQ, anchor navigation, and contact validation remain functional. Dialog focus restores to its trigger on close. Escape closes dropdowns, mobile navigation, and dialogs. Contact validation is local only; nothing is sent or stored. Real contact is through the verified email/phone links.

See [VERIFICATION.md](VERIFICATION.md) for the exact checks performed and saved screenshots. No commit, push, or deployment was performed.
