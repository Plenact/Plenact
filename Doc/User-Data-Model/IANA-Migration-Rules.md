# Pinned timezone data for native migration

**Supported User Data Model versions:** 1.0. Private projection format 1.

`Src/Persistence/MigrationTimeZoneRules.json` is reproducibly generated from tzdata 2025.2 / IANA 2025b. It contains exact-second offset transitions for America/Chicago and Etc/UTC over the explicitly bounded native migration interval. GMT/UTC aliases use the UTC projection while retaining a valid original IANA alias token. This small migration resource is not a general operating-system timezone replacement or a restriction on the published Model 1.0 contract.

The generator scans six-hour intervals and binary-searches transition seconds for these known zone histories. The reference tests verify each projected transition, interval midpoint and final second against pinned Python zoneinfo. Native tests independently exercise both repeated fall-back occurrences, the spring transition and date/time-only intent. Unsupported contexts are preserved for review rather than approximated using the computer's current rules.

From an environment with the pinned tooling requirements:

```sh
python Tools/UserDataModel/build_migration_time_zones.py
```

This checks exact reproducibility. Use `--write` only for intentional resource regeneration; changing the supported version/range requires updating its native support checks, tests and documentation together.

Timezone facts derive from the [IANA Time Zone Database](https://www.iana.org/time-zones), distributed here through the pinned [Python tzdata package](https://tzdata.readthedocs.io/). No Python library code is bundled into the iOS application. Upstream license notices are retained at [tzdata license](../../Tools/UserDataModel/Licenses/tzdata-LICENSE.txt) and [Apache license](../../Tools/UserDataModel/Licenses/tzdata-APACHE-2.0.txt).
