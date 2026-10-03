**Status:** Local Profile remains device-only. Source now includes an HTTPS shared-demo login/directory/Board client and Keychain session, but no Bluehost migration or API deployment has occurred. The demo is shared only with authenticated registered users; production privacy, tenant isolation, and organization ownership are deferred

## Intent

The demo is intended to provide one shared directory of registered Plenact demo users so a person can identify themselves and reference other people on cards. Demo content is not private and must contain only information safe for every demo user to see. A registered directory identity is distinct from:

- The current **Local Profile**, which is stored only on this installation and has no authentication credentials
- A **card assignment**, which connects a person or manually entered name to a card
- **Board authorization**, which determines who can read or change Board content

For this demo phase, the shared Board and minimal user directory are visible to authenticated registered demo users. Jim alone edits canonical Board content. Other members can add or remove only their own assignment; Jim can manage any active user's assignment. Keep read visibility, permission to edit shared demo records, and any future private or organization data as separate concepts

## Proposed Minimal Model

Use a stable server-generated user ID as the durable identity. Do not use a display name or email address as a foreign key

| Concept | Proposed data | Notes |
| --- | --- | --- |
| Registered demo user | Stable ID, normalized unique username, display name, optional email, account status, server-generated creation/update timestamps | Password material is never returned by an API |
| Card assignee | Card ID, assignee kind, optional registered-user ID, optional manual display name, ordering metadata | Enforce exactly one identity form for each assignment |
| Directory entry | Stable ID, username or chosen handle, display name, optional avatar metadata | Return only explicitly approved fields; never return email or password hashes in directory responses |

Registered users and manual assignees should remain distinguishable in the model and UI. A manual name is useful for a person who does not have a Plenact account, but it must not be mistaken for a verified account or grant access

Card assignment and card listing are separate relationships. The demo Board is shared, so assignment identifies a person associated with a card; it does not imply private ownership. Production may later define private Boards and different access rules

## Registration And Session Boundary

Accounts are invite/admin-created; open self-registration is not part of v1. A CLI-only operator tool creates Jim as the sole Board editor, and Jim can create member accounts after signing in

Even though demo content is public, account passwords remain authentication secrets: they identify who is acting, may permit edits, and may be reused elsewhere. Accept them only over HTTPS, hash them on the server with a maintained password-hashing API such as Argon2id or bcrypt, and never store, log, commit, or share them in plaintext. Use unique disposable demo credentials; rotate any credential already shared in chat or another uncontrolled channel. Password reset, rate limiting, account recovery, session expiry, logout, and credential revocation are part of an account feature, not optional polish

The reference app token is not a user login credential. The Plenact API uses per-user sessions and server-side authorization. Keep the local profile usable without an account; linking it to a remote account is a separate, explicit operation

## Demo Visibility And Production Boundary

For the demo phase, the user directory and shared demo records are intentionally visible to registered demo users. They must contain no private, health-sensitive, or otherwise confidential information. A bearer token or login gate may restrict API operations, but it does not make shared demo records confidential from demo users

Production is deferred. Before handling non-demo data, define tenant ownership, per-record authorization, organization membership, directory consent and visibility, retention, account deletion, and whether users can hide or suspend directory entries

Never expose passwords, password hashes, session tokens, private profile context, or authentication state in a directory response. If email is not required for the demo workflow, omit it from shared directory responses

## Card Assignment Behavior

`KanbanCard.members` is now a typed Codable assignment collection. Existing string values migrate to manual assignments; registered assignments preserve their stable user IDs

Proposed assignment behavior:

- **Assign registered user**-  persist a stable user ID and show the approved display name
- **Add manual person**-  persist the entered display text as an explicitly unregistered assignment
- **Reference/tag**-  if product semantics differ from ownership of an action, define a separate relation rather than overloading assignment
- **Rename/display changes**-  retain the cached display name in the snapshot; the directory remains authoritative for current profile display
- **Unavailable account**-  keep the reference and show a clear inactive/unavailable state; do not silently retarget or delete it
- **Removal**-  remove only the card assignment unless an explicit account-deletion workflow says otherwise

Decide whether the UI uses separate “Assign” and “Mention/reference” actions or one unified people picker before implementing the card editor. Those actions can imply different expectations to users

## Bluehost Data And API Boundary

The `Plenact Database Demo` is a reference for transport and database techniques, not a user schema to copy wholesale. Its Planner snapshot is stored under one configured installation ID and its API uses a shared app token. This can inform a controlled shared demo only; it is not a production account or ownership model

Before a user migration or endpoint is written, define:

- Demo registration policy and unique user identity
- Server-side password hashing, login/session handling, logout, rate limiting, and account recovery
- Which demo records are shared and visible, and which write actions demo users may perform
- Production directory visibility, ownership, tenancy, and per-record authorization (deferred)
- Stable IDs, uniqueness, deletion/deactivation, and retention behavior
- API request/response contracts and safe error semantics
- Schema version and migration path for existing `[String]` card members
- UTC server timestamps, storage actor/provenance, backup, restore, and operational ownership

Schema version describes payload shape; record revision describes changes over time. Keep those concepts separate. Use server-generated timestamps and actor IDs; never trust client-supplied ownership or storage-author fields

## Staged Delivery

1. Keep the directory and Board shared, non-private, and limited to safe demo data
2. Rotate any credentials previously exposed in chat, Git history, or shared archives before using the development host. Never copy an exposed password into source or fixtures
3. Test the local PHP API, migration, and role restrictions against a disposable Bluehost-compatible database
4. Configure the production hostname in the app build setting, deploy the API over HTTPS, and verify login/logout, throttling, seed idempotency, and revision conflicts
5. Test shared Board browsing, self-only assignment changes, manual names, inactive-user handling, offline behavior, and explicit future local-Board synchronization

Do not use real or sensitive personal data in the shared demo. Never put passwords in source control or share them in plaintext. Keep production accounts and private or organization data out of scope until their ownership and authorization model is approved

## Deferred Decisions

- Whether mentions/reference should become distinct from assignments
- How inactive accounts remain recognizable in existing assignments
- Whether a local-only profile should link to a demo account
- Which production identity, tenant ownership, and access-control model will replace the demo boundary