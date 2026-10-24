// --------------------------------------------------------------------------------------------------
// @file       AppearanceEditors.swift
// @brief      Draft appearance and List surface controls
// @details    Edits colors, icons, backgrounds, preview choices, and inline capture styling
//             through owner-accepted saves.
//
// --------------------------------------------------------------------------------------------------
import AVKit
import Foundation
import ImageIO
import PencilKit
import PhotosUI
import SwiftUI
import UIKit


///
/// Edits appearance overrides in a checked draft
///
/// @section    Purpose
///     Coordinates icon, banner, List background, capture colors, and optional display format; a
///     rejected save keeps the editor open.
///
struct ItemAppearanceSheet: View
{


    let title:                       String
    let onSave:                      (ItemAppearance?) -> Bool
    let onOpenCover:                 (() -> Void)?
    let onOpenLayout:                (() -> Void)?
    let showsListBackground:         Bool
    let inheritedAddItemTextColor:   Color?
    let onSaveDisplay:               ((ItemAppearance?, ItemDisplayFormat) -> Bool)?
    @State private var draftDisplay: ItemDisplayFormat?
    @State private var draft:        ItemAppearance
    @Environment(\.dismiss) private var dismiss


    ///
    /// @fcn        ItemAppearanceSheet.init
    /// @brief      Initialize editable appearance and optional display controls
    /// @details    Seeds local draft state from the supplied appearance and display format and retains the checked
    ///             save and auxiliary-editor callbacks.
    ///
    /// @param[in]  title                      Display title or proposed title text
    /// @param[in]  appearance                 Optional or explicit appearance overrides supplied by the caller
    /// @param[in]  onOpenCover                Optional action for opening the cover editor
    /// @param[in]  onOpenLayout               Optional action for opening the section-layout editor
    /// @param[in]  showsListBackground        Whether list-background controls are available in this appearance editor
    /// @param[in]  displayFormat              Optional item display format to edit with its appearance
    /// @param[in]  onSaveDisplay              Optional checked save callback for appearance and item display format
    /// @param[in]  inheritedAddItemTextColor  Resolved Board color used when this List has no override
    /// @param[in]  onSave                     Save callback returning true only when the owner accepts the edited value
    ///
    /// @return     (ItemAppearanceSheet) initialized instance
    ///
    init(
        title: String, appearance: ItemAppearance?, onOpenCover: (() -> Void)? = nil, onOpenLayout: (() -> Void)? = nil,
        showsListBackground: Bool = false, displayFormat: ItemDisplayFormat? = nil,
        onSaveDisplay: ((ItemAppearance?, ItemDisplayFormat) -> Bool)? = nil, inheritedAddItemTextColor: Color? = nil,
        onSave: @escaping (ItemAppearance?) -> Bool
    )
    {

        self.title = title
        self.showsListBackground = showsListBackground
        self.inheritedAddItemTextColor = inheritedAddItemTextColor
        self.onSave = onSave
        self.onOpenCover = onOpenCover
        self.onOpenLayout = onOpenLayout
        self.onSaveDisplay = onSaveDisplay
        _draftDisplay = State(initialValue: displayFormat)
        _draft = State(initialValue: appearance ?? ItemAppearance())
    }


    var body: some View
    {

        NavigationStack
        {

            Form
            {

                StudioSurfaceSettings(surface: $draft.studioSurface, header: $draft.background, italic: $draft.subtitleItalic,
                                      titleColor: $draft.cardTitleColor, textColor: $draft.cardTextColor)
                if showsListBackground
                {
                    StudioSurfaceSettings(surface: $draft.studioCardSurface, title: "Default Card and Note artwork")
                }

                if draftDisplay != nil
                {

                    Section("Display as")
                    {

                        Picker(
                                                                        "Format",
                                                                        selection: Binding(
                                                                            get:
                                                                            {
                                                                                draftDisplay ?? .card
                                                                            }, set:
                                                                            {
                                                                                draftDisplay = $0
                                                                            }
                                                                        )
                        )
                        {

                            ForEach(ItemDisplayFormat.allCases)
                            {
                                format in
                                Label(format.title, systemImage: format.symbol).tag(format)
                            }

                        }
                        .accessibilityIdentifier("appearance.displayFormat")
                        Text(
                                                                        "Changes how this item is displayed. Its writing, actions, dates, and photos are retained."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if draftDisplay == .picture
                        {

                            Text(
                                                                                    "Picture uses the selected Card Cover. Save this format, then choose a picture in Card Cover if needed."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                    }

                }

                Section("Subtitle style")
                {
                    Picker("Italic subtitle", selection: $draft.subtitleItalic)
                    {
                        Text("Inherit").tag(Optional<Bool>.none)
                        Text("Regular").tag(Optional(false))
                        Text("Italic").tag(Optional(true))
                    }
                    .accessibilityIdentifier("appearance.subtitleItalic")
                    Text("Inherit uses the parent List or Board setting. This also becomes the default for items inside a List.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if draftDisplay == .card
                {

                    Section("Subtitle")
                    {

                        Toggle(
                                                                        "Hide subtitle when empty",
                                                                        isOn: Binding(
                                                                            get:
                                                                            {
                                                                                draft.hideEmptySubtitle == true
                                                                            },
                                                                            set:
                                                                            {
                                                                                draft.hideEmptySubtitle = $0 ? true : nil
                                                                            }
                                                                        )
                        )
                        .accessibilityIdentifier("appearance.hideEmptySubtitle")
                        Text(
                                                                        "Filled subtitles stay visible. Use Add subtitle from the card menu to write one when the empty field is hidden."
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }

                    if let onOpenLayout
                    {

                        Section("Card Layout")
                        {

                            Button("Layout", systemImage: "rectangle.3.group", action: onOpenLayout)
                            .accessibilityIdentifier("appearance.layout")
                        }

                    }

                }

                if showsListBackground || (draftDisplay != nil && draftDisplay != .divider)
                {

                    Section("Card display")
                    {

                        CardDisplayProfilePicker(selection: $draft.cardDetail)
                        Text(
                            showsListBackground
                            ? "Unchanged follows the Board or existing layout. Individual items can override this List."
                            : "Unchanged follows the List, then Board. This changes the list preview; opening the item still shows its full contents."
                        )
                        .font(.footnote).foregroundStyle(.secondary)
                    }

                }

                if showsListBackground || draftDisplay != .divider
                {

                    PreviewTextColorsSection(
                        titleColor: $draft.cardTitleColor, textColor: $draft.cardTextColor,
                        explanation: showsListBackground
                        ? "Unchanged follows the Board. Individual Cards and Notes can override this List. Colors affect previews only."
                        : "Unchanged follows the List, then Board. Colors affect previews only; opened editors, dates, labels, and status indicators keep their own styling."
                    )
                }

                if showsListBackground
                {

                    AddItemTextColorSection(
                        selection: $draft.addItemTextColor,
                        defaultColor: inheritedAddItemTextColor ?? BoardAppearance().resolvedAddItemTextColor(
                            list: nil, title: title)?.color ?? .primary)
                }

                Section("Preview")
                {

                    HStack
                    {

                        ItemAppearanceMark(appearance: draft)
                        Text(title).font(.headline)
                    }

                }

                if showsListBackground && KanbanList.defaultHeaderIcon(for: title) == nil
                {

                    Section("List header")
                    {

                        Toggle(
                                                                        "Show icon in title bar",
                                                                        isOn: Binding(
                                                                            get:
                                                                            {
                                                                                draft.showsIconInHeader ?? (KanbanList.defaultHeaderIcon(for: title) != nil)
                                                                            },
                                                                            set:
                                                                            {
                                                                                draft.showsIconInHeader = $0
                                                                            }
                                                                        ))
                        Text("Show this List's icon beside its title when opening the List or Day view.")
                        .font(.footnote).foregroundStyle(.secondary)
                    }

                }

                if showsListBackground
                {

                    Section("Icon color")
                    {

                        ListIconColorPicker(
                            selection: $draft.iconColor, fixedColor: KanbanList.fixedHeaderIconColor(for: title))
                    }

                }

                Section("Leading icon")
                {

                    Picker("Icon", selection: $draft.icon)
                    {

                        Text("None").tag(Optional<PersonalCollectionIcon>.none)
                        ForEach(PersonalCollectionIcon.allCases, id: \.self)
                        {
                            icon in
                            Label(icon.title, systemImage: icon.rawValue).tag(Optional(icon))
                        }

                    }
                    .accessibilityIdentifier("appearance.icon")
                }

                if showsListBackground
                {

                    Section("List background")
                    {

                        Picker("Background color", selection: $draft.listBackground)
                        {

                            Text("Use Board default").tag(Optional<KanbanListTint>.none)
                            ForEach(KanbanListTint.allCases)
                            {
                                tint in
                                Text(tint.title).tag(Optional(tint))
                            }

                        }
                        .accessibilityIdentifier("appearance.listBackground")
                        ListSurfaceOpacityPicker(
                            title: title, tint: draft.listBackground ?? .neutral,
                            opacity: Binding(
                                get:
                                {
                                    draft.resolvedListBackgroundOpacity
                                },
                                set:
                                {
                                    draft.listBackgroundOpacity = $0
                                }
                            ))
                        Text(
                                                                        "Only the List surface fades. Cards, text and controls stay fully visible. Save applies your choice; Cancel discards it."
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        Text(
                                                                        "A subtle color behind the items in this Board’s list. Use Board default inherits the Board’s choice; Default keeps a neutral background."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                }

                if !showsListBackground && draftDisplay != .divider
                {

                    Section("Card background")
                    {

                        Picker("Background color", selection: $draft.cardBackground)
                        {

                            Text("Use Board default").tag(Optional<KanbanListTint>.none)
                            ForEach(KanbanListTint.allCases)
                            {
                                tint in
                                Text(tint.title).tag(Optional(tint))
                            }

                        }
                        .accessibilityIdentifier("appearance.cardBackground")
                        Text(
                                                                        "A soft color behind this item's list and Gallery preview. Default keeps the Card neutral; Use Board default follows its Board."
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }

                }

                Section("Banner background")
                {

                    Picker("Background color", selection: $draft.background)
                    {

                        Text(showsListBackground ? "Use Board default" : "None").tag(Optional<ItemAccent>.none)
                        ForEach(ItemAccent.allCases, id: \.self)
                        {
                            color in
                            Text(color.rawValue.capitalized).tag(Optional(color))
                        }

                    }
                    .accessibilityIdentifier("appearance.background")
                    Text("A soft color across the full header and upper bar, independent of the icon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let onOpenCover
                {

                    Section("Card Cover")
                    {

                        Button("Card Cover", systemImage: "photo", action: onOpenCover)
                        .accessibilityIdentifier("appearance.cover")
                        Text(
                                                                        "Choose or remove a cover. Cover changes apply immediately and are separate from saving or canceling the icon and background draft."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                }

                Section
                {

                    Button("Reset appearance")
                    {
                        draft = ItemAppearance()
                    }
                    .accessibilityIdentifier("appearance.reset")
                    Text(
                                                            "Icon and background are optional and independent. Titles, covers, photos, and other content stay unchanged. Save applies your choices; Cancel discards them."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

            }
            .navigationTitle("Appearance")
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

                        let appearance = draft.isEmpty ? nil : draft
                        let saved: Bool
                        if let draftDisplay, let onSaveDisplay
                        {

                            saved = onSaveDisplay(appearance, draftDisplay)
                        }
                        else
                        {

                            saved = onSave(appearance)
                        }

                        if saved
                        {
                            dismiss()
                        }

                    }
                    .accessibilityIdentifier("appearance.save")
                }

            }

        }
        .databaseActivityOverlay()
    }

}


///
/// Edits Board and List surface appearance as a draft
///
/// @section    Purpose
///     Combines backgrounds, imported photos, preview colors, and optional List surface controls
///     before handing the result to the owner.
///
struct BoardAppearanceSheet: View
{


    @State private var photoSelection: PhotosPickerItem?
    @State private var draftPhoto:     Data?
    @State private var isImportingPhoto = false
    @State private var backgroundError:      String?
    let allowsCollectionBackground:          Bool
    var defaultCollectionBackground:         CollectionBackground? = nil
    @State private var draft:                BoardAppearance
    let listSurface:                         KanbanList?
    let onSaveListSurface:                   ((Double, Bool, PersonalCollectionIcon, ProfileColor?) -> Void)?
    @State private var draftSurfaceOpacity:  Double
    @State private var draftShowsHeaderIcon: Bool
    @State private var draftIconColor:       ProfileColor?
    @State private var draftHeaderIcon:      PersonalCollectionIcon
    @State private var applyToAll = false
    @State private var draftPresentation: BoardPresentation
    let onSavePresentation:               ((BoardPresentation) -> Void)?
    let onSave:                           (BoardAppearance, Bool) -> Bool
    @Environment(\.dismiss) private var dismiss


    ///
    /// @fcn        BoardAppearanceSheet.init
    /// @brief      Seed board appearance and optional list-surface editing
    /// @details    Builds independent draft values for presentation, surface opacity, icon visibility, icon color,
    ///             and inherited defaults before retaining the save callbacks.
    ///
    /// @param[in]  appearance                   Optional or explicit appearance overrides supplied by the caller
    /// @param[in]  presentation                 Card, note, or board presentation selected by the caller
    /// @param[in]  onSavePresentation           Optional callback for committing the chosen board presentation
    /// @param[in]  allowsCollectionBackground   Whether the editor should offer collection-level background controls
    /// @param[in]  defaultCollectionBackground  Built-in collection background used when no explicit override is
    ///                                          selected
    /// @param[in]  listSurface                  Optional list whose surface and header settings are being edited
    /// @param[in]  listHeaderIcon               Inherited icon used when the list has no explicit header choice
    /// @param[in]  onSaveListSurface            Optional callback for saving list opacity, header visibility, icon,
    ///                                          and icon color
    /// @param[in]  onSave                       Save callback returning true only when the owner accepts the edited
    ///                                          value
    ///
    /// @return     (BoardAppearanceSheet) initialized instance
    ///
    init(
        appearance: BoardAppearance, presentation: BoardPresentation = .standard,
        onSavePresentation: ((BoardPresentation) -> Void)? = nil,
        allowsCollectionBackground: Bool = false,
        defaultCollectionBackground: CollectionBackground? = nil,
        listSurface: KanbanList? = nil,
        listHeaderIcon: PersonalCollectionIcon? = nil,
        onSaveListSurface: ((Double, Bool, PersonalCollectionIcon, ProfileColor?) -> Void)? = nil,
        onSave: @escaping (BoardAppearance, Bool) -> Bool
    )
    {

        _draftShowsHeaderIcon = State(initialValue: listSurface?.showsIconInHeader ?? false)
        _draftHeaderIcon = State(
            initialValue: listSurface?.appearance?.icon ?? listHeaderIcon ?? KanbanList.defaultHeaderIcon(
                for: listSurface?.title ?? "") ?? .notes)
        _draftIconColor = State(initialValue: listSurface?.appearance?.iconColor)
        self.listSurface = listSurface
        self.onSaveListSurface = onSaveListSurface
        _draftSurfaceOpacity = State(initialValue: listSurface?.appearance?.resolvedListBackgroundOpacity ?? 1)
        self.allowsCollectionBackground = allowsCollectionBackground
        self.defaultCollectionBackground = defaultCollectionBackground
        _draft = State(initialValue: appearance)
        _draftPresentation = State(initialValue: presentation)
        self.onSavePresentation = onSavePresentation
        self.onSave = onSave
    }


    var body: some View
    {

        NavigationStack
        {

            Form
            {

                StudioSurfaceSettings(surface: $draft.studioSurface, title: "Board artwork", header: $draft.bannerBackground,
                                      italic: $draft.subtitleItalic, titleColor: $draft.cardTitleColor, textColor: $draft.cardTextColor)
                StudioSurfaceSettings(surface: $draft.studioCardSurface, title: "Default Card and Note artwork")

                if allowsCollectionBackground
                {
                    collectionBackgroundSection
                }

                if let listSurface
                {

                    if !listSurface.hasFixedHeaderIcon
                    {

                        Section("List header")
                        {

                            Toggle("Show icon in title bar", isOn: $draftShowsHeaderIcon)
                            Picker("Header icon", selection: $draftHeaderIcon)
                            {

                                ForEach(PersonalCollectionIcon.allCases, id: \.self)
                                {
                                    icon in
                                    Label(icon.title, systemImage: icon.rawValue).tag(icon)
                                }

                            }
                            .disabled(!draftShowsHeaderIcon)
                        }

                    }

                    Section("Icon color")
                    {

                        ListIconColorPicker(
                            selection: $draftIconColor,
                            fixedColor: KanbanList.fixedHeaderIconColor(for: listSurface.title))
                    }

                    Section("List surface")
                    {

                        ListSurfaceOpacityPicker(
                            title: listSurface.title,
                            tint: listSurface.appearance?.listBackground ?? draft.listBackground ?? .neutral,
                            opacity: $draftSurfaceOpacity)
                        Text(
                                                                        "Fades only the surface behind this List's cards. Cards and controls stay fully visible. Save applies your choice; Cancel discards it."
                        )
                        .font(.footnote).foregroundStyle(.secondary)
                    }

                }

                if onSavePresentation != nil
                {

                    Section("Display")
                    {

                        Picker("Board presentation", selection: $draftPresentation)
                        {

                            ForEach(BoardPresentation.allCases)
                            {
                                option in
                                Text(option.title).tag(option)
                            }

                        }
                        .pickerStyle(.menu)
                    }

                }

                Section("Subtitle style")
                {
                    Toggle("Italic subtitle", isOn: Binding(
                        get:
                        {
                            draft.subtitleItalic == true
                        },
                        set:
                        {
                            draft.subtitleItalic = $0 ? true : nil
                        }
                    ))
                    .accessibilityIdentifier("boardAppearance.subtitleItalic")
                    Text("Sets the default for this Board, its Lists, and their Cards and Notes. Individual items can override it.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Card display")
                {

                    CardDisplayProfilePicker(selection: $draft.cardDetail)
                    Text(
                                                            "Unchanged keeps the existing layout. Compact emphasizes titles and small indicators; Detailed includes supporting content. Lists and individual items can override this choice."
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                }

                PreviewTextColorsSection(
                    titleColor: $draft.cardTitleColor, textColor: $draft.cardTextColor,
                    explanation:
                                                        "Unchanged keeps the app defaults. Lists and individual Cards and Notes can override each color independently. Colors affect previews only."
                )
                AddItemTextColorSection(
                    selection: $draft.addItemTextColor,
                    defaultColor: BoardAppearance().resolvedAddItemTextColor(
                        list: nil, title: listSurface?.title ?? "")?.color ?? .primary)
                Section("List banner color")
                {

                    Picker("Banner background", selection: $draft.bannerBackground)
                    {

                        Text("Default").tag(Optional<ItemAccent>.none)
                        ForEach(ItemAccent.allCases, id: \.self)
                        {
                            color in
                            Text(color.rawValue.capitalized).tag(Optional(color))
                        }

                    }

                }

                Section("List background color")
                {

                    Picker("List background", selection: $draft.listBackground)
                    {

                        Text("Default").tag(Optional<KanbanListTint>.none)
                        ForEach(KanbanListTint.allCases.filter
                            {
                                $0 != .neutral
                            })
                        {
                            tint in
                            Text(tint.title).tag(Optional(tint))
                        }

                    }

                }

                Section("Card background color")
                {

                    Picker("Card background", selection: $draft.cardBackground)
                    {

                        Text("Default").tag(Optional<KanbanListTint>.none)
                        ForEach(KanbanListTint.allCases.filter
                            {
                                $0 != .neutral
                            })
                        {
                            tint in
                            Text(tint.title).tag(Optional(tint))
                        }

                    }

                    Text(
                                                            "A soft tint for Card and Note rows on this Board. Pictures, Dividers, and individual item banner colors are retained."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section
                {

                    Toggle("Apply to all Lists", isOn: $applyToAll)
                    Text(
                        applyToAll
                        ? "Save replaces color overrides in active and archived Lists. Icons and content are retained."
                        : "New Lists and Lists using Board defaults inherit these colors. Individually chosen List colors are retained."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

            }
            .navigationTitle(listSurface == nil ? "Board Appearance" : "List Appearance")
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

                        saveAppearance()
                    }
                    .disabled(isImportingPhoto)
                }

            }

        }
        .task(id: photoSelection)
        {

            guard let photoSelection else
            {
                return
            }

            isImportingPhoto = true
            defer
            {
                isImportingPhoto = false
            }

            do
            {

                guard let data = try await photoSelection.loadTransferable(type: Data.self) else
                {

                    throw CocoaError(.fileReadCorruptFile)
                }

                let prepared = try await Task.detached(priority: .userInitiated)
                {

                    try CollectionBackgroundPhotoStore.preparedPhoto(data)
                } .value
                try Task.checkCancellation()
                draftPhoto = prepared
                draft.collectionBackground = CollectionBackground(preset: .photo)
            }
            catch is CancellationError
            {

            }
            catch
            {

                backgroundError = "This photo could not be opened. Please choose another image."
            }

        }
        .alert(
                        "Background",
                        isPresented: Binding(get:
                            {
                                backgroundError != nil
                            }, set:
                            {
                                if !$0
                                {
                                    backgroundError = nil
                                }

                            })
        )
        {

            Button("OK", role: .cancel)
            {
                backgroundError = nil
            }

        }
        message:
        {

            Text(backgroundError ?? "")
        }
        .databaseActivityOverlay()
    }


    private var collectionBackgroundSection: some View
    {

        Section("Background")
        {

            CollectionBackgroundSurface(
                background: draft.collectionBackground ?? defaultCollectionBackground, draftPhoto: draftPhoto
            )
            .frame(height: 136)
            .overlay(alignment: .bottomLeading)
            {

                Text((draft.collectionBackground ?? defaultCollectionBackground)?.preset.title ?? "Plenact default")
                .font(.headline).foregroundStyle(.white).padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            Picker(
                                    "Background",
                                    selection: Binding(
                                        get:
                                        {
                                            draft.collectionBackground?.preset
                                        },
                                        set:
                                        {
                                            preset in
                                            guard preset != draft.collectionBackground?.preset else
                                            {
                                                return
                                            }

                                            if preset != .photo
                                            {
                                                draftPhoto = nil
                                            }

                                            draft.collectionBackground = preset.map
                                            {
                                                CollectionBackground(preset: $0)
                                            }

                                        }
                                    )
            )
            {

                Text("Default").tag(Optional<CollectionBackgroundPreset>.none)
                ForEach(CollectionBackgroundPreset.allCases.filter
                    {
                        $0 != .photo
                    })
                {
                    preset in
                    Text(preset.title).tag(Optional(preset))
                }

                if draft.collectionBackground?.preset == .photo
                {

                    Text("Your photo").tag(Optional(CollectionBackgroundPreset.photo))
                }

            }
            .accessibilityIdentifier("appearance.collectionBackground")
            .disabled(isImportingPhoto)
            PhotosPicker(selection: $photoSelection, matching: .images)
            {

                Label("Choose photo", systemImage: "photo")
            }
            .disabled(isImportingPhoto)
            if isImportingPhoto
            {
                ProgressView("Preparing photo…")
            }

            Text(
                                    "A personal background for this Board or List. Photos stay on this device. Week and Day views keep their Plenact background."
            )
            .font(.footnote).foregroundStyle(.secondary)
        }

    }


    ///
    /// @fcn        BoardAppearanceSheet.saveAppearance
    /// @brief      Commit the edited board and list appearance settings
    /// @details    Uses the provided save callbacks and dismisses only through the editor's accepted save flow,
    ///             retaining failed edits for correction.
    ///
    /// @return     (Void) no return value
    ///
    private func saveAppearance()
    {

        guard !isImportingPhoto else
        {
            return
        }

        var updated = draft
        var importedName: String?
        do
        {

            if allowsCollectionBackground, updated.collectionBackground?.preset == .photo, let draftPhoto
            {

                let name = try CollectionBackgroundPhotoStore.save(draftPhoto)
                importedName = name
                updated.collectionBackground?.photoFileName = name
            }

            if onSave(updated, applyToAll)
            {

                if listSurface != nil
                {

                    onSaveListSurface?(draftSurfaceOpacity, draftShowsHeaderIcon, draftHeaderIcon, draftIconColor)
                }

                onSavePresentation?(draftPresentation)
                dismiss()
            }
            else if let importedName
            {

                CollectionBackgroundPhotoStore.remove(importedName)
            }

        }
        catch
        {

            if let importedName
            {
                CollectionBackgroundPhotoStore.remove(importedName)
            }

            backgroundError = "The background could not be saved. Your current appearance has been kept."
        }

    }

}


///
/// Edits the inline Add-item text and button color
///
/// @section    Purpose
///     Keeps a view-scoped override separate from Card preview styling and allows reset to the
///     inherited color.
///
struct AddItemTextColorSection: View
{


    @Binding var selection: ProfileColor?
    var defaultColor:       Color = .primary

    var body: some View
    {

        Section("Add Card field")
        {

            ColorPicker(
                                    "Text color",
                                    selection: Binding(
                                        get:
                                        {
                                            selection?.color ?? defaultColor
                                        },
                                        set:
                                        {
                                            color in
                                            var red: CGFloat = 0
                                            var green: CGFloat = 0
                                            var blue: CGFloat = 0
                                            var alpha: CGFloat = 0
                                            guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else
                                            {
                                                return
                                            }

                                            selection = ProfileColor(red: Double(red), green: Double(green), blue: Double(blue))
                                        }), supportsOpacity: false
            )
            .accessibilityIdentifier("appearance.addItemTextColor")
            Button("Use default color")
            {
                selection = nil
            }
            .disabled(selection == nil)
            Text(
                                    "Changes the Add Card or Add Note text and its + button in this view. Lists can override their Board's color."
            )
            .font(.footnote).foregroundStyle(.secondary)
        }

    }

}


///
/// Edits optional title and body preview colors
///
/// @section    Purpose
///     Binds explicit palette choices while allowing nil to retain inherited presentation.
///
struct PreviewTextColorsSection: View
{


    @Binding var titleColor: ListPreviewTextColor?
    @Binding var textColor:  ListPreviewTextColor?
    let explanation:         String


    ///
    /// @fcn        PreviewTextColorsSection.picker
    /// @brief      Build a preview text-color override picker
    /// @details    Binds the optional color choice so users can select an explicit color or retain inherited styling.
    ///
    /// @param[in]  title      Display title or proposed title text
    /// @param[in]  selection  Text selection or resolved navigation selection to retain
    ///
    /// @return     (some View) a preview text-color override picker
    ///
    private func picker(_ title: String, selection: Binding<ListPreviewTextColor?>) -> some View
    {

        Picker(title, selection: selection)
        {

            Text("Unchanged").tag(Optional<ListPreviewTextColor>.none)
            ForEach(ListPreviewTextColor.allCases)
            {
                color in
                Text(color.title).tag(Optional(color))
            }

        }

    }

    var body: some View
    {

        Section("Preview text colors")
        {

            picker("Title color", selection: $titleColor)
            picker("Supporting text color", selection: $textColor)
            VStack(alignment: .leading, spacing: 6)
            {

                Text("Card or note title").font(.headline).foregroundStyle(titleColor?.color ?? .primary)
                Text("Subtitle or note preview").font(.subheadline).foregroundStyle(textColor?.color ?? .secondary)
            } .padding(.vertical, 8)
            Text(explanation).font(.footnote).foregroundStyle(.secondary)
        }

    }

}


///
/// Edits List surface opacity in a local draft
///
/// @section    Purpose
///     Shares the same preview control across List appearance and Library settings without saving
///     until the surrounding editor accepts it.
///
struct ListSurfaceOpacityPicker: View
{


    let title:            String
    var tint:             KanbanListTint = .neutral
    @Binding var opacity: Double
    var body:             some View
    {

        VStack(alignment: .leading, spacing: 12)
        {

            VStack(alignment: .leading, spacing: 8)
            {

                HStack
                {

                    Text("Background opacity")
                    Spacer()
                    Text(opacity, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit().foregroundStyle(.secondary)
                }

                Slider(value: $opacity, in: 0 ... 1, step: 0.05)
                .accessibilityLabel("List background opacity")
                .accessibilityValue(opacity.formatted(.percent.precision(.fractionLength(0))))
                .accessibilityIdentifier("appearance.listBackgroundOpacity")
                HStack
                {

                    Text("Transparent")
                    Spacer()
                    Text("Solid")
                } .font(.caption).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10)
            {

                Text(title).font(.headline)
                Label("Example item", systemImage: "square")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(12)
            .background(
                tint.color.opacity(opacity),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .padding(8)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            .accessibilityLabel("List background preview")
        }

    }

}


///
/// Edits List icon tint independently of its banner
///
/// @section    Purpose
///     Preserves the special shortcut Lists' read-only controls while binding editable custom List
///     color choices.
///
struct ListIconColorPicker: View
{


    @Binding var selection: ProfileColor?
    var fixedColor:         ProfileColor? = nil
    private let presets:    [(String, ProfileColor)] = [
        ("Teal", .teal), ("Blue", .blue), ("Green", .green), ("Orange", .orange),
        ("Coral", .coral), ("Graphite", .graphite), ("White", .white),
        ("Charcoal", .charcoal), ("Yellow", .lemon), ("Sky", .sky)
    ]
    var body: some View
    {

        if let fixedColor
        {

            LabeledContent("Icon color")
            {

                HStack
                {

                    Circle().fill(fixedColor.color).frame(width: 18, height: 18)
                    Text("Fixed").foregroundStyle(.secondary)
                }

            }
            .accessibilityLabel("Icon color, fixed for this List")
        }
        else
        {

            Picker("Icon color", selection: $selection)
            {

                Text("Default").tag(Optional<ProfileColor>.none)
                ForEach(presets.indices, id: \.self)
                {
                    index in
                    HStack
                    {

                        Circle().fill(presets[index].1.color).frame(width: 18, height: 18)
                        Text(presets[index].0)
                    } .tag(Optional(presets[index].1))
                }

            }
            .accessibilityIdentifier("appearance.listIconColor")
        }

    }

}
