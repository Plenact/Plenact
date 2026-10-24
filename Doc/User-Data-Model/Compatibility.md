# iOS, web and Windows compatibility

**Supported User Data Model versions:** 1.0. **Protocol:** 1.0. **Specification status:** final.


## Version support

| Consumer | Contract target | Definition status | Runtime status at publication |
| --- | --- | --- | --- |
| Plenact iOS | Model 1.0 / Protocol 1.0 | Defined | Existing saved formats remain local; native adapters/sync not implemented. |
| Plenact.com web | Model 1.0 / Protocol 1.0 | Defined | Web data/sync integration not implemented by this release. |
| Windows C# | Model 1.0 / Protocol 1.0 | Defined | Upcoming application; console codec probes are not its UI or sync engine. |
| PHP/Bluehost | Model 1.0 / Protocol 1.0 | Defined | Reserved v1 namespace not deployed; existing Version 0 demo remains separate. |

A client offer identifies platform (`ios`, `web`, `windows`), device UUID, application version, readable/writable model versions and readable/writable record types. Writes must be a subset of reads. Negotiate exact set intersection; do not numerically compare dotted strings or infer capability from app release numbers.

A client can retain and preview opaque unsupported record types but cannot edit them. Full snapshots are not filtered to hide unknown types; preserve unsupported bytes and their server metadata. Model 1.0’s schema resources and per-type payload version 1 are immutable. A future field/type/meaning change requires a new explicitly advertised model/payload contract. Never publish a new field under unchanged 1.0 schemas and rely on older clients dropping it.

Version 0 shared Board data is not a supported private-workspace representation. Reusing `schema_version: 1` or local `.v1` preference keys does not establish Model 1.0 compatibility. Native source adapters and account linking are explicit migration work.

## Platform persistence

All clients atomically persist records, base revisions, pending operations and cursor changes. iOS may use an application-owned transactional store; Windows should use SQLite; web should use IndexedDB with durable asset storage appropriate to the browser. These are storage choices, not different wire models.

Indefinite offline use means **no application-imposed expiration**. Browser storage can be cleared by its user or evicted without persistent-storage protection. Request persistence where supported, check quota, and disclose when the environment cannot guarantee durable local storage. A browser tab that cannot retain an outbox safely must not claim an offline edit is durably saved. Private browsing, user-cleared storage and OS/file loss cannot be overridden by a protocol guarantee. See the [Storage Standard](https://storage.spec.whatwg.org/).

Do not clear local data when a token expires or an account disappears remotely. Reauthentication only gates network operations. After cloud-account deletion, local copies stay user-controlled; provide export/remove choices and do not automatically re-upload into a new account.

## Shared intent and fallbacks

Shared preferences include creation defaults, sorting/focus rules, fonts/colors/surfaces/artwork, star style, maps choice, display choices, review cadence and shortcuts. Unset values remain unset until the chosen default is actually saved. Device viewport/window state, OS permissions, credential storage, notification delivery and unfinished drafts remain local.

Preserve unsupported fonts, symbols, surfaces, original media and maps preferences. Use a renderer/fallback or read-only placeholder rather than overwriting them. A non-mobile client may ignore lower-corner back behavior visually but must retain the Boolean. Notification intent follows the user, while each device explicitly opts into delivery; the client MUST NOT silently enable OS notifications merely because another device enabled the shared preference. Multi-device delivery is user-controlled, so duplicate delivery is possible when intentionally enabled on multiple devices.

Web clients render rich text as safe text/runs, never executable HTML. Keep sessions in the platform-appropriate secure boundary and apply the Origin/CSRF requirements in the synchronization contract. The conformance tools run on synthetic files and do not verify a browser deployment or real credential handling.

## Definition readiness versus application readiness

This specification is ready to be used by all three implementers. Production support is claimed only after that application implements its decoder/encoder, persistence, graph validation, conflict/recovery behavior, asset handling and transport acceptance checks. The [conformance report](Conformance.md) states exactly which checks currently exist; no release note may turn codec evidence into a claim of deployed synchronization.
