// --------------------------------------------------------------------------------------------------
// @file       PlanSettingsView.swift
// @brief      Compact Plan Settings directory and shared preference-draft lifecycle
// @details    Focused pages edit one draft. Save commits it once; Back retains it; Cancel discards it.
//             Independent editors retain their existing checked save controls
// --------------------------------------------------------------------------------------------------
import SwiftUI


///
/// Presents planning settings independently of profile editing
///
/// @section    Purpose
///     Edits a local preference draft and publishes display and planning choices through the
///     established save flow
///
struct PlanSettingsView: View
{


    @Environment(\.dismiss) private var dismiss
    @Environment(\.planningCalendarAccess) private var access
    @State private var preferences                     = PlanPreferencesStore.load()
    @State private var firstWeekday                    = 1
    @State private var loaded                          = false
    @State private var showsTemplates                  = false
    @State private var opensLibraryAfterTemplates      = false
    @State private var confirmsTemplateNavigation      = false
    @State private var showsShortcuts                  = false
    @State private var showsReviewRhythmSettings       = false
    @State private var showsStudio                     = false
    @State private var path: [PlanSettingsPage]        = []
    @AppStorage(TodayListPins.key) private var pinData = Data()
    let lists:         [KanbanList]
    let onSaveProfile: (LocalProfile) -> Void
    var onOpenTemplateLibrary: (() -> Void)? = nil


    /// @fcn PlanSettingsView.savePreferences
    /// @brief Publish the settings draft through the existing checked calendar/profile save path
    /// @return True after preferences can be saved; false when the calendar rejects its boundary change
    private func savePreferences() -> Bool
    {

        guard access?.setFirstWeekday(firstWeekday) != false else
        {

            return false
        }
        PlanPreferencesStore.save(preferences)
        if var profile = LocalProfileStore.load()
        {

            profile.preferences = preferences

            onSaveProfile(profile)
        }
        return true
    }

    /// @fcn PlanSettingsView.commitAndDismiss
    /// @brief Save the shared draft once from any preference page, then close Plan Settings
    /// @return Void; a rejected calendar change keeps the draft and its current page open
    private func commitAndDismiss()
    {

        if savePreferences()
        {

            dismiss()
        }
    }


    var body: some View
    {

        NavigationStack(path: $path)
        {

            Form
            {

                Section
                {

                    ForEach(PlanSettingsPage.menuPages)
                    {
                        page in
                        if page == .review
                        {

                            Button
                            {

                                showsReviewRhythmSettings = true

                            }
                            label:
                            {

                                PlanSettingsMenuRow(page: page)
                            }
                            .foregroundStyle(.primary)
                        }
                        else
                        {

                            NavigationLink(value: page)
                            {

                                Label(page.title, systemImage: page.symbol)
                            }
                            .accessibilityIdentifier("settings.page." + page.rawValue)
                        }
                    }
                }
                footer:
                {

                    Text("Save applies your Plan Settings changes. Studio, reminders, shortcuts, and templates save in their own editors.")
                }
            }
            .navigationDestination(for: PlanSettingsPage.self)
            {
                page in
                PlanSettingsModulePage(page: page, preferences: $preferences, firstWeekday: $firstWeekday,
                    lists: lists, onSave: commitAndDismiss,
                    onStudio: {

                        showsStudio = true

                    }, onTemplates: {

                        showsTemplates = true

                    },
                    onShortcuts: {

                        showsShortcuts = true

                    })
            }
            .modifier(StudioFormWallpaper(destination: .settings))
            .navigationTitle("Plan Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {

                ToolbarItem(placement: .cancellationAction)
                {
                    if path.isEmpty
                    {

                        Button("Cancel")
                        {

                            dismiss()
                        }
                    }

                }

                ToolbarItem(placement: .confirmationAction)
                {

                    if path.isEmpty
                    {

                        Button("Save", action: commitAndDismiss)
                    }
                }

            }
            .onAppear
            {

                guard !loaded else
                {
                    return
                }

                firstWeekday = access?.document.firstWeekday ?? Calendar.current.firstWeekday
                loaded = true

            }
        }
        .sheet(isPresented: $showsStudio)
        {

            NavigationStack
            {

                StudioSettingsView()
            }
        }
        .sheet(isPresented: $showsReviewRhythmSettings)
        {
            ReviewRhythmSettingsView()
        }
        .sheet(isPresented: $showsTemplates, onDismiss:
        {

            guard opensLibraryAfterTemplates else
            {

                return
            }

            opensLibraryAfterTemplates = false

            let savedFirstWeekday = access?.document.firstWeekday ?? Calendar.current.firstWeekday

            if preferences != PlanPreferencesStore.load() || firstWeekday != savedFirstWeekday
            {

                confirmsTemplateNavigation = true

            }
            else
            {

                onOpenTemplateLibrary?()
            }
        })
        {

            PlanningTemplatesView(onOpenLibrary: onOpenTemplateLibrary == nil ? nil :
            {

                opensLibraryAfterTemplates = true
                showsTemplates = false

            })
        }
        .confirmationDialog("Save settings before opening Templates?", isPresented: $confirmsTemplateNavigation,
            titleVisibility: .visible)
        {

            Button("Save and Open Templates")
            {

                if savePreferences()
                {

                    onOpenTemplateLibrary?()
                }
            }
            Button("Discard Settings Changes and Open Templates", role: .destructive)
            {

                onOpenTemplateLibrary?()
            }
            Button("Keep Editing Settings", role: .cancel)
            {

            }
        }
        .sheet(isPresented: $showsShortcuts)
        {

            TodayShortcutEditor(
                pins: TodayListPins.decode(pinData),
                owners: WorkspaceBrowseIndex.owners(document: access?.document, library: access?.library ?? [])
            )
            {

                pinData = TodayListPins.encode($0)

            }

        }
        .databaseActivityOverlay()
        .presentationDetents([.large])
    }

}


