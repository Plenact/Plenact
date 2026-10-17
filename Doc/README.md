# Plenact Documentation

Product, UX, architecture, demonstrations, and engineering references. Current behavior and future direction are identified explicitly

## Start here

- [Your Planning Rhythm](Design/Planning-Rhythm.md) — approved operating vision for Today's Vision, Today's Check-in, Today's Review, Weekly Review, and Periodic Review; morning, midday, and evening reviews are implemented; Weekly Review is implemented; the first Periodic Review flow is implemented
- [Planning Rhythm delivery plan](Design/Planning-Rhythm-Delivery.md) — staged delivery, source identity, local persistence, interruption safety, and acceptance gates
- [Life planning model](Design/Life-Planning-Model.md) — current organizing model, default Lists, and the connection between daily action and reflection
- [Today interaction design](Design/Today-View-UI.md) — current Today experience and proposed Today's Plan evolution
- [Application architecture](Design/Today-View-Architecture.md) — current ownership and proposed shared review foundation
- [Board and scheduled planning](Design/Board-and-Scheduled-Views.md) — dated views, the Scheduled List, and the separate agenda proposal

## Supporting references

- [Board presentation](Design/Board-Presentation.md) — historical implementation detail with a current-context note
- [Checklist actions](Design/Checklist-Actions-Architecture.md) — action identity and detail boundaries
- [Local profile](Design/Local-Profile-Architecture.md) — device-local identity, settings, and session boundary
- [Users](Users/README.md) — separate shared-demo user/account direction
- [Database](Database/README.md) — shared-demo data and import contracts, not review storage
- [Server](../Server/README.md) — separate API and SQL work
- [Organization profile source](GitHub-Organization-Profile/README.md) — repository-maintained public-facing copy; editing it does not publish remotely
- [Demo recordings](Demo/README.md), [coding style](Style/README.md), and [legacy source pointers](Src/README.md)

## Historical release handoffs

These are October 4, 2026 audit snapshots, not current implementation inventories. Preserve their dated evidence and consult the updated design documents for subsequent direction

- [Agent One handoff](Establishment/Production-Preparation-Handoff_AgentOne.md)
- [Agent Two handoff](Establishment/Production-Preparation-Handoff_AgentTwo.md)

## Status at October 16, 2026

The app has local Today/Week/Day/Calendar planning, personal Lists and Boards, Cards and Notes, labels, Activity, Appearance, starter tutorials, and offline example workspace restoration. Today's date opens a saved Today's Plan with linked priorities and optional intention, constraints, and concerns

Today's Check-in, Today's Review, Weekly Review, Periodic Review, saved review summaries, optional objectives/milestones, and review cadence preferences are approved direction. They are not implemented by this documentation change

## Documentation rules

- Label implemented, approved/proposed, exploratory, and historical material explicitly
- Keep one shared operating vision and link supporting docs to it
- Distinguish local Calendar planning from external-calendar synchronization
- Distinguish the separate shared-demo client/server from private production accounts or synchronization
- Do not describe planned reviews, notifications, cloud/team sync, or web/desktop clients as available
- Preserve historical verification dates; documentation changes are not new runtime test evidence
- Avoid medical, treatment, clinical-validation, privacy-compliance, or regulatory claims
- Keep examples respectful and update documentation as implementation is validated

The `.webloc` files are local resource shortcuts, not source dependencies. This update publishes Markdown within the repository; it does not deploy a website or modify remote services
