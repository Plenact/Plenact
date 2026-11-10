// --------------------------------------------------------------------------------------------------
// @file       StudioEditors.swift
// @brief      Native material editor, personal artwork library, and live previews
// @details    Keeps edits local until Done, supports Photos and Files imports, and saves reusable looks
//             without coupling artwork lifetime to the items displaying it
// --------------------------------------------------------------------------------------------------
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers


/// Opens the same background editor from any owner appearance form
/// @section Purpose
///     Keeps per-owner editing inside the caller's existing checked Save and Cancel transaction
struct StudioSurfaceSettings: View
{
    @Binding var surface: StudioSurface?                                        /* Artwork surface definition  */
    var title                                       = "Background artwork"      /* User-facing title           */
    var header:     Binding<ItemAccent?>?           = nil                       /* Resolved header appearance  */
    var italic:     Binding<Bool?>?                 = nil                       /* Inherited subtitle emphasis */
    var titleColor: Binding<ListPreviewTextColor?>? = nil                       /* Title color                 */
    var textColor:  Binding<ListPreviewTextColor?>? = nil                       /* Text color                  */

    ///
    /// @fcn        StudioSurfaceSettings.body
    /// @brief      Compose the native personalization interface for this destination
    /// @details    Keeps editing state within its owning view and preserves existing behavior
    ///             when no material override is configured. Decorative art stays below controls
    ///
    /// @return     (some View) accessible surface controls or resolved workspace background
    ///
    var body: some View         /* Studio Surface Settings layout */
    {
        Section(title)
        {
            NavigationLink
            {
                StudioSurfaceEditor(surface: $surface, header: header, italic: italic, titleColor: titleColor, textColor: textColor)
            }

            label:
            {
                Label(surface?.material.title ?? "Inherit existing appearance", systemImage: "paintpalette")
            }
            .accessibilityIdentifier("studio.surfaceEditor")
            if surface != nil
            {
                Button("Use inherited appearance")
                {
                    surface = nil
                }
            }
        }
    }
}



/// Edits one reusable surface with live readable content
/// @section Purpose
///     Provides consistent color, texture, photo, and online-image controls for all surface destinations
struct StudioSurfaceEditor: View
{
    let header:                         Binding<ItemAccent?>?                   /* Resolved header appearance  */
    let italic:                         Binding<Bool?>?                         /* Inherited subtitle emphasis */
    let titleColor:                     Binding<ListPreviewTextColor?>?         /* Title color                 */
    let textColor:                      Binding<ListPreviewTextColor?>?         /* Text color                  */
    @State private var draft:           StudioSurface                           /* Local editing draft         */
    @State private var importsFile    = false                                   /* Imports file                */
    @State private var artworkName    = "My look"                               /* Artwork name                */
    @State private var showsLibrary   = false                                   /* Library visibility          */
    @State private var showsUnsplash  = false                                   /* Unsplash visibility         */
    @State private var isApplying     = false                                   /* Apply operation in progress */
    @State private var savedToLibrary = false                                   /* Saved to library            */

    @Binding private var surface:       StudioSurface?                          /* Artwork surface definition     */
    @State private var draftHeader:     ItemAccent?                             /* Draft header                   */
    @State private var draftItalic:     Bool?                                   /* Draft italic                   */
    @State private var draftTitleColor: ListPreviewTextColor?                   /* Draft title color              */
    @State private var draftTextColor:  ListPreviewTextColor?                   /* Draft text color               */
    @State private var photo:           PhotosPickerItem?                       /* Photo selection or source      */
    @State private var error: String?                                           /* Reported operation failure     */
    @State private var applyTask: Task<Void, Never>?                            /* Apply task                     */
    @Environment(\.dismiss) private var dismiss                                 /* Close the current presentation */
    @AppStorage(StudioSettings.libraryKey) private var libraryData = Data()     /* Library data                   */


    /// @fcn StudioSurfaceEditor.init(surface:header:italic:titleColor:textColor:)
    /// @brief Capture a local surface draft and optional look settings
    /// @details Child cancellation preserves the owner draft, while Done passes the chosen material back
    /// @param[in] surface Optional owner material binding
    /// @param[in] header Optional owner header-color draft
    /// @param[in] italic Optional subtitle-style draft
    /// @param[in] titleColor Optional preview title-color draft
    /// @param[in] textColor Optional supporting-text color draft
    /// @return (StudioSurfaceEditor) initialized local editor
    init(surface: Binding<StudioSurface?>, header: Binding<ItemAccent?>? = nil, italic: Binding<Bool?>? = nil,
        titleColor: Binding<ListPreviewTextColor?>? = nil, textColor: Binding<ListPreviewTextColor?>? = nil)
    {
        _surface = surface
        self.header = header
        self.italic = italic
        self.titleColor = titleColor
        self.textColor = textColor
        _draftHeader = State(initialValue: header?.wrappedValue)
        _draftItalic = State(initialValue: italic?.wrappedValue)
        _draftTitleColor = State(initialValue: titleColor?.wrappedValue)
        _draftTextColor = State(initialValue: textColor?.wrappedValue)
        _draft = State(initialValue: surface.wrappedValue ?? StudioSurface())
    }



    /// @fcn StudioSurfaceEditor.colorBinding(_:)
    /// @brief Bridge a stored RGB string to the native color picker
    /// @details Stores opaque six-digit colors independently of display appearance
    /// @param[in] path Writable color field in the draft
    /// @return (Binding<Color>) editable RGB color
    private func colorBinding(_ path: WritableKeyPath<StudioSurface, String>) -> Binding<Color>
    {
        Binding(get:
            {
                StudioSurfaceView.color(draft[keyPath: path])
            }, set:
            {
            color in

                var r: CGFloat =                                        /* Resolved RGBA channels */
                    0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0

                guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else
                {
                    return
                }

                draft[keyPath: path] = String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
            })
    }



    /// @fcn StudioSurfaceEditor.importImage(_:)
    /// @brief Retain a personal image in the reusable library
    /// @details Enforces an input-size bound and stores one immutable artwork reference for future uses
    /// @param[in] data User-selected encoded image
    /// @return (Void) updates the draft after successful storage, otherwise presents an error
    private func importImage(_ data: Data)
    {
        do
        {
            guard data.count <= 30_000_000 else
            {
                throw CocoaError(.fileReadTooLarge)
            }

            let name = try StudioArtworkStore.importImage(data)         /* Display or lookup name */

            draft.material = .photo
            draft.photoFileName = name
            draft.remotePhoto = nil

            try saveArtwork(name: "My image", surface: draft)
        }

        catch
        {
            self.error = error.localizedDescription
        }
    }



    /// @fcn StudioSurfaceEditor.saveArtwork(name:surface:)
    /// @brief Save a named reusable look without copying its image
    /// @details Encodes the complete library before replacing preferences and preserves optional header styling
    /// @param[in] name User-visible library name
    /// @param[in] surface Material to retain
    /// @return (Void) replaces the encoded library after successful encoding
    /// @throws Encoding or malformed-library errors are presented by the caller
    private func saveArtwork(name: String, surface: StudioSurface) throws
    {
        var saved =     /* Saved state under review */
            libraryData.isEmpty ? [] : try JSONDecoder().decode([StudioArtwork].self, from: libraryData)

        saved.append(StudioArtwork(name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "My look" : name,
            surface: surface, header: draftHeader, italicSubtitle: draftItalic,
            titleColor: draftTitleColor, textColor: draftTextColor))

        libraryData = try JSONEncoder().encode(saved)
        savedToLibrary = true
    }


    /// @fcn StudioSurfaceEditor.applySurface()
    /// @brief Commit a captured look only after required provider selection tracking succeeds
    /// @details Preserves the owner draft on failed or cancelled requests and counts favorite reuse
    /// @return (Void) starts a cancellable, checked application of the selected artwork
    private func applySurface()
    {
        let chosen           = draft                    /* Explicit user selection */
        let chosenHeader     = draftHeader              /* Chosen header           */
        let chosenItalic     = draftItalic              /* Chosen italic           */
        let chosenTitleColor = draftTitleColor          /* Chosen title color      */
        let chosenTextColor  = draftTextColor           /* Chosen text color       */

        applyTask?.cancel()

        applyTask = Task
        {
            isApplying = true

            defer
            {
                isApplying = false
            }

            do
            {
                if chosen.material == .unsplash, let remote = chosen.remotePhoto
                {
                    _ = try await StudioUnsplash.request(remote.downloadURL)
                }

                try Task.checkCancellation()

                surface = chosen
                header?.wrappedValue = chosenHeader
                italic?.wrappedValue = chosenItalic
                titleColor?.wrappedValue = chosenTitleColor
                textColor?.wrappedValue = chosenTextColor

                dismiss()
            }

            catch is CancellationError
            {
            }

            catch
            {
                self.error = "Artwork could not be applied. Check the connection and Unsplash access key."
            }
        }
    }



    ///
    /// @fcn        StudioSurfaceEditor.body
    /// @brief      Compose the native personalization interface for this destination
    /// @details    Keeps editing state within its owning view and preserves existing behavior
    ///             when no material override is configured. Decorative art stays below controls
    ///
    /// @return     (some View) accessible surface controls or resolved workspace background
    ///
    var body: some View         /* Studio Surface Editor layout */
    {
        Form
        {
            Section("Live preview")
            {
                ZStack
                {
                    StudioSurfaceView(surface: draft)
                    VStack(alignment: .leading, spacing: 8)
                    {
                        Text("A little room to think").font(.headline).foregroundStyle(draftTitleColor?.color ?? .primary)
                        Text("Your words stay readable over your artwork.").font(draftItalic == true ? .subheadline.italic() : .subheadline)
                        .foregroundStyle(draftTextColor?.color ?? .secondary)
                        Label("0/3 steps", systemImage: "checklist").font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                }
                .frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Section("Surface")
            {
                Picker("Material", selection: $draft.material)
                {
                    ForEach(StudioMaterial.allCases)
                    {
                    material in
                        Text(material.title).tag(material)
                    }
                }

                ColorPicker("Primary color", selection: colorBinding(\.color), supportsOpacity: false)
                ColorPicker("Secondary color", selection: colorBinding(\.secondaryColor), supportsOpacity: false)
                Text("Artwork strength: \(Int(draft.strength * 100))%")
                Slider(value: $draft.strength, in: 0 ... 1)
                Text("Readability layer: \(Int(draft.readability * 100))%")
                Slider(value: $draft.readability, in: 0 ... 1)
                Toggle("Show artwork in item previews", isOn: $draft.showsInPreviews)
                if [.photo, .unsplash].contains(draft.material)
                {
                    Text("Vertical position")
                    Slider(value: $draft.verticalPosition, in: 0 ... 1)
                    Text("Zoom")
                    Slider(value: $draft.zoom, in: 1 ... 2)
                }
            }

            if header != nil || titleColor != nil || textColor != nil || italic != nil
            {
                Section("Complete look")
                {
                    if header != nil
                    {
                        Picker("Header", selection: $draftHeader)
                        {
                            Text("Inherit").tag(Optional<ItemAccent>.none)
                            ForEach(ItemAccent.allCases, id: \.self)
                            {
                            color in
                                Text(color.rawValue.capitalized).tag(Optional(color))
                            }
                        }
                    }

                    if italic != nil
                    {
                        Picker("Italic subtitle", selection: $draftItalic)
                        {
                            Text("Inherit").tag(Optional<Bool>.none)
                            Text("Regular").tag(Optional(false))
                            Text("Italic").tag(Optional(true))
                        }
                    }

                    if titleColor != nil
                    {
                        Picker("Title text", selection: $draftTitleColor)
                        {
                            Text("Inherit").tag(Optional<ListPreviewTextColor>.none)
                            ForEach(ListPreviewTextColor.allCases)
                            {
                            color in
                                Text(color.title).tag(Optional(color))
                            }
                        }
                    }

                    if textColor != nil
                    {
                        Picker("Supporting text", selection: $draftTextColor)
                        {
                            Text("Inherit").tag(Optional<ListPreviewTextColor>.none)
                            ForEach(ListPreviewTextColor.allCases)
                            {
                            color in
                                Text(color.title).tag(Optional(color))
                            }
                        }
                    }
                }
            }

            Section("Background portfolio")
            {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 12)
                {
                    ForEach(CardBackgroundPortfolio.titles.indices, id: \.self)
                    {
                        index in
                        Button
                        {
                            do
                            {
                                draft = try CardBackgroundPortfolio.surface(at: index)
                            }
                            catch
                            {
                                self.error = "This background could not be opened. Please try again."
                            }
                        }
                        label:
                        {
                            VStack(spacing: 5)
                            {
                                Image(CardBackgroundPortfolio.assetName(at: index))
                                    .resizable().scaledToFill().frame(height: 90).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(CardBackgroundPortfolio.titles[index])
                                    .font(.caption).lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Use " + CardBackgroundPortfolio.titles[index] + " background")
                    }
                }

                Text("Choose a photo for this background. New Notes rotate through this collection unless you choose a creation default.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("My art")
            {
                Button("Choose a saved look", systemImage: "square.grid.2x2")
                {
                    showsLibrary = true
                }

                PhotosPicker(selection: $photo, matching: .images)
                {
                    Label("Import from Photos", systemImage: "photo")
                }

                Button("Import from Files", systemImage: "folder")
                {
                    importsFile = true
                }

                Button("Find a photo on Unsplash", systemImage: "magnifyingglass")
                {
                    showsUnsplash = true
                }

                if savedToLibrary
                {
                    Label("Saved to My art", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                }
                Text("Imported images remain in My art. Done applies this look to the appearance draft.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Name this look", text: $artworkName)
                Button("Save this look to My art", systemImage: "bookmark")
                {
                    do
                    {
                        try saveArtwork(name: artworkName, surface: draft)
                    }

                    catch
                    {
                        self.error = error.localizedDescription
                    }
                }
            }
        }
        .navigationTitle("Make it yours").navigationBarTitleDisplayMode(.inline)
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
                Button("Done", action: applySurface)
                .disabled(isApplying || (draft.material == .photo && draft.photoFileName == nil)
                    || (draft.material == .unsplash && draft.remotePhoto == nil))
            }
        }
        .onDisappear
        {
            applyTask?.cancel()
        }
        .sheet(isPresented: $showsLibrary)
        {
            StudioLibraryView
            {
            look in

                draft = look.surface
                draftHeader = look.header
                draftItalic = look.italicSubtitle
                draftTitleColor = look.titleColor
                draftTextColor = look.textColor
            }
        }
        .sheet(isPresented: $showsUnsplash)
        {
            StudioUnsplashPicker
            {
            remote in

                draft.material = .unsplash
                draft.remotePhoto = remote
                draft.photoFileName = nil
            }
        }
        .onChange(of: photo)
        {
        _, item in
            Task
            {
                do
                {
                    if let data = try await item?.loadTransferable(type: Data.self)
                    {
                        importImage(data)
                    }
                }

                catch
                {
                    self.error = error.localizedDescription
                }
            }
        }
        .fileImporter(isPresented: $importsFile, allowedContentTypes: [.image])
        {
        result in
            do
            {
                let url    = try result.get()                   /* Resource location             */
                let access =                                    /* Security-scoped access result */
                    url.startAccessingSecurityScopedResource()

                defer
                {
                    if access
                    {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                importImage(try Data(contentsOf: url))
            }

            catch
            {
                self.error = error.localizedDescription
            }
        }
        .alert("Artwork could not be saved", isPresented: Binding(get:
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



/// Browses named artwork without deleting files referenced by existing content
/// @section Purpose
///     Reuses looks, permits renaming, and removes favorites while retaining underlying image files
struct StudioLibraryView: View
{
    var onSelect: ((StudioArtwork) -> Void)?                = nil       /* Handle the selected value      */
    @AppStorage(StudioSettings.libraryKey) private var data = Data()    /* Persisted settings bytes       */
    @Environment(\.dismiss) private var dismiss                         /* Close the current presentation */
    @State private var renamed = ""                                     /* Item after renaming            */

    @State private var error:    String?                /* Reported operation failure */
    @State private var renaming: StudioArtwork?         /* Item with an edited name   */

    private var artworks: [StudioArtwork]       /* Reusable saved artwork */
    {
        (try? JSONDecoder().decode([StudioArtwork].self, from: data)) ?? []
    }


    /// @fcn StudioLibraryView.saveRename()
    /// @brief Update one saved look name without replacing its artwork reference
    /// @details Ignores empty names and presents encoding failures without losing the library
    /// @return (Void) commits the renamed library entry when valid
    private func saveRename()
    {
        guard let id = renaming?.id else
        {
            return
        }

        let name =                                                      /* Display or lookup name */
            renamed.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else
        {
            return
        }

        do
        {
            var saved = artworks        /* Saved state under review */

            guard let index = saved.firstIndex(where:
                {
                    $0.id == id
                }) else
            {
                return
            }

            saved[index].name = name
            data = try JSONEncoder().encode(saved)
            renaming = nil
        }

        catch
        {
            self.error = error.localizedDescription
        }
    }



    ///
    /// @fcn        StudioLibraryView.body
    /// @brief      Compose the native personalization interface for this destination
    /// @details    Keeps editing state within its owning view and preserves existing behavior
    ///             when no material override is configured. Decorative art stays below controls
    ///
    /// @return     (some View) accessible surface controls or resolved workspace background
    ///
    var body: some View         /* Studio Library layout */
    {
        NavigationStack
        {
            List
            {
                if artworks.isEmpty
                {
                    ContentUnavailableView("Your art belongs here", systemImage: "paintpalette",
                        description: Text("Save a look or import an image from a background editor."))
                }

                ForEach(artworks)
                {
                look in
                    Button
                    {
                        onSelect?(look)
                        if onSelect != nil
                        {
                            dismiss()
                        }

                        else
                        {
                            renamed = look.name;
                            renaming = look
                        }
                    }

                    label:
                    {
                        HStack(spacing: 12)
                        {
                            StudioSurfaceView(surface: look.surface).frame(width: 70, height: 65)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading)
                            {
                                Text(look.name).foregroundStyle(.primary)
                                Text(look.surface.material.title).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete
                {
                indices in
                    do
                    {
                        var retained = artworks         /* State retained for recovery */

                        retained.remove(atOffsets: indices)

                        data = try JSONEncoder().encode(retained)
                    }

                    catch
                    {
                        self.error = error.localizedDescription
                    }
                }
            }
            .navigationTitle("My art")
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
            .safeAreaInset(edge: .bottom)
            {
                Text("Removing a saved look keeps artwork already used by your Cards and views.")
                .font(.caption).padding().background(.regularMaterial)
            }
            .alert("Rename artwork", isPresented: Binding(get:
                    {
                        renaming != nil
                    }, set:
                    {
                        if !$0
                        {
                            renaming = nil
                        }
                    }))
            {
                TextField("Name", text: $renamed)
                Button("Save", action: saveRename)
                Button("Cancel", role: .cancel)
                {
                    renaming = nil
                }
            }
            .alert("Library could not be updated", isPresented: Binding(get:
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
        }
    }
}

