# Dates and compatibility

**Supported User Data Model versions:** 1.0; Version 0 is historical reference only.
**Status:** Final specification. Application/API integration is tracked separately.

The normative rules are [Value-Types.md](Value-Types.md) and [Compatibility.md](Compatibility.md); transport recovery is specified in [Synchronization.md](Synchronization.md).

Date-only values preserve Gregorian calendar intent. Time-only values do not invent a calendar date. Zoned values retain local components, IANA zone, rules release, resolved UTC instant, offset and occurrence information. Gaps are rejected; folds require the selected occurrence. A metadata-only edit must not reinterpret historical times using newer rules. Legacy migration retains source bytes and reports unknown timezone intent rather than applying the importing computer's timezone.

Services advertise accepted timezone-rule releases. The reference runner pins 2025b for reproducible examples; this is not a permanent product restriction. Unsupported releases or payloads block unsafe writes while preserving local work.

Schema format assertions are required but do not prove zone/instant agreement. The semantic validator checks that agreement and [negotiates capabilities](Contracts/1.0/client-capabilities.schema.json). JSON Schema validity does not establish account authorization. See [conformance evidence](Conformance.md).
