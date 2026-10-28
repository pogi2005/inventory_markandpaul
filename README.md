
# The System

## About the System

The System is an application developed using Flutter and Dart. It uses Supabase to store and manage data and Xendit to process online payments.

The goal of the system is to make its main tasks easier, faster, and more convenient for users.

## Technologies Used

- **Flutter** – Used to build the application's interface.
- **Dart** – The programming language used to develop the application.
- **Supabase** – Used to store and manage data.
- **PostgreSQL** – The database used by Supabase.
- **Xendit** – Used to handle online payments.
- **GitHub** – Used to store and manage the source code.

## System Requirements

Before running the system, make sure you have:

- Flutter SDK installed.
- Android Studio or Visual Studio Code.
- An Android emulator, physical device, or supported browser.
- A Supabase project.
- A configured Xendit account if payment features are required.
- An internet connection.

## How to Install the System

### Step 1: Download the Project

Download the project from GitHub or clone the repository:

```bash
git clone <repository-url>
```

### Step 2: Open the Project

Open the project folder in Android Studio or Visual Studio Code.

Make sure you are inside the folder containing `pubspec.yaml`.

### Step 3: Install Dependencies

Open the terminal and run:

```bash
flutter pub get
```

This command installs the packages needed by the system.

### Step 4: Configure Supabase

Open the [Supabase Dashboard](https://supabase.com/dashboard/).

Select your project and make sure the application has the correct project URL and publishable key.

Check that the required database tables and access permissions are configured.

### Step 5: Configure Xendit

Open the [Xendit Dashboard](https://dashboard.xendit.co/).

Make sure the payment integration is configured correctly.

Keep secret API keys in the secure backend. Do not place them in the Flutter application or upload them to GitHub.

## How to Run the System

Open the terminal inside the project folder and run:

```bash
flutter run
```

To run the application using Chrome, if web support is configured:

```bash
flutter run -d chrome
```

## How to Use the System

1. Open the application.
2. Go to the screen you want to use.
3. Enter the required information.
4. Review the information before submitting.
5. Click the appropriate button to continue.
6. If payment is required, follow the available Xendit payment instructions.
7. Check the result displayed by the system.

The exact steps depend on the features available in the application.

## Database

The system uses Supabase to connect to a PostgreSQL database.

The database stores the information required by the application. Depending on the implemented features, the system may add, view, update, or delete records.

Access to the database should be protected by proper security rules.

## Payment

The system uses Xendit for online payment processing.

Depending on the implementation, users may be redirected to a payment page or use another supported payment method.

The system should verify the payment result before marking a transaction as successful.

## Security

To help protect the system:

- Do not share passwords or secret API keys.
- Protect database access using Supabase security rules.
- Keep Xendit secret keys on the secure backend.
- Check payment results before confirming transactions.
- Do not upload sensitive information to GitHub.

## Troubleshooting

| Problem | Possible Solution |
|---|---|
| The system does not run | Check Flutter installation and run `flutter pub get`. |
| Database connection fails | Check the Supabase URL, key, internet connection, and permissions. |
| Payment does not work | Check the Xendit configuration and payment integration. |
| Application build fails | Run `flutter doctor` and check the error message. |

## Future Improvements

Possible improvements include:

- Improving the application design.
- Making the system easier to use.
- Improving error messages.
- Adding more tests.
- Improving database and payment security.

## Project Information

- **Project Name:** The System
- **Framework:** Flutter
- **Language:** Dart
- **Backend:** Supabase
- **Database:** PostgreSQL
- **Payment Gateway:** Xendit
- **Source Code:** GitHub
- **Developed By:** Add the developers' names

---

This README explains the system, the technologies used, and the basic steps for installing and running the application.
