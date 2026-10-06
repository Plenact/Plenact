// --------------------------------------------------------------------------------------------------
// @file       LocalProfileStore.swift
// @brief      Local profile persistence
// @details    Encodes one optional local profile without accounts, passwords, or network access
//
// --------------------------------------------------------------------------------------------------
import Foundation


// -------------------------------------- MARK: - Profile Store -------------------------------- //

///
/// Loads, saves, and removes the local profile on the current installation
///
/// @section    Purpose
///     Isolate local profile persistence from authentication, credentials, network access, and
///     the app's Board data
///
/// @note   Removing the profile never removes Board, label, or attachment data
///
enum LocalProfileStore {

    private static let storageKey = "Plenact.LocalProfile.v1"   /* Versioned profile key */

    ///
    /// @fcn        LocalProfileStore.load(from:)
    /// @brief      Load the locally saved profile
    /// @details    Returns no profile when the key is absent or stored data cannot be decoded
    ///
    /// @param[in]  defaults  Preference store containing local profile data
    ///
    /// @return     (LocalProfile?) decoded local profile when available
    ///
    /// @pre        defaults is available to the current process
    /// @post       Stored data remains unchanged
    ///
    static func load(from defaults: UserDefaults = .standard) -> LocalProfile? {

        guard let data = defaults.data(forKey: storageKey) else {

            return nil
        } /* Stored profile bytes */

        return try? JSONDecoder().decode(LocalProfile.self, from: data)
    }


    ///
    /// @fcn        LocalProfileStore.save(_:to:)
    /// @brief      Save the complete local profile snapshot
    /// @details    Replaces only the profile preference value after successful encoding
    ///
    /// @param[in]  profile   Local identity and personalization to store
    /// @param[in]  defaults  Preference store receiving encoded profile data
    ///
    /// @return     (Void) persists the profile when encoding succeeds
    ///
    /// @pre        profile contains valid local-only values
    /// @post       Existing Board and feature persistence remains unchanged
    ///
    static func save(_ profile: LocalProfile, to defaults: UserDefaults = .standard) {

        guard let data = try? JSONEncoder().encode(profile) else {

            return
        } /* Encoded profile snapshot */

        defaults.set(data, forKey: storageKey)
    }


    ///
    /// @fcn        LocalProfileStore.remove(from:)
    /// @brief      Remove only the local profile snapshot
    /// @details    Clears local identity and personalization without deleting user Board content
    ///
    /// @param[in]  defaults  Preference store containing local profile data
    ///
    /// @return     (Void) removes the versioned local profile value
    ///
    /// @post       Board, labels, attachments, and Today selections remain available
    ///
    static func remove(from defaults: UserDefaults = .standard) {

        defaults.removeObject(forKey: storageKey)
    }
}


///
/// Stores avatar photo bytes separately from the Codable local profile
///
/// @section    Purpose
///     Keep image data in the app container while the profile stores only its filename
///
enum ProfileAvatarPhotoStore {

    ///
    /// @fcn        ProfileAvatarPhotoStore.directory()
    /// @brief      Resolve and create the local avatar-photo directory
    /// @details    Uses the app's Documents directory and creates the ProfileAvatars subdirectory
    ///
    /// @return     (URL) app-local avatar photo directory
    ///
    /// @throws     File-system error when the Documents directory cannot be resolved or created
    ///
    private static func directory() throws -> URL {

        let documents = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let directory = documents.appendingPathComponent("ProfileAvatars", isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return directory
    }


    ///
    /// @fcn        ProfileAvatarPhotoStore.save(_:)
    /// @brief      Save avatar photo data in the app's local photo directory
    /// @details    Writes the data atomically to a unique JPEG-named file
    ///
    /// @param[in]  data  Avatar photo bytes to persist
    ///
    /// @return     (String) unique filename for the saved photo
    ///
    /// @throws     File-system error when directory creation or file writing fails
    ///
    static func save(_ data: Data) throws -> String {

        let fileName = "\(UUID().uuidString).jpg"

        try data.write(to: directory().appendingPathComponent(fileName), options: .atomic)

        return fileName
    }


    ///
    /// @fcn        ProfileAvatarPhotoStore.load(_:)
    /// @brief      Load a locally stored avatar photo
    /// @details    Accepts only a single filename component before reading from the avatar
    ///             directory
    ///
    /// @param[in]  fileName  Stored avatar filename, when available
    ///
    /// @return     (Data?) photo bytes when the file can be read, otherwise nil
    ///
    /// @pre        fileName is a filename previously returned by save(_:)
    /// @post       The stored photo is unchanged
    ///
    static func load(_ fileName: String?) -> Data? {

        guard let fileName, fileName == URL(fileURLWithPath: fileName).lastPathComponent,
              let directory = try? directory() else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(fileName))
    }


    ///
    /// @fcn        ProfileAvatarPhotoStore.remove(_:)
    /// @brief      Remove a locally stored avatar photo
    /// @details    Resolves only a single filename component within the avatar directory
    ///
    /// @param[in]  fileName  Stored avatar filename, when available
    ///
    /// @return     (Void) removes the matching file when it can be resolved
    ///
    /// @pre        fileName identifies a photo stored by this store
    /// @post       Other local profile, Board, label, and attachment data is unchanged
    ///
    static func remove(_ fileName: String?) {

        guard let fileName, fileName == URL(fileURLWithPath: fileName).lastPathComponent,
              let directory = try? directory() else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
    }
}

