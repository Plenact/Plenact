// --------------------------------------------------------------------------------------------------
// @file       StudioUnsplash.swift
// @brief      Optional credited Unsplash search and selection
// @details    Keeps the access key in Keychain, hotlinks provider images, and tracks selection before
//             applying artwork. Unsplash photos are not copied into the offline artwork directory.
// --------------------------------------------------------------------------------------------------
import Security
import SwiftUI


/// Provides checked requests to the optional online photography catalog.
/// @section Purpose
///     Restricts credential-bearing requests to the Unsplash API and preserves provider credits.
enum StudioUnsplash
{


    private static let service = "com.plenact.studio.unsplash"


    /// @fcn StudioUnsplash.key()
    /// @brief Read the locally configured developer access key
    /// @details Never embeds credentials in URLs, Card history, or saved artwork.
    /// @return (String) configured key or an empty string
    static func key() -> String
    {


        var value: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecReturnData as String: true]
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
        let data = value as? Data else
        {
            return ""
        }

        return String(data: data, encoding: .utf8) ?? ""
    }



    /// @fcn StudioUnsplash.saveKey(_:)
    /// @brief Store or clear the provider access key securely
    /// @details Uses a device-only Keychain item and reports failures instead of silently losing configuration.
    /// @param[in] key Access key entered in the provider configuration screen
    /// @return (Void) updates local Keychain configuration
    /// @throws Keychain write failures propagate to the configuration UI.
    static func saveKey(_ key: String) throws
    {


        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty
        {
            SecItemDelete(query as CFDictionary);
            return
        }

        let values: [String: Any] = [kSecValueData as String: Data(cleaned.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let updated = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if updated == errSecItemNotFound
        {

            guard SecItemAdd(query.merging(values)
                {
                _, new in
                    new
                }
                as CFDictionary, nil) == errSecSuccess
            else
            {
                throw CocoaError(.fileWriteUnknown)
            }

        }

        else if updated != errSecSuccess
        {
            throw CocoaError(.fileWriteUnknown)
        }

    }



    /// @fcn StudioUnsplash.request(_:)
    /// @brief Send one credential-bearing provider API request
    /// @details Requires HTTPS and the exact API host, checks HTTP status, and leaves CDN image loading separate.
    /// @param[in] url Approved API endpoint
    /// @return (Data) response bytes
    /// @throws Invalid hosts, missing configuration, and HTTP/network errors propagate to the picker.
    static func request(_ url: URL) async throws -> Data
    {


        guard url.scheme == "https", url.host == "api.unsplash.com", !key().isEmpty else
        {
            throw URLError(.userAuthenticationRequired)
        }

        var request = URLRequest(url: url)
        request.setValue("Client-ID " + key(), forHTTPHeaderField: "Authorization")
        request.setValue("v1", forHTTPHeaderField: "Accept-Version")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else
        {
            throw URLError(.badServerResponse)
        }

        return data
    }



    /// @fcn StudioUnsplash.search(_:)
    /// @brief Search a bounded page of provider photographs
    /// @details Validates CDN and profile hosts before making results selectable.
    /// @param[in] query User-entered search text
    /// @return ([StudioRemotePhoto]) credited photo references
    /// @throws Request or response validation failures propagate without changing artwork.
    static func search(_ query: String) async throws -> [StudioRemotePhoto]
    {


        var url = URLComponents(string: "https://api.unsplash.com/search/photos")!
        url.queryItems = [URLQueryItem(name: "query", value: query), URLQueryItem(name: "per_page", value: "20")]
        let data = try await request(url.url!)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (object? ["results"] as? [[String: Any]] ?? []).compactMap
        {

        photo in
            guard let id = photo["id"] as? String,
            let urls = photo["urls"] as? [String: String], let imageText = urls["regular"],
            let image = URL(string: imageText), image.scheme == "https", image.host == "images.unsplash.com",
            let links = photo["links"] as? [String: String], let downloadText = links["download_location"],
            let download = URL(string: downloadText), download.host == "api.unsplash.com", download.scheme == "https",
            let user = photo["user"] as? [String: Any], let name = user["name"] as? String,
            let userLinks = user["links"] as? [String: String], let profileText = userLinks["html"],
            var profile = URLComponents(string: profileText), profile.host == "unsplash.com", profile.scheme == "https"
            else
            {
                return nil
            }

            profile.queryItems = [URLQueryItem(name: "utm_source", value: "plenact"),
                URLQueryItem(name: "utm_medium", value: "referral")]
            guard let profileURL = profile.url else
            {
                return nil
            }

            return StudioRemotePhoto(id: id, imageURL: image, photographer: name, profileURL: profileURL,
                downloadURL: download)
        }

    }

}



/// Searches and selects credited online photos after optional provider configuration.
/// @section Purpose
///     Keeps failed or cancelled searches from applying an image; the final surface editor tracks each use.
struct StudioUnsplashPicker: View
{


    let onSelect: (StudioRemotePhoto) -> Void
    @State private var query = ""
    @State private var key = StudioUnsplash.key()
    @State private var photos: [StudioRemotePhoto] = []
    @State private var isBusy = false
    @State private var error:       String?
    @State private var requestTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    ///
    /// @fcn        StudioUnsplashPicker.body
    /// @brief      Compose the native personalization interface for this destination
    /// @details    Keeps editing state within its owning view and preserves existing behavior
    ///             when no material override is configured. Decorative art stays below controls.
    ///
    /// @return     (some View) accessible surface controls or resolved workspace background
    ///
    var body: some View
    {


        NavigationStack
        {

            List
            {

                Section("Unsplash configuration")
                {

                    SecureField("Developer access key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save key")
                    {

                        do
                        {
                            try StudioUnsplash.saveKey(key)
                        }

                        catch
                        {
                            self.error = error.localizedDescription
                        }

                    }

                    Link("Create an Unsplash developer application", destination: URL(string: "https://unsplash.com/developers")!)
                    Text("Online photos retain linked photographer credits. Configure your application's access key to enable search.")
                    .font(.caption)
                }

                Section("Find a photograph")
                {

                    TextField("Forest, sea, quiet textures…", text: $query).submitLabel(.search)
                    Button("Search")
                    {

                        requestTask?.cancel()
                        requestTask = Task
                        {

                            isBusy = true
                            defer
                            {
                                isBusy = false
                            }

                            do
                            {
                                photos = try await StudioUnsplash.search(query)
                            }

                            catch is CancellationError
                            {

                            }

                            catch
                            {
                                self.error = "Search failed. Check the access key, connection, and API quota."
                            }

                        }

                    }
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
                    if isBusy
                    {
                        ProgressView()
                    }

                    if let error
                    {
                        Text(error).foregroundStyle(.red)
                    }

                }

                ForEach(photos, id: \.id)
                {

                photo in
                    VStack(alignment: .leading)
                    {

                        AsyncImage(url: photo.imageURL)
                        {
                        image in
                            image.resizable().scaledToFill()
                        }

                        placeholder:
                        {
                            Color(.secondarySystemBackground)
                        }
                        .frame(height: 140).clipped()
                        HStack
                        {

                            Link(photo.photographer, destination: photo.profileURL)
                            Link("on Unsplash", destination: URL(string: "https://unsplash.com/?utm_source=plenact&utm_medium=referral")!)
                        }
                        .font(.caption)
                        Button("Use this photo")
                        {

                            onSelect(photo)
                            dismiss()
                        }
                        .disabled(isBusy)
                    }

                }

            }
            .navigationTitle("Unsplash")
            .toolbar
            {
                ToolbarItem(placement: .cancellationAction)
                {
                    Button("Cancel")
                    {
                        dismiss()
                    }

                }

            }
            .onDisappear
            {
                requestTask?.cancel()
            }

        }

    }

}

