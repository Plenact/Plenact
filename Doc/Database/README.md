**Status:** Planning and local schema draft. No Plenact application database migration has been applied and no user-registration API has been deployed. This folder is not connected to, imported from, or dependent on the separate Database Demo project

## Goal

Prepare a new, dedicated Bluehost MySQL-compatible database for a shared Plenact demonstration. Registered demo users will be able to discover one another and reference people on shared demo cards. Demo content is intentionally visible to registered demo users and must contain only information safe for that audience

For the initial demo, all registered users can browse shared content; Jim is the sole canonical Board-content editor, while other registered users can manage assignments. This phase is not a production tenant/privacy design. Do not store personal, health-sensitive, confidential, or real customer content in the shared demo database

## Documents

- [`Plenact-Data-Contract.md`](Plenact-Data-Contract.md) - proposed entities, relationships, date semantics, metadata, and decisions still needed before schema creation
- [`Initial-Demo-Import-Plan.md`](Initial-Demo-Import-Plan.md) - proposed synthetic starter-data seed and Jim demo-account sequence
- [`../../Server/SQL/README.md`](../../Server/SQL/README.md) - draft migration status and application rules

## Bluehost Setup Boundary

Database provisioning must be completed in the Bluehost control panel by an authorized operator. Do not put cPanel passwords, database passwords, API tokens, or populated configuration in this repository or chat

After the contract and draft migration are reviewed and tested, provision a **new database distinct from any reference/demo database**, using a Bluehost-assigned database name and a dedicated database user. Store runtime configuration outside `public_html`. Give the API account only the DML permissions it requires; apply schema migrations using a separate administrative workflow

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

The draft contract distinguishes:

- **Schema version:** structure/meaning of an encoded payload or migration level
- **Record revision:** changes to a particular stored record or snapshot
- **Provenance:** who performed an operation and its server-side UTC time

These must not be conflated. Server-generated timestamps and verified actor IDs are authoritative; client clocks and client-supplied ownership are not

## Current App Boundary

Plenact currently persists Board and Profile data locally. The separate reference project informed the transport/database discussion but is not a source dependency or deployment target. The Board must not connect to Bluehost until the data contract, migration, and compatibility tests are approved