# Backend and admin integration plan

## Identity and access

Introduce organisations, verified employee accounts, admin/manager roles and device enrollment. Authorise every query by organisation and role on the server. Employee IDs entered into this review app are labels, not credentials. Configure client ownership, account recovery and employment offboarding before rollout.

## Data contract

The local JSON v1 backup documents today's fields. Use server-issued organisation and employee IDs with UUID record IDs in the backend:

- employee: id, organisation_id, name, employee_code, active
- lead: id, organisation_id, assigned_employee_id, name, company, phone_e164, status, notes, follow_up_at
- shift: id, employee_id, start_at, end_at
- break: id, shift_id, start_at, end_at
- call: id, employee_id, lead_id, device_id, device_call_id, started_at, duration_seconds, direction, source, outcome, notes
- audit_event: actor_id, organisation_id, entity_id, event_type, server_timestamp

Store timestamps in UTC and display the organisation timezone. Preserve source and audit manual corrections. Device call IDs alone are not globally unique. Normalise international numbers with a proper numbering library. Preserve lead/number history rather than retroactively attributing older calls to newly edited numbers.

## Synchronisation

Use a durable local database and transactional outbox, idempotency keys, server acknowledgements, retries, tombstones, device identity and conflict resolution. Do not mark local writes as uploaded. Keep last successful import distinct from last successful server sync. Enforce assignment and tenant access on the server, not in Flutter alone. Design foreground/background ingestion against the agreed distribution model and phone pilot results.

## Admin dashboard

Team attendance and breaks, call count/duration and source, lead assignment/import, follow-up queues, employee/date filters, last successful sync, offline/stale-device badges, exports and an audit trail. Treat gaps between calls as gaps, not proof of inactivity. Include attendance correction/approval workflows and avoid conflating talk time with total work.

## Before deployment

Move from shared preferences to durable application storage with a migration plan. Add real authentication, encryption/key management, role enforcement, backups, retention/deletion controls, employee privacy notices, crash/error telemetry, signed builds and a client-owned release keystore. Validate a representative set of real Android devices and the required Play/distribution permissions. Decide whether recording or cloud telephony is actually required before adding either.
