// --------------------------------------------------------------------------------------------------
// @file       CardLocation.swift
// @brief      Optional Card locations and app-wide map-provider selection
// @details    Stores a place name or address without geocoding, opens a place search in the chosen
//             maps provider, and keeps location edits in a checked Save/Cancel draft. Optional
//             Apple Maps search fills that draft without committing the Card.
//
// --------------------------------------------------------------------------------------------------
import SwiftUI


///
/// Selects the maps provider used by every saved Card location
///
/// @section    Purpose
///     Uses official HTTPS place-search links so Maps owns place resolution and subsequent actions.
///     Google links open its app when available and its website otherwise; no API key is required.
///
enum PreferredMapsApp: String, Codable, CaseIterable, Identifiable, Sendable
{


    case apple, google

    var id: String
    {

        rawValue
    }


    var title: String
    {

        self == .apple ? "Apple Maps" : "Google Maps"
    }



    ///
    /// @fcn        PreferredMapsApp.placeURL
    /// @brief      Build a provider-controlled place-search link for a saved location
    /// @details    Treats all entered text as one encoded query, including punctuation and Unicode.
    ///             Never requests directions or navigation and returns nil for an empty location.
    /// @param[in]  location Optional user-entered place name or address
    /// @return     (URL?) official provider URL containing the normalized location query
    ///
    func placeURL(for location: String?) -> URL?
    {

        guard let query = CardLocation.normalized(location) else
        {

            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = self == .apple ? "maps.apple.com" : "www.google.com"
        components.path = self == .apple ? "/" : "/maps/search/"
        components.queryItems = self == .apple
        ? [URLQueryItem(name: "q", value: query)]
        : [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: query)]
        // Preserve literal plus signs when a provider decodes form-style query parameters.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

}



///
/// Normalizes optional place text without imposing an address format
///
/// @section    Purpose
///     Accepts place names and addresses, trims accidental outer whitespace, and treats empty
///     text as removal. Cards created before location support continue to have no location.
///
enum CardLocation
{


    ///
    /// @fcn        CardLocation.normalized
    /// @brief      Convert a location draft into optional persisted place text
    /// @details    Preserves internal punctuation and line breaks while discarding empty drafts.
    /// @param[in]  value Optional unnormalized place text
    /// @return     (String?) trimmed location, or nil when absent or blank
    ///
    static func normalized(_ value: String?) -> String?
    {

        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else
        {

            return nil
        }

        return trimmed
    }

}



///
/// Displays a tappable location independently of its editing control
///
/// @section    Purpose
///     Reads the current app-wide maps preference at display time. Locked and read-only Cards
///     retain their location link while hiding editing controls.
///
struct CardLocationRow: View
{


    let location: String?
    var canEdit = false
    var onEdit: () -> Void =
    {

    }

    @AppStorage(PlanPreferencesStore.key) private var preferencesData = Data()
    @AppStorage(LocalProfileStore.storageKey) private var profileData = Data()


    ///
    /// @fcn        CardLocationRow.body
    /// @brief      Render a saved place link or an Add location affordance
    /// @details    Keeps the link and pencil as separate accessible actions and supports multiline
    ///             addresses without changing the stored Card when a place is opened.
    /// @return     (some View) an optional metadata row with provider-aware place navigation
    ///
    var body: some View
    {

        let maps = PlanPreferencesStore.resolved(
            preferencesData: preferencesData, profileData: profileData).preferredMapsApp
        if let location = CardLocation.normalized(location), let url = maps.placeURL(for: location)
        {

            HStack(spacing: 10)
            {

                Image(systemName: "mappin.and.ellipse")
                .frame(width: 22)
                .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3)
                {

                    Text("Location")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Link(location, destination: url)
                    .lineLimit(3)
                    .accessibilityHint("Opens in \(maps.title)")
                    .accessibilityIdentifier("card.location.open")
                }

                Spacer(minLength: 0)
                if canEdit
                {

                    Button(action: onEdit)
                    {

                        Image(systemName: "pencil")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit location")
                    .accessibilityIdentifier("card.location.edit")
                }

            }
            .frame(minHeight: 44)
        }

        else if canEdit
        {

            Button(action: onEdit)
            {

                Label("Add location", systemImage: "mappin.and.ellipse")
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("card.location.add")
        }

    }

}



///
/// Edits a place name or address as a checked local draft
///
/// @section    Purpose
///     Saves only after explicit confirmation, supports removing an existing location, and
///     retains the draft when the owning Card cannot accept an update.
///
struct CardLocationEditorSheet: View
{


    let onSave: (String?) -> Bool
    private let hasLocation: Bool
    @State private var text: String
    @State private var saveFailed = false
    @Environment(\.dismiss) private var dismiss


    ///
    /// @fcn        CardLocationEditorSheet.init
    /// @brief      Initialize a location draft from the current Card value
    /// @details    Keeps editing local until Save or Remove is explicitly accepted by the owner.
    /// @param[in]  location Existing optional place text
    /// @param[in]  onSave   Callback accepting or rejecting the submitted location
    /// @return     (CardLocationEditorSheet) initialized location editor
    ///
    init(location: String?, onSave: @escaping (String?) -> Bool)
    {

        self.onSave = onSave
        self.hasLocation = CardLocation.normalized(location) != nil
        self._text = State(initialValue: location ?? "")
    }



    ///
    /// @fcn        CardLocationEditorSheet.save
    /// @brief      Submit a normalized draft and dismiss only after acceptance
    /// @details    A rejected update retains the text and explains that the Card was not changed.
    /// @param[in]  value Place text to retain, or nil to remove the location
    /// @return     (Void) dismisses the accepted draft or presents failure feedback
    ///
    private func save(_ value: String?)
    {

        if onSave(CardLocation.normalized(value))
        {

            dismiss()
        }

        else
        {

            saveFailed = true
        }

    }



    ///
    /// @fcn        CardLocationEditorSheet.body
    /// @brief      Present the optional place field with Save, Cancel, and Remove actions
    /// @details    Accepts manual text or an Apple Maps place selection without device-location
    ///             permission. Map selection fills this draft; Save remains the content boundary.
    /// @return     (some View) native form for editing the Card's location
    ///
    var body: some View
    {

        NavigationStack
        {

            Form
            {

                Section("Place or address")
                {

                    TextField("Enter a place or address", text: $text, axis: .vertical)
                    .lineLimit(2 ... 5)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("card.location.field")

                    NavigationLink
                    {
                        CardLocationSearchView(query: text)
                        {
                            text = $0
                        }
                        .presentationDetents([.large])
                    }
                    label:
                    {
                        Label("Find on map", systemImage: "map")
                    }
                    .accessibilityIdentifier("card.location.findOnMap")
                }

                if hasLocation
                {

                    Button("Remove location", role: .destructive)
                    {

                        save(nil)
                    }

                }

            }
            .navigationTitle("Location")
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

                        save(text)
                    }

                }

            }
            .alert("Couldn’t save location", isPresented: $saveFailed)
            {

                Button("OK", role: .cancel)
                {

                }

            }

            message:
            {

                Text("This Card could not be updated. It may have been locked or removed.")
            }

        }

    }

}



///
/// Edits the shared maps preference within either settings draft
///
/// @section    Purpose
///     Keeps provider selection consistent between Account settings and Plan settings, using
///     their existing Save and Cancel behavior rather than changing a preference on selection.
///
struct MapsAppSettingsSection: View
{


    @Binding var selection: PreferredMapsApp


    ///
    /// @fcn        MapsAppSettingsSection.body
    /// @brief      Offer Apple Maps and Google Maps as the app-wide place-link provider
    /// @details    Apple Maps is the default; the selected provider owns all subsequent map actions.
    /// @return     (some View) a settings section bound to the surrounding preference draft
    ///
    var body: some View
    {

        Section("Maps")
        {

            Picker("Preferred maps app", selection: $selection)
            {

                ForEach(PreferredMapsApp.allCases)
                {

                maps in
                    Text(maps.title).tag(maps)
                }

            }

        }

    }

}

