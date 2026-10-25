# Local Profile Architecture

> **Data-model context — October 24, 2026:** The [current application/data plan](../Application-Data-Plan.md) supersedes older cloud, ownership and cross-device assumptions below. Model 1.0 is published for iOS/web/Windows; runtime synchronization remains unimplemented. Dated feature/design evidence below retains its original scope.

## Planning Rhythm preferences

The [Planning Rhythm vision](Planning-Rhythm.md) introduces optional morning/evening, weekly and periodic review experiences. Cadence and planning preferences now exist locally; Model 1.0 defines their shared representation while native conversion and synchronization remain implementation work

Daily plans, drafts, decisions, and saved summaries belong to planning data, not identity credentials. Keep them usable without creating a Local Profile. Removing the profile must not implicitly remove review history. Notification permissions and delivery are separate future decisions. See the [delivery plan](Planning-Rhythm-Delivery.md)

**Status:** Implemented as a local-only profile and personalization feature. It is not online authentication.

## Product Intent

The Today avatar provides a discreet entry into identity and settings without placing a name, email, or private configuration on the main screen. Before profile creation it uses a generic person symbol; afterward it displays compact initials and the selected palette color.

## Source Ownership

```text
Src/Features/Profile/
├── ProfileModels.swift
├── LocalProfileStore.swift
├── AccountSettingsView.swift
└── README.md
```

- `ProfileModels.swift` owns local identity and personalization values.
- `LocalProfileStore.swift` owns versioned local persistence.
- `AccountSettingsView.swift` owns avatar and profile/settings presentation.
- `AppRootView` owns the current optional profile session and supplies it to Today.

This boundary can later be wrapped or replaced by an authenticated session without converting `LocalProfile` into a credential record.

## Current Profile Data

- Stable local profile ID and creation date.
- Display name and avatar color.
- Optional email and planning context stored as unverified local text.
- Optional preferred Today list.
- Reduced-content and larger-control preferences for Today.

## Persistence and Removal

The profile is encoded in local `UserDefaults` under `Plenact.LocalProfile.v1`. It is independent from Board, label, attachment, and date-specific Today persistence.

Removing the local profile deletes only this profile value. Board cards, lists, labels, attachments, comments, and Today selections remain on the installation.

## Privacy Boundary

The feature has no password, token, online account, identity provider, analytics ID, or network request. The optional email is not verified or transmitted. Product copy must call this a local profile rather than sign-in or secure account access.

Any future authentication work requires explicit provider, backend, account deletion, recovery, retention, and privacy decisions.
