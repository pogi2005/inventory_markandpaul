# Simple Inventory

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Supabase setup

1. Create a Supabase project.
2. In the Supabase SQL Editor, run [`supabase/schema.sql`](supabase/schema.sql).
3. In Authentication settings, enable anonymous sign-ins.
4. Run the app with the project URL and publishable anon key:

```powershell
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_ANON_KEY
```

The app signs in anonymously and uses row-level security so each anonymous user
can access only their own inventory. A different device or a cleared app session
gets a different anonymous user and therefore a separate inventory. Add a real
sign-in flow before using the same inventory across devices.

The first Supabase session imports products, sales, and reset state from this
device's existing local cache if the Supabase account has not been initialized.
Existing Firestore data is not copied automatically; export it separately and
import it into Supabase if that history must be retained.

Never put a Supabase service-role key in the app. The anon key is intended for
client use; row-level security in `supabase/schema.sql` is required.

## Xendit checkout setup

1. Revoke any Xendit API key previously pasted into chat, then create a new
	development key in Xendit.
2. Run the updated `supabase/schema.sql` in the Supabase SQL Editor.
3. From this project folder, link the Supabase CLI and deploy both functions:

```powershell
supabase link --project-ref YOUR_PROJECT_REF
supabase functions deploy create-xendit-invoice
supabase functions deploy xendit-webhook
```

4. Set the rotated Xendit development secret and a webhook callback token as
	Supabase Function secrets. Never put either value in Flutter or commit it:

```powershell
supabase secrets set XENDIT_SECRET_KEY=YOUR_ROTATED_DEVELOPMENT_KEY XENDIT_WEBHOOK_TOKEN=YOUR_WEBHOOK_TOKEN
```

5. In Xendit, configure the invoice paid/expired callback URL as
	`https://YOUR_PROJECT_REF.supabase.co/functions/v1/xendit-webhook` and set
	its callback verification token to the same `XENDIT_WEBHOOK_TOKEN` value.
6. Launch the Flutter app with the Supabase URL and publishable anon key as
	described above. Xendit presents its available payment methods on the hosted
	checkout page; the app records a sale only after the verified webhook.

Use Xendit development mode for testing. This workspace does not contain your
Supabase project credentials, so function deployment and a real webhook test
must be completed from your environment.
