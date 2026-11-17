# Engineering refresh verification — 17 November 2026

- Reviewed all 20 pages of the client PDF through text extraction; rendered and inspected page one.
- Reviewed Finulent's public navigation and section structure as design reference.
- Production build: `npm.cmd run build` passed.
- Browser QA: desktop homepage, mobile BIM detail page at 390 x 844, shared service dropdown, mobile menu open/close, home-to-service and service-to-home navigation.
- Service search: `clash` returns BIM & VDC.
- Mobile document width does not exceed the viewport; no broken loaded images were found.
- Enquiry validation: blank fields display name, business email, and project description errors. Valid test details produce an email draft link; no email was sent.
- Browser logs show no application error for the Slonix preview.
- Screenshot: screenshots/engineering-homepage.jpg.

Limitations: automatic email delivery, server uploads, approved legal policies, and verified client portfolio assets are not configured. This is a local repository update, not a production deployment.

## Scroll motion correction

Replaced one-shot reveal keyframes with a reusable observer that tracks individual headings, images, cards, process steps, and contact panels. Added hidden pre-entry states, 64px desktop / 42px mobile rise, directional image reveals, 110ms card stagger, replay after scrolling back above a section, dynamic search-result observation, and a header scroll progress line. Reduced-motion preferences keep all content visible without transitions.

Browser verification: first service cards measured opacity 0 and translateY(64px) before entering, then opacity 1 and translateY(0) after natural Page Down scrolling. Card delays measured 0 / 110 / 220ms. Production build passed. The client quick tunnel was stopped at the user's request; no replacement public tunnel was created.

## Generated imagery refresh

Created 12 distinct images with the built-in image generation tool. Replaced all repeated stock imagery in homepage sections and added individual service-page banner imagery. All generated assets converted to WebP (approximately 2.8 MB combined). Reviewed a contact sheet of all 12 outputs and checked portfolio crops, MEP desktop banner, and mobile banner. No duplicate image sources remain within the homepage content. Mobile document width remains within its viewport. Production build and diff whitespace checks pass. No new public tunnel was started.
