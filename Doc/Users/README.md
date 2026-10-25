# User identity and private workspace ownership

**Supported User Data Model versions:** 1.0; Version 0 historical reference only.
**Updated:** October 24, 2026.

The current private-workspace definition is [Model 1.0](../User-Data-Model/Specification.md). Its initial owner is Justin Reina; a verified stable account UUID establishes ownership. The display name, local profile email and device UUID do not grant access.

A Local Profile remains usable without login. Model 1.0 synchronizes profile text and shared preferences as private owned content, separately from credentials, OS permissions and operational device state. The normal app is not cloud-backed by this definition release.

The historical **Version 0** demo uses registered users, a shared directory and Jim as canonical Board editor. Repository records report its October 3, 2026 deployment with synthetic content; no fresh host verification was performed here. See [historical contract](../Database/Version-0/Plenact-Data-Contract.md). Those shared-demo identities and sessions must not automatically become private-workspace ownership.

Manual assignees remain manual. Legacy directory references retain legacy_demo provenance unless verified account linking proves otherwise. Model 1.0 is initially one private owner, not multi-user sharing or an organization-directory service.

Native sessions belong in secure platform storage; browser cookie sessions require the Origin/CSRF boundary. Account provisioning/session acquisition is a separate identity interface, not editable profile JSON. See [synchronization](../User-Data-Model/Synchronization.md), [compatibility](../User-Data-Model/Compatibility.md), [lifecycle](../User-Data-Model/Data-Lifecycle.md) and the [delivery plan](../Application-Data-Plan.md).
