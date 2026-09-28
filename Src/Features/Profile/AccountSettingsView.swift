// -------------------------------------------------------------------------------------------------
// @file       AccountSettingsView.swift
// @brief      Local profile avatar and Account & Settings experience
// @details    Creates, edits, and removes local-only profile information and personalization
//
// @notes      This feature performs no authentication, credential storage, or network access
//
// -------------------------------------------------------------------------------------------------
import SwiftUI


// -------------------------------------- MARK: - Avatar Palette ------------------------------- //

extension ProfileAvatarColor {

    ///
    /// @fcn        ProfileAvatarColor.title
    /// @brief      Return the user-facing palette name
    /// @details    Keeps persisted palette tokens separate from display copy
    ///
    /// @return     (String) readable avatar-color title
    ///
    var title: String {   /* Palette title */
        switch self {
            case .teal:     "Teal"
            case .blue:     "Blue"
            case .green:    "Green"
            case .orange:   "Orange"
            case .graphite: "Graphite"
        }
    }

    ///
    /// @fcn        ProfileAvatarColor.color
    /// @brief      Resolve the palette token to its SwiftUI color
    /// @details    Keeps SwiftUI presentation outside the Codable profile model
    ///
    /// @return     (Color) avatar presentation color
    ///
    var color: Color {   /* Avatar color */
        switch self {
            case .teal:     Color.teal
            case .blue:     Color.blue
            case .green:    Color.green
            case .orange:   Color.orange
            case .graphite: Color.gray
        }
    }
}


// -------------------------------------- MARK: - Profile Avatar ------------------------------- //

///
/// Displays a discreet local profile identity or signed-out-style placeholder
///
/// @section    Purpose
///     Provide an obvious Account & Settings entry without exposing profile details on Today
///
struct ProfileAvatarView: View {

    let profile: LocalProfile?   /* Current local profile */
    let size:    CGFloat         /* Stable avatar size    */

    ///
    /// @fcn        ProfileAvatarView.body
    /// @brief      Build the local profile avatar
    /// @details    Shows initials for an existing profile and a person symbol before profile creation
    ///
    /// @return     (some View) circular profile identity
    ///
    var body: some View {

        ZStack {
            Circle()
                .fill(profile?.avatarColor.color ?? Color.secondary.opacity(0.16))

            if let profile {

                Text(profile.initials)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.white)

            } else {
                
                Image(systemName: "person.crop.circle")
                    .font(.system(size: size * 0.58))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
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
struct AccountSettingsView: View {

    let profile:  LocalProfile?                  /* Existing local profile */
    let lists:    [KanbanList]                   /* Default-list choices   */
    let onSave:   (LocalProfile) -> Void         /* Profile save callback  */
    let onRemove: () -> Void                     /* Profile removal        */

    @Environment(\.dismiss) private var dismiss  /* Sheet dismissal       */

    @State private var profileID:           UUID                     /* Draft profile ID       */
    @State private var createdAt:           Date                     /* Draft creation date    */
    @State private var displayName:         String                   /* Draft display name     */
    @State private var email:               String                   /* Draft local email      */
    @State private var context:             String                   /* Draft planning context */
    @State private var avatarColor:         ProfileAvatarColor       /* Draft avatar color     */
    @State private var defaultListID:       Int?                     /* Draft default list     */
    @State private var usesReducedContent:  Bool                     /* Draft content density  */
    @State private var usesLargeControls:   Bool                     /* Draft control sizing   */
    @State private var confirmsRemoval      = false                  /* Removal confirmation   */

    ///
    /// @fcn        AccountSettingsView.trimmedDisplayName
    /// @brief      Return the display-name draft without surrounding whitespace
    /// @details    Supplies profile validation and normalized saving
    ///
    /// @return     (String) normalized display name
    ///
    private var trimmedDisplayName: String {   /* Normalized name */
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    ///
    /// @fcn        AccountSettingsView.init(profile:lists:onSave:onRemove:)
    /// @brief      Initialize local profile drafts and callbacks
    /// @details    Seeds existing values or calm defaults for first profile creation
    ///
    /// @param[in]  profile   Existing local profile, when created
    /// @param[in]  lists     Current Board lists available as a default
    /// @param[in]  onSave    Callback receiving a complete profile snapshot
    /// @param[in]  onRemove  Callback removing only local profile data
    ///
    /// @return     (AccountSettingsView) configured local profile form
    ///
    init(
        profile:  LocalProfile?,
        lists:    [KanbanList],
        onSave:   @escaping (LocalProfile) -> Void,
        onRemove: @escaping ()             -> Void
    ) {

        let preferences = profile?.preferences ?? LocalProfilePreferences()   /* Initial settings */

        self.profile  = profile
        self.lists    = lists
        self.onSave   = onSave
        self.onRemove = onRemove

        _profileID          = State(initialValue: profile?.id          ?? UUID())
        _createdAt          = State(initialValue: profile?.createdAt   ?? .now)
        _displayName        = State(initialValue: profile?.displayName ?? "")
        _email              = State(initialValue: profile?.email       ?? "")
        _context            = State(initialValue: profile?.context     ?? "")
        _avatarColor        = State(initialValue: profile?.avatarColor ?? .teal)

        _defaultListID      = State(initialValue: lists.contains(where: { $0.id == preferences.defaultListID }) ? preferences.defaultListID : nil)
     
        _usesReducedContent = State(initialValue: preferences.usesReducedContent)
        _usesLargeControls  = State(initialValue: preferences.usesLargeControls)
    }

    ///
    /// @fcn        AccountSettingsView.saveProfile
    /// @brief      Save normalized local identity and personalization
    /// @details    Preserves profile identity and creation date across edits
    ///
    /// @return     (Void) invokes the save callback and dismisses the sheet
    ///
    private func saveProfile() {

        let updatedProfile = LocalProfile(   /* Completed profile */
            id:          profileID,
            createdAt:   createdAt,
            displayName: trimmedDisplayName,
            email:       email.trimmingCharacters(in:   .whitespacesAndNewlines),
            context:     context.trimmingCharacters(in: .whitespacesAndNewlines),
            avatarColor: avatarColor,
            preferences: LocalProfilePreferences(
                defaultListID:      defaultListID,
                usesReducedContent: usesReducedContent,
                usesLargeControls:  usesLargeControls
            )
        )

        onSave(updatedProfile)
        dismiss()
    }

    ///
    /// @fcn        AccountSettingsView.body
    /// @brief      Build the local Account & Settings form
    /// @details    Separates profile, planning, accessibility, privacy, and removal controls
    ///
    /// @return     (some View) local profile creation or editing sheet
    ///
    var body: some View {

        NavigationStack {

            Form {

                Section("Profile") {

                    HStack(spacing: 14) {

                        ProfileAvatarView(
                            profile: LocalProfile(
                                id:          profileID,
                                createdAt:   createdAt,
                                displayName: trimmedDisplayName,
                                avatarColor: avatarColor
                            ),
                            size: 52
                        )

                        VStack(alignment: .leading, spacing: 2) {

                            Text(trimmedDisplayName.isEmpty ? "Local profile" : trimmedDisplayName)
                                .font(.headline)

                            Text("Stored on this device")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    TextField("Display name", text: $displayName)
                        .textContentType(.name)

                    TextField("Email (optional)", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)

                    TextField("Planning context (optional)", text: $context)

                    Picker("Avatar color", selection: $avatarColor) {

                        ForEach(ProfileAvatarColor.allCases) { color in

                            Label(color.title, systemImage: "circle.fill")
                                .foregroundStyle(color.color)
                                .tag(color)
                        }
                    }
                }

                Section {

                    Picker("Default Today list", selection: $defaultListID) {

                        Text("Choose each day").tag(nil as Int?)

                        ForEach(lists) { list in
                            Text(list.title).tag(Optional(list.id))
                        }
                    }
                } header: {
                    Text("Planning")

                } footer: {
                    Text("The default is used only when no list has been chosen for that date.")
                }

                Section {
                    Toggle("Reduce supporting content", isOn: $usesReducedContent)
                    Toggle("Use larger primary controls", isOn: $usesLargeControls)

                } header: {
                    Text("Accessibility")

                } footer: {
                    Text("Plenact also follows system Dynamic Type, VoiceOver, contrast, and Reduce Motion settings.")
                }

                Section("Privacy & Data") {
                    LabeledContent("Profile storage", value: "This device")
                    LabeledContent("Online account", value: "None")
                    LabeledContent("Network access", value: "Not used")

                    Text("Profile settings are separate from your Board, labels, and attachments.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let profile {

                    Section {

                        LabeledContent("Created", value: profile.createdAt.formatted(date: .abbreviated, time: .omitted))

                        Button("Remove local profile", role: .destructive) {
                            confirmsRemoval = true
                        }

                    } header: {
                        Text("Local Profile")
                    } footer: {
                        Text("Removing this profile keeps all Board cards, labels, and attachments.")
                    }
                }
            }
            .navigationTitle(profile == nil ? "Create Profile" : "Account & Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {

                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {

                    Button("Save", action: saveProfile)
                        .disabled(trimmedDisplayName.isEmpty)
                }
            }
            .confirmationDialog(
                "Remove local profile?",
                isPresented: $confirmsRemoval,
                titleVisibility: .visible
            ) {
                Button("Remove profile", role: .destructive) {
                    onRemove()
                    dismiss()
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your Board, labels, and attachments will remain on this device.")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}