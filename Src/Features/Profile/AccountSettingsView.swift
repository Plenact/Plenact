// -------------------------------------------------------------------------------------------------
// @file       AccountSettingsView.swift
// @brief      Local profile avatar and Account & Settings experience
// @details    Creates, edits, and removes local-only profile information and personalization
//
// @notes      This feature performs no authentication, credential storage, or network access
//
// -------------------------------------------------------------------------------------------------
import SwiftUI
import PhotosUI
import UIKit
import ImageIO


// -------------------------------------- MARK: - Avatar Palette ------------------------------- //

extension ProfileColor {

    ///
    /// @fcn        ProfileAvatarColor.color
    /// @brief      Resolve the palette token to its SwiftUI color
    /// @details    Keeps SwiftUI presentation outside the Codable profile model
    ///
    /// @return     (Color) avatar presentation color
    ///
    var color: Color {   /* Avatar color */
        switch legacyToken {
            case "teal":     Color.teal
            case "blue":     Color.blue
            case "green":    Color.green
            case "orange":   Color.orange
            case "graphite": Color.gray
            default:          Color(red: red, green: green, blue: blue)
        }
    }

    var hexString: String {
        String(
            format: "#%02X%02X%02X",
            Int(min(max(red, 0), 1) * 255),
            Int(min(max(green, 0), 1) * 255),
            Int(min(max(blue, 0), 1) * 255)
        )
    }
}

extension ProfileAvatarIcon {

    var title: String {
        switch self {
            case .initials:     "Initials"
            case .person:       "Person"
            case .personCircle: "Portrait"
            case .smilingFace:  "Smile"
            case .leaf:         "Leaf"
            case .sun:          "Sun"
            case .moon:         "Moon"
            case .sparkles:     "Sparkles"
            case .bolt:         "Bolt"
            case .heart:        "Heart"
            case .star:         "Star"
            case .cloud:        "Cloud"
        }
    }

    var symbolName: String? {
        switch self {
            case .initials:     nil
            case .person:       "person.fill"
            case .personCircle: "person.crop.circle.fill"
            case .smilingFace:  "face.smiling"
            case .leaf:         "leaf.fill"
            case .sun:          "sun.max.fill"
            case .moon:         "moon.stars.fill"
            case .sparkles:     "sparkles"
            case .bolt:         "bolt.fill"
            case .heart:        "heart.fill"
            case .star:         "star.fill"
            case .cloud:        "cloud.sun.fill"
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
    var photoData: Data? = nil

    ///
    /// @fcn        ProfileAvatarView.body
    /// @brief      Build the local profile avatar
    /// @details    Shows the selected symbol or initials for an existing profile
    ///
    /// @return     (some View) circular profile identity
    ///
    var body: some View { /* Circular local-profile avatar */

        ZStack {
            Circle()
                .fill(profile?.avatarColor.color ?? Color.secondary.opacity(0.16))

            if let profile {
                if let symbolName = profile.avatarIcon.symbolName {
                    Image(systemName: symbolName)
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(profile.avatarForegroundColor.color)
                } else {
                    Text(profile.initials)
                        .font(.system(size: size * 0.36, weight: .semibold))
                        .foregroundStyle(profile.avatarForegroundColor.color)
                }
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: size * 0.58))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if let data = photoData ?? ProfileAvatarPhotoStore.load(profile?.avatarPhotoFileName),
               let image = UIImage(data: data) {
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
struct AccountSettingsView: View {

    let profile:  LocalProfile?                  /* Existing local profile */
    let lists:    [KanbanList]                   /* Default-list choices   */
    let onSave:   (LocalProfile) -> Void         /* Profile save callback  */
    let onRemove: () -> Void                     /* Profile removal        */
    let onLoadExample: () -> Bool
    let onUndoExampleLoad: () -> Bool

    @Environment(\.dismiss) private var dismiss  /* Sheet dismissal       */

    @State private var profileID:           UUID                     /* Draft profile ID       */
    @State private var createdAt:           Date                     /* Draft creation date    */
    @State private var displayName:         String                   /* Draft display name     */
    @State private var email:               String                   /* Draft local email      */
    @State private var context:             String                   /* Draft planning context */
    @State private var avatarColor:         ProfileAvatarColor       /* Draft avatar color     */
    @State private var avatarIcon:          ProfileAvatarIcon        /* Draft avatar icon      */
    @State private var avatarForegroundColor: ProfileAvatarForegroundColor /* Draft icon color */
    @State private var defaultListID:       Int?                     /* Draft default list     */
    @State private var usesReducedContent:  Bool                     /* Draft content density  */
    @State private var usesLargeControls:   Bool                     /* Draft control sizing   */
    @State private var showsNavigationLabels: Bool                   /* Draft navigation captions */
    @State private var confirmsRemoval      = false                  /* Removal confirmation   */
    @State private var confirmsLoadExample  = false
    @State private var confirmsUndoExample = false
    @State private var hasUndoableExample = false
    @State private var exampleOperationError: String?
    @State private var isChoosingAvatarIcon = false
    @State private var profileSheetDetent: PresentationDetent = .large
    @State private var avatarPhotoData:    Data?
    @State private var photoSaveError:     String?

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
        onRemove: @escaping ()             -> Void,
        onLoadExample: @escaping ()         -> Bool,
        onUndoExampleLoad: @escaping ()     -> Bool
    ) {

        let preferences = profile?.preferences ?? LocalProfilePreferences()   /* Initial settings */

        self.profile  = profile
        self.lists    = lists
        self.onSave   = onSave
        self.onRemove = onRemove
        self.onLoadExample = onLoadExample
        self.onUndoExampleLoad = onUndoExampleLoad

        _profileID          = State(initialValue: profile?.id          ?? UUID())
        _createdAt          = State(initialValue: profile?.createdAt   ?? .now)
        _displayName        = State(initialValue: profile?.displayName ?? "")
        _email              = State(initialValue: profile?.email       ?? "")
        _context            = State(initialValue: profile?.context     ?? "")
        _avatarColor        = State(initialValue: profile?.avatarColor ?? .teal)
        _avatarIcon         = State(initialValue: profile?.avatarIcon  ?? .initials)
        _avatarForegroundColor = State(initialValue: profile?.avatarForegroundColor ?? .white)
        _avatarPhotoData = State(initialValue: ProfileAvatarPhotoStore.load(profile?.avatarPhotoFileName))
        _hasUndoableExample = State(initialValue: ExampleLoadUndoStore.load() != nil)

        _defaultListID      = State(initialValue: lists.contains(where: { $0.id == preferences.defaultListID }) ? preferences.defaultListID : nil)
     
        _usesReducedContent = State(initialValue: preferences.usesReducedContent)
        _usesLargeControls  = State(initialValue: preferences.usesLargeControls)
        _showsNavigationLabels = State(initialValue: preferences.showsNavigationLabels)
    }

    ///
    /// @fcn        AccountSettingsView.saveProfile
    /// @brief      Save normalized local identity and personalization
    /// @details    Preserves profile identity and creation date across edits
    ///
    /// @return     (Void) invokes the save callback and dismisses the sheet
    ///
    private func saveProfile() {

        let photoFileName: String?
        do {
            if let avatarPhotoData {
                photoFileName = try ProfileAvatarPhotoStore.save(avatarPhotoData)
            } else {
                photoFileName = nil
            }
        } catch {
            photoSaveError = error.localizedDescription
            return
        }

        let updatedProfile = LocalProfile(   /* Completed profile */
            id:          profileID,
            createdAt:   createdAt,
            displayName: trimmedDisplayName,
            email:       email.trimmingCharacters(in:   .whitespacesAndNewlines),
            context:     context.trimmingCharacters(in: .whitespacesAndNewlines),
            avatarColor: avatarColor,
            avatarIcon:  avatarIcon,
            avatarForegroundColor: avatarForegroundColor,
            avatarPhotoFileName: photoFileName,
            preferences: LocalProfilePreferences(
                defaultListID:      defaultListID,
                usesReducedContent: usesReducedContent,
                usesLargeControls:  usesLargeControls,
                showsNavigationLabels: showsNavigationLabels
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
    var body: some View { /* Local profile form and shared-demo controls */

        NavigationStack {

            TabView {
                Form {
                    Section("Profile") {
                        NavigationLink {
                            ProfileAvatarIconPicker(
                                selection: $avatarIcon,
                                avatarColor: $avatarColor,
                                foregroundColor: $avatarForegroundColor,
                                photoData: $avatarPhotoData,
                                displayName: trimmedDisplayName
                            )
                            .onAppear {
                                isChoosingAvatarIcon = true
                                profileSheetDetent = .height(620)
                            }
                            .onDisappear {
                                isChoosingAvatarIcon = false
                                profileSheetDetent = .large
                            }
                        } label: {
                            HStack(spacing: 14) {
                                ProfileAvatarView(
                                    profile: LocalProfile(
                                        id:          profileID,
                                        createdAt:   createdAt,
                                        displayName: trimmedDisplayName,
                                        avatarColor: avatarColor,
                                        avatarIcon:  avatarIcon,
                                        avatarForegroundColor: avatarForegroundColor
                                    ),
                                    size: 52,
                                    photoData: avatarPhotoData
                                )

                                VStack(alignment: .leading, spacing: 2) {
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

                        TextField("Display name", text: $displayName)
                            .textContentType(.name)

                        TextField("Email (optional)", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)

                        TextField("Planning context (optional)", text: $context)

                    }

                    Section {
                        Button {
                            confirmsLoadExample = true
                        } label: {
                            Label("Load Example", systemImage: "square.and.arrow.down")
                        }
                        if hasUndoableExample {
                            Button("Undo Last Load", systemImage: "arrow.uturn.backward", role: .destructive) {
                                confirmsUndoExample = true
                            }
                        }
                    } footer: {
                        Text(hasUndoableExample
                             ? "Your previous board is saved on this device and can be restored with Undo Last Load."
                             : "Load Plenact's example board on this device. This replaces your current lists and cards.")
                    }
                    .alert("Could not update board", isPresented: Binding(
                        get: { exampleOperationError != nil },
                        set: { if !$0 { exampleOperationError = nil } }
                    )) {
                        Button("OK", role: .cancel) { exampleOperationError = nil }
                    } message: {
                        Text(exampleOperationError ?? "")
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
                .tabItem {
                    Label("Account", systemImage: "person.crop.circle")
                }

                Form {
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
                        Toggle("Show navigation labels", isOn: $showsNavigationLabels)
                    } header: {
                        Text("Accessibility")
                    } footer: {
                        Text("Navigation labels appear beneath the Today, Week, New, Calendar, and Saved icons. Plenact also follows system Dynamic Type, VoiceOver, contrast, and Reduce Motion settings.")
                    }

                    Section("Privacy & Data") {
                        LabeledContent("Profile storage", value: "This device")
                        LabeledContent("Online account", value: "None")
                        LabeledContent("Network access", value: "Not used")

                        Text("Profile settings are separate from your Board, labels, and attachments.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .navigationTitle(profile == nil ? "Create Profile" : "Account & Settings")
            .databaseActivityOverlay()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isChoosingAvatarIcon {
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
            }
            .confirmationDialog(
                "Remove local profile?",
                isPresented: $confirmsRemoval,
                titleVisibility: .visible
            ) {
                Button("Remove profile", role: .destructive) {
                    onRemove()
                    ProfileAvatarPhotoStore.remove(profile?.avatarPhotoFileName)
                    dismiss()
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your Board, labels, and attachments will remain on this device.")
            }
            .confirmationDialog(
                "Replace this board with the example?",
                isPresented: $confirmsLoadExample,
                titleVisibility: .visible
            ) {
                Button("Load Example", role: .destructive) {
                    if onLoadExample() {
                        hasUndoableExample = true
                    } else {
                        exampleOperationError = "A backup could not be saved, so the example was not loaded."
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your current lists and cards on this device will be replaced. No data will be uploaded.")
            }
            .confirmationDialog(
                "Restore the board from before the example was loaded?",
                isPresented: $confirmsUndoExample,
                titleVisibility: .visible
            ) {
                Button("Undo Load Example", role: .destructive) {
                    if onUndoExampleLoad() {
                        hasUndoableExample = false
                    } else {
                        exampleOperationError = "The saved board snapshot could not be restored."
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This replaces the current board with the saved lists and cards from before Load Example.")
            }
        }
        .presentationDetents([.height(620), .large], selection: $profileSheetDetent)
        .presentationDragIndicator(.visible)
        .alert("Could not save avatar", isPresented: Binding(
            get: { photoSaveError != nil },
            set: { if !$0 { photoSaveError = nil } }
        )) {
            Button("OK", role: .cancel) { photoSaveError = nil }
        } message: {
            Text(photoSaveError ?? "")
        }
    }
}


private struct ProfileAvatarIconPicker: View {

    @Binding var selection: ProfileAvatarIcon
    @Binding var avatarColor: ProfileAvatarColor
    @Binding var foregroundColor: ProfileAvatarForegroundColor
    @Binding var photoData: Data?
    let displayName: String

    @Environment(\.dismiss) private var dismiss
    @State private var draftIcon: ProfileAvatarIcon
    @State private var draftAvatarColor: ProfileAvatarColor
    @State private var draftForegroundColor: ProfileAvatarForegroundColor
    @State private var isEditingColorMap = false
    @State private var draftPhotoData: Data?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var cropImage: AvatarCropImage?
    @State private var isLoadingPhoto = false
    @State private var photoError: String?

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 12)]

    init(
        selection: Binding<ProfileAvatarIcon>,
        avatarColor: Binding<ProfileAvatarColor>,
        foregroundColor: Binding<ProfileAvatarForegroundColor>,
        photoData: Binding<Data?>,
        displayName: String
    ) {
        _selection = selection
        _avatarColor = avatarColor
        _foregroundColor = foregroundColor
        _photoData = photoData
        self.displayName = displayName
        _draftIcon = State(initialValue: selection.wrappedValue)
        _draftAvatarColor = State(initialValue: avatarColor.wrappedValue)
        _draftForegroundColor = State(initialValue: foregroundColor.wrappedValue)
        _draftPhotoData = State(initialValue: photoData.wrappedValue)
    }

    private var initials: String {
        LocalProfile(displayName: displayName).initials
    }

    private func saveSelection() {
        selection = draftIcon
        avatarColor = draftAvatarColor
        foregroundColor = draftForegroundColor
        photoData = draftPhotoData
        dismiss()
    }

    private var previewHeader: some View {
        HStack(spacing: 14) {
            ProfileAvatarView(
                profile: LocalProfile(
                    displayName: displayName, avatarColor: draftAvatarColor,
                    avatarIcon: draftIcon, avatarForegroundColor: draftForegroundColor
                ),
                size: 60,
                photoData: draftPhotoData
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName.isEmpty ? "Local profile" : displayName)
                    .font(.headline)
                Text("Preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var colorControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                ProfileColorMapPicker(
                    title: "Avatar color",
                    selection: $draftAvatarColor,
                    defaultColor: .teal,
                    presets: [
                        .init(name: "Teal", color: .teal),
                        .init(name: "Blue", color: .blue),
                        .init(name: "Green", color: .green),
                        .init(name: "Orange", color: .orange),
                        .init(name: "Graphite", color: .graphite)
                    ]
                )
                    .onAppear { isEditingColorMap = true }
                    .onDisappear { isEditingColorMap = false }
            } label: {
                colorSettingRow("Avatar color", color: draftAvatarColor)
            }
            .buttonStyle(.plain)

            NavigationLink {
                ProfileColorMapPicker(
                    title: "Icon and initials",
                    selection: $draftForegroundColor,
                    defaultColor: .white,
                    presets: [
                        .init(name: "White", color: .white),
                        .init(name: "Charcoal", color: .charcoal),
                        .init(name: "Lemon", color: .lemon),
                        .init(name: "Sky", color: .sky),
                        .init(name: "Coral", color: .coral)
                    ]
                )
                    .onAppear { isEditingColorMap = true }
                    .onDisappear { isEditingColorMap = false }
            } label: {
                colorSettingRow("Icon and initials", color: draftForegroundColor)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private var iconGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose an icon")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ProfileAvatarIcon.allCases) { icon in
                    Button {
                        draftIcon = icon
                        draftPhotoData = nil
                    } label: {
                        VStack(spacing: 6) {
                            avatarPreview(icon: icon, background: draftAvatarColor, foreground: draftForegroundColor, size: 42)

                            Text(icon.title)
                                .font(.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 68)
                        .background(
                            draftIcon == icon ? Color.accentColor.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    draftIcon == icon ? Color.accentColor : Color.secondary.opacity(0.22),
                                    lineWidth: draftIcon == icon ? 2 : 1
                                )
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(icon.title)
                    .accessibilityValue(draftIcon == icon ? "Selected" : "")
                    .accessibilityHint("Select this profile icon.")
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
    }

    var body: some View {
        VStack(spacing: 0) {
            previewHeader

            ScrollView {
                VStack(spacing: 10) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(draftPhotoData == nil ? "Choose Photo" : "Replace Photo", systemImage: "photo")
                    }
                    .disabled(isLoadingPhoto)
                    if isLoadingPhoto { ProgressView() }
                    if draftPhotoData != nil {
                        Button("Remove Photo", role: .destructive) { draftPhotoData = nil }
                    } else {
                        colorControls
                    }
                }
                .padding(.top, 12)
            }
            .frame(maxHeight: .infinity)

            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)

            iconGrid
        }
        .navigationTitle("Choose Icon")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { return }
            isLoadingPhoto = true
            defer { isLoadingPhoto = false }
            do {
                guard let data = try await selectedPhoto.loadTransferable(type: Data.self),
                      let image = AvatarPhotoCrop.image(from: data) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                guard !Task.isCancelled else { return }
                cropImage = AvatarCropImage(image: image)
            } catch {
                if !Task.isCancelled { photoError = error.localizedDescription }
            }
        }
        .sheet(item: $cropImage, onDismiss: { selectedPhoto = nil }) { crop in
            AvatarPhotoCropView(image: crop.image) { data in
                draftPhotoData = data
            }
        }
        .alert("Could not load photo", isPresented: Binding(
            get: { photoError != nil },
            set: { if !$0 { photoError = nil; selectedPhoto = nil } }
        )) {
            Button("OK", role: .cancel) { photoError = nil; selectedPhoto = nil }
        } message: {
            Text(photoError ?? "")
        }
        .toolbar {
            if !isEditingColorMap {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: saveSelection)
                }
            }
        }
    }

    private func colorSettingRow(_ title: String, color: ProfileColor) -> some View {
        HStack(spacing: 10) {
            Text(title)
            Spacer()
            Circle()
                .fill(color.color)
                .frame(width: 20, height: 20)
                .overlay {
                    Circle()
                        .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
                }
            Text(color.hexString)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }

    private func avatarPreview(
        icon: ProfileAvatarIcon,
        background: ProfileAvatarColor,
        foreground: ProfileAvatarForegroundColor,
        size: CGFloat
    ) -> some View {
        ZStack {
            Circle()
                .fill(background.color)
                .frame(width: size, height: size)

            if let symbolName = icon.symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(foreground.color)
            } else {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(foreground.color)
            }
        }
        .accessibilityHidden(true)
    }
}


private struct AvatarCropImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

enum AvatarPhotoCrop {

    static func image(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail)
    }

    static func constrainedOffset(_ offset: CGSize, imageSize: CGSize, side: CGFloat, zoom: CGFloat) -> CGSize {
        let scale = max(side / imageSize.width, side / imageSize.height) * zoom
        let horizontalLimit = max(0, (imageSize.width * scale - side) / 2)
        let verticalLimit = max(0, (imageSize.height * scale - side) / 2)
        return CGSize(
            width: min(max(offset.width, -horizontalLimit), horizontalLimit),
            height: min(max(offset.height, -verticalLimit), verticalLimit)
        )
    }

    static func jpeg(image: UIImage, side: CGFloat, zoom: CGFloat, offset: CGSize) -> Data? {
        guard side > 0, image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = max(side / image.size.width, side / image.size.height) * zoom
        let offset = constrainedOffset(offset, imageSize: image.size, side: side, zoom: zoom)
        let outputScale = 512 / side
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(
                x: ((side - image.size.width * scale) / 2 + offset.width) * outputScale,
                y: ((side - image.size.height * scale) / 2 + offset.height) * outputScale,
                width: image.size.width * scale * outputScale,
                height: image.size.height * scale * outputScale
            ))
        }.jpegData(compressionQuality: 0.9)
    }
}

private struct AvatarPhotoCropView: View {

    let image: UIImage
    let onUsePhoto: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var cropSide: CGFloat = 1
    @GestureState private var drag: CGSize = .zero
    @GestureState private var magnification: CGFloat = 1
    @State private var cropFailed = false

    private func stage(side: CGFloat) -> some View {
        let currentZoom = min(max(zoom * magnification, 1), 6)
        let currentOffset = AvatarPhotoCrop.constrainedOffset(
            CGSize(width: offset.width + drag.width, height: offset.height + drag.height),
            imageSize: image.size, side: side, zoom: currentZoom
        )
        let scale = max(side / image.size.width, side / image.size.height) * currentZoom

        return ZStack {
            Image(uiImage: image)
                .resizable()
                .frame(width: image.size.width * scale, height: image.size.height * scale)
                .offset(currentOffset)

            Path { path in
                path.addRect(CGRect(x: 0, y: 0, width: side, height: side))
                path.addEllipse(in: CGRect(x: 0, y: 0, width: side, height: side))
            }
            .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            Circle()
                .strokeBorder(.white, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .frame(width: side, height: side)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .updating($drag) { value, state, _ in state = value.translation }
                .onEnded { value in
                    offset = AvatarPhotoCrop.constrainedOffset(
                        CGSize(width: offset.width + value.translation.width, height: offset.height + value.translation.height),
                        imageSize: image.size, side: side, zoom: zoom
                    )
                }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .updating($magnification) { value, state, _ in state = value }
                .onEnded { value in
                    zoom = min(max(zoom * value, 1), 6)
                    offset = AvatarPhotoCrop.constrainedOffset(offset, imageSize: image.size, side: side, zoom: zoom)
                }
        )
        .accessibilityLabel("Avatar photo crop")
        .onAppear { cropSide = side }
        .onChange(of: side) { oldSide, newSide in
            offset = CGSize(width: offset.width * newSide / oldSide, height: offset.height * newSide / oldSide)
            cropSide = newSide
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let side = max(1, min(geometry.size.width - 32, geometry.size.height - 160, 360))
                VStack(spacing: 16) {
                    stage(side: side)

                    HStack {
                        Image(systemName: "minus.magnifyingglass")
                        Slider(value: $zoom, in: 1...6)
                            .accessibilityLabel("Photo zoom")
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .frame(maxWidth: 360)

                    HStack(spacing: 20) {
                        Button { offset.width -= side / 10 } label: { Image(systemName: "arrow.left") }
                            .accessibilityLabel("Move photo left")
                        Button { offset.height -= side / 10 } label: { Image(systemName: "arrow.up") }
                            .accessibilityLabel("Move photo up")
                        Button { offset.height += side / 10 } label: { Image(systemName: "arrow.down") }
                            .accessibilityLabel("Move photo down")
                        Button { offset.width += side / 10 } label: { Image(systemName: "arrow.right") }
                            .accessibilityLabel("Move photo right")
                        Button("Reset") { zoom = 1; offset = .zero }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle("Crop Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Use Photo") {
                        if let data = AvatarPhotoCrop.jpeg(image: image, side: cropSide, zoom: zoom, offset: offset) {
                            onUsePhoto(data)
                            dismiss()
                        } else {
                            cropFailed = true
                        }
                    }
                }
            }
            .alert("Could not crop photo", isPresented: $cropFailed) {
                Button("OK", role: .cancel) {}
            }
        }
        .presentationDetents([.large])
    }
}

private struct ProfileColorPreset: Identifiable {

    let name: String
    let color: ProfileColor

    var id: String { name }
}


private struct ProfileColorMapPicker: View {

    let title: String
    let defaultColor: ProfileColor
    let presets: [ProfileColorPreset]
    @Binding var selection: ProfileColor
    private let initialColor: ProfileColor

    @Environment(\.dismiss) private var dismiss
    @State private var hue: Double
    @State private var saturation: Double
    @State private var brightness: Double
    @State private var isEditingRGB = false

    init(
        title: String,
        selection: Binding<ProfileColor>,
        defaultColor: ProfileColor,
        presets: [ProfileColorPreset]
    ) {
        self.title = title
        self.defaultColor = defaultColor
        self.presets = presets
        _selection = selection
        initialColor = selection.wrappedValue
        let components = selection.wrappedValue.hueSaturationBrightness
        _hue = State(initialValue: components.hue)
        _saturation = State(initialValue: components.saturation)
        _brightness = State(initialValue: components.brightness)
    }

    private var selectedColor: ProfileColor {
        ProfileColor(hue: hue, saturation: saturation, brightness: brightness)
    }

    private func saveSelection() {
        selection = selectedColor
        dismiss()
    }

    private func resetColor() {
        setColor(initialColor)
    }

    private func useDefaultColor() {
        setColor(defaultColor)
    }

    private func setColor(_ color: ProfileColor) {
        let components = color.hueSaturationBrightness
        hue = components.hue
        saturation = components.saturation
        brightness = components.brightness
    }

    private var hexEditorLink: some View {
        NavigationLink {
            ProfileRGBColorEditor(color: selectedColor) { updatedColor in
                setColor(updatedColor)
            }
            .onAppear { isEditingRGB = true }
            .onDisappear { isEditingRGB = false }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(selectedColor.color)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(selectedColor.hexString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tint)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            hexEditorLink

            ProfileColorMapSurface(hue: $hue, saturation: $saturation, brightness: brightness)
                .frame(height: 240)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(presets) { preset in
                        Button {
                            setColor(preset.color)
                        } label: {
                            VStack(spacing: 5) {
                                Circle()
                                    .fill(preset.color.color)
                                    .frame(width: 26, height: 26)
                                    .overlay {
                                        Circle()
                                            .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
                                    }

                                Text(preset.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            .frame(width: 56, height: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(preset.name) preset")
                    }
                }
                .padding(.vertical, 2)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Brightness")
                    Spacer()
                    Text("\(Int((brightness * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $brightness, in: 0...1)
                    .tint(selectedColor.color)
            }

            HStack {
                Button("Reset", action: resetColor)
                Spacer()
                Button("Default", action: useDefaultColor)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if !isEditingRGB {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: saveSelection)
                }
            }
        }
    }
}


private struct ProfileRGBColorEditor: View {

    let onSave: (ProfileColor) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var red: Double
    @State private var green: Double
    @State private var blue: Double

    init(color: ProfileColor, onSave: @escaping (ProfileColor) -> Void) {
        self.onSave = onSave
        _red = State(initialValue: color.red * 255)
        _green = State(initialValue: color.green * 255)
        _blue = State(initialValue: color.blue * 255)
    }

    private var editedColor: ProfileColor {
        ProfileColor(red: red / 255, green: green / 255, blue: blue / 255)
    }

    private func saveColor() {
        onSave(editedColor)
        dismiss()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Circle()
                    .fill(editedColor.color)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text("RGB color")
                        .font(.headline)
                    Text(editedColor.hexString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            RGBChannelControl(title: "Red", value: $red)
            RGBChannelControl(title: "Green", value: $green)
            RGBChannelControl(title: "Blue", value: $blue)

            Spacer(minLength: 0)
        }
        .padding()
        .navigationTitle("RGB Values")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: saveColor)
            }
        }
    }
}


private struct RGBChannelControl: View {

    let title: String
    @Binding var value: Double

    @State private var hexValue: String
    @FocusState private var isEditingHex: Bool

    init(title: String, value: Binding<Double>) {
        self.title = title
        _value = value
        _hexValue = State(initialValue: Self.hexString(value.wrappedValue))
    }

    private static func hexString(_ value: Double) -> String {
        String(format: "%02X", Int(value.rounded()))
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(width: 48, alignment: .leading)

            Slider(value: $value, in: 0...255, step: 1)

            TextField("00", text: $hexValue)
                .frame(width: 54)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .focused($isEditingHex)
                .onChange(of: value) { _, newValue in
                    if !isEditingHex {
                        hexValue = Self.hexString(newValue)
                    }
                }
                .onChange(of: hexValue) { _, newValue in
                    let validCharacters = Set("0123456789ABCDEF")
                    let normalized = String(newValue.uppercased().filter { validCharacters.contains($0) }.prefix(2))
                    if normalized != newValue {
                        hexValue = normalized
                    }
                    value = normalized.isEmpty ? 0 : Double(UInt8(normalized, radix: 16) ?? 0)
                }
                .onChange(of: isEditingHex) { _, isEditing in
                    if !isEditing {
                        hexValue = Self.hexString(value)
                    }
                }
        }
    }
}


private struct ProfileColorMapSurface: View {

    @Binding var hue: Double
    @Binding var saturation: Double
    let brightness: Double

    private var spectrum: [Color] {
        [
            Color(hue: 0, saturation: 1, brightness: 1, opacity: 1),
            Color(hue: 1.0 / 6, saturation: 1, brightness: 1, opacity: 1),
            Color(hue: 2.0 / 6, saturation: 1, brightness: 1, opacity: 1),
            Color(hue: 3.0 / 6, saturation: 1, brightness: 1, opacity: 1),
            Color(hue: 4.0 / 6, saturation: 1, brightness: 1, opacity: 1),
            Color(hue: 5.0 / 6, saturation: 1, brightness: 1, opacity: 1),
            Color(hue: 1, saturation: 1, brightness: 1, opacity: 1)
        ]
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let height = max(geometry.size.height, 1)

            ZStack {
                LinearGradient(colors: spectrum, startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom)
                Color.black.opacity(1 - brightness)

                Circle()
                    .fill(Color(hue: hue, saturation: saturation, brightness: brightness, opacity: 1))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Circle()
                            .strokeBorder(.white, lineWidth: 3)
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(.black.opacity(0.75), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.25), radius: 2)
                    .position(
                        x: min(max(hue * width, 15), width - 15),
                        y: min(max((1 - saturation) * height, 15), height - 15)
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        hue = min(max(value.location.x / width, 0), 1)
                        saturation = 1 - min(max(value.location.y / height, 0), 1)
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Hue and saturation color map")
            .accessibilityValue("Hue \(Int(hue * 360)) degrees, saturation \(Int(saturation * 100)) percent")
            .accessibilityAdjustableAction { direction in
                switch direction {
                    case .increment: hue = min(hue + 0.02, 1)
                    case .decrement: hue = max(hue - 0.02, 0)
                    @unknown default: break
                }
            }
        }
        .frame(height: 240)
    }
}