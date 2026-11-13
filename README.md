# CampusIQ

CampusIQ is a Flutter classroom hub backed by Supabase and Groq. This package is configured for a **new Supabase project**.

## Important safety note

- `supabase/schema.sql` is a **fresh-install script**. It drops/recreates CampusIQ application tables. Run it only once in a brand-new Supabase project with no CampusIQ data.
- Do not run it on an existing project or rerun it to apply updates.
- For future updates, use a new numbered migration file rather than editing/rerunning the initial schema.
- Never share your Supabase `service_role` key or Groq API key.

## 1. Create a Supabase project

1. Open https://supabase.com/dashboard and create a new project.
2. Save the database password somewhere secure.
3. Wait until the project is ready.
4. Open **Project Settings > API** (or **API Keys**).
5. Copy the **Project URL** and the **anon/public** or **publishable** key.

## 2. Create the database

1. In the Supabase Dashboard, open **SQL Editor**.
2. Choose **New query**.
3. Open `supabase/schema.sql` from this project.
4. Paste the complete file into the SQL editor and run it once.
5. Confirm the query completes successfully.

This creates the CampusIQ tables, constraints, database functions, RLS policies, and private `class-files` Storage bucket.

### Optional automatic class cleanup

Class deletion is delayed by 30 days and can be cancelled before the deadline. To permanently purge expired classes automatically:

1. Open **Database > Extensions** and enable `pg_cron` if it is available on your plan/project.
2. Open SQL Editor and run `supabase/step2_cron.sql`.

Without the cron job, expired classes remain scheduled for deletion until `purge_deleted_classes()` is run by an administrator. The app still treats expired classes as unavailable.

## 3. Configure Flutter

Edit `lib/constants.dart`:

```dart
const String supabaseUrl = 'https://YOUR_PROJECT_REF.supabase.co';
const String supabaseKey = 'YOUR_SUPABASE_ANON_OR_PUBLISHABLE_KEY';
```

Use the Project URL and public/anon/publishable key copied in step 1. These are public client values. **Never use the service_role key here.**

## 4. Configure authentication

In Supabase Dashboard:

1. Open **Authentication > Providers > Email**.
2. Ensure Email provider is enabled.
3. For production, keep email confirmation enabled and configure SMTP/email templates.
4. For local testing only, you may disable email confirmation to simplify sign-up.
5. Configure your allowed redirect URLs if you later add email confirmation or password-reset deep links.

## 5. Configure Groq

1. Create or sign in to your Groq account: https://console.groq.com/
2. Create an API key: https://console.groq.com/keys
3. Keep the key private.

The Edge Function uses:

- Endpoint: `https://api.groq.com/openai/v1/chat/completions`
- Default model: `openai/gpt-oss-120b`
- Temperature: `0.1`
- Reasoning effort: `low`
- Maximum completion tokens: `2000`

The Groq key is stored only as a Supabase Edge Function secret.

### Deploy using Supabase CLI

Install the Supabase CLI, sign in, and link this folder to your new project:

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase secrets set GROQ_API_KEY=YOUR_GROQ_API_KEY
# Optional; default is openai/gpt-oss-120b
supabase secrets set GROQ_MODEL=openai/gpt-oss-120b
supabase functions deploy groq-chat
```

The included `supabase/config.toml` sets `verify_jwt = true`. Keep JWT verification enabled.

You can also deploy the function from the Supabase Dashboard's Edge Functions area, but ensure JWT verification is enabled and add the same secrets under **Edge Functions > Secrets**.

## 6. Run the Flutter app

Install Flutter (Dart SDK 3.3 or later), then from this folder:

```bash
flutter pub get
flutter run
```

To build an Android APK:

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

## 7. Implemented product rules in this package

- A class has one creator, teacher members, and up to 100 student members.
- A student can belong to only one class; a user may be a teacher in multiple classes and a student in one class.
- A teacher can belong to at most 100 classes.
- Both class codes are visible to all class members.
- Subject names are unique within a class (case-insensitive).
- The creator can manage any subject, including subjects created by teachers who later leave.
- The creator can remove students. Students can also leave themselves.
- The creator must transfer ownership to another existing teacher before leaving.
- Class deletion is scheduled for 30 days later and can be cancelled only before its deadline.
- One shared weekly timetable and date-specific overrides are used.
- A holiday overrides the normal timetable and all temporary timetable overrides for that date. Removing the holiday restores the applicable schedule.
- Exams are individual date/time entries, not a separate exam-week timetable.
- Notes always belong to a subject and have a teacher-provided label.
- Uploading the same label under the same subject creates a new version. Teachers can see version history; students see the latest version.
- Notes and announcement attachments use private Storage.
- Creating an updated announcement from an existing post publishes a fresh post; the original remains in the feed. Attachments are added to the new post separately.
- The chatbot refreshes class data before answering and fails closed if the refresh fails.

## 8. Account deletion and data preservation

- Deleting a teacher account removes their teacher membership, but authored announcements, notes, events and exam records remain; creator/uploader references are set to null where applicable.
- Subject assignment is set to null if its assigned teacher account is deleted. The class creator can then reassign or manage the subject.
- A class creator account cannot be deleted while it owns a class. Transfer ownership to another current teacher first. This prevents classes becoming ownerless.
- Leaving a class is different from deleting an account.
- Account deletion should be performed through a trusted server/admin workflow, not by exposing a service-role key in the mobile app.

## 9. Before production

This source bundle has not been built against your Supabase project or tested on a physical device. Before releasing it:

- Run `flutter analyze` and `flutter test`.
- Test sign-up, sign-in, password reset and email confirmation.
- Test student/teacher joins with separate accounts.
- Test class/student/teacher limits under concurrent requests.
- Test all RLS rules using real student and teacher accounts.
- Test private file access from both roles.
- Test ownership transfer, creator removal of students, and creator deletion restrictions.
- Test holiday priority over both day and slot overrides.
- Test chatbot behaviour when Supabase is offline and when Groq returns an error.
- Configure backups, SMTP, monitoring and production policies.

## Folder map

- `lib/` — Flutter application
- `supabase/schema.sql` — fresh-install database schema
- `supabase/step2_cron.sql` — optional scheduled cleanup
- `supabase/functions/groq-chat/` — Groq proxy Edge Function
- `supabase/config.toml` — Edge Function JWT configuration
