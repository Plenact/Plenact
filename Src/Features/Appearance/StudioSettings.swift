// --------------------------------------------------------------------------------------------------
// @file       StudioSettings.swift
// @brief      Personalization Studio settings and per-view wallpaper integration
// @details    Keeps workspace choices local until Save and exposes independent Card/Note creation
//             defaults, reusable artwork, and wallpaper choices for primary workspace destinations.
// --------------------------------------------------------------------------------------------------
import SwiftUI


/// Edits global creation defaults and main-view wallpapers.
/// @section Purpose
///     Makes personalization discoverable from Plan Settings while preserving all existing defaults.
struct StudioSettingsView: View
{


    @State private var draft = StudioSettings.load()
    @State private var palette = StudioSettings.load().palette.joined(separator: ", ")
    @State private var error: String?
    @State private var showsLibrary = false
    @Environment(\.dismiss) private var dismiss
    @AppStorage(StudioSettings.key) private var data = Data()


    /// @fcn StudioSettingsView.destinationBinding(_:)
    /// @brief Bind one optional view wallpaper into the shared editor
    /// @details Removing an override preserves the destination's established background.
    /// @param[in] destination Workspace view being personalized
    /// @return (Binding<StudioSurface?>) optional wallpaper draft
    private func destinationBinding(_ destination: StudioDestination) -> Binding<StudioSurface?>
    {


        Binding(get:
            {
                draft.views[destination.rawValue]
            }, set:
            {
                draft.views[destination.rawValue] = $0
            })
    }


    ///
    /// @fcn        StudioSettingsView.body
    /// @brief      Compose the native personalization interface for this destination
    /// @details    Keeps editing state within its owning view and preserves existing behavior
    ///             when no material override is configured. Decorative art stays below controls.
    ///
    /// @return     (some View) accessible surface controls or resolved workspace background
    ///
    var body: some View
    {


        Form
        {

            Section("Your artwork")
            {

                Button("My art", systemImage: "paintpalette")
                {
                    showsLibrary = true
                }

                Text("Reuse a favorite image or complete look across Cards, Notes, Lists, and Boards. Imported artwork stays on this device.")
                .font(.caption)
            }

            StudioSurfaceSettings(surface: $draft.defaultCardSurface, title: "New Card background")
            StudioSurfaceSettings(surface: $draft.defaultNoteSurface, title: "New Note background")
            Section("Coordinated variety")
            {

                Toggle("Vary new item colors", isOn: $draft.variesNewSurfaces)
                Toggle("Vary new item header colors", isOn: $draft.variesNewHeaders)
                TextField("Palette: comma-separated RGB hex colors", text: $palette)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                Text("Colors are chosen once when an item is created. Existing items keep their saved appearance.")
                .font(.caption)
            }

            ForEach(StudioDestination.allCases)
            {

            destination in
                StudioSurfaceSettings(surface: destinationBinding(destination), title: destination.rawValue + " wallpaper")
            }

        }
        .navigationTitle("Plenact Studio").navigationBarTitleDisplayMode(.inline)
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

                    let colors = palette.split(separator: ",").map
                    {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    }

                    guard !colors.isEmpty, colors.allSatisfy(
                        {
                            $0.count == 6 && UInt32($0, radix: 16) != nil
                        }) else
                    {
                        error = "Use comma-separated six-digit RGB colors, such as EDE3CA, DDE8D8.";
                        return
                    }

                    draft.palette = colors
                    do
                    {
                        data = try JSONEncoder().encode(draft);
                        dismiss()
                    }

                    catch
                    {
                        self.error = error.localizedDescription
                    }

                }

            }

        }
        .sheet(isPresented: $showsLibrary)
        {
            StudioLibraryView()
        }
        .alert("Personalization could not be saved", isPresented: Binding(get:
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



/// Places a saved wallpaper above an existing fallback without replacing unconfigured views.
/// @section Purpose
///     Shares per-view selection consistently across primary destinations and their existing safe areas.
struct StudioWorkspaceBackground: View
{


    let destination: StudioDestination
    @AppStorage(StudioSettings.key) private var data = Data()

    ///
    /// @fcn        StudioWorkspaceBackground.body
    /// @brief      Compose the native personalization interface for this destination
    /// @details    Keeps editing state within its owning view and preserves existing behavior
    ///             when no material override is configured. Decorative art stays below controls.
    ///
    /// @return     (some View) accessible surface controls or resolved workspace background
    ///
    var body: some View
    {


        if let settings = try? JSONDecoder().decode(StudioSettings.self, from: data),
        let surface = settings.views[destination.rawValue]
        {

            StudioSurfaceView(surface: surface)
        }

    }

}



/// Applies configured wallpapers to native forms while preserving their default rendering when unset.
/// @section Purpose
///     Keeps Settings wallpaper opt-in and avoids changing unconfigured form backgrounds.
struct StudioFormWallpaper: ViewModifier
{


    let destination: StudioDestination
    @AppStorage(StudioSettings.key) private var data = Data()

    ///
    /// @fcn        StudioFormWallpaper.body
    /// @brief      Compose the native personalization interface for this destination
    /// @details    Keeps editing state within its owning view and preserves existing behavior
    ///             when no material override is configured. Decorative art stays below controls.
    ///
    /// @param[in]  content  Existing workspace content receiving the optional wallpaper
    /// @return     (some View) accessible surface controls or resolved workspace background
    ///
    func body(content: Content) -> some View
    {


        if let settings = try? JSONDecoder().decode(StudioSettings.self, from: data),
        let surface = settings.views[destination.rawValue]
        {

            content.scrollContentBackground(.hidden).background
            {
                StudioSurfaceView(surface: surface)
            }

        }

        else
        {
            content
        }

    }

}

