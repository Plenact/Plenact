# Version 1.0 — Defining Plenact’s User Data Model

**Supported User Data Model versions:** 1.0; Version 0 is historical reference only.
**Status:** Final specification. Application/API integration is tracked separately.

The final contract is [Specification.md](Specification.md) and its linked normative documents, together with the [schema registry](Contracts/1.0/registry.json). This overview is an entry point, not a second competing wire definition.

Confirmed product requirements: one private owner initially (Justin Reina), stable verified account identity, iOS/web/Windows interoperability, indefinite offline use and shared settings by default. Credentials, permissions, caches, viewport, operational recent history, unfinished creation drafts and recovery journals remain local.

Complete records use stable UUIDs and explicit wire fields. Revision-checked transactions are atomic; conflicting edits retain local/base/remote values. Successful deduplication receipts and deletion markers last for the account lifetime. A device returning after a long absence reauthenticates and reconciles a fresh snapshot without losing pending work.

The [GitHub release](Publication.md) publishes the definition and test tools. [Integration status](Integration-Plan.md) remains separate: no production Model 1.0 API, native migration or synchronized personal workspace is claimed.
