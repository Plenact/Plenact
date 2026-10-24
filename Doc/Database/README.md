**Supported User Data Model versions:** Version 0 reference; see [Version 1.0 documentation](../User-Data-Model/README.md) for the final successor specification.

## Planning Rhythm storage boundary — October 16, 2026

The [five review experiences](../Design/Planning-Rhythm.md) are approved direction. Today's Plan, morning progress, and evening review decisions/reflections use versioned local daily-plan storage; evening mutations have a recovery journal. Midday, weekly, and periodic workflows remain planned; the existing shared-demo schema is not their storage contract

No database deployment, remote review endpoint, schema migration, or user-data upload is authorized by the [delivery plan](../Design/Planning-Rhythm-Delivery.md). Extend local example-workspace restoration coverage before new review stores ship

**Status:** Version 0 shared-demo reference. Newer [deployment records](../../Server/SQL/README.md) report migration 001 and the synthetic seed applied October 3, 2026. Live deployment was not reverified for this update. The separate Database Demo project is not a dependency.

## Goal

Prepare a new, dedicated Bluehost MySQL-compatible database for a shared Plenact demonstration. Registered demo users will be able to discover one another and reference people on shared demo cards. Demo content is intentionally visible to registered demo users and must contain only information safe for that audience

For the initial demo, all registered users can browse shared content; Jim is the sole canonical Board-content editor, while other registered users can manage assignments. This phase is not a production tenant/privacy design. Do not store personal, health-sensitive, confidential, or real customer content in the shared demo database

## Documents

- [`Plenact-Data-Contract.md`](Plenact-Data-Contract.md) - historical shared-demo entities, relationships and limitations
- [`Initial-Demo-Import-Plan.md`](Initial-Demo-Import-Plan.md) - synthetic starter-data seed and recorded demo deployment
- [`../../Server/SQL/README.md`](../../Server/SQL/README.md) - recorded migration/deployment status and application rules

## Bluehost Setup Boundary

Database provisioning must be completed in the Bluehost control panel by an authorized operator. Do not put cPanel passwords, database passwords, API tokens, or populated configuration in this repository or chat

For a new isolated environment, after reviewing and testing its migration, provision a **new database distinct from any reference/demo database**, using a Bluehost-assigned database name and a dedicated database user. Store runtime configuration outside `public_html`. Give the API account only the DML permissions it requires; apply schema migrations using a separate administrative workflow

The local app must call an HTTPS API. It must never connect directly to MySQL or contain database credentials. Keep development/demo and any future production resources separate

## Provisioning Checklist

1. Confirm the reviewed data contract and supported Bluehost MySQL-compatible server version
2. Create a new database for Plenact using a unique name; record the actual Bluehost-prefixed name privately
3. Create a dedicated database user with a unique generated password stored in a password manager
4. Grant only the privileges needed by the API account. Keep schema-change privileges in the administrator workflow
5. Create private API/database configuration outside the web root with restrictive directory/file permissions
6. Prepare reviewed, ordered, additive SQL migrations and a migration ledger before applying schema
7. Deploy API code over HTTPS, then test health, registration/login, directory visibility, authorization, validation, and CRUD using synthetic demo data
8. Verify backup/restore, credential rotation, and that public demo records contain no sensitive information

This checklist does not create the Bluehost database or apply migrations. Exact names, credentials, and hosting actions remain in Bluehost and the password manager; do not paste secrets here

## Storage Metadata

The historical contract distinguishes:

- **Schema version:** structure/meaning of an encoded payload or migration level
- **Record revision:** changes to a particular stored record or snapshot
- **Provenance:** who performed an operation and its server-side UTC time

These must not be conflated. Server-generated timestamps and verified actor IDs are authoritative; client clocks and client-supplied ownership are not

## Current App Boundary

Plenact currently persists Board and Profile data locally. The separate reference project informed the transport/database discussion but is not a source dependency or deployment target. The normal workspace is not automatically synchronized; the separate demo transport must not be treated as private-user synchronization
