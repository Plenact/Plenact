# Complexity, confidence, and building Plenact with AI

**Date:** October 26, 2026  
**Context:** Justin Reina and Alex's Plenact development collaboration, following owner acceptance of portable test package v12.

This reflection grew out of Justin's question: did the migration work really need to be this complicated, and is building Plenact without AI or a large, experienced team possible?

The answer is yes: a solo developer can build Plenact. The practical conditions are a manageable scope, time to learn, clear boundaries, and appropriate review. AI can make the work more accessible, but it does not eliminate engineering judgment or the need to understand the result.

Some of today's complexity was necessary. Some came from the scope we chose. Some friction was avoidable. Those deserve separate examination, because each calls for a different response.

## 1. Why this work was difficult

Building a screen that saves a value is different from proving that an existing user's complete workspace can be converted, edited, exported, restored, and recovered safely.

Our Step 1 work involves several representations of the same information:

- Existing native application stores and original media files.
- A portable, versioned user data model.
- An editable native workspace reconstructed from that portable model.
- A new portable export representing supported edits after import.
- Recovery evidence capable of restoring the previous workspace.

Each representation has a purpose. The difficulty is keeping their meanings aligned. An export can be valid JSON and still refer to the wrong Card, omit a preference, reorder authored history, or lose an attachment.

The intended guarantee is therefore stronger than “the file opened.” We want supported changes to survive, unsupported changes to be reported, originals to remain available, and recovery to remain possible.

### Identity is more difficult than appearance

Two Cards can have the same title. Native numeric identifiers can overlap across owners or Weeks. A deleted item can leave historical references behind. A newer item can reuse a local number.

Consequently, a migration cannot safely resolve identity from a title or an unqualified number. It needs explicit ownership, stable identifiers, and creation provenance where required. Otherwise, an apparently reasonable conversion can attach a saved reflection or bookmark to the wrong item.

Monday rollover exposed this directly: newly created Weeks reused local numeric identifiers. Owner-qualified mapping was necessary to preserve the actual relationships.

### Historical writing is not a live view

A saved check-in describes a moment in time. Later changes to a Card's title, location, or completion do not authorize rewriting that snapshot.

Likewise, a recorded review decision is history. Exporting a decision must not execute it again. A saved instruction to move or complete an item cannot be treated as a new command during reconstruction.

This distinction explains why planning and review data require more care than copying current text fields.

### Recovery is part of the feature

A successful import is only one outcome. Interrupted installation, malformed input, changed originals, and unsupported edits also need defined behavior.

Retaining the previous workspace, preserving exact native evidence, checking hashes, and keeping recovery history contribute to the feature's reliability. They are not merely administrative work around the feature.

Still, every extra recovery mechanism adds maintenance cost. Its purpose and authority must remain clear, especially when an isolated inspection copy and an editable main workspace coexist.

## 2. Which complexity came from our chosen scope?

We chose to preserve an existing application while introducing a portable model and supporting edits after import. That is a substantial compatibility commitment.

A narrower project could begin with one platform, one storage representation, a small set of features, and a one-time migration. It would have fewer conversion paths to verify.

Plenact's intended direction includes indefinite offline use, settings that generally follow the user, verified original media, and eventual iOS, web, and Windows clients sharing a contract. Those choices are reasonable product requirements, but they expand the work.

In particular, “this category migrates” does not establish “every later edit to this category can be exported.” The latter requires reconciliation between the imported baseline and the current workspace, with explicit rules for identity, creation, deletion, and references.

That is why we have treated daily plans, evening reviews, and weekly reviews as separate checkpoints. They share infrastructure, but they have distinct lifecycle and historical requirements.

The lesson is not that every product needs this architecture. It is that reliability claims must match the scope actually promised.

## 3. What was avoidable today?

Necessary complexity does not excuse confusing instructions, incomplete fixtures, or difficult diagnostics.

### The initial timestamp fixture was too convenient

The first daily-plan export test used a timestamp already aligned to milliseconds. An ordinary application save produced finer precision. Portable timestamps use milliseconds, and the final native comparison rejected the representational difference.

The owner encountered the failure even though the initial automated tests passed.

We inspected the saved source, reproduced the rejection with a synthetic high-precision timestamp, and corrected comparison at the declared wire precision. Exact native source timestamps remained in the accompanying backup. Additional checks still distinguish changed milliseconds and authored values.

The improvement was not simply another passing test. We replaced an unrealistic assumption with a test of ordinary save behavior.

### The failure message did not identify the boundary

The export error listed supported features and said another saved change needed an adapter. It protected the workspace by refusing export, but did not explain the actual precision mismatch.

Refusing an unsafe export is valuable. Giving the owner a useful reason is also part of engineering quality. Future diagnostics should identify the affected domain and reason without exposing private writing or media.

### I gave an incorrect navigation instruction

I initially directed Justin to Daily review, which opens saved history, instead of the guided evening-review editor. The correct entry uses Start, Resume, or Revisit today's review depending on saved state.

That caused unnecessary navigation and uncertainty. It was an instruction error, not an owner error.

Future acceptance instructions should be checked against the current UI, identify state-dependent labels, and distinguish viewing history from editing it.

### The workflow asks the owner to distinguish too many operations

Native backup, migration preview, package review, isolated installation, editable import, edited export, and two different Undo operations have different effects.

The distinction is technically important, but remembering it should not become the owner's primary task. The confusion between a native backup ZIP and an edited portable package showed why clearer labels and state guidance would help.

An eventual workflow improvement should make the next valid action easier to recognize while preserving the safeguards. We should not solve interface confusion by weakening verification.

### One focus problem remains unexplained

Reflection fields initially appeared unable to accept focus. They later worked after reopening the flow. Hosted standalone and nested synthetic editors accepted focus and typing, but those results did not reproduce the reported failed interaction.

We must retain that uncertainty. We did not establish a root cause or deliver a product UI fix for that incident. Recovery of the interaction is not proof that its cause has been removed.

## 4. What Justin contributed as an engineer

Justin's contribution was not limited to operating the Simulator.

He established the requirements that made the work meaningful: preserve existing data, retain originals and Undo history, support offline use, avoid silent loss, keep personal data out of fixtures, and do not claim synchronization before it exists.

He also supplied evidence that changed the implementation. Real package exports, screenshots, saved settings, rollover behavior, and failure reports exposed gaps that simplified fixtures did not cover.

These are engineering activities:

- Defining what must remain true when the implementation changes.
- Distinguishing an expected result from a plausible-looking result.
- Testing the application through its actual user workflow.
- Reporting failures rather than accepting reassuring summaries.
- Insisting that completion claims be supported by evidence.

Learning every internal adapter immediately is not a prerequisite for contributing this judgment. At the same time, the implementation should become more understandable as the project matures. The owner should not have to accept permanent dependence on an opaque system.

## 5. Is a solo-led Plenact realistic?

Yes, with a sustainable definition of the next deliverable.

A solo developer can build useful software by sequencing work, learning as needed, choosing supported dependencies, and keeping the initial product smaller than the eventual vision. Team size is not the only way to manage complexity; reducing simultaneous commitments is often more effective.

The complete cross-platform vision is a larger responsibility than a local application. Authentication, synchronization conflicts, durable offline changes, verified media transfer, backend operations, security, and recovery each add distinct failure modes.

It would be misleading to promise that AI makes all of that easy, or that one person must master it all before continuing. A reasonable path is to keep ownership and product direction with Justin, use AI for focused implementation and investigation, and seek experienced review at consequential boundaries.

Examples of useful review points include real account ownership, production migration behavior, authorization, synchronization semantics, and disaster recovery. Such review can be targeted; it does not necessarily require assembling a large permanent team.

The important question is whether the next commitment is understandable, testable, and maintainable with the resources available.

## 6. What AI changes—and what it does not

AI can read a broad codebase, connect related behaviors, draft adapters, generate synthetic cases, inspect package differences, and help document decisions. That can reduce the effort needed to explore an unfamiliar area.

It can also produce more code than a person can comfortably review, make an incorrect assumption consistently across implementation and tests, or give a confident explanation for behavior it has not observed.

Today's timestamp failure is a useful reminder: an implementation and its fixture can agree while both miss normal application behavior.

Therefore, AI-generated work should remain subject to ordinary engineering discipline:

- State the supported scope and remaining uncertainty.
- Check against independent contracts and source evidence.
- Exercise meaningful failure cases, not only successful examples.
- Preserve reviewable changes and recovery boundaries.
- Correct claims when evidence contradicts them.

AI assistance is most useful when it increases the owner's ability to make informed decisions. The volume of generated code is not itself progress.

## 7. Confidence comes from different kinds of evidence

The current evidence includes 65 affected native tests, 112 tooling tests, independent synthetic package validation, and owner-confirmed round trips through v12. These are dated checkpoint results, not a permanent guarantee or a completion percentage.

Each layer answers a different question:

| Evidence | What it helps establish | What it does not establish alone |
| --- | --- | --- |
| Native synthetic tests | Specified conversions, rejection paths, reconstruction, and recovery behavior | Every real workspace shape or user interaction |
| Independent package checks | Schemas, references, identities, manifests, and original-byte integrity | Correct application presentation or authenticated ownership |
| Private source/package comparison | What actually changed and whether retained data was preserved | Every possible future edit |
| Owner acceptance | Expected values returned through the real application workflow | All untested features or interruption scenarios |
| Recoverable checkpoints | A known state to return to and evidence to inspect | A complete production disaster-recovery guarantee |

The tests become stronger when their failure assumptions differ. Repeating the same assumption in several tools is less valuable than checking the result from another direction.

## 8. How we should make the work easier to own

### Keep one understandable responsibility per boundary

Conversion, edited-export reconciliation, installation, and recovery should have clear responsibilities. Shared logic should be reused where semantics match, while identity-changing operations should remain explicit.

Consolidation is useful when it removes duplicated rules. It becomes harmful if it hides important differences behind a large generic mechanism.

### Make the architecture explainable

The owner should be able to locate the answers to a few practical questions:

1. Where is the saved value stored?
2. Which representation is authoritative for this operation?
3. Which code converts or reconciles it?
4. What rejects unsupported changes?
5. How is the previous workspace recovered?

Documentation should make those answers easier to find. It should not require reading a long conversation or interpreting every historical “pending” note as current status.

### Prefer representative fixtures

Fixtures should include ordinary save timestamps, nonempty bookmarks, overlapping local identifiers, absent and explicit-empty values, historical snapshots, and relevant original files.

We should add these because they exercise real requirements, not to inflate test counts. Regression cases should explain the failure they prevent.

### Use manual tests where they add evidence

Automated checks should run first. Then the owner should perform one focused acceptance test for the concrete checkpoint.

If that test fails, we should inspect the saved source before asking for repeated steps. Once a value is safely saved and verified, the owner should not need to re-enter it merely to accommodate our debugging.

### Treat understandability as a deliverable

A feature is harder to own if its successful operation depends on remembering hidden exceptions. Clear names, bounded modules, useful errors, documented invariants, and reproducible checks reduce future dependence on any particular assistant or developer.

The aim is for Justin to become more capable of navigating the system over time, even if specialist review remains valuable.

## 9. Our checkpoint and the next responsibility

At this checkpoint, v12 is the latest owner-accepted portable package. Weekly reflection writing returned after verified export and editable re-import, alongside earlier daily/evening writing. Personal packages, screenshots, and originals remain outside repository fixtures.

Step 1 of the four-step plan remains in progress. Periodic reviews and objective snapshots are next. Template metadata, remaining calendar and structural operations, drawing-file changes, broader personalization acceptance, verified ownership, and final reconciliation/compatibility/recovery work remain.

Cloud synchronization is disabled. Published Model 1.0 remains unchanged; working Model 1.1 is not published. Passing the current checkpoint does not authorize or establish completion of the later cloud, synchronization, web, or Windows steps.

The next responsibility is to keep making progress without making the system harder to understand than it needs to be. That means completing bounded work, acknowledging what evidence does and does not show, and reducing avoidable complexity as deliberately as we add capability.

## Related records

- [Editable import and owner acceptance checkpoints](../User-Data-Model/Editable-Import.md)
- [Edited-export support inventory](../User-Data-Model/Edited-Export-Inventory.md)
- [Integration plan](../User-Data-Model/Integration-Plan.md)
- [Current application and data plan](../Application-Data-Plan.md)
