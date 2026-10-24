// --------------------------------------------------------------------------------------------------
// @file       AccountSettingsView.swift
// @brief      Local identity editing and standalone planning settings
// @details    Provides profile creation and removal, avatar selection and cropping, and accessible
//             color controls. Edits planning and display preferences including Today Focus,
//             new-Card colors, title reading, corner Back navigation, and importance-star
//             presentation through explicit settings drafts.
//
// --------------------------------------------------------------------------------------------------
import ImageIO
import PhotosUI
import SwiftUI
import UIKit


// -------------------------------------- MARK: - Profile Avatar ------------------------------- //


///
/// Displays a discreet local profile identity or signed-out-style placeholder
///
/// @section    Purpose
///     Provide an obvious Account & Settings entry without exposing profile details on Today
///
struct ProfileAvatarView: View
{


    let profile:   LocalProfile?  /* Current local profile                                      */
    let size:      CGFloat        /* Stable avatar size                                         */
    var photoData: Data? = nil    /* In-memory photo override for the profile's stored filename */

    ///
    /// @fcn        ProfileAvatarView.body
    /// @brief      Build the local profile avatar
    /// @details    Shows an available local photo over the selected symbol or initials for an
    ///             existing profile
    ///
    /// @return     (some View) circular profile identity
    ///
    /// @pre        The optional profile and avatar size are configured
    /// @post       Rendering does not modify profile or photo data
    ///
    var body: some View
    {  /* Circular local-profile avatar */


        ZStack
        {

            Circle()
            .fill(profile?.avatarColor.color ?? Color.secondary.opacity(0.16))

            if let profile
            {  /* Available local profile */


                if let symbolName = profile.avatarIcon.symbolName
                {  /* Chosen icon's SF Symbol */


                    Image(systemName: symbolName)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(profile.avatarForegroundColor.color)
                }
                else
                {


                    Text(profile.initials)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(profile.avatarForegroundColor.color)
                }

            }
            else
            {


                Image(systemName: "person.crop.circle")
                .font(.system(size: size * 0.58))
                .foregroundStyle(.secondary)
            }

        }

        .frame(width: size, height: size)
        .overlay
        {

            if let data = photoData
            ?? ProfileAvatarPhotoStore.load(profile?.avatarPhotoFileName), /* Selected or saved avatar bytes */
            let image = UIImage(data: data)
            {  /* Decoded avatar photo           */

                Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
            }

        }

        .accessibilityHidden(true)
    }

}


// -------------------------------------- MARK: - Account Settings ----------------------------- //


///
/// Presents local identity, planning, accessibility, privacy, and profile controls
///
/// @section    Purpose
///     Let the user create or personalize a local Plenact profile without online authentication
///
/// @note   Removing a local profile does not remove Board or attachment data
///
struct AccountSettingsView: View
{


    ///
    /// Identifies the account editor's settings tabs
    ///
    /// @section    Purpose
    ///     Separates profile information from preferences without creating independent profile
    ///     drafts.
    ///
    private enum SettingsTab: String, CaseIterable
    {


        case account = "Account"
        case settings = "Settings"
    }

    @State private var selectedTab: SettingsTab = .account

    let profile:  LocalProfile?           /* Existing local profile */
    let lists:    [KanbanList]            /* Default-list choices   */
    let onSave:   (LocalProfile) -> Void  /* Profile save callback  */
    let onRemove: () -> Void              /* Profile removal        */

    @Environment(\.planningCalendarAccess) private var planningAccess
    @AppStorage(TodayListPins.key) private var listPinData = Data()
    @State private var showsShortcutEditor = false
    @State private var firstWeekday = 1
    @State private var didLoadWeekStart = false
    @Environment(\.dismiss) private var dismiss /* Sheet dismissal       */

    @State private var profileID:                    UUID                          /* Draft profile ID       */
    @State private var createdAt:                    Date                          /* Draft creation date    */
    @State private var displayName:                  String                        /* Draft display name     */
    @State private var email:                        String                        /* Draft local email      */
    @State private var context:                      String                        /* Draft planning context */
    @State private var avatarColor:                  ProfileAvatarColor            /* Draft avatar color     */
    @State private var avatarIcon:                   ProfileAvatarIcon             /* Draft avatar icon      */
    @State private var avatarForegroundColor:        ProfileAvatarForegroundColor  /* Draft icon color       */
    @State private var defaultListID:                Int?                          /* Draft default list     */
    @State private var usesReducedContent:           Bool                          /* Draft content density  */
    @State private var scrollsOverflowingTitles:     Bool
    @State private var importanceStarStyle:          ImportanceStarStyle
    @State private var enablesLowerCornerBack:       Bool
    @State private var usesLargeControls:            Bool /* Draft control sizing   */
    @State private var randomizesNewCardHeaders:     Bool
    @State private var randomizesNewCardBackgrounds: Bool
    @State private var showsDueDatesOnNewCards:      Bool
    @State private var todayFocusIncludesUpNext:     Bool
    @State private var todayFocusIncludesImportant:  Bool
    @State private var todayFocusIncludesBookmarked: Bool
    @State private var todayFocusOrder:              TodayFocusOrder
    @State private var todayFocusGroupsBySection:    Bool
    @State private var todayFocusHidesCompleted:     Bool
    @State private var todayFocusItemCount:          Int
    @State private var showsNavigationLabels:        Bool /* Draft navigation captions */
    @State private var showsReviewRhythmSettings = false
    @State private var confirmsRemoval = false       /* Removal confirmation                        */
    @State private var isChoosingAvatarIcon = false  /* Whether the nested avatar picker is visible */
    @State private var profileSheetDetent: PresentationDetent =
    .large                                       /* Current profile-sheet height        */
    @State private var avatarPhotoData: Data?    /* Draft avatar photo bytes            */
    @State private var photoSaveError:  String?  /* Avatar photo persistence error text */


    ///
    /// @fcn        AccountSettingsView.trimmedDisplayName
    /// @brief      Return the display-name draft without surrounding whitespace
    /// @details    Supplies profile validation and normalized saving
    ///
    /// @return     (String) normalized display name
    ///
    /// @pre        displayName contains the current draft
    /// @post       The draft remains unchanged
    ///
    private var trimmedDisplayName: String
    {  /* Normalized name */

        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }


    ///
    /// @fcn        AccountSettingsView.init(profile:lists:onSave:onRemove:)
    /// @brief      Initialize local profile drafts and callbacks
    /// @details    Seeds existing values or calm defaults for first profile creation
    ///
    /// @param[in]  profile   Existing local profile when editing, or nil when creating
    /// @param[in]  lists     Current Board lists available as a default
    /// @param[in]  onSave    Callback receiving a complete profile snapshot
    /// @param[in]  onRemove  Callback removing only local profile data
    ///
    /// @return     (AccountSettingsView) configured local profile form
    ///
    /// @post       Draft state begins with the existing profile or local defaults
    ///
    init(
        profile: LocalProfile?,
        lists: [KanbanList],
        onSave: @escaping (LocalProfile) -> Void,
        onRemove: @escaping () -> Void
    )
    {


        let preferences = PlanPreferencesStore.load() /* Initial settings */

        self.profile = profile
        self.lists = lists
        self.onSave = onSave
        self.onRemove = onRemove

        _profileID = State(initialValue: profile?.id ?? UUID())
        _createdAt = State(initialValue: profile?.createdAt ?? .now)
        _displayName = State(initialValue: profile?.displayName ?? "")
        _email = State(initialValue: profile?.email ?? "")
        _context = State(initialValue: profile?.context ?? "")
        _avatarColor = State(initialValue: profile?.avatarColor ?? .teal)
        _avatarIcon = State(initialValue: profile?.avatarIcon ?? .initials)
        _avatarForegroundColor = State(initialValue: profile?.avatarForegroundColor ?? .white)
        _avatarPhotoData = State(initialValue: ProfileAvatarPhotoStore.load(profile?.avatarPhotoFileName))

        _defaultListID = State(
            initialValue: lists.contains(where:
                {
                    $0.id == preferences.defaultListID
                })
            ? preferences.defaultListID : nil)

        _usesReducedContent = State(initialValue: preferences.usesReducedContent)
        _usesLargeControls = State(initialValue: preferences.usesLargeControls)
        _scrollsOverflowingTitles = State(initialValue: preferences.scrollsOverflowingTitles)
        _enablesLowerCornerBack = State(initialValue: preferences.enablesLowerCornerBack)
        _importanceStarStyle = State(initialValue: preferences.importanceStarStyle)
        _showsNavigationLabels = State(initialValue: preferences.showsNavigationLabels)
        _showsDueDatesOnNewCards = State(initialValue: preferences.showsDueDatesOnNewCards)
        _randomizesNewCardHeaders = State(initialValue: preferences.randomizesNewCardHeaders)
        _randomizesNewCardBackgrounds = State(initialValue: preferences.randomizesNewCardBackgrounds)
        _todayFocusItemCount = State(initialValue: preferences.todayFocusItemCount)
        _todayFocusIncludesUpNext = State(initialValue: preferences.todayFocusIncludesUpNext)
        _todayFocusIncludesImportant = State(initialValue: preferences.todayFocusIncludesImportant)
        _todayFocusIncludesBookmarked = State(initialValue: preferences.todayFocusIncludesBookmarked)
        _todayFocusOrder = State(initialValue: preferences.todayFocusOrder)
        _todayFocusGroupsBySection = State(initialValue: preferences.todayFocusGroupsBySection)
        _todayFocusHidesCompleted = State(initialValue: preferences.todayFocusHidesCompleted)
    }


    ///
    /// @fcn        AccountSettingsView.saveProfile()
    /// @brief      Save normalized local identity and personalization
    /// @details    Preserves profile identity and creation date across edits
    ///
    /// @return     (Void) invokes the save callback and dismisses the sheet
    ///
    /// @pre        The caller enables Save only when the normalized display name is non-empty
    /// @post       On successful photo persistence, the normalized profile is saved and the sheet
    ///             is dismissed; a photo write failure leaves the sheet open
    ///
    private func saveProfile()
    {


        let photoFileName: String? /* Stored filename for the new avatar photo */

        do
        {


            if let avatarPhotoData
            {  /* Newly selected avatar-photo bytes */


                photoFileName = try ProfileAvatarPhotoStore.save(avatarPhotoData)
            }
            else
            {


                photoFileName = nil
            }

        }
        catch
        {


            photoSaveError = error.localizedDescription

            return
        }


        guard
        planningAccess?.setFirstWeekday(
            didLoadWeekStart ? firstWeekday : (planningAccess?.document.firstWeekday ?? 1)) != false
        else
        {

            ProfileAvatarPhotoStore.remove(photoFileName)
            return
        }


        let updatedProfile = LocalProfile( /* Completed profile */
            id: profileID,
            createdAt: createdAt,
            displayName: trimmedDisplayName,
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            context: context.trimmingCharacters(in: .whitespacesAndNewlines),
            avatarColor: avatarColor,
            avatarIcon: avatarIcon,
            avatarForegroundColor: avatarForegroundColor,
            avatarPhotoFileName: photoFileName,
            preferences: LocalProfilePreferences(
                defaultListID: defaultListID,
                usesReducedContent: usesReducedContent,
                usesLargeControls: usesLargeControls,
                showsNavigationLabels: showsNavigationLabels,
                showsDueDatesOnNewCards: showsDueDatesOnNewCards,
                todayFocusItemCount: todayFocusItemCount,
                randomizesNewCardHeaders: randomizesNewCardHeaders,
                randomizesNewCardBackgrounds: randomizesNewCardBackgrounds,
                todayFocusOrder: todayFocusOrder,
                todayFocusGroupsBySection: todayFocusGroupsBySection,
                todayFocusHidesCompleted: todayFocusHidesCompleted,
                todayFocusIncludesImportant: todayFocusIncludesImportant,
                todayFocusIncludesBookmarked: todayFocusIncludesBookmarked,
                todayFocusIncludesUpNext: todayFocusIncludesUpNext,
                scrollsOverflowingTitles: scrollsOverflowingTitles,
                enablesLowerCornerBack: enablesLowerCornerBack,
                importanceStarStyle: importanceStarStyle
            )
        )

        onSave(updatedProfile)
        ProfileAvatarPhotoStore.remove(profile?.avatarPhotoFileName)
        dismiss()
    }


    ///
    /// @fcn        AccountSettingsView.body
    /// @brief      Build the local Account & Settings form
    /// @details    Separates account details from planning, accessibility, and privacy settings
    ///
    /// @return     (some View) local profile creation or editing sheet
    ///
    /// @pre        Profile callbacks and list choices are initialized
    /// @post       Profile and settings changes stay local; loading the synthetic example board is
    ///             an explicit local replacement action
    ///
    var body: some View
    {  /* Local profile form and local example-board controls */


        NavigationStack
        {


            VStack(spacing: 0)
            {

                Picker("Account and settings", selection: $selectedTab)
                {

                    ForEach(SettingsTab.allCases, id: \.self)
                    {
                        tab in
                        Text(tab.rawValue).tag(tab)
                    }

                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

                if selectedTab == .account
                {

                    Form
                    {

                        Section("Profile")
                        {

                            NavigationLink
                            {

                                ProfileAvatarIconPicker(
                                    selection: $avatarIcon,
                                    avatarColor: $avatarColor,
                                    foregroundColor: $avatarForegroundColor,
                                    photoData: $avatarPhotoData,
                                    displayName: trimmedDisplayName
                                )
                                .onAppear
                                {

                                    isChoosingAvatarIcon = true
                                    profileSheetDetent = .height(620)
                                }
                                .onDisappear
                                {

                                    isChoosingAvatarIcon = false
                                    profileSheetDetent = .large
                                }

                            }
                            label:
                            {

                                HStack(spacing: 14)
                                {

                                    ProfileAvatarView(
                                        profile: LocalProfile(
                                            id: profileID,
                                            createdAt: createdAt,
                                            displayName: trimmedDisplayName,
                                            avatarColor: avatarColor,
                                            avatarIcon: avatarIcon,
                                            avatarForegroundColor: avatarForegroundColor
                                        ),
                                        size: 52,
                                        photoData: avatarPhotoData
                                    )

                                    VStack(alignment: .leading, spacing: 2)
                                    {

                                        Text(trimmedDisplayName.isEmpty ? "Local profile" : trimmedDisplayName)
                                        .font(.headline)

                                        Text("Stored on this device")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }


                                    Spacer()
                                }

                            }

                            .accessibilityLabel("Choose profile icon")
                            .accessibilityHint("Choose an icon or use your initials.")

                            TextField("Display name", text: $displayName).textInputAutocapitalization(.sentences)
                            .textContentType(.name)

                            TextField("Email (optional)", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)

                            TextField("Planning context (optional)", text: $context).textInputAutocapitalization(
                                .sentences)
                        }


                        if let profile
                        {  /* Existing profile being edited */


                            Section
                            {

                                LabeledContent(
                                                                                                "Created", value: profile.createdAt.formatted(date: .abbreviated, time: .omitted))

                                Button("Remove local profile", role: .destructive)
                                {

                                    confirmsRemoval = true
                                }

                            }
                            header:
                            {

                                Text("Local Profile")
                            }
                            footer:
                            {

                                Text("Removing this profile keeps all Board cards, labels, and attachments.")
                            }

                        }

                    }

                }
                else
                {

                    Form
                    {

                        Section
                        {

                            Button
                            {

                                showsShortcutEditor = true
                            }
                            label:
                            {

                                Label("My shortcuts", systemImage: "square.grid.3x2")
                            }

                            Picker("Week starts on", selection: $firstWeekday)
                            {

                                Text("Sunday").tag(1)
                                Text("Monday").tag(2)
                            }
                            .onAppear
                            {

                                guard !didLoadWeekStart else
                                {
                                    return
                                }

                                firstWeekday = planningAccess?.document.firstWeekday ?? Calendar.current.firstWeekday
                                didLoadWeekStart = true
                            }

                            Toggle("Show due dates on new cards", isOn: $showsDueDatesOnNewCards)
                            Picker("Default Today list", selection: $defaultListID)
                            {

                                Text("Choose each day").tag(nil as Int?)

                                ForEach(lists)
                                {
                                    list in
                                    Text(list.title).tag(Optional(list.id))
                                }

                            }

                        }
                        header:
                        {

                            Text("Planning")
                        }
                        footer:
                        {

                            Text(
                                                                                    "The week start applies to Week view and Calendar. Existing plans keep their dates. Due date visibility is a default for new cards and can be changed on each card. Cards without a due date show no date. The default Today list is used only when no list has been chosen for that date."
                            )
                        }


                        Section("Planning rhythm")
                        {

                            Button("Review invitations & reminders")
                            {
                                showsReviewRhythmSettings = true
                            }

                        }

                        NewCardColorDefaultsSection(
                            headers: $randomizesNewCardHeaders, backgrounds: $randomizesNewCardBackgrounds)

                        TodayFocusSettingsSection(
                            count: $todayFocusItemCount, order: $todayFocusOrder,
                            groups: $todayFocusGroupsBySection, hidesCompleted: $todayFocusHidesCompleted,
                            important: $todayFocusIncludesImportant, bookmarked: $todayFocusIncludesBookmarked,
                            upNext: $todayFocusIncludesUpNext)

                        Section
                        {

                            Toggle("Reduce supporting content", isOn: $usesReducedContent)
                            Toggle("Use larger primary controls", isOn: $usesLargeControls)
                            Toggle("Show navigation labels", isOn: $showsNavigationLabels)
                            ImportanceStarStylePicker(selection: $importanceStarStyle)
                            Toggle("Lower-left corner Back shortcut", isOn: $enablesLowerCornerBack)
                            .accessibilityHint(
                                                                                        "Enable an invisible Back target above the bottom toolbar in supported views")
                            Toggle("Scroll overflowing titles and subtitles", isOn: $scrollsOverflowingTitles)
                            .accessibilityHint("Allow manual horizontal reading in detail and title-bar headers")
                        }
                        header:
                        {

                            Text("Accessibility")
                        }
                        footer:
                        {

                            Text(
                                                                                    "Navigation labels appear beneath the Today, Week, New, Calendar, and Saved icons. Plenact also follows system Dynamic Type, VoiceOver, contrast, and Reduce Motion settings."
                            )
                        }


                        Section("Privacy & Data")
                        {

                            LabeledContent("Profile storage", value: "This device")
                            LabeledContent("Online account", value: "None")
                            LabeledContent("Network access", value: "Not used")

                            Text("Profile settings are separate from your Board, labels, and attachments.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }

                    }

                }

            }
            .background(Color(.systemGroupedBackground))

            .sheet(isPresented: $showsReviewRhythmSettings)
            {
                ReviewRhythmSettingsView()
            }
            .navigationTitle(profile == nil ? "Create Profile" : "Account & Settings")
            .sheet(isPresented: $showsShortcutEditor)
            {

                TodayShortcutEditor(
                    pins: TodayListPins.decode(listPinData),
                    owners: WorkspaceBrowseIndex.owners(
                        document: planningAccess?.document, library: planningAccess?.library ?? [])
                )
                {
                    pins in
                    listPinData = TodayListPins.encode(pins)
                }

            }
            .databaseActivityOverlay()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {

                if !isChoosingAvatarIcon
                {


                    ToolbarItem(placement: .cancellationAction)
                    {

                        Button("Cancel")
                        {

                            dismiss()
                        }

                    }


                    ToolbarItem(placement: .confirmationAction)
                    {

                        Button("Save", action: saveProfile)
                        .disabled(trimmedDisplayName.isEmpty)
                    }

                }

            }

            .confirmationDialog(
                                    "Remove local profile?",
                                    isPresented: $confirmsRemoval,
                                    titleVisibility: .visible
            )
            {

                Button("Remove profile", role: .destructive)
                {

                    onRemove()
                    ProfileAvatarPhotoStore.remove(profile?.avatarPhotoFileName)
                    dismiss()
                }


                Button("Cancel", role: .cancel)
                {

                }

            }
            message:
            {

                Text("Your Board, labels, and attachments will remain on this device.")
            }

        }

        .presentationDetents([.height(620), .large], selection: $profileSheetDetent)
        .presentationDragIndicator(.visible)
        .alert(
                        "Could not save avatar",
                        isPresented: Binding(
                            get:
                            {
                                photoSaveError != nil
                            },
                            set:
                            {
                                if !$0
                                {
                                    photoSaveError = nil
                                }

                            }
                        )
        )
        {

            Button("OK", role: .cancel)
            {
                photoSaveError = nil
            }

        }
        message:
        {

            Text(photoSaveError ?? "")
        }

    }

}


///
/// Presents planning settings independently of profile editing
///
/// @section    Purpose
///     Edits a local preference draft and publishes display and planning choices through the
///     established save flow.
///
struct PlanSettingsView: View
{


    @Environment(\.dismiss) private var dismiss
    @Environment(\.planningCalendarAccess) private var access
    @State private var preferences = PlanPreferencesStore.load()
    @State private var firstWeekday = 1
    @State private var loaded = false
    @State private var showsTemplates = false
    @State private var showsShortcuts = false
    @State private var showsReviewRhythmSettings = false
    @AppStorage(TodayListPins.key) private var pinData = Data()
    let lists:         [KanbanList]
    let onSaveProfile: (LocalProfile) -> Void

    var body: some View
    {

        NavigationStack
        {

            Form
            {

                TodayFocusSettingsSection(
                    count: $preferences.todayFocusItemCount, order: $preferences.todayFocusOrder,
                    groups: $preferences.todayFocusGroupsBySection,
                    hidesCompleted: $preferences.todayFocusHidesCompleted,
                    important: $preferences.todayFocusIncludesImportant,
                    bookmarked: $preferences.todayFocusIncludesBookmarked, upNext: $preferences.todayFocusIncludesUpNext
                )
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
                header:
                {

                    Text("Today")
                }
                footer:
                {

                    Text("Choose the fallback list for Today.")
                }

                Section
                {

                    Picker("Week starts on", selection: $firstWeekday)
                    {

                        Text("Sunday").tag(1)
                        Text("Monday").tag(2)
                    }

                    Toggle("Show due dates on new cards", isOn: $preferences.showsDueDatesOnNewCards)
                }
                header:
                {

                    Text("Planning")
                }
                footer:
                {

                    Text(
                                                            "Existing plans keep their dates. Due date visibility is a default for new cards and can be changed on each card."
                    )
                }

                Section("Planning rhythm")
                {

                    Button("Review invitations & reminders")
                    {
                        showsReviewRhythmSettings = true
                    }

                }

                NewCardColorDefaultsSection(
                    headers: $preferences.randomizesNewCardHeaders,
                    backgrounds: $preferences.randomizesNewCardBackgrounds)
                Section
                {

                    Button("My shortcuts", systemImage: "square.grid.3x2")
                    {
                        showsShortcuts = true
                    }

                    Button("Day & Week Templates", systemImage: "doc.on.doc")
                    {
                        showsTemplates = true
                    }

                }
                footer:
                {

                    Text(
                                                            "Shortcuts and templates have their own save controls. Choose the default for new weeks in Templates."
                    )
                }

                Section("Display")
                {

                    Toggle("Reduce supporting content", isOn: $preferences.usesReducedContent)
                    Toggle("Use larger primary controls", isOn: $preferences.usesLargeControls)
                    Toggle("Show navigation labels", isOn: $preferences.showsNavigationLabels)
                    ImportanceStarStylePicker(selection: $preferences.importanceStarStyle)
                    Toggle("Lower-left corner Back shortcut", isOn: $preferences.enablesLowerCornerBack)
                    .accessibilityHint(
                                                                "Enable an invisible Back target above the bottom toolbar in supported views")
                    Toggle("Scroll overflowing titles and subtitles", isOn: $preferences.scrollsOverflowingTitles)
                    .accessibilityHint("Allow manual horizontal reading in detail and title-bar headers")
                }

            }
            .navigationTitle("Plan Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {

                ToolbarItem(placement: .cancellationAction)
                {
                    Button("Cancel")
                    {
                        dismiss()
                    }

                }

                ToolbarItem(placement: .confirmationAction)
                {

                    Button("Save")
                    {

                        guard access?.setFirstWeekday(firstWeekday) != false else
                        {
                            return
                        }

                        PlanPreferencesStore.save(preferences)
                        if var profile = LocalProfileStore.load()
                        {

                            profile.preferences = preferences
                            onSaveProfile(profile)
                        }

                        dismiss()
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
            .sheet(isPresented: $showsReviewRhythmSettings)
            {
                ReviewRhythmSettingsView()
            }
            .sheet(isPresented: $showsTemplates)
            {
                PlanningTemplatesView()
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
        }
        .presentationDetents([.large])
    }

}


///
/// Edits creation-only Card color preferences
///
/// @section    Purpose
///     Binds independent random-header and random-background switches while explaining that
///     existing content and Notes retain their colors.
///
struct NewCardColorDefaultsSection: View
{


    @Binding var headers:     Bool
    @Binding var backgrounds: Bool
    var body:                 some View
    {

        Section
        {

            Toggle("Random header color", isOn: $headers)
            .accessibilityIdentifier("settings.newCards.randomHeader")
            Toggle("Random background color", isOn: $backgrounds)
            .accessibilityIdentifier("settings.newCards.randomBackground")
        }
        header:
        {

            Text("New Cards")
        }
        footer:
        {

            Text(
                                    "Give each new Card a saved color from a soft palette. The switches work independently. Existing items, Notes, and section dividers keep their colors. Change or reset an individual Card's colors in Appearance."
            )
        }

    }

}


///
/// Edits the user's Today Focus presentation and filters
///
/// @section    Purpose
///     Binds item count, ordering, section grouping, completion visibility, and selection sources
///     within the surrounding settings draft.
///
struct TodayFocusSettingsSection: View
{


    @Binding var count:          Int
    @Binding var order:          TodayFocusOrder
    @Binding var groups:         Bool
    @Binding var hidesCompleted: Bool
    @Binding var important:      Bool
    @Binding var bookmarked:     Bool
    @Binding var upNext:         Bool

    var body: some View
    {

        Section
        {

            Picker("Visible rows in Today's Focus", selection: $count)
            {

                ForEach(1 ... 12, id: \.self)
                {
                    Text("\($0)").tag($0)
                }

                Text("Expand all rows").tag(0)
            }

            Picker("Order", selection: $order)
            {

                ForEach(TodayFocusOrder.allCases, id: \.self)
                {
                    Text($0.title).tag($0)
                }

            }

            Toggle("Group by Day list sections", isOn: $groups)
            Toggle("Up Next", isOn: $upNext)
            Toggle("Cards marked important", isOn: $important)
            Toggle("Cards bookmarked", isOn: $bookmarked)
            Toggle("Hide completed items", isOn: $hidesCompleted)
        }
        header:
        {

            Text("Today's Focus")
        }
        footer:
        {

            Text(
                                    "Focus includes items matching any selected filter. Up Next shows current or upcoming schedules today and skips ended time slots. Important and Bookmarked can also include unscheduled items. With no filters enabled, all today’s items are eligible. Focus follows your Day list by default. Grouping uses your section headings; chronological order uses start dates, then due dates when no start is set, within each group. Undated items keep their relative order after dated items. These choices never rearrange your Day list. The row count controls how many items fit in the preview at once, not how many match. Scroll inside Focus to reach every additional match. Section headings do not count as items; progress always counts the whole day."
            )
        }

    }

}
