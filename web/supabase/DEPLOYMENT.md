# Montme 0.4 deployment and notification setup

The database upgrades and trusted functions use the existing Supabase project. Keep all RLS policies enabled. Do not rerun the initial schema against an installed database.

## Database and functions

Initial installs: run `schema.sql`, then migrations 004, 005 and 006. Existing 0.3 installations: run only the new migrations in order. Version 004 adds roles, institution compatibility, normalized break history, activity events, notifications, read receipts and delivery queues. Version 005 installs a one-minute scheduler. Version 006 adds operational retries and reminders for carried-over open breaks.

The upgrades were checked in an isolated PostgreSQL runtime before deployment. Existing employee/contact/call/shift history is preserved. `contacts.institution` is canonical; a trigger synchronizes legacy `company` values for older app compatibility.

From the repository root:

```powershell
npx --yes supabase login
npx --yes supabase functions deploy --remote=xnbqhzawxnjflhoskkds --workdir web --yes
```

Functions:

- `employee-admin`: verifies the caller's current employee-management permission before creating/updating Auth accounts. Privileged account changes also require role-management permission. The owner account cannot be modified here. Passwords are sent only to Supabase Auth, not to employee tables or browser storage.
- `employee-login`: resolves employee ID to an active enrolled account on the server, applies a ten-attempt/15-minute account limit, then verifies the supplied password through Auth.
- `deliver-notifications`: requires the scheduler secret or a signed-in user with notification-management permission. Claims due deliveries atomically, retries temporary failures and records actual provider responses.

`verify_jwt=false` in the function configuration is intentional: employee login is public and the other handlers verify their own user/worker credentials. It does not make account management public.

The scheduler credential is generated and installed in Supabase Secrets and Vault by `scripts/configure-scheduler.mjs`. No generated credential is committed or printed. This setup has already been completed for the current project; do not rotate it routinely.

## Email: Resend setup still required

1. Create an account at https://resend.com and verify a sender domain you own. Configure the DNS records shown by Resend.
2. Create an email-sending API key.
3. In Supabase **Project Settings → Edge Functions → Secrets**, add:
   - `RESEND_API_KEY`: the private sending API key.
   - `MONTME_EMAIL_FROM`: a sender on that verified domain, for example `Montme <notifications@your-domain.example>`.
4. In the admin dashboard, open **Settings → Check delivery setup**. Then use **Retry blocked deliveries** after configuration is complete.

High and Urgent employee notifications queue email to the employee's stored address. High-priority admin break alerts target the owner and active managers with activity-view permission. Scheduled notifications are not sent before their delivery time. Passwords are not included in these emails.

Without a valid provider/sender, email deliveries are reported as blocked, never sent. A provider acceptance is distinct from an employee read receipt. Resend idempotency keys reduce duplicate email on retries; no exactly-once transport guarantee is claimed.

## Android background push: Firebase setup still required

1. Create a Firebase project at https://console.firebase.google.com. Add an Android app with package name **com.montme.montme**.
2. From that Android app's public configuration, enter these in **Admin Settings → Manage rules & Firebase**:
   - Project ID (`project_info.project_id`).
   - Android app ID (`client_info.mobilesdk_app_id`).
   - Project number/sender ID (`project_info.project_number`).
   - Public API key (`api_key.current_key`).
3. Create a server service-account credential with permission to send Firebase Cloud Messaging messages. Add its JSON as the **FIREBASE_SERVICE_ACCOUNT** secret in Supabase. Keep this private JSON out of Git, app assets and chat.
4. Enable Cloud Messaging HTTP v1 for the project if required. On the phone, allow Montme notifications and reopen/sign in so its device token can register. The public Firebase configuration is loaded from the database; a new APK is not required merely to enter it.
5. Check delivery setup and retry blocked deliveries. Test on a real Android device with Google Play services, including a backgrounded app.

The app contains the native Firebase transport, but remote background push is inactive until the Firebase project and server credential exist. Android local break alarms and the in-app inbox do not require Firebase. OS power-saving rules can delay local alarms; test timing on the target phones. Force-stopping an app, denying notification permission, offline devices and vendor restrictions affect delivery.

Browser alerts work while the admin dashboard is open after permission is granted. This release does not implement closed-browser web push.

## Break policy

All policy times use IST (Asia/Kolkata).

- Lunch: 1:30 PM–2:30 PM. A late start still ends at 2:30 PM.
- Evening: 5:00 PM–5:30 PM. A late start still ends at 5:30 PM.
- One extra break per IST calendar day: up to ten minutes from the actual start.

Employees explicitly start/resume breaks; scheduled windows do not invent attendance intervals. The app keeps the shift clock running and separately shows current break duration, recorded break totals and net work time. Break timestamps and type survive app restarts. Server events and normalized break rows expose the history to authorized admins. Duplicate uploads do not recreate the same alerts. Overruns queue employee/admin alerts. Offline intervals arrive after the next successful sync; the admin cannot see an offline device's unsynced state.

The UI prevents a second extra break. If an older or modified client uploads an additional one, the server preserves the interval and alerts the employee/admin instead of silently dropping attendance data. Device records remain self-reported.

## Contact imports

Supported: `.xlsx` Excel workbooks and text-based `.pdf` contact tables. Required headers: **Contact name**, **Phone**, **Institution**. **Email** is optional, but validated when present.

Use one sheet and one contact per row, with phone values stored as Text. Download the template from the import dialog. Limits: 500 contacts, 20 MB, PDF up to 50 pages. Missing headers and row fields are listed before saving; any validation error blocks the whole import. Existing/duplicate phone numbers are skipped and reported. Scanned/image-only PDFs require OCR or conversion first; the parser does not guess absent data. Legacy `.xls` should be converted to `.xlsx`.

Files are parsed locally in the browser. Only the validated contact records are submitted when Import is pressed. Uploaded content-library files remain a separate feature.

## Validation and pilot

Run the Flutter tests/analyzer from `app/`, `npm test` from `web/`, and `npm run test:backend` from `web/`. Rebuild bundled import dependencies with `npm run build:imports` after changing the parser or its locked dependencies.

Tests cover migration/history preservation and RLS, read/unread receipts, fixed break windows and daily extra-break limits, local persistence, import field errors, real XLSX extraction, PDF text-column extraction, password non-persistence, login throttling, privileged-account authorization and failed-provider status reporting.

No physical Android device was attached during development. Verify employee provisioning/ID login, real break alarms, background FCM, attachment downloads and SIM call return on a company test phone. Configure production signing before public APK distribution.

## 0.5 sync, early clock-out and Gmail update

Migration 007 preserves all existing records and adds device-lead call names, early clock-out requests and private employee report submissions. Apply it after 006, then apply 008 to normalize legacy IST break timestamps and deploy all three Edge Functions. The new migration is already applied to the connected project.

The mobile notification bell and Reload appear on every main page. Android 13+ requests notification permission after first authenticated startup; if previously denied, use Notifications > Enable device alerts or Android app settings. Remote closed-app messages still require Firebase. In-app messages and local alarms remain separate.

Employees request early clock-out with a reason. Activity > Early clock-out requests lets authorized admins approve or dismiss with a note. The employee receives a notification; an approval applies to that shift only and is consumed at clock-out. This is clock-out, not account sign-out.

Work > Send all calls as Excel sends the current device report directly. Upload report file accepts an exported workbook or PDF/text/CSV/JSON up to 20 MB. Activity > Employee report uploads lists private downloads. These files are reviewed separately and do not insert duplicate call rows.

### Admin Gmail activation

1. Enable Google 2-Step Verification for the admin sender account.
2. Generate an app password at https://myaccount.google.com/apppasswords .
3. In Supabase > Edge Functions > Secrets set `GMAIL_USER` to the full admin Gmail address and `GMAIL_APP_PASSWORD` to the app password. Do not use the ordinary account password or commit these values.
4. In Notifications check delivery setup, retry blocked deliveries and process pending alerts.
5. New employee accounts and password resets email a greeting, employee ID, assigned password, email and access role to the employee's recorded email. The password is used only for Auth and this immediate email; it is not stored in notifications or database rows. If the email fails, the account remains saved and the admin sees the result. Set a fresh password to retry credential email; an old password cannot be recovered.

Gmail uses TLS to smtp.gmail.com:465. Google may restrict app passwords on managed/Advanced Protection accounts and applies sending quotas. Provider acceptance is not proof of Inbox delivery; check Spam and Gmail Sent. Resend remains an optional fallback when Gmail secrets are absent. SMTP retries can produce duplicate messages after ambiguous network failures.
