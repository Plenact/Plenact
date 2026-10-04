# Plenact Production-Preparation Handoff

**Prepared:** 2026-10-04  
**Purpose:** Give the next product/engineering agent an evidence-based starting point for taking Plenact from its current local-first development build toward a responsible iOS release.  
**Repository snapshot audited:** `main` at `5a39025` (`comment updates`), clean and synchronized with `origin/main` at the time of audit.

> This is a handoff and release-planning document, not a claim that Plenact is production-ready. “Implemented” below means present in the current source and/or covered by the active test target. “Verified” means a check was actually run during this audit. Release, privacy, backend, and App Store decisions still require the product owner and appropriate reviewers.

## 1. Executive Summary

Plenact is an iPhone planning and personal-organization app built around a Week Kanban Board. Today is a quick daily entry point into that existing Board, while Lists has expanded the product into separate personal lists and multi-column boards. Cards are intended to hold useful context, notes, plans, and actions without making every thought a scheduled event.

The most important product distinction is:

- **Board**: an organized workspace of ordered lists and cards.
- **List**: a single card column, such as a Week weekday, Shopping, or Reminders.
- **Card**: an activity, note, or plan with supporting content.
- **Checklist action**: a next step inside a card; some actions link to a card or own reduced Action Detail.
- **Today**: a date-specific projection onto one existing list, not a duplicate task store.
- **Personal collection**: a local List or Board in the Lists library, separate from the Week Board.

The product is currently **local-first**. Week, personal collections, labels, profile settings, and media are stored on the installation. There is no production multi-tenant account system or multi-device sync for personal collections. The repository also contains a deployed shared-demo API/database implementation, but the Shared Demo UI entry point was replaced by a local Load Example action. The remote API is a synthetic, shared demo with a single Board and is not suitable for personal/private production data without a separate security and tenancy redesign.

The immediate production-preparation priorities are therefore not feature volume. They are:

1. Decide and document the release product boundary: local-first only, or real accounts/sync.
2. Protect user data against decode failures, accidental replacement, device loss, and app deletion.
3. Reconcile the app's current source with older documentation, privacy disclosures, and server configuration.
4. Finalize the App Store identity, privacy, accessibility, and release workflow.
5. Validate user-critical flows on real devices and supported iOS versions, not just simulator unit tests.

## 2. Product North Star

Plenact grew from a weekly Kanban planning workflow and is expanding toward a calm personal organizer for planning, recording, and preparing. A person should be able to put an item somewhere meaningful without first deciding that it is a dated calendar event.

Examples that motivated the Lists library include:

- Week Board: weekday lists and open planning.
- On the table: plans or ideas currently being considered.
- In the queue: things to do later.
- Upcoming: preparations and near-future intentions.
- Shopping: groceries and household purchases.
- Reminders: recurring or easy-to-forget intentions.
- General Notes: useful facts and reference material.
- Personal or project boards: multi-column workspaces for a project or subject.

Treat these as product examples and starter-template ideas, not required default user content. Some names can contain intimate personal details. Plenact currently has no app-level lock or encrypted private-collection boundary; do not imply that local collections are protected from someone with access to an unlocked device.

The design is informed by a recovery-oriented preference for predictable navigation, readable information, and reduced cognitive load. This is product inspiration, not a medical indication: Plenact provides no treatment, clinical efficacy, or recovery outcome claims.

The user cited Awesome Note 2 as inspiration for folders/categories, icons, and colors. Its App Store listing was reviewed during discovery: it describes folder-based note organization, varied icons/colors, and multiple content views. Use those broad organizational ideas only. Do not copy screenshots, interface artwork, copy, or other protected assets. The listing also indicates Awesome Note 2 is discontinued; it is not a technical dependency or source of truth.

## 3. Product and Navigation As Implemented

The current primary navigation is:

- **Today**: date-specific focus list, quick capture, list/category surfaces, search entry, and local profile access.
- **Week**: the original horizontally paged Monday-through-Sunday Kanban Board. The Calendar opens from the Week header.
- **New**: the center bottom action. Tap opens the card composer; a hold shakes and creates a Week list on release.
- **Lists**: a searchable directory with a Week Board entry and locally stored personal collections.
- **Saved**: device-local saved cards and archived-board access.

Other current workflows:

- Today selects Monday on first use if there is no valid date-specific selection or local profile default. A valid saved selection and then a valid profile default take precedence.
- Today quick capture can add directly to its selected list. The full New Card form has an Add to picker.
- The bottom New button opens one shared card form directly; its Add to choice initializes from the last viewed Week list, then Today’s selected list, then the first active Week list.
- Week’s Calendar button presents the existing month/date view. The calendar currently projects card start/due dates; it is not an iOS Calendar integration.
- Lists contains a distinct Week Board directory, personal Lists, and personal Boards. A List starts with one column. A Board starts with Ideas, In progress, Done. Templates include On the table, In the queue, Upcoming, Shopping, Reminders, General Notes, Girlfriend Important Details, and New Project Notes.
- Personal collection entries support local search, icon/color customization, reordering, rename, and confirmed delete. Boards can have multiple lists; Lists are single-column collections.
- Search shows recent searches and Clear; filters include All, Boards, Labels, and Users. It searches the local Week data, and card results open card detail directly. It does not yet search personal collections.
- Saved bookmarks are local. Collection bookmarks are stored with their personal collection; Week bookmarks use a separate local key.
- Account & Settings is split into Account and Settings tabs. Profile information is local. Avatar selection supports initials, built-in icons, custom background/foreground colors, 2D color maps, presets, RGB/hex editing, and a local photo picker with circular pan/zoom crop.
- Load Example replaces the Week lists with local deterministic SampleData after confirmation. Undo Last Load saves/restores a prior Week snapshot and Today list selection. It is not a general history/undo system.
- Week supports archived cards, archived lists, and archiving the entire Week Board to Saved as a separate personal board. Personal Boards can also be archived/restored.

## 4. Domain Model and Ownership

### 4.1 Week Board

`KanbanList` and `KanbanCard` in `Src/Features/Boards/Models.swift` are the core models. The Week Board is seven Monday-through-Sunday starter lists. `SampleData` currently builds 49 list rows/card records (including divider rows) and uses the starter label library. The Week list IDs and card IDs are integer values scoped to this board snapshot.

Cards currently include:

- Stable integer ID, word/title, and list title.
- Divider and title-completion flags.
- Typed manual/registered assignee entries and label IDs.
- Optional date-only start/due fields and optional description/subtitle overrides.
- Stable checklist items with standard, linked-card, or reduced Action Detail content.
- Comments, local attachment metadata, and dismissed activity IDs.
- Active and archived card partitions; divider rows are not individually archivable.

`KanbanList` has active cards, archived cards, and an archive flag. Custom Codable decoding defaults newly introduced archive fields so earlier snapshots can still decode. Archive operations preserve IDs, completion, checklist/detail data, and attachment references. Restoring a card appends it back to its original list. Restoring an archived list retains its content and returns it to the active partition.

### 4.2 Personal Collections

`PersonalCollection` in `Src/Features/Boards/Models.swift` contains a UUID, title, kind (`List` or `Board`), SF Symbol token, `ProfileColor`, lists, collection-local saved card IDs, and an optional archive flag. Personal collection data lives under the separate `Plenact.PersonalCollections.v1` key. It does not overwrite the Week Board snapshot.

- A List creates one `KanbanList` whose title follows the collection title.
- A Board creates three initial columns: Ideas, In progress, Done.
- Collection/card/list ID namespaces are scoped to each collection editor; do not introduce global cross-collection card links without first making identity globally unique or composite.
- Personal collections and their card contents are local-only and are not part of `PlenactBoardDocument` v1.
- Week is a distinguished existing workspace, not just a personal collection row. Archiving Week copies the full board and its bookmarks into an archived collection, then leaves Week empty. Restoring a Week archive creates a separate uniquely named personal Board; it does not replace the current Week.

### 4.3 Shared Definitions and Profile Data

- `LabelLibrary` is a single local catalog shared by Week and personal collections. Cards store label IDs. Personal collections do not have isolated label catalogs today.
- `LocalProfile` is a local identity/personalization record, not an authenticated account. Optional email is unverified local text.
- The avatar photo is a separate local file in `Documents/ProfileAvatars`; the profile stores a filename. Photo-picker cropping outputs a bounded 512-pixel JPEG.
- Card photo/video bytes are in `Documents/CardAttachments`; card JSON stores attachment metadata/filenames. Web links are metadata and may open external websites.
- No app-managed cloud attachment store, multi-device sync, or export/restore workflow for all user content is implemented.

## 5. Persistence Map and Compatibility Contracts

| Data | Current owner | Storage | Important boundary |
| --- | --- | --- | --- |
| Week active/archived lists and cards | `KanbanBoardPersistence` | `UserDefaults`, `Plenact.Board.v1` | Custom asynchronous serial save/load path; Codable shape and stable IDs are compatibility contracts. |
| Personal lists and boards | `PersonalCollectionStore` | `UserDefaults`, `Plenact.PersonalCollections.v1` | Separate from Week; save failures on mutations are surfaced in the activity banner. |
| Label definitions | `LabelLibraryStore` | Local `UserDefaults` key | Shared across current Week and personal collections. |
| Local profile/preferences/avatar filename | `LocalProfileStore` | `UserDefaults`, `Plenact.LocalProfile.v1` | Separate from board data; older avatar color tokens have migration decoders. |
| Week bookmarks | `SavedCardPersistence` | `UserDefaults`, `Plenact.SavedCardIDs.v1` | Integer IDs are interpreted against Week. |
| Personal-board bookmarks | `PersonalCollection.savedCardIDs` | Within personal collection snapshot | Kept separate from Week bookmarks. |
| Last viewed Week list | `LastViewedListStore` | `UserDefaults`, `Plenact.LastViewedList.v1` | Validated against current active lists before use. |
| Recent Week searches | `RecentSearchStore` | `UserDefaults`, `Plenact.RecentSearches.v1` | Most recent first, case-insensitive dedupe, max ten, user-clearable. |
| Undo Load Example snapshot | `ExampleLoadUndoStore` | `UserDefaults`, `Plenact.ExampleLoadUndo.v1` | One previous Week lists snapshot plus Today list ID; not app-wide undo. |
| Profile images | `ProfileAvatarPhotoStore` | `Documents/ProfileAvatars` | File-based and referenced by filename in profile. |
| Card media | `CardAttachmentStore` | `Documents/CardAttachments` | Cleanup must retain references from Week, personal collections, archives, and undo snapshots. |

### Required Data-Safety Rules

1. Never clear `UserDefaults`, delete Documents media, or replace corrupt saved state as a debugging shortcut.
2. Add a migration and fixture test before changing any Codable field, key, stable ID, or media filename contract.
3. Use isolated `UserDefaults(suiteName:)` fixtures in tests; never use live app data for test mutation.
4. Any replacement/import/archive operation must save a recoverable snapshot first, preserve related IDs/files, and leave in-memory state unchanged if durable save fails.
5. Verify background write completion/error handling before claiming “saved.” The UI currently uses `DatabaseActivity` messaging even for local file/`UserDefaults` activity; do not present that as a remote database connection.
6. Decide whether local data belongs in device backups, and verify file protection and backup exclusion/inclusion. “Local” does not mean encrypted, private from someone with unlocked-device access, or backed up by Plenact.

### Known Data Risks To Resolve Before Release

- `PersonalCollectionStore.load()` currently converts a decode failure into an empty array. If a later edit saves that empty/partial state, a user’s inaccessible collections could be overwritten. Change this to a recoverable load result/error state and add a corruption-preservation test before release.
- `LocalProfileStore.load()` returns `nil` on decoding failure. Avoid silently treating a damaged existing profile as a new profile and overwriting it without recovery or explicit user choice.
- Week background load reports a decode error and displays starter data without deleting the saved bytes. Confirm that later edits cannot silently overwrite the unreadable snapshot; block writes or offer a recover/backup path.
- Load Example undo stores lists and the Today selection. Review whether Week bookmarks should also be included/reset/restored; `savedCardIDs` is stored separately and current sample card IDs can overlap old Week IDs.
- Local photo/attachment files live in Documents; no end-to-end export/import or user-facing storage-management workflow is present. Confirm iOS backup treatment and privacy expectations.
- Personal collection snapshots are synchronously encoded through `saveChecked` from observed app state. Stress-test larger collections; move storage off the main actor if measured work causes hitches.
- Whole Week and personal-board `Int` card IDs can overlap. All current card destinations must remain collection-scoped. Cross-board linked-card references need a new durable identity design.

## 6. Shared Demo API: Separate, Not Production-Ready

The repository contains `Src/Features/Sync`, `Server/api`, and `Server/SQL`. The API is deployed according to the Server README and has a synthetic shared Board seeded with SampleData. The old Shared Demo UI is not mounted in current Account & Settings; the current visible action is local Load Example. The API client source remains compiled, and `PLENACT_API_BASE_URL` is set in the Xcode project to the production HTTPS API URL. Treat this as an intentional decision point, not as proof that personal data sync is implemented.

Current v1 server model, as documented:

- One Board key (`shared-demo`), complete immutable JSON snapshots, optimistic revision checks.
- Demo accounts are invite/admin-created, with `board_editor` and `member` roles.
- The editor can write canonical Board snapshots; members can browse and make restricted assignment-only changes.
- Password hashes remain server-side; random bearer tokens are hashed server-side and stored in the iOS Keychain.
- Request/response and serialized document limit is 1 MiB. HTTPS is required.
- Local photo/video attachment references/bytes do not sync. API normalization strips local media records.
- API is not multi-tenant personal storage, does not contain per-user private boards, and has not been approved for real user/private content.

The Server README records PHP 8.2 and MySQL-compatible server 5.7.44-48. The SQL migration README records seven InnoDB tables and an initial synthetic revision. The PHP contract validator passed locally during this handoff audit, but deployed permission, concurrency, seed-retry, operational restore, and user-management behavior are not fully verified.

**Production gate:** choose one path before submitting a production app:

- **Local-first release:** remove/disable unused shared-demo UI/client configuration and disclose local storage/backup honestly; or
- **Authenticated product:** design real account ownership, private-board isolation, tenant authorization, migration, deletion/export, rate limits, operational controls, and security review. The shared demo database is not a shortcut to this architecture.

Server docs explicitly warn that the demo runtime user’s database-scoped DML grants can modify/delete revision rows even though the API treats revisions as immutable. This is acceptable only for a closed synthetic demo under current assumptions; restrict permissions and independently review the API/database before public or personal data is allowed. Do not run a production data migration or expose customer data using the demo account model.

## 7. Current UX and Product Boundaries

### Today

- First boot selects Monday when there is no valid date-specific selection or profile default; selection is date-specific.
- A valid saved daily selection takes precedence over the profile’s default; then a valid profile default; then Monday; then first available list as defensive fallback.
- Today is a projection on existing Week lists and cards, not an independent focus-card store.
- Quick Capture can add directly to today’s selected list; the full composer has Add to list.
- Search opens from Today and currently indexes Week content (All/Boards/Labels/Users), not personal collections.

### Week

- Horizontal Monday–Sunday starter Kanban.
- Lists size to content; empty lists remain compact. Long lists scroll with reserved footer clearance for Add card above the custom bottom bar.
- List order can be changed with a dedicated Move earlier/later path and hold-and-drag with edge scrolling; respect Reduce Motion.
- Cards support title completion, descriptions, dates, labels, checklists, comments, assignees, attachments, and card details.
- Calendar is in the Week header and derives entries from existing start/due dates. It is not a system calendar event integration.

### New Card and Capture

- Tap the bottom New button to open the card composer directly; hold until the button shakes, release to add a Week list.
- Add to initializes to last viewed active Week list; fallback is Today’s selected list, then first active list.
- A Today quick-capture plus action remains a faster direct-add path to Today’s list.

### Lists and Saved

- Lists directory contains Week Board and active local personal collections. Personal Lists are single-column; Boards have multiple Kanban columns.
- Optional templates are user-selected, not silently seeded into a person's data.
- Lists/cards can be searched by name in the collection directory. Personal collection archive preserves content; Saved contains bookmarks and archived boards.
- Search supports recent queries and user-clearable history. Results open card detail directly. The main Search remains Week-scoped; decide whether to make it cross-collection.
- Labels remain global/shared between local Week and personal collections. Decide whether this is the intended mental model or add per-collection labels deliberately.

### Profile and Attachments

- Account & Settings has Account and Settings tabs.
- Profile identity is local. Account includes custom icon/photo, color maps, RGB/hex controls, photo cropping, and profile deletion.
- Choose Photo uses PhotosPicker (limited selection access), circular crop guide, pan/zoom, and local 512px JPEG output. Card attachments support photos, video, and HTTPS/HTTP web links; no media sync.
- Do not treat private relationship, medical, or other sensitive notes as protected content. No collection-level lock or encrypted vault is currently established.

## 8. Repository Map and Ownership

- `Src/App.swift`: root tabs/navigation, Today, Lists directory, Search, local profile entry, load-example/undo orchestration, shared state routing. Large file; avoid broad refactors during stabilization.
- `Src/Features/Boards/Models.swift`: card/list/checklist/archive/personal collection models, SampleData, local board persistence.
- `Src/Features/Boards/ContentView.swift`: Week and reusable Kanban list/card screens, list/card actions, archives, drag reorder, navigation, attachment cleanup retention.
- `Src/Features/Boards/CardDetailView.swift`: card detail editing, labels, checklists, comments, members, attachments, archive actions.
- `Src/Features/Profile/`: local profile model/store, avatar photo storage, Account & Settings UI.
- `Src/Features/Labels/`: local reusable categories and labels.
- `Src/Features/Attachments/PhotoAttachments.swift`: local attachment model/store, picker and preview UI.
- `Src/Features/Sync/`: shared-demo versioned payload, API client, old shared demo account section. The account section is currently not mounted.
- `Server/api/`, `Server/SQL/`, `Server/tests/`: PHP API, schema migration, local contract validator. Separate from the Xcode runtime's local stores.
- `Test/`: active XCTest target; 52 `func test...` declarations at the time of this audit.
- `Doc/`: multiple architecture notes predate recent Lists/archive/background persistence changes. Cross-check documents against source and label proposals vs implementation.

`Src/Models.swift` and root-level `Src/CardDetailView.swift` are legacy/reference copies that may overlap feature-scoped files. Check Xcode project membership and call sites before editing or removing them; avoid assuming every same-named file is active.

## 9. Build, Test, and Repository Workflow

Verified on the audit machine:

```sh
xcodebuild -project Plenact.xcodeproj -scheme Plenact \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

The full iOS test suite passed on 2026-10-04. The suite includes persistence and migration, checklist compatibility, archives, board/list reordering, background save failure ordering, Search scopes/history, collection persistence/rename, avatar photo crop/file storage, and API client request validation.

The local PHP contract check passed on 2026-10-04:

```sh
php Server/tests/board_contract_test.php
```

Local PHP was 8.5.11; the server documentation reports PHP 8.2, so run/maintain compatibility against the deployed PHP version as well.

Project information observed:

- Xcode 27.0, build 27A266a on audit machine.
- Xcode targets: `Plenact`, `PlenactTests`; shared scheme: `Plenact`.
- Deployment target: iOS 17.0; Swift language mode 5.
- `TARGETED_DEVICE_FAMILY = 1` (iPhone). The plist contains iPad orientation keys, but project family is iPhone-only; settle actual support and test matrix.
- Bundle identifier currently `com.plenact.Plenact02`; marketing version `1.0`; build `1` in project settings. A development team is configured. Confirm intended App Store Connect ownership, final bundle ID, signing, version, and build number.
- `Src/Assets.xcassets/AppIcon.appiconset/Contents.json` references a 1024x1024 `AppIcon.png`.
- No tracked `.github/workflows`, `PrivacyInfo.xcprivacy`, `.entitlements`, `Package.resolved`, or `.xcconfig` was found in the audited tree.
- The Xcode project contains `PLENACT_API_BASE_URL=https://plenact.com/api/` in build settings. That endpoint is for the shared demo. Decide whether to keep/remove per build configuration before a public release.

Working practices that have served this repository well:

1. Check `git status -sb` and the exact staged/unstaged diff before editing. The user often has intentional staged work.
2. Preserve user edits. Never reset, checkout, clean, stage, or commit without explicit authorization.
3. Keep changes narrow and follow the current Swift documentation/comment style.
4. User prefers vertical alignment in adjacent declarations: align enum raw-value `=`, property type `:`, and assignment `=` columns using spaces. Align locally; avoid unsolicited whole-repository reformatting.
5. The user prefers to perform commits personally. Provide a commit message; do not create commits unless explicitly asked.
6. Run a focused check after edits, then full suite for storage/navigation changes. Keep PHP contract tests in the release process.

## 10. Verified vs. Unverified

### Verified at handoff

- Working tree clean; branch `main` synchronized with `origin/main` at commit `5a39025` during audit.
- iOS simulator unit test suite passed on 2026-10-04.
- PHP board-contract validator passed on 2026-10-04.
- Xcode project/scheme and current build settings were inspected.
- Week and personal collection stores are separate; personal collection tests explicitly ensure Week snapshot remains untouched.
- No CI workflow, privacy manifest, package lock, or entitlements file is tracked in the audited tree.

### Not verified / not performed

- Release-configuration build, Archive, export, App Store Connect upload, TestFlight install, or review submission.
- Physical iPhone tests, iOS 17 min-version device, VoiceOver, large Dynamic Type, dark mode, color contrast, reduced motion, landscape, or device-rotation layout review.
- Real-user recovery/export/restore, iCloud device-backup behavior, or multi-window write consistency.
- Full PhotoPicker/crop gesture interaction on physical devices.
- Production privacy policy, terms, support URL, data collection answers, age rating, export compliance, trademark review, or marketing claims.
- Independent API authorization, stale-revision, seed-retry, password/session expiry, rate-limit, DB backup/restore, least-privilege, penetration, or operational incident tests.
- Whether the current Bluehost shared demo is reachable and healthy at release time.

## 11. Production Readiness Assessment

**Recommendation:** Do not call the app production-ready yet. It is a substantial local-first product foundation and a good candidate for internal/TestFlight validation after the highest-risk data and release decisions are resolved.

### P0: Decide the release product boundary

Choose and record one of these:

1. **Local-first personal organizer:** disable/remove unused Shared Demo sign-in/API configuration for production; keep each person's data on-device; define export/import and backup behavior; publish accurate local-storage disclosures.
2. **Authenticated cloud product:** design true user-owned private collections, tenant isolation, authorization, account lifecycle, data export/deletion, sync conflict behavior, attachment storage, backups, retention, and breach response before exposing personal data.

Do not market the shared-demo API as private cloud sync. It stores one shared-demo Board. All demo users can browse it, and demo permissions are not production tenant isolation.

### P0: Protect user data and recovery

- Make all load paths distinguish “no saved data” from “saved data failed to decode.” Do not substitute an editable sample silently over a damaged snapshot.
- Personal collection load currently returns an empty array on decode failure. Add surfaced/recoverable failure state and tests proving subsequent edits cannot overwrite an unreadable saved collection.
- Week load reports decoding failure and displays SampleData while preserving raw stored bytes, but audit whether later user edits can persist over the unreadable snapshot.
- Define an app-level export/import and recovery approach before claiming user content is safe. Device backups may include app data; test and disclose rather than guessing.
- Extend Load Example undo to include Week bookmarks if exact restoration is intended. Current `ExampleLoadUndoSnapshot` stores lists and Today list ID, not `SavedCardIDs`; Load Example can leave bookmark IDs that coincide with sample card IDs.
- Test archive retention/deletion for photos shared or duplicated across Week, personal collections, archived collections, and undo snapshots.
- Add migration tests for all user-facing persisted snapshots and collection archives before changing IDs/schema.

### P0: Reconcile shared demo and privacy

- Current project build settings point at a deployed HTTPS API, and PHP/MySQL code remains in the repo even though Shared Demo UI is not mounted.
- The v1 server is one synthetic shared Board, not per-user private storage. The documented database runtime account has broad DML over schema tables, which can bypass append-only revision intent. Tighten and independently review before any real user content or public account surface.
- Decide if the API should be compiled/configured in the production app at all. Prefer a clearly separate demo build if the service remains only for synthetic testing.
- Add/verify a current privacy manifest and required-reason API declarations (the app uses UserDefaults extensively). Complete App Store privacy answers, privacy policy, terms, support contact, and exact data-retention/disclosure text.
- Custom collections may contain intimate notes. Define local device protection, backup, deletion, and recovery expectations before encouraging sensitive use.
- Check current App Store requirements for Health/medical adjacent claims. Keep Plenact positioned as a planner; do not imply clinical efficacy, treatment, certification, or recovery outcomes.

### P1: Release mechanics

- Confirm the shipping bundle identifier before app registration; current suffix `Plenact02` looks like a development identity.
- Verify the configured development team belongs to the intended publisher and has correct distribution certificates/profiles.
- Set a deliberate release version/build; current project values are `1.0`/`1`.
- Produce a Release configuration build and signed Archive; validate the exported IPA and App Store Connect processing.
- Confirm the app icon artwork, launch presentation, screenshots, preview video if desired, subtitle, keywords, age rating, category, privacy URLs, copyright, and support contact.
- Create TestFlight internal/external validation plan, feedback channel, crash collection policy, and rollback/revocation plan.
- Add CI for build/test and static checks. There is no tracked workflow in `.github/workflows` at handoff.

### P1: Human-centered QA

- Test first launch, existing install upgrade, Today defaulting, board/list/collection creation, archive/restore, deletion, Search, card editing, profile Save/Cancel, avatar photo crop, and Load Example/Undo.
- Verify current New-button long press does not also trigger a tap; test tap/hold/drag on devices.
- Test long Week lists with bottom Add card, scroll position, keyboard, nested sheets, and safe areas on compact and large iPhones.
- Test VoiceOver order and labels for all icon controls, collection types, destructive dialogs, crop map, RGB/hex editor, and selection state.
- Exercise Dynamic Type, Reduce Motion, increased contrast, dark/light appearances, landscape only if supported, and localization pressure.
- Test airplane mode, low storage, corrupted UserDefaults, full device disk, interrupted file writes, and app termination during persistence.
- Add UI automation/snapshot tests for critical navigation and destructive/recovery flows; current suite is XCTest unit/model/persistence heavy and has no dedicated UI-test target.

## 12. Suggested Phased Plan For The Next Agent

### Phase A: Product and release decision

1. Agree on target user, price/monetization, distribution channel, launch geography/language, and whether v1 is local-only.
2. Decide if the shared API is removed, demo-only, or undergoing a separately designed production rewrite.
3. Agree on whether personal notes can contain sensitive content, whether device lock is enough, and how backup/export works.
4. Confirm platform scope (currently iPhone-only target despite iPad orientation plist entries).

### Phase B: Data durability first

1. Add non-destructive corruption handling for Week, personal collections, labels, profile, bookmarks, and archive snapshots.
2. Expand Load Example undo to cover bookmarks and any other Week-scoped preferences it resets.
3. Define manual export/import with schema version, attachment package handling, validation, and recoverable failures.
4. Review archive restore uniqueness and attachment cleanup across every collection.
5. Stress-test load/save latency with large local boards; consider moving PersonalCollectionStore to background/SQLite only after an explicit, tested migration design.

### Phase C: Release security and privacy

1. Remove dormant shared-demo controls/API config from production if the app is local-only; keep demo credentials and demo databases separate.
2. If backend use remains, conduct threat modeling, least-privilege review, authorization tests, API fuzz/input-size tests, key/session rotation, restore tests, and independent security review.
3. Audit filesystem Data Protection classes, backup inclusion/exclusion, logs/analytics, URL handling, clipboard, PhotosPicker, and crash reports.
4. Create current privacy manifest, privacy policy, terms, and App Store disclosures matched to observed code.

### Phase D: Accessibility, reliability, and release candidate

1. Build a manual QA matrix by device/OS/text size/appearance/accessibility settings.
2. Add UI automation for onboarding/Today, New/Add-to, list/board management, Search-to-card, archive/restore, and photo crop.
3. Add CI to clean checkout, build Debug/Release, run tests, run PHP contract tests, and check formatting/schema fixtures.
4. Configure final app identity/version/icon/screenshots and Archive with signed distribution artifacts.
5. Ship to internal TestFlight first, gather feedback, fix data-loss/accessibility issues, then consider external TestFlight and App Store review.

## 13. Questions The Production Agent Must Not Silently Decide

- Is v1 explicitly local-only, or must it support sync/accounts at launch?
- Is “Week Board” a system board with special Today/Calendar semantics, or should users be able to create multiple Week-like boards?
- Should Search span Week only or all personal collections? What should duplicate card IDs mean globally?
- Should Labels be shared across collections or scoped by collection?
- Is the global Saved tab a cross-collection bookmark library or should bookmarks stay within collections?
- What is the intended behavior when a board/list/card is archived versus permanently deleted?
- Should deleting a personal board require export/undo? How long is undo retained?
- Are account avatars/photos and card attachments included in app/device backup, and can users export/delete them?
- Should personal notes be protected by an app lock or Face ID? What private/sensitive content is actually in scope?
- How should named personal templates be reviewed for sensitive relationship/health implications and user control?
- What is the retention and crash-report policy? Does the app collect any analytics or diagnostics?
- Should production contain dormant demo API code or a separately signed demo configuration?

## 14. Coding and Collaboration Notes

- The app uses SwiftUI and a single app target. Keep ownership boundaries direct and avoid premature repository/service abstractions.
- Stable `Identifiable` keys are persisted. Do not use titles, array positions, or an ID from a different board as a cross-board identity.
- Keep local profile, Week Board, personal collections, global labels, per-board archive data, bookmarks, and attachment files separate unless a deliberate migration consolidates them.
- Existing background Week persistence has a serial queue so snapshot writes preserve order. Preserve that ordering when adding asynchronous persistence.
- Use “active” vs “archived” views without dropping archived IDs/media from retention calculations.
- The user's preferred Swift formatting aligns consecutive property types, enum raw-value assignments, and assignment operators vertically with spaces. Apply to edited blocks; do not run a repo-wide formatter without review.
- The user makes commits personally. Do not commit, stage, reset, or branch unless explicitly requested. Recent commit subjects use `(+)` for feature work and `(C)` for changes/corrections; code commit messages should follow current repo style.
- Keep status updates short and actionable. Confirm before expanding scope to remove server infrastructure or rewrite persisted models.

## 15. Useful Links Within This Repository

- [Root README](../README.md)
- [Architecture index](README.md)
- [Today architecture](Today-View-Architecture.md)
- [Today UI](Today-View-UI.md)
- [Board and Scheduled proposal](Board-and-Scheduled-Views.md)
- [Checklist action architecture](Checklist-Actions-Architecture.md)
- [Local profile architecture](Local-Profile-Architecture.md)
- [Board feature guide](../Src/Features/Boards/README.md)
- [Profile feature guide](../Src/Features/Profile/README.md)
- [Labels feature guide](../Src/Features/Labels/README.md)
- [Attachments feature guide](../Src/Features/Attachments/README.md)
- [Sync feature guide](../Src/Features/Sync/README.md)
- [Data contract](Database/Plenact-Data-Contract.md)
- [Demo seed plan](Database/Initial-Demo-Import-Plan.md)
- [Server implementation](../Server/README.md)
- [Server API contract](../Server/api/README.md)
- [Server SQL migrations](../Server/SQL/README.md)
- [Test guide](../Test/README.md)

---

**Hand-off instruction:** Start with the release product-boundary decision and the data-safety gaps. Do not add another major feature before deciding whether Plenact v1 is local-first or authenticated cloud software, and do not expose the current shared-demo backend to personal/private user data.
