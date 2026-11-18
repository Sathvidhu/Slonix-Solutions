# Montme employee app - 0.4.0

Flutter Android employee workspace. The admin dashboard is in [`../web/`](../web/README.md); the existing Slonix public website remains at repository root.

## Run and build

```powershell
# From app/
flutter pub get
flutter run
flutter analyze
flutter test
flutter build apk --release
```

APK output: `build/app/outputs/flutter-apk/app-release.apk` relative to this folder. Generated APKs and caches are excluded from Git. Review releases currently use debug signing; production signing is not configured.

## Employee access

Admin creates an account with employee ID, email, password and access role. Sign into the app using that ID and password and review the work-record sync disclosure. Passwords are not saved; the signed-in session is kept in secure device storage. There is no self-registration step for admin-created accounts.

Existing local history is preserved. To link an older local workspace, its employee ID must match the admin-created account. After linking, a saved owner binding prevents those records being connected to another employee.

## Work and breaks

Leads, follow-ups, shifts, breaks, business calls, assignment messages/resources and notification read status sync to Supabase after login. Recording audio remains on the device.

The shift clock continues through breaks; net work subtracts break intervals. Lunch is 1:30-2:30 PM IST, evening is 5:00-5:30 PM IST, and one extra break per IST calendar day is limited to ten minutes. A late lunch/evening start does not extend the fixed end. Employees explicitly start/resume breaks. A separate timer/history records actual intervals, and overruns alert the employee/admin after sync.

The app includes an in-app notification inbox, read/unread controls and local Android break alarms. Enable device alerts in Notifications. Remote background push is wired but requires the Firebase project/configuration described in the deployment guide. OS permission, force-stop and power-saving rules affect alerts.

## Current boundaries

Call metadata import requires Android permission and consent. Only business-number matches within recorded shifts are saved. The external dialer can allow number edits. OEM restrictions can prevent access to protected recording folders. Recording file dates/durations alone do not prove a call match.

Data is locally durable, with company sync and retry on network recovery while the app is open. Offline activity is not visible remotely until sync. Device attendance and manual entries remain self-reported. Export a backup from the previous version before changing employee IDs or uninstalling.

No physical phone was attached. Validate employee login, alarm timing, background push, notification read receipts, downloads, SIM-call return and recording-folder permissions on a company test phone.

See [backend and notification setup](../web/supabase/DEPLOYMENT.md) for server/provider requirements. `app/web/` is optional Flutter browser-platform source, separate from the top-level admin `web/` directory.
