// --------------------------------------------------------------------------------------------------
// @file       StudioSettings.swift
// @brief      Personalization Studio settings and per-view wallpaper integration
// @details    Keeps workspace choices local until Save and exposes independent Card/Note creation
//             defaults, reusable artwork, and wallpaper choices for primary workspace destinations
// --------------------------------------------------------------------------------------------------
import SwiftUI


/// Edits global creation defaults and main-view wallpapers
/// @section Purpose
///     Makes personalization discoverable from Plan Settings while preserving all existing defaults
struct StudioSettingsView: View
{


    @State private var draft   = StudioSettings.load() /* Local editing draft   */
    @State private var palette =                       /* Artwork color palette */
        StudioSettings.load().palette.joined(separator: ", ")
    @State private var showsLibrary = false                   /* Library visibility             */

    @State private var error: String?                         /* Reported operation failure     */
    @Environment(\.dismiss) private var dismiss               /* Close the current presentation */
    @AppStorage(StudioSettings.key) private var data = Data() /* Persisted settings bytes       */


    /// @fcn StudioSettingsView.destinationBinding(_:)
    /// @brief Bind one optional view wallpaper into the shared editor
    /// @details Removing an override preserves the destination's established background
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


    /// @fcn StudioSettingsView.save
    /// @brief Validate and commit the shared Studio draft once from any focused page
    /// @return Void; invalid palette input keeps the draft open for correction
    private func save()
    {

        let colors = palette.split(separator: ",").map /* Colors used by this appearance */
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


    /// @fcn StudioSettingsView.page
    /// @brief Build a short Studio page over the same parent-owned draft
    /// @param[in] title Focused navigation title
    /// @param[in] content Controls bound to this Studio session
    /// @return Scrollable native form; Back retains edits and Save commits the whole Studio draft
    private func page<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View
    {

        Form(content: content)
            .modifier(StudioFormWallpaper(destination: .settings))
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar
            {

                ToolbarItem(placement: .confirmationAction)
                {

                    Button("Save", action: save)
                }
            }
    }


    ///
    /// @fcn        StudioSettingsView.body
    /// @brief      Compose the native personalization interface for this destination
    /// @details    Keeps editing state within its owning view and preserves existing behavior
    ///             when no material override is configured. Decorative art stays below controls
    ///
    /// @return     (some View) accessible surface controls or resolved workspace background
    ///
    var body: some View /* Studio directory and editors */
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

            Section("Creation defaults")
            {

                NavigationLink("New item backgrounds")
                {

                    page("New Item Backgrounds")
                    {

                        StudioSurfaceSettings(surface: $draft.defaultCardSurface, title: "New Card background")
                        StudioSurfaceSettings(surface: $draft.defaultNoteSurface, title: "New Note background")
                    }
                }
                NavigationLink("Coordinated variety")
                {

                    page("Coordinated Variety")
                    {

                        Section
                        {

                            Toggle("Vary new item colors", isOn: $draft.variesNewSurfaces)
                            Toggle("Vary new item header colors", isOn: $draft.variesNewHeaders)
                            TextField("Palette: comma-separated RGB hex colors", text: $palette)
                                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        }
                        footer:
                        {

                            Text("Colors are chosen once when an item is created. Existing items keep their saved appearance.")
                        }
                    }
                }
            }
            Section("Wallpapers")
            {

                NavigationLink("View wallpapers")
                {

                    page("View Wallpapers")
                    {

                        Section
                        {

                            ForEach(StudioDestination.allCases)
                            {
                                destination in
                                NavigationLink(destination.rawValue)
                                {

                                    page(destination.rawValue + " Wallpaper")
                                    {

                                        StudioSurfaceSettings(surface: destinationBinding(destination), title: "Wallpaper")
                                    }
                                }
                            }
                        }
                    }
                }
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

                Button("Save", action: save)

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



/// Places a saved wallpaper above an existing fallback without replacing unconfigured views
/// @section Purpose
///     Shares per-view selection consistently across primary destinations and their existing safe areas
struct StudioWorkspaceBackground: View
{


    let destination: StudioDestination                        /* Destination for the operation */
    @AppStorage(StudioSettings.key) private var data = Data() /* Persisted settings bytes      */

    ///
    /// @fcn        StudioWorkspaceBackground.body
    /// @brief      Compose the native personalization interface for this destination
    /// @details    Keeps editing state within its owning view and preserves existing behavior
    ///             when no material override is configured. Decorative art stays below controls
    ///
    /// @return     (some View) accessible surface controls or resolved workspace background
    ///
    var body: some View /* Studio Workspace Background layout */
    {


        if let settings = try? JSONDecoder().decode(StudioSettings.self, from: data),
        let surface = settings.views[destination.rawValue]
        {

            StudioSurfaceView(surface: surface)
        }

    }

}



/// Applies configured wallpapers to native forms while preserving their default rendering when unset
/// @section Purpose
///     Keeps Settings wallpaper opt-in and avoids changing unconfigured form backgrounds
struct StudioFormWallpaper: ViewModifier
{


    let destination: StudioDestination                        /* Destination for the operation */
    @AppStorage(StudioSettings.key) private var data = Data() /* Persisted settings bytes      */

    ///
    /// @fcn        StudioFormWallpaper.body
    /// @brief      Compose the native personalization interface for this destination
    /// @details    Keeps editing state within its owning view and preserves existing behavior
    ///             when no material override is configured. Decorative art stays below controls
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

