# Plenact Application Architecture and Planning Rhythm

> **Data-model context — October 24, 2026:** The [current application/data plan](../Application-Data-Plan.md) supersedes older cloud, ownership and cross-device assumptions below. Model 1.0 is published for iOS/web/Windows; runtime synchronization remains unimplemented. Dated feature/design evidence below retains its original scope.

**Status:** Current ownership reference and proposed review architecture, updated October 16, 2026. Today's Plan and the first Today's Vision flow are implemented; Today's Review is also implemented; Weekly Review is implemented; the first Periodic Review flow is implemented

## Product intent

Plenact helps users turn intentions into action, notice progress, and begin again with a clear plan. Today is the daily home; dated planning weeks and personal collections remain canonical owners of Cards and Notes

The approved [Planning Rhythm](Planning-Rhythm.md) adds morning intention, midday adjustment, evening reflection, weekly direction, and periodic assessment. It must connect existing content rather than create another task system

## Current source and state boundaries

- `Src/App.swift` and `Src/App/`: scene setup, root composition, navigation, and checked owner operations
- `Src/Features/Boards/`, `Lists/`, and `Cards/`: Board and focused List presentation, previews, editing, and native interactions
- `Src/Models/`, `Persistence/`, and `Features/Appearance/`: canonical records, compatible local storage, and appearance inheritance
- `Src/Features/Calendar/`: local date keys, dated Weeks, mappings, browsing, and owner access
- `Src/Features/Examples/FullMonthExamples.swift`: example workspace generation and reversible user-data backup/restore
- [Current project layout](../ProjectLayout.md): the complete source map and 1,200-code-line file policy
- `Src/Features/Labels/`: local shared label catalog, including Reference guidance labeling
- `Src/Features/Attachments/`: attachment handling, covers, and personal background assets/imports
- `Src/Features/Profile/`: device-local identity and settings, independent from remote authentication
- `Src/Features/Sync/` and `Server/`: separate shared-demo client/server material; not a production private planning sync system

Cards and Notes share a canonical record with different presentation. They are not separate task and writing databases. Optional dates and times on Cards do not establish external calendar events, recurrence, or reminders

## Current persistence

Dated planning weeks, current-Week compatibility data, personal collections, labels, bookmarks, profile, and UI preferences are stored locally in versioned preferences. Local attachments and avatars live under Documents; imported background photos live under Application Support. Bundled backgrounds are app resources

The full-month example switch preserves an offline snapshot of app preferences and local Documents/Application Support before replacing active planning data. Restore reloads the workspace. That feature is not cloud backup or synchronization

Existing formats are compatibility contracts. Preserve unsupported/corrupt data and report errors rather than replacing it with samples. Source mutations and media deletion must honor all retained references

## Proposed architecture increment

```text
AppRootView
├── Today, Week, Plans / Library, Activity          current
├── Today's Plan with local saved priorities       current
└── Planning Rhythm                               proposed
    ├── Review integration with Today's Plan
    ├── Today's Vision / Check-in / Review
    ├── Weekly Review
    ├── Periodic Review
    └── Draft sessions and saved summaries
```

Exact view names and presentation controls remain open. The proposal does not require a new root tab

### Presentation

Render existing source status and a resumable session. Collect optional reflection, show proposed actions, and require confirmation before mutation. Do not place storage, source movement, or duplicate eligibility rules in each of the five views

### Application coordination

Reuse or extract a focused service from current root coordination for source resolution, eligibility, confirmed decisions, and persistence. Coordinate session progress with source writes using operation identity and recovery; UI callbacks alone cannot establish exactly-once behavior

### Domain

Proposed Daily Plan and Review Session concepts record priorities, periods, reflection, decisions, and draft/completed state. Objectives and milestones are optional later additions. References require owner context plus item identity; update references explicitly when a cross-owner move remaps IDs

Saved summaries retain dated context separate from live tasks. Missing or deleted sources remain identifiable as unavailable, not recreated from summary text

### Persistence

Choose a versioned local session/plan format after the write/recovery boundary is designed. Do not silently add review fields to the shared-demo transport. Extend example backup/restore coverage and in-memory reset behavior before new review state ships

## Navigation, dates, and scope

- Resolve Day/Week dates using `PlanningCalendarDocument`, its first weekday, and `PlanningDate`
- Use explicit date kinds; do not infer timed appointments from a title or Scheduled List membership
- Retain the actual source owner when opening a priority from Today or a saved review
- Back returns to the presenting review or source context without unintended tab changes
- Allow selected historical periods without altering the current-day plan silently
- Configure working List roles by identity so renamed/removed defaults have a repair path
- Keep notification delivery, remote sync, and external-calendar permissions outside this implementation plan

## Delivery and verification

Build daily planning and evening carry-forward first, then midday adjustment, weekly direction, and periodic objectives. See [Planning Rhythm delivery plan](Planning-Rhythm-Delivery.md) for failure handling, compatibility requirements, open decisions, and acceptance scenarios

Tests must establish persistence and mutation safety; hosted rendering alone does not prove drafts, gestures, accessibility, or recovery on a physical device

## Daily-plan source and storage

`Src/Features/Planning/TodayPlan.swift` provides the first daily planning increment. `DailyPlanStore` reads/writes a versioned `Plenact.DailyPlans.v1` document, retains corrupt/unsupported data, merges other days, and detects conflicting same-day saves. Priorities retain owner-qualified source links and display context rather than copying tasks. The view opens original items through existing presenter-preserving wrappers

The local example workspace already captures this preference key; restoration remounts Today and discards demo view state. Daily-plan round-trip, source ownership, current completion, corrupt-data retention, conflict, example restoration, and hosted rendering checks cover this increment. Review drafts, decisions, summaries, and cadence still require their staged design
