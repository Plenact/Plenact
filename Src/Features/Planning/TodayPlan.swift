// --------------------------------------------------------------------------------------------------
// @file       TodayPlan.swift
// @brief      Daily intentions, owner-qualified priorities, check-ins, and history
// @details    Defines compatible daily planning documents and checked baseline saves. Presents
//             intention setting, live priority selection or creation, morning guidance, contextual
//             check-ins, retained history, and Today summaries without duplicating canonical Cards.
//
// --------------------------------------------------------------------------------------------------
import SwiftUI


///
/// Links a daily priority to its original workspace item
///
/// @section    Purpose
///     Retains owner-qualified identity and creation time with a display snapshot so local numeric
///     IDs cannot resolve to another owner's Card.
///
struct DailyPlanPriority: Codable, Hashable, Identifiable
{


    let ownerID:         UUID
    let cardID:          Int
    let title:           String
    let location:        String
    let sourceCreatedAt: Date?
    var id:              String
    {
            "\(ownerID):\(cardID)"
    }


    ///
    /// @fcn        DailyPlanPriority.init
    /// @brief      Capture a workspace item's owner-qualified priority reference
    /// @details    Stores the source identity and snapshot fields needed to display and later resolve the priority.
    ///
    /// @param[in]  source  Live source item with its calendar or Library location
    ///
    /// @return     (DailyPlanPriority) initialized instance
    ///
    init(_ source: PlanningSearchResult)
    {

        ownerID = source.collectionID
        cardID = source.card.id
        sourceCreatedAt = source.card.createdAt
        title = source.card.word
        location =
        source.collectionTitle == source.listTitle
        ? source.listTitle : source.collectionTitle + " · " + source.listTitle
    }


    ///
    /// @fcn        DailyPlanPriority.resolve
    /// @brief      Resolve a retained daily priority against live workspace sources
    /// @details    Matches its owner-qualified identity and returns nil when the original item is no longer
    ///             available.
    ///
    /// @param[in]  sources  Live owner-qualified workspace items used to resolve retained references
    ///
    /// @return     (PlanningSearchResult?) live item matching owner UUID, card ID, and creation timestamp, or nil if
    ///             unavailable
    ///
    func resolve(in sources: [PlanningSearchResult]) -> PlanningSearchResult?
    {

        sources.first
        {
            $0.collectionID == ownerID && $0.card.id == cardID && $0.card.createdAt == sourceCreatedAt
        }

    }

}


///
/// Retains intentions, priorities, and review history for one day
///
/// @section    Purpose
///     Uses a local date key and time-zone identity while keeping linked workspace items distinct
///     from copied planning snapshots.
///
struct DailyPlan: Codable, Equatable, Identifiable
{


    let id:         String
    let timeZoneID: String
    var intention = ""
    var constraints = ""
    var concerns = ""
    var priorities:        [DailyPlanPriority] = []
    var updatedAt:         Date? = nil
    var checkIn:           DailyCheckIn? = nil
    var checkIns:          [DailyCheckInEntry]? = nil
    var eveningReview:     DailyEveningReview? = nil
    var visionStep:        Int? = nil
    var visionCompletedAt: Date? = nil


    ///
    /// @fcn        DailyPlan.init
    /// @brief      Create an empty plan for a represented calendar day
    /// @details    Stores the local day key and calendar context used by daily planning and subsequent check-in
    ///             history.
    ///
    /// @param[in]  date      Represented date for the operation
    /// @param[in]  calendar  Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     (DailyPlan) initialized instance
    ///
    init(date: Date, calendar: Calendar = .current)
    {

        id = PlanningDate.key(date, calendar: calendar)
        timeZoneID = calendar.timeZone.identifier
    }

}


///
/// Persists validated daily planning documents
///
/// @section    Purpose
///     Loads versioned plans and saves against baselines, reporting corruption, unsupported
///     formats, conflicts, and write failures explicitly.
///
@MainActor
enum DailyPlanStore
{


    static let key = "Plenact.DailyPlans.v1"


    ///
    /// Wraps daily plans in a versioned document
    ///
    /// @section    Purpose
    ///     Keys retained plans by represented local day and preserves a schema version for
    ///     compatibility checks.
    ///
    struct Document: Codable
    {


        var version = 1
        var plans: [String: DailyPlan] = [:]
    }


    ///
    /// Defines recoverable daily-plan storage failures
    ///
    /// @section    Purpose
    ///     Distinguishes unsupported, corrupt, conflicting, and unwritable data and supplies
    ///     actionable localized messages.
    ///
    enum Failure: LocalizedError
    {


        case unsupported, corrupt, conflict, write
        var errorDescription: String?
        {

            switch self
            {

            case .unsupported:
                            "This saved plan format needs a newer version of Plenact. Your saved data has been kept."
            case .corrupt:
                            "Your saved plans could not be read. They have been kept unchanged."
            case .conflict:
                                    "This plan changed while it was open. Close and reopen it before saving so the other changes are kept."
            case .write:
                            "The plan could not be saved. Your changes are still open; please try again."
            }

        }

    }


    ///
    /// @fcn        DailyPlanStore.load
    /// @brief      Load and validate the retained daily-plan document
    /// @details    Returns an empty document for absent storage and surfaces unsupported or invalid saved data rather
    ///             than resetting it silently.
    ///
    /// @param[in]  defaults  Preferences store used for this operation
    ///
    /// @return     (Document) validated daily-plan document, or an empty document for absent storage
    /// @throws     Explicit failures include `Failure.corrupt`, `Failure.unsupported`. Errors from throwing
    ///             dependencies propagate unless handled within this operation.
    ///
    static func load(from defaults: UserDefaults = .standard) throws -> Document
    {

        guard defaults.object(forKey: key) != nil else
        {
            return Document()
        }

        guard let data = defaults.data(forKey: key) else
        {
            throw Failure.corrupt
        }

        let document: Document
        do
        {
            document = try JSONDecoder().decode(Document.self, from: data)
        }
        catch
        {
            throw Failure.corrupt
        }

        guard document.version == 1 else
        {
            throw Failure.unsupported
        }

        for (key, plan) in document.plans
        {

            guard key == plan.id, key.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
            TimeZone(identifier: plan.timeZoneID) != nil,
            Set(plan.priorities.map(\.id)).count == plan.priorities.count,
            Set((plan.checkIns ?? []).map(\.id)).count == (plan.checkIns ?? []).count,
            (plan.visionStep.map(
                    {
                        (0 ... 2).contains($0)
                    }) ?? true),
            (plan.eveningReview.map(
                    {

                        (0 ... 2).contains($0.step) && Set($0.decisions.map(\.id)).count == $0.decisions.count
                    }) ?? true)
            else
            {
                throw Failure.corrupt
            }

        }

        return document
    }


    ///
    /// @fcn        DailyPlanStore.relocatingSection
    /// @brief      Follow moved section members in retained daily priorities
    /// @details    Uses the transfer receipt's owner and card identity mapping to update affected references while
    ///             preserving unrelated plans.
    ///
    /// @param[in]  receipt   Checked section-transfer receipt containing before/after owners and ID mapping
    /// @param[in]  document  Retained document containing the operation's current workspace records
    ///
    /// @return     (Document) document with affected priorities redirected and unrelated plans preserved
    ///
    /// @note       Keep explicit priorities linked to content when its whole section changes owner or list.
    ///
    static func relocatingSection(_ receipt: SectionTransferReceipt, in document: Document) -> Document
    {

        guard let owner = receipt.after.first(where:
            {
                $0.id == receipt.destination.ownerID
            }),
        let list = owner.lists.first(where:
            {
                $0.id == receipt.destination.listID
            })
        else
        {
            return document
        }

        var result = document
        for key in result.plans.keys
        {

            result.plans[key]?.priorities = (document.plans[key]?.priorities ?? []).map
            {
                priority in
                guard priority.ownerID == receipt.source.ownerID, let newID = receipt.mapping[priority.cardID],
                let card = list.cards.first(where:
                    {
                        $0.id == newID && $0.createdAt == priority.sourceCreatedAt
                    })
                else
                {
                    return priority
                }

                return DailyPlanPriority(
                    PlanningSearchResult(
                        weekKey: nil, collectionID: owner.id, collectionTitle: owner.title,
                        listID: list.id, listTitle: list.title, card: card))
            }

        }

        return result
    }


    ///
    /// @fcn        DailyPlanStore.save
    /// @brief      Save a daily plan against its expected retained value
    /// @details    Checks the supplied baseline to avoid overwriting concurrent changes, then encodes and returns the
    ///             accepted saved plan.
    ///
    /// @param[in]  plan      Daily plan supplying the retained priorities and review state
    /// @param[in]  expected  Expected retained plan; nil requires that no plan already exists
    /// @param[in]  defaults  Preferences store used for this operation
    ///
    /// @return     (DailyPlan) saved plan with an updated timestamp after baseline and write verification
    /// @throws     Explicit failures include `Failure.conflict`, `Failure.corrupt`, `Failure.write`. Errors from
    ///             throwing dependencies propagate unless handled within this operation.
    ///
    /// @note       Merge one day into the latest document, preserving every other day's plan.
    ///
    @discardableResult
    static func save(_ plan: DailyPlan, replacing expected: DailyPlan?, to defaults: UserDefaults = .standard) throws
    -> DailyPlan
    {

        var document = try load(from: defaults)
        guard document.plans[plan.id] == expected else
        {
            throw Failure.conflict
        }

        guard Set(plan.priorities.map(\.id)).count == plan.priorities.count,
        Set((plan.checkIns ?? []).map(\.id)).count == (plan.checkIns ?? []).count
        else
        {
            throw Failure.corrupt
        }

        var saved = plan
        saved.updatedAt = .now
        document.plans[saved.id] = saved
        let data = try JSONEncoder().encode(document)
        let previous = defaults.object(forKey: key)
        defaults.set(data, forKey: key)
        guard defaults.synchronize(), defaults.data(forKey: key) == data else
        {

            if let previous
            {
                defaults.set(previous, forKey: key)
            }
            else
            {
                defaults.removeObject(forKey: key)
            }

            throw Failure.write
        }

        return saved
    }

}


///
/// Presents the shared daily planning workspace
///
/// @section    Purpose
///     Loads a baseline-backed plan, coordinates priorities and review destinations, and keeps
///     unsaved writing available when persistence fails.
///
struct TodayPlanView: View
{


    @Environment(\.dismiss) private var dismiss
    @Environment(\.planningCalendarAccess) private var access
    @State private var date:     Date
    private let defaults:        UserDefaults
    @State private var draft:    DailyPlan
    @State private var baseline: DailyPlan?
    @State private var loaded = false
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var showsPicker = false
    @State private var showsNewPriority = false
    @State private var showsVision = false
    @State private var showsReview = false
    @State private var showsCheckIn = false
    @State private var showsDailyReview = false
    @State private var showsWeeklyReview = false
    @State private var showsPeriodicReview = false
    @State private var confirmsDiscard = false
    @State private var openedItem:  PlanningSearchResult?
    private let opensEveningReview: Bool


    ///
    /// @fcn        TodayPlanView.init
    /// @brief      Seed daily planning and its optional evening-review entry
    /// @details    Retains preferences and entry mode and creates the represented day's initial draft without
    ///             persisting during initialization.
    ///
    /// @param[in]  date                Represented date for the operation
    /// @param[in]  calendar            Calendar supplying local-day, time-zone, and week-boundary rules
    /// @param[in]  defaults            Preferences store used for this operation
    /// @param[in]  opensEveningReview  Whether daily planning should enter its evening-review flow
    ///
    /// @return     (TodayPlanView) initialized instance
    ///
    init(
        date: Date = .now, calendar: Calendar = .current, defaults: UserDefaults = .standard,
        opensEveningReview: Bool = false
    )
    {

        self.opensEveningReview = opensEveningReview
        _date = State(initialValue: date)
        self.defaults = defaults
        _draft = State(initialValue: DailyPlan(date: date, calendar: calendar))
    }

    private var sources: [PlanningSearchResult]
    {
        access?.searchableItems ?? []
    }

    private var hasChanges: Bool
    {

        guard loaded, loadError == nil else
        {
            return false
        }

        return draft != (baseline ?? DailyPlan(date: date, calendar: planCalendar))
    }

    private var planCalendar: Calendar
    {

        var value = Calendar.current
        value.timeZone = TimeZone(identifier: draft.timeZoneID) ?? .current
        return value
    }


    ///
    /// @fcn        TodayPlanView.load
    /// @brief      Load the represented day's editable plan
    /// @details    Restores the current draft and persistence baseline and reports retained-data failures through the
    ///             view's error state.
    ///
    /// @return     (Void) no return value
    ///
    private func load()
    {

        do
        {

            let saved = try DailyPlanStore.load(from: defaults).plans[draft.id]
            baseline = saved
            draft = saved ?? draft
            loadError = nil
            loaded = true
        }
        catch
        {
            loadError = error.localizedDescription;
            loaded = true
        }

    }


    ///
    /// @fcn        TodayPlanView.save
    /// @brief      Save and dismiss the edited daily plan
    /// @details    Uses baseline-aware persistence, replaces the draft with the saved value, and dismisses on
    ///             success; failure retains the editor and sets its save error.
    ///
    /// @return     (Void) no return value
    ///
    private func save()
    {

        do
        {

            baseline = try DailyPlanStore.save(draft, replacing: baseline, to: defaults)
            draft = baseline!
            dismiss()
        }
        catch
        {
            saveError = error.localizedDescription
        }

    }


    ///
    /// @fcn        TodayPlanView.close
    /// @brief      Request dismissal of daily planning
    /// @details    Prompts to discard unsaved changes when the draft differs from its baseline; otherwise dismisses
    ///             immediately without writing.
    ///
    /// @return     (Void) no return value
    ///
    private func close()
    {

        if hasChanges
        {
            confirmsDiscard = true
        }
        else
        {
            dismiss()
        }

    }


    ///
    /// @fcn        TodayPlanView.saveVisionProgress
    /// @brief      Save daily vision progress without dismissing
    /// @details    Updates the draft and baseline from the accepted saved plan and returns false if the checked store
    ///             rejects it.
    ///
    /// @return     (Bool) true after updating the draft and baseline from storage; false on save failure
    ///
    private func saveVisionProgress() -> Bool
    {

        do
        {

            let saved = try DailyPlanStore.save(draft, replacing: baseline, to: defaults)
            baseline = saved
            draft = saved
            return true
        }
        catch
        {
            return false
        }

    }


    ///
    /// @fcn        TodayPlanView.priorityRow
    /// @brief      Build a daily priority row with its live workspace context
    /// @details    Resolves the stored priority to available source content and presents the corresponding navigation
    ///             and planning controls.
    ///
    /// @param[in]  priority  Owner-qualified daily priority to render or resolve
    ///
    /// @return     (some View) a daily priority row with its live workspace context
    ///
    private func priorityRow(_ priority: DailyPlanPriority) -> some View
    {

        let source = priority.resolve(in: sources)
        return Button
        {

            openedItem = source
        }
        label:
        {

            HStack(alignment: .top, spacing: 12)
            {

                Image(
                    systemName: source == nil
                    ? "link.badge.plus"
                    : (source?.card.presentation == .note
                        ? "note.text" : (source?.card.isTitleChecked == true ? "checkmark.circle.fill" : "circle"))
                )
                .foregroundStyle(source?.card.isTitleChecked == true ? Color.green : Color.secondary)
                .font(.title3)
                VStack(alignment: .leading, spacing: 5)
                {

                    Text(source?.card.word ?? priority.title).font(.headline).foregroundStyle(.primary)
                    if DailyCheckInProgress.focus(plan: draft, sources: sources)?.id == priority.id
                    {

                        Label("Next focus", systemImage: "scope").font(.caption).foregroundStyle(.blue)
                    }

                    Text(
                        source.map
                        {

                            $0.collectionTitle == $0.listTitle
                            ? $0.listTitle : $0.collectionTitle + " · " + $0.listTitle
                        }
                        ?? priority.location
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    if let source
                    {

                        Text(
                            source.card.presentation == .note
                            ? "Note" : (source.card.isTitleChecked ? "Complete" : "Not complete")
                        )
                        .font(.caption).foregroundStyle(source.card.isTitleChecked ? .green : .secondary)
                    }
                    else
                    {

                        Text(
                                                                        "Unavailable: archived, removed, or moved to another Board. Remove this link and choose the item again if needed."
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }

                }

                Spacer(minLength: 0)
                if source != nil
                {
                    Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                }

            } .padding(.vertical, 6).frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(source == nil)
        .accessibilityHint(
            source == nil
            ? "The saved priority remains in your plan" : "Opens the original item; Back returns to this plan")
    }

    private var planForm: some View
    {

        Form
        {

            Section
            {

                VStack(alignment: .leading, spacing: 8)
                {

                    Text(date.formatted(date: .complete, time: .omitted)).font(.subheadline).foregroundStyle(.secondary)
                    Text("A clear plan for today").font(.title.weight(.bold))
                    Text("Choose what matters, leave room for real life, and take one useful step.").foregroundStyle(
                        .secondary)
                } .padding(.vertical, 6)
            }

            Section
            {

                Button
                {

                    showsVision = true
                }
                label:
                {

                    Label(
                        draft.visionStep != nil
                        ? "Resume today's vision"
                        : (draft.visionCompletedAt == nil ? "Start today's vision" : "Revisit today's vision"),
                        systemImage: "sunrise"
                    )
                    .font(.headline).frame(minHeight: 44)
                } .disabled(access == nil)
                Button
                {

                    showsCheckIn = true
                }
                label:
                {

                    Label("Check in now", systemImage: "sun.max")
                    .font(.headline).frame(minHeight: 44)
                } .disabled(access == nil)
                Button
                {

                    showsReview = true
                }
                label:
                {

                    Label(
                        draft.eveningReview?.completedAt != nil
                        ? "Revisit today's review"
                        : (draft.eveningReview == nil ? "Start today's review" : "Resume today's review"),
                        systemImage: "moon.stars"
                    )
                    .font(.headline).frame(minHeight: 44)
                } .disabled(access == nil)
            }
            footer:
            {

                Text(
                                                "Plan your morning, adjust during the day, and reflect in the evening. Save within each flow to keep your progress."
                )
            }

            Section
            {

                Button
                {

                    showsDailyReview = true
                }
                label:
                {

                    Label("Daily review", systemImage: "list.bullet.clipboard").font(.headline).frame(minHeight: 44)
                }

                Button
                {

                    showsWeeklyReview = true
                }
                label:
                {

                    Label("Weekly review", systemImage: "calendar.badge.clock").font(.headline).frame(minHeight: 44)
                } .disabled(access == nil)
                Button
                {

                    showsPeriodicReview = true
                }
                label:
                {

                    Label("Periodic review", systemImage: "flag.checkered").font(.headline).frame(minHeight: 44)
                } .disabled(access == nil)
            }

            Section
            {

                if draft.priorities.isEmpty
                {

                    Text("Start with a Card or Note you would like to give attention to today.").foregroundStyle(
                        .secondary)
                }

                ForEach(draft.priorities)
                {
                    priority in
                    priorityRow(priority)
                }
                .onDelete
                {
                    draft.priorities.remove(atOffsets: $0)
                }
                .onMove
                {
                    draft.priorities.move(fromOffsets: $0, toOffset: $1)
                }

                Button
                {

                    showsPicker = true
                }
                label:
                {

                    Label("Choose priorities", systemImage: "plus.circle").frame(minHeight: 44)
                } .disabled(access == nil)
                Button
                {

                    showsNewPriority = true
                }
                label:
                {

                    Label("Add priority", systemImage: "square.and.pencil").frame(minHeight: 44)
                } .disabled(access == nil)
            }
            header:
            {

                Text("What matters today")
            }
            footer:
            {

                Text(
                                                "Priorities link to existing items. Choosing, reordering, or removing a priority does not move or delete the original. Swipe to remove a link; use Edit to reorder."
                )
            }

            Section("Your intention")
            {

                TextField("What would make today meaningful? (optional)", text: $draft.intention, axis: .vertical)
                .textInputAutocapitalization(.sentences).lineLimit(2 ... 6)
            }

            Section("Make room for")
            {

                TextField("Time, energy, or other constraints (optional)", text: $draft.constraints, axis: .vertical)
                .textInputAutocapitalization(.sentences).lineLimit(2 ... 6)
            }

            Section("Risks or concerns")
            {

                TextField("Anything that could get in the way? (optional)", text: $draft.concerns, axis: .vertical)
                .textInputAutocapitalization(.sentences).lineLimit(2 ... 6)
            }

            Section
            {

                if let saved = baseline?.updatedAt
                {

                    Text("Last saved " + saved.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                    .foregroundStyle(.secondary)
                }

                Text(
                    hasChanges
                    ? "You have unsaved changes. Tap Save to keep your plan on this device."
                    : "Your plan stays on this device. Item status updates as your work changes."
                )
                .font(.footnote).foregroundStyle(.secondary)
            }

        }

    }

    var body: some View
    {

        NavigationStack
        {

            Group
            {

                if let loadError
                {

                    VStack(spacing: 16)
                    {

                        Text("Your plan couldn't be opened").font(.headline)
                        Text(loadError).foregroundStyle(.secondary)
                        Button("Try again", action: load)
                    } .padding()
                }
                else
                {

                    planForm.disabled(!loaded)
                }

            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today's Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {

                ToolbarItem(placement: .cancellationAction)
                {
                    Button(hasChanges ? "Cancel" : "Done", action: close)
                }

                ToolbarItemGroup(placement: .confirmationAction)
                {

                    if loadError == nil
                    {

                        EditButton();
                        Button("Save", action: save).disabled(!loaded || (!hasChanges && baseline != nil))
                    }

                }

            }
            .task
            {

                if !loaded
                {

                    load()
                    if opensEveningReview && loadError == nil
                    {
                        showsReview = true
                    }

                }

            }
            .sheet(isPresented: $showsPeriodicReview)
            {

                PeriodicReviewView(calendar: access?.document.calendar ?? planCalendar)
            }
            .sheet(isPresented: $showsWeeklyReview)
            {

                WeeklyReviewView(calendar: access?.document.calendar ?? planCalendar)
            }
            .sheet(isPresented: $showsDailyReview)
            {

                DailyHistoryReviewView(date: date, calendar: planCalendar, defaults: defaults)
            }
            .sheet(isPresented: $showsCheckIn)
            {

                TodayCheckInView(plan: $draft, date: date, onSave: saveVisionProgress)
            }
            .sheet(isPresented: $showsVision)
            {
                TodayVisionView(plan: $draft, date: date, onSave: saveVisionProgress)
            }
            .sheet(isPresented: $showsReview)
            {

                TodayReviewView(
                    plan: $draft, date: date, baseline: baseline, onSave: saveVisionProgress,
                    onCommitted:
                    {
                        saved in
                        baseline = saved;
                        draft = saved
                    })
            }
            .sheet(isPresented: $showsPicker)
            {
                DailyPriorityPicker(sources: sources, priorities: $draft.priorities)
            }
            .sheet(isPresented: $showsNewPriority)
            {

                NewDailyPriorityView
                {
                    source in
                    let priority = DailyPlanPriority(source)
                    if !draft.priorities.contains(where:
                        {
                            $0.id == priority.id
                        })
                    {
                        draft.priorities.append(priority)
                    }

                }

            }
            .fullScreenCover(item: $openedItem)
            {
                result in
                if let week = access?.document.weeks.first(where:
                    {
                        $0.id == result.collectionID
                    })
                {

                    PlanningCalendarWeekView(
                        week: week, initialDayID: result.listID, initialCardID: result.card.id,
                        onLeaveForHome:
                        {
                            openedItem = nil
                        })
                }
                else if let owner = access?.library.first(where:
                    {
                        $0.id == result.collectionID && $0.isActive
                    })
                {

                    PlanningSearchLibraryView(
                        collection: owner, initialListID: result.listID, initialCardID: result.card.id,
                        onLeaveForHome:
                        {
                            openedItem = nil
                        })
                }
                else
                {

                    VStack(spacing: 16)
                    {

                        ContentUnavailableView("Item unavailable", systemImage: "link.badge.plus")
                        Button("Back to plan")
                        {
                            openedItem = nil
                        } .padding()
                    }

                }

            }

        }
        .interactiveDismissDisabled(hasChanges)
        .confirmationDialog("Discard changes to this plan?", isPresented: $confirmsDiscard, titleVisibility: .visible)
        {

            Button("Discard changes", role: .destructive)
            {
                dismiss()
            }

            Button("Keep editing", role: .cancel)
            {

            }

        }
        .alert("Plan not saved", isPresented: Binding(get:
                {
                    saveError != nil
                }, set:
                {
                    if !$0
                    {
                        saveError = nil
                    }

                }))
        {

            Button("OK")
            {
                saveError = nil
            }

        }
        message:
        {

            Text(saveError ?? "")
        }
        .presentationBackground(Color(.systemGroupedBackground))
        .presentationDetents([.fraction(0.7), .large])
        .presentationDragIndicator(.visible)
    }

}


///
/// Selects live workspace items as daily priorities
///
/// @section    Purpose
///     Searches supplied owner-qualified sources and updates linked priority references without
///     duplicating their Cards.
///
struct DailyPriorityPicker: View
{


    let sources:             [PlanningSearchResult]
    @Binding var priorities: [DailyPlanPriority]
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var matches: [PlanningSearchResult]
    {

        sources.filter
        {

            query.isEmpty || $0.card.word.localizedStandardContains(query)
            || $0.collectionTitle.localizedStandardContains(query) || $0.listTitle.localizedStandardContains(query)
        }

    }

    var body: some View
    {

        NavigationStack
        {

            List
            {

                Section
                {

                    Text("Choose existing Cards and Notes. Their locations and contents stay unchanged.").font(
                        .subheadline
                    ).foregroundStyle(.secondary)
                }

                if matches.isEmpty
                {
                    Text("No active Cards or Notes match.").foregroundStyle(.secondary)
                }

                ForEach(matches)
                {
                    source in
                    let priority = DailyPlanPriority(source)
                    let selected = priorities.contains
                    {
                        $0.id == priority.id
                    }

                    Button
                    {

                        if selected
                        {

                            priorities.removeAll
                            {
                                $0.id == priority.id
                            }

                        }
                        else
                        {

                            priorities.append(priority)
                        }

                    }
                    label:
                    {

                        HStack(spacing: 12)
                        {

                            Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(
                                selected ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 4)
                            {

                                Text(source.card.word).font(.headline).foregroundStyle(.primary)
                                Text(priority.location).font(.caption).foregroundStyle(.secondary)
                            }

                            Spacer()
                            Image(systemName: source.card.presentation == .note ? "note.text" : "rectangle")
                            .foregroundStyle(.secondary)
                        } .frame(minHeight: 44)
                    } .accessibilityAddTraits(selected ? [.isSelected] : [])
                }

            }
            .navigationTitle("Choose priorities")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Find a Card, Note, List, or Board")
            .toolbar
            {
                ToolbarItem(placement: .confirmationAction)
                {
                    Button("Done")
                    {
                        dismiss()
                    }

                }

            }

        }

    }

}


///
/// Creates a new item for inclusion as a daily priority
///
/// @section    Purpose
///     Uses the selected calendar or personal owner and returns its searchable reference only after
///     content and attachments are accepted.
///
@MainActor
enum DailyPriorityCreation
{


    ///
    /// @fcn        DailyPriorityCreation.create
    /// @brief      Create a new card or note in the chosen priority destination
    /// @details    Uses calendar or personal-owner access to save full content and attachments, returning the
    ///             resulting searchable item only after accepted persistence.
    ///
    /// @param[in]  title         Display title or proposed title text
    /// @param[in]  body          Body text for the new item
    /// @param[in]  presentation  Card, note, or board presentation selected by the caller
    /// @param[in]  destination   Owner-qualified destination list reference
    /// @param[in]  access        Checked calendar and personal-owner access callbacks
    /// @param[in]  attachments   Attachment records already available for the new item
    ///
    /// @return     (PlanningSearchResult?) saved item and its owner context, or nil when creation is rejected
    ///
    static func create(
        title: String, body: String, presentation: ItemPresentation,
        destination: WorkspaceListReference, access: PlanningCalendarAccess, attachments: [KanbanAttachment] = []
    ) -> PlanningSearchResult?
    {

        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else
        {
            return nil
        }

        let week = access.document.weeks.first
        {
            $0.id == destination.ownerID
        }

        guard
        var owner = week?.collection
        ?? access.library.first(where:
            {
                $0.id == destination.ownerID && $0.isActive
            }),
        let index = owner.lists.firstIndex(where:
            {
                $0.id == destination.listID && !$0.isArchived
            })
        else
        {
            return nil
        }

        let id = (owner.lists.flatMap(\.allCards).map(\.id).max() ?? -1) + 1
        var card = KanbanCard(
            id: id, word: title, listTitle: owner.lists[index].title,
            checklists: [], comments: [], members: [], labelIDs: [], attachments: attachments,
            coverAttachmentID: attachments.first(where:
                {
                    $0.kind == .photo
                })?.id,
            descriptionOverride: body, subtitleOverride: "", presentation: presentation, createdAt: .now)
        NewCardAppearanceDefaults.apply(to: &card)
        owner.lists[index].cards.append(card)
        let saved: Bool
        if var week
        {

            week.collection = owner;
            saved = access.saveWeek(week)
        }
        else
        {

            saved = access.saveLibrary(owner)
        }

        guard saved else
        {
            return nil
        }

        return PlanningSearchResult(
            weekKey: week?.startKey, collectionID: owner.id,
            collectionTitle: week?.rangeTitle ?? owner.title, listID: destination.listID,
            listTitle: card.listTitle, card: card)
    }

}


///
/// Edits a new daily priority item before creation
///
/// @section    Purpose
///     Retains writing, destination, and attachment drafts and reports the created owner-qualified
///     result through the caller's callback.
///
struct NewDailyPriorityView: View
{


    @Environment(\.planningCalendarAccess) private var access
    @Environment(\.dismiss) private var dismiss
    let onCreate: (PlanningSearchResult) -> Void
    @StateObject private var attachmentDraft = CreationAttachmentDraft()
    @State private var keyboardContextID = UUID()
    @State private var title = ""
    @State private var bodyText = ""
    @State private var presentation: ItemPresentation = .card
    @State private var destination:  WorkspaceListReference?
    @State private var initialized = false
    @State private var error: String?
    @State private var confirmsDiscard = false
    private var destinations: [WorkspaceListDestination]
    {

        WorkspaceBrowseIndex.lists(
            in: WorkspaceBrowseIndex.owners(document: access?.document, library: access?.library ?? []))
    }


    ///
    /// @fcn        NewDailyPriorityView.saveDraft
    /// @brief      Save the new priority draft and its imported media
    /// @details    Uses the checked capture and creation paths and retains the composer with feedback when the
    ///             destination cannot be saved.
    ///
    /// @return     (Void) no return value
    ///
    private func saveDraft()
    {

        guard let access, let destination else
        {
            return
        }

        do
        {

            guard
            try attachmentDraft.save(commit:
                {
                    attachments in
                    guard
                    let created = DailyPriorityCreation.create(
                        title: title, body: bodyText, presentation: presentation,
                        destination: destination, access: access, attachments: attachments)
                    else
                    {
                        return false
                    }

                    onCreate(created)
                    return true
                })
            else
            {

                error = "The item could not be saved. Your draft and attachments are still here."
                return
            }

        }
        catch
        {
            self.error = "Attachments couldn't be saved. Your draft is still here; please try again.";
            return
        }

        dismiss()
    }


    ///
    /// @fcn        NewDailyPriorityView.initializeDestination
    /// @brief      Choose On the Table as the initial priority destination
    /// @details    Runs once and selects the first available standalone On the Table owner; leaves the destination
    ///             unset when that choice is unavailable.
    ///
    /// @return     (Void) no return value
    ///
    private func initializeDestination()
    {

        guard !initialized else
        {
            return
        }

        initialized = true
        for target in destinations where target.owner.kind == .list && target.owner.title == "On the Table"
        {

            destination = target.reference
            break
        }

    }

    var body: some View
    {

        NavigationStack
        {

            Form
            {

                Section
                {

                    Picker("Create", selection: $presentation)
                    {

                        Text("Card").tag(ItemPresentation.card)
                        Text("Note").tag(ItemPresentation.note)
                    } .pickerStyle(.segmented)
                    TextField("Title", text: $title, axis: .vertical).textInputAutocapitalization(.sentences)
                    TextField(
                        presentation == .note ? "Start writing…" : "Details (optional)", text: $bodyText,
                        axis: .vertical
                    ).textInputAutocapitalization(.sentences).lineLimit(4 ... 10)
                }

                Section("Attachments")
                {
                    CreationAttachmentList(draft: attachmentDraft)
                }

                Section("Save in")
                {

                    Picker("List", selection: $destination)
                    {

                        Text("Choose a List").tag(Optional<WorkspaceListReference>.none)
                        ForEach(destinations)
                        {
                            target in
                            Text(
                                target.owner.kind == .list
                                ? target.owner.title : target.owner.title + " · " + target.list.title
                            )
                            .tag(Optional(target.reference))
                        }

                    } .pickerStyle(.navigationLink)
                    if destinations.isEmpty
                    {

                        Text("Create a List in Plans first, then return here.").foregroundStyle(.secondary)
                    }

                }

                Section
                {

                    Text(
                                                            "Add saves the original item in this List and selects it in your plan. Tap Save on Today's Plan to keep the priority link. Canceling this composer creates nothing."
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                }

            }
            .navigationTitle("Add priority")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {

                ToolbarItem(placement: .cancellationAction)
                {

                    Button("Cancel")
                    {

                        if title.isEmpty && bodyText.isEmpty && attachmentDraft.entries.isEmpty
                        {

                            dismiss()
                        }
                        else
                        {

                            confirmsDiscard = true
                        }

                    }

                }

                ToolbarItem(placement: .confirmationAction)
                {

                    Button("Add")
                    {

                        saveDraft()
                    } .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || destination == nil
                        || access == nil || attachmentDraft.isImporting)
                }

            }
            .onAppear(perform: initializeDestination)
        }
        .modifier(CreationAttachmentPresentation(draft: attachmentDraft))
        .onAppear
        {

            PlenactKeyboard.shared.setContext(
                keyboardContextID,
                actions: KeyboardCardActions(
                    exit:
                    {
                        confirmsDiscard = true
                    }, attachment: attachmentDraft.openSources, showsUpperBorder: true))
        }
        .onDisappear
        {
            PlenactKeyboard.shared.removeContext(keyboardContextID)
        }
        .interactiveDismissDisabled(!title.isEmpty || !bodyText.isEmpty || !attachmentDraft.entries.isEmpty)
        .confirmationDialog("Discard this priority draft?", isPresented: $confirmsDiscard, titleVisibility: .visible)
        {

            Button("Discard draft", role: .destructive)
            {
                dismiss()
            }

            Button("Keep editing", role: .cancel)
            {

            }

        }
        .alert("Priority not added", isPresented: Binding(get:
                {
                    error != nil
                }, set:
                {
                    if !$0
                    {
                        error = nil
                    }

                }))
        {

            Button("OK")
            {
                error = nil
            }

        }
        message:
        {

            Text(error ?? "")
        }

    }

}
