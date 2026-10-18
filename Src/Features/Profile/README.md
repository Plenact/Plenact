# Local Profile

This feature provides a local-only identity, Today avatar, Account & Settings screen, and personalization without passwords, authentication, accounts, or network access.

## Contents

- `ProfileModels.swift`: Codable local identity, avatar palette, and preferences.
- `LocalProfileStore.swift`: versioned local persistence isolated from Board data.
- `AccountSettingsView.swift`: profile creation/editing, planning preferences, accessibility controls, privacy details, and profile removal.

Week example loading is not a profile setting. Use **Library → + Examples → Load Example Week View**; **Undo Last Load** is in that same chooser. These confirmed Week-replacement actions retain their existing local undo format and do not change personal collections or profile data.

## Data Boundary

The profile is stored in local `UserDefaults` under `Plenact.LocalProfile.v1`. Removing it does not remove Board cards, labels, Today selections, or attachment files. Email is optional local text and is not verified or transmitted.

No password, token, Sign in with Apple credential, analytics identifier, or remote account is created. Future authentication should replace or wrap the store boundary rather than changing the local profile into a pretend online account.

## Account & Settings navigation

A segmented Account / Settings control sits directly below the sheet's navigation bar on iPhone and iPad. Account opens by default. Each tab has its own scrolling form; the selector stays above the form. Profile and preference drafts live in the parent view, so switching tabs preserves edits until the existing Save or Cancel action. Avatar editing and shortcut selection keep their existing navigation and save behavior.

## Personalization

- A preferred Board list may fill Today when no date-specific choice exists.
- Reduced content hides optional supporting copy on Today.
- Larger controls increase the height of primary Today actions.

System Dynamic Type, VoiceOver, contrast, and Reduce Motion behavior remains authoritative.
The Settings tab includes a Today section with **Items in Today's Focus**: 1–12 or All open items. The local profile stores `todayFocusItemCount` (0 means All); older profiles default to 4. Save commits the draft; Cancel leaves the existing preference intact. Today uses this limit on both device layouts, preserving list order and excluding completed items/dividers. The day's total progress remains unchanged; longer previews scroll naturally.


Plan Settings opens from the gear in Today’s header. It shares planning and display
preferences with Account & Settings, including Today’s Focus count. Preferences also
save without creating a profile and survive profile removal. Shortcuts and day/week
templates open their existing editors with separate save controls.
