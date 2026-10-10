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

## Personalization

- A preferred Board list may fill Today when no date-specific choice exists.
- Reduced content hides optional supporting copy on Today.
- Larger controls increase the height of primary Today actions.

System Dynamic Type, VoiceOver, contrast, and Reduce Motion behavior remains authoritative.