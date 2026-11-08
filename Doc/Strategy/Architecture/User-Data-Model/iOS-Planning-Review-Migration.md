# iOS daily planning and review migration preview

**Supported User Data Model versions:** 1.0. Native source/preview format 1; local planning-preview format 1; private identity journal formats 1/2/3.
**Status:** Working-branch canonical planning converters with synthetic source/output verification. Verified account/workspace binding, appearance representation gaps and complete workspace import/recovery remain pending.

## Saved domains converted

| Source | Canonical output | Preserved values |
| --- | --- | --- |
| `Plenact.DailyPlans.v1` | `daily_plan` | Saved civil date/timezone, intention/constraints/concerns, ordered priorities, update time, nullable legacy check-in and submitted history, mood/progress snapshots, evening review and vision progress/completion. |
| `Plenact.WeeklyReviews.v1` | `weekly_review` | Original review key, week start, timezone/first weekday, reflection writing, priorities, decisions, workflow step and nullable completion/update times. |
| `Plenact.PeriodicReviews.v1` | `periodic_review` | Stable source UUID mapping, exact title/date range/timezone, reflections, independent starting/current objectives, priorities, workflow progress and timestamps. |
| `Plenact.ReviewRhythm.v1` | `review_rhythm` | Daily/weekly invitation flags, minute/weekday choices and notification intent. No OS permission or scheduled-notification state is transferred. |

Absent stores produce no plans/reviews/reminder defaults. Explicitly saved empty version-one documents remain identified as present/converted in local coverage evidence. Source document versions other than one fail closed; the rhythm preferences source has no invented store-version field. Unknown raw fields are rejected recursively before native decoding can ignore them. Native Codable decoders validate source types without invoking persistence loaders, current-value projections or workflow actions.

## Historical snapshots remain historical

Priority title and source-location strings are copied from each original snapshot rather than replaced with a current Card's writing or location. The same applies to saved check-in intentions, constraints, concerns, mood labels/emojis, progress counts and unavailable counts. No counts or achievements are recalculated from current completion state.

The saved legacy `checkIn` and nullable `checkIns` history remain separate. A missing/null history remains null; a saved empty array stays empty. The adapter never calls the native computed `checkInHistory` projection to manufacture an old historical plan/progress snapshot. Zero counts, false legacy flags, empty text, null optional values and finer timestamp evidence remain distinct.

Starting and current objective arrays retain their original UUIDs and independent writing/progress/status snapshots. Sharing an objective UUID across those two arrays is intentional; duplicates within either array are rejected. Source statuses map explicitly: Active → active, Achieved → achieved, Paused → paused, Let go → released. Objective titles are validated but never trimmed in the output.

All eight recorded review action kinds are retained: keep, keep_tomorrow, table, complete, archive, queue, tomorrow and a specific date. Their source/result priority snapshots, original decision UUIDs and recording timestamps remain history. Migration does not complete/archive/move any Cards or replay decisions.

## Exact owner and creation provenance

A priority link uses original Collection UUID, numeric Card ID and nullable source creation identity. Creation matching uses the **original native reference-epoch Double**, before UTC conversion or millisecond formatting can change its precision. This matches the existing content converter's identity discriminator. A current Card is linked only when its original owner/ID/creation provenance agrees. Missing/deleted owners, absent Cards, reused numeric IDs or different creation provenance receive stable explicit `unavailable_reference` targets rather than resolving to unrelated content.

Original snapshot writing and creation timestamps stay available even when the linked content is unavailable. Existing typed unavailable declarations are reused; no duplicate target records are emitted. Historical references never resolve into independent template copies merely because numeric IDs or retained legacy Collection UUIDs match.

Daily plan identities qualify the original source day by its saved timezone. Weekly identities retain the original full review key; periodic identities map the original UUID. Native checklist/objective/decision history UUIDs are not replaced merely to refresh a timestamp or title. Repeated preparation of an unchanged source reuses the private journal's record identities.

## Dates, ranges and safe failure

Source Date values use native seconds since the 2001 reference epoch. The converter retains those raw values through identity resolution and explicitly converts them to millisecond UTC for canonical timestamp fields, with finer evidence in the local planning report. It never relabels raw reference seconds as Unix timestamps.

Civil dates are validated exactly as Gregorian keys during 1900–2100. Saved timezone support remains the bounded pinned Chicago/UTC projection, including recognized UTC/GMT aliases. Weekly starts must agree with the saved first weekday and review key. Period starts cannot exceed ends. Progress steps must be zero through two; check-in counts must be nonnegative bounded integers with completed counts no greater than totals when both are known. Reminder minutes/weekdays are validated without invoking native normalization. Duplicate priorities, check-in IDs, decision IDs or within-array objectives require review.

The planning slice uses a candidate journal. Any unsupported source/version/shape/context discards the whole planning slice and its candidate allocations, while leaving previously converted content/settings/appearance and original backup bytes intact. `planning_blocker` and a visible review row describe the pending source. Legitimately unavailable historical targets remain explicit successful-conversion evidence and contribute to the review count; they do not fabricate missing content.

## Output and verification

The preview UI adds **Plans and reviews converted** and nonzero **Planning review items**. `Report.json` exposes `planning_review_record_count`, `planning_unavailable_reference_count` and `planning_blocker`. Successfully converted planning source keys leave the remaining-adapter inventory, including explicitly saved empty documents.

`PlanningPreview.json` is a local `plenact.ios-planning-preview` artifact, format version 1, targeting User Data Model 1.0. It retains converted store names, actual source store versions, planning/unavailable counts, source precision evidence and literal false `review_actions_executed` / `notifications_scheduled`. Canonical records still belong to the explicitly local preview workspace; no authenticated account/workspace ownership is manufactured.

The focused suite passes **65 native tests** and **86 model/tooling checks**. Five planning cases cover rich history, all action kinds, current-versus-deleted/reused references, null/empty history, independent objective snapshots, absent/empty stores, future source versions/fields, invalid timezones/counts/progress/actions/ranges and duplicate histories. Native fixtures preserve exact original bytes and stable retry records. Actual output includes five planning records and three explicit unavailable references within a 46-record synthetic snapshot; schemas/relationships and source history values are independently verified. No real owner backup, review action or OS notification is executed by these tests.

## Owner-driven acceptance

In **Plenact Import Test**:

1. Rebuild/run the app.
2. Open **See today’s list → Open today’s plan**, enter a short intention and tap **Save**. Existing saved plans/reviews may also be used.
3. Prepare a fresh local backup and migration preview using **Central — America/Chicago**.
4. Inspect **Plans and reviews converted** and any **Planning review items**.
5. Save under a new name for source-by-source ZIP verification, retaining earlier backups.

A simple saved intention exercises the daily-plan path; it does not manually accept every review workflow. Additional hands-on check-in/weekly/periodic acceptance and final whole-workspace recovery remain separate from synthetic coverage. The next Step 1 integration work includes global Week-theme/artwork-order representation, verified ownership and canonical account-bound drafts, complete export/import and original-versus-restored comparison. Cloud synchronization remains off.


### Additive appearance representation update

The global Week/theme and artwork-order gaps described at earlier checkpoints now have working Model 1.1 records, emitted separately from base records. See [versioned representation and compatibility](Version-1.1.md). Publication, ownership binding and complete workspace recovery remain pending.
