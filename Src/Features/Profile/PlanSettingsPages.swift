// --------------------------------------------------------------------------------------------------
// @file       PlanSettingsPages.swift
// @brief      Focused Plan Settings destinations sharing one parent-owned preference draft
// @details    Keeps ordinary preference pages short without constraining accessibility scrolling.
//             Studio, reminders, templates and shortcuts retain independent editing transactions
// --------------------------------------------------------------------------------------------------
import SwiftUI


/// Identifies the compact directory and its focused preference pages
/// @section Purpose
///     Keep visible navigation names, order and accessibility identifiers consistent
enum PlanSettingsPage: String, CaseIterable, Identifiable
{

    case appearance, focus, planning, review, navigation, display, maps, data, focusFilters

    static let menuPages: [Self] = /* Menu pages */
        [.appearance, .focus, .planning, .review, .navigation, .display, .maps, .data]

    var id: String /* Record or view identity */
    {

        rawValue
    }

    var title: String /* User-facing title */
    {

        switch self
        {

        case .appearance: "Appearance & Studio"
        case .focus: "Today’s Focus"
        case .planning: "Planning"
        case .review: "Review & Reminders"
        case .navigation: "Navigation & Shortcuts"
        case .display: "Display & Accessibility"
        case .maps: "Maps"
        case .data: "Your Data"
        case .focusFilters: "Included Items"
        }
    }

    var symbol: String /* Selected symbol name */
    {

        switch self
        {

        case .appearance: "paintpalette"
        case .focus, .focusFilters: "line.3.horizontal.decrease.circle"
        case .planning: "calendar"
        case .review: "bell"
        case .navigation: "square.grid.3x2"
        case .display: "textformat.size"
        case .maps: "map"
        case .data: "externaldrive"
        }
    }
}


/// Matches a sheet-backed settings editor to the directory's disclosure rows
/// @section Purpose
///     Preserve the reminder editor's existing independent Save and Cancel controls
struct PlanSettingsMenuRow: View
{

    let page: PlanSettingsPage /* Current settings destination */

    var body: some View /* Plan Settings Menu layout */
    {

        HStack
        {

            Label
            {

                Text(page.title)
            }
            icon:
            {

                Image(systemName: page.symbol).foregroundStyle(.tint)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.page." + page.rawValue)
    }
}


/// Renders a single preference module without owning or saving another draft
/// @section Purpose
///     Back retains the parent draft; Save publishes it once and closes the settings flow
struct PlanSettingsModulePage: View
{

    let page: PlanSettingsPage                        /* Current settings destination */
    @Binding var preferences: LocalProfilePreferences /* Planning and display choices */
    @Binding var firstWeekday: Int                    /* Calendar week boundary       */
    let lists: [KanbanList]                           /* Ordered List records         */
    let onSave: () -> Void                            /* Persist the edited value     */
    let onStudio: () -> Void                          /* Studio callback              */
    let onTemplates: () -> Void                       /* Templates callback           */
    let onShortcuts: () -> Void                       /* Shortcuts callback           */
    @State private var showsDefaultCardLayout = false /* Layout editor visibility */

    var body: some View /* Focused preference controls */
    {

        Form
        {

            content
        }
        .modifier(StudioFormWallpaper(destination: .settings))
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsDefaultCardLayout)
        {

            CardLayoutEditor(layout: NewCardLayoutStore.load() ?? CardSectionLayout(), title: "Default Card Layout")
            {
                NewCardLayoutStore.save($0)
            }
        }
        .toolbar
        {

            if page != .data
            {

                ToolbarItem(placement: .confirmationAction)
                {

                    Button("Save", action: onSave)
                        .accessibilityIdentifier("settings.saveDraft")
                }
            }
        }
    }


    /// @fcn PlanSettingsModulePage.content
    /// @brief Bind each existing preference to its focused destination
    /// @return Controls editing only the parent-owned draft, or opening an independent editor
    @ViewBuilder
    private var content: some View /* Content being processed */
    {

        switch page
        {

        case .appearance:
            Section
            {

                Button("Plenact Studio", systemImage: "paintpalette", action: onStudio)
            }
            footer:
            {

                Text("Wallpapers, item surfaces, coordinated colors, and saved looks. Studio has its own Save and Cancel.")
            }
            NewCardColorDefaultsSection(headers: $preferences.randomizesNewCardHeaders,
                backgrounds: $preferences.randomizesNewCardBackgrounds)
            Section
            {

                Button("Default Card Layout", systemImage: "rectangle.3.group")
                {
                    showsDefaultCardLayout = true
                }
            }
            footer:
            {

                Text("Choose which sections new Cards show and in what order. Save applies this default on this device.")
            }

        case .focus:
            focusLayout
            Section
            {

                NavigationLink(value: PlanSettingsPage.focusFilters)
                {

                    Label("Included items", systemImage: "line.3.horizontal.decrease")
                }
            }
            Section
            {

                Picker("Default Today list", selection: $preferences.defaultListID)
                {

                    Text("Choose each day").tag(nil as Int?)
                    ForEach(lists)
                    {

                        Text($0.title).tag(Optional($0.id))
                    }
                }
            }
            footer:
            {

                Text("The fallback List for Today when no date-specific choice exists.")
            }

        case .focusFilters:
            Section
            {

                Toggle("Up Next", isOn: $preferences.todayFocusIncludesUpNext)
                Toggle("Cards marked important", isOn: $preferences.todayFocusIncludesImportant)
                Toggle("Cards bookmarked", isOn: $preferences.todayFocusIncludesBookmarked)
            }
            header:
            {

                Text("Include matching items")
            }
            footer:
            {

                Text("An item can match any enabled filter. Up Next includes current or upcoming schedules and skips ended time slots. Important and bookmarked items can be unscheduled. With no filters enabled, all today’s items are eligible.")
            }
            Section
            {

                Toggle("Hide completed items", isOn: $preferences.todayFocusHidesCompleted)
            }
            footer:
            {

                Text("Progress always counts the whole day, even when completed items are hidden.")
            }

        case .planning:
            Section
            {

                Picker("Week starts on", selection: $firstWeekday)
                {

                    Text("Sunday").tag(1)
                    Text("Monday").tag(2)
                }
                Toggle("Show due dates on new cards", isOn: $preferences.showsDueDatesOnNewCards)
            }
            footer:
            {

                Text("Existing plans keep their dates. Due date visibility is a default for new Cards and can be changed on each Card.")
            }
            Section
            {

                Button("Planning Templates", systemImage: "doc.on.doc", action: onTemplates)
            }
            footer:
            {

                Text("Choose the default for new weeks or save a layout as a template. Templates have their own save controls.")
            }

        case .navigation:
            Section
            {

                Button("My shortcuts", systemImage: "square.grid.3x2", action: onShortcuts)
            }
            footer:
            {

                Text("Choose and reorder pinned shortcuts. Done in that editor saves them independently.")
            }
            Section("Navigation")
            {

                Toggle("Show navigation labels", isOn: $preferences.showsNavigationLabels)
                Toggle("Lower-left corner Back shortcut", isOn: $preferences.enablesLowerCornerBack)
                    .accessibilityHint("Enable an invisible Back target above the bottom toolbar in supported views")
            }

        case .display:
            Section("Reading & controls")
            {

                Toggle("Reduce supporting content", isOn: $preferences.usesReducedContent)
                Toggle("Use larger primary controls", isOn: $preferences.usesLargeControls)
                Toggle("Scroll overflowing titles and subtitles", isOn: $preferences.scrollsOverflowingTitles)
                    .accessibilityHint("Allow manual horizontal reading in detail and title-bar headers")
            }
            Section("Importance")
            {

                ImportanceStarStylePicker(selection: $preferences.importanceStarStyle)
            }

        case .maps:
            MapsAppSettingsSection(selection: $preferences.preferredMapsApp)

        case .data:
            Section
            {

                NavigationLink
                {

                    LocalDataExportView()
                }
                label:
                {

                    Label("Local backup", systemImage: "externaldrive")
                }
            }
            footer:
            {

                Text("Prepare backups, review portable packages, and access local recovery tools.")
            }

        case .review:
            EmptyView()
        }
    }


    /// @fcn PlanSettingsModulePage.focusLayout
    /// @brief Keep layout and ordering controls separate from inclusion filters
    /// @return Existing count, ordering and grouping preferences with focused guidance
    private var focusLayout: some View /* Focus layout */
    {

        Section
        {

            Picker("Visible rows in Today’s Focus", selection: $preferences.todayFocusItemCount)
            {

                ForEach(1 ... 12, id: \.self)
                {

                    Text("\($0)").tag($0)
                }
                Text("Expand all rows").tag(0)
            }
            Toggle("Keep Day Lists in time order", isOn: $preferences.keepsDayListsInTimeOrder)
            Picker("Focus order", selection: Binding(get:
                {
                    preferences.keepsDayListsInTimeOrder ? .chronological : preferences.todayFocusOrder
                }, set:
                {

                    preferences.todayFocusOrder = $0

                }))
            {

                ForEach(TodayFocusOrder.allCases, id: \.self)
                {

                    Text($0.title).tag($0)
                }
            }
            .disabled(preferences.keepsDayListsInTimeOrder)
            Toggle("Group by Day list sections", isOn: $preferences.todayFocusGroupsBySection)
        }
        footer:
        {

            Text("Rows set preview height; every match remains scrollable. Time ordering uses start, then due times; untimed items keep their manually chosen positions. Day List sections stay intact. Turn time ordering off to manually arrange timed Cards and choose a separate Focus order. Section headings do not count as rows.")
        }
    }
}
