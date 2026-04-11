# Traffic Management Flutter App

## Overview

This Flutter app is the frontend for the traffic violation management system.
It serves both regular users and administrative operators with a shared
workspace model, role-aware navigation, and a responsive dashboard shell.

Core areas include:

- violation lookup and payment flow
- appeal and progress tracking
- driver, vehicle, and profile management
- administrative monitoring and operational workflows
- AI assistant surfaces inside the dashboard

## Structure

- `lib/features/`: business pages, controllers, models, API wrappers
- `lib/config/`: routes, themes, app-level configuration
- `lib/i18n/`: translations and localization helpers
- `lib/shared_components/`: shared UI building blocks
- `lib/utils/`: helpers, navigation, service utilities
- `test/`: widget and viewport regression tests
- `tool/`: local development and validation scripts

## Common Commands

Install dependencies:

```bash
flutter pub get
```

Run the app:

```bash
flutter run
```

Static analysis:

```bash
flutter analyze
```

## Viewport Regression

Run the all-platform viewport regression suite with:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\test_viewports.ps1
```

Run tests only:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\test_viewports.ps1 -SkipAnalyze
```

The script automatically bypasses local proxy settings that can otherwise break
`flutter test` on Windows when `flutter_tester` tries to open a localhost
WebSocket.

## Notes

- State management and routing are primarily organized with GetX.
- Theme switching is persisted locally.
- Translation content is maintained in `lib/i18n/app_translations.dart`.
- The viewport regression suite currently covers login, dashboard shell, user
  home, admin home, and selected-page states across phone, tablet portrait,
  tablet landscape, and wide desktop breakpoints.
