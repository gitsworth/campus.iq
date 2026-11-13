# CampusIQ implementation status

This is an updated source package based on the uploaded Flutter project. It is configured for a **new Supabase project**.

## Changes made in this package

- Replaced the old hard-coded Supabase project URL/key with setup placeholders.
- Updated the class-code read policy and Class Details UI so both codes are available to all class members.
- Added creator-only student removal in the Class Details UI and matching RLS policy.
- Added class ownership transfer UI/RPC; the current creator cannot leave until ownership is transferred.
- Updated subject policies so the creator can manage subjects created by teachers who have left.
- Added case-insensitive unique subject names within each class.
- Made assigned subject teacher references nullable on account deletion so subjects and class materials are retained.
- Added private note version history: same subject + same label creates a new version; teachers see history and students see the latest version.
- Added “create a new announcement from this” behaviour; the old announcement remains in the feed.
- Updated holiday resolution so a holiday suppresses the regular timetable and all temporary timetable overrides for that date.
- Updated the chatbot client to stop when a fresh class-data load fails rather than answering from stale in-memory data.
- Hardened the Groq Edge Function request validation and enabled JWT verification in Supabase CLI config.
- Replaced the README with fresh-project setup instructions.

## Not yet verified

- Flutter SDK/Dart SDK were not available in the build environment, so `flutter analyze`, unit tests and APK compilation were not run.
- No Supabase project was connected, and the SQL schema/Edge Function were not deployed or exercised against a live backend.
- No real multi-account/RLS test was run.
- The app's automatic announcements are still initiated by Flutter after the underlying change rather than being a single database transaction. For production-grade guarantees, convert these into database-triggered/outbox events and test retries.
- Configure production SMTP/email confirmation, backups, rate limits, monitoring and privacy/legal requirements before release.

## Installation safety

`supabase/schema.sql` is a one-time fresh-install script that drops/recreates CampusIQ application tables. Run it only once in a newly created Supabase project with no CampusIQ data. Never use it as an update script on a live installation.
