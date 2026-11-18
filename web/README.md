# Montme admin dashboard - 0.5.0

Source: `web/`. Browser assets: `dist/`. The Flutter employee app is in [`../app/`](../app/README.md). The original Slonix public website remains at repository root.

## Local preview

```powershell
# From repository root
python -m http.server 5184 --bind 127.0.0.1 --directory web/dist
```

Open http://127.0.0.1:5184. Runtime assets are bundled, so serving needs no Node installation. Local preview stores isolated browser data, discards employee passwords and does not create real Auth accounts or send notifications to employees.

The hosted admin Site is https://montme-admin-workspace.artfultanager4.chatgpt.site and remains owner-private. For an external client walkthrough, keep the local server running and use `cloudflared tunnel --url http://127.0.0.1:5184 --no-autoupdate`. Share its temporary trycloudflare.com URL. Serve only `web/dist`, never the repository root.

## Management features

- Admin-created employee IDs/passwords, password resets and active access.
- Server-enforced access roles with explicit management permissions.
- Contacts using Institution, including Excel/PDF import with field validation.
- Reusable messages, links and private resource uploads.
- Assignments, delivery/deadline scheduling and repeating work.
- Activity timeline, recorded shifts and normalized break intervals.
- Admin notification inbox, employee read/unread receipts and delivery status.
- Queued high-priority email and configurable Android push transport.

Admin username `lokesh` resolves to the configured owner email; Supabase Auth verifies its password. It is never embedded in source. Employee account operations run through the authorized Edge Function; clients do not receive a service-role credential.

## Deployment

See [Supabase and provider setup](supabase/DEPLOYMENT.md) for migrations, functions, break policy, email, Firebase and current limits. The scheduler and account functions are deployed for the existing project. Resend and Firebase activation still require owner configuration; delivery is never reported as successful without provider acceptance.

For Vercel, import this same repository as a separate project with Root Directory `web`, Framework Preset `Other`, empty build/install overrides and Output Directory `dist`. `vercel.json` supplies these static settings. Keep the original Slonix root/Vite deployment unchanged.

The preserved Sites deployment repository is local at `.sites-deploy/admin/` and excluded from the main Git repository. Keep it synchronized with reviewed `web/` source before publishing a Sites update.

## Development checks

```powershell
# From web/
npm ci
npm test
npm run test:backend
npm run build:imports
```

Node tests cover scheduling, contact validation, a real Excel workbook, PostgreSQL migration/RLS behavior, read receipts and password non-persistence. Deno tests cover trusted account/login/delivery handlers. Browser QA used fictional local-preview fixtures, not live employee records. No physical Android device was attached.

Version 0.5 adds early clock-out decisions and employee report downloads under Activity, global Reload, employee IDs in filters, device-lead call syncing, legacy break timezone repair and Gmail welcome/priority emails. Apply migrations 007 and 008 after 006. See Supabase deployment instructions for private Gmail secrets.
