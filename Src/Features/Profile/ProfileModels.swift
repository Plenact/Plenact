// -------------------------------------------------------------------------------------------------
// @file       ProfileModels.swift
// @brief      Local profile identity and personalization models
// @details    Defines user-controlled local identity and settings without online authentication
//
// @notes      Profile data remains separate from Board persistence and never stores passwords
//
// -------------------------------------------------------------------------------------------------
import Foundation


// -------------------------------------- MARK: - Avatar Color --------------------------------- //

///
/// Identifies a persistent palette choice for the local profile avatar
///
/// @section    Purpose
///     Store a stable color token without coupling the profile model to SwiftUI
///
enum ProfileAvatarColor: String, CaseIterable, Codable, Identifiable {

    case teal       /* Calm teal avatar   */
    case blue       /* Familiar blue      */
    case green      /* Focus green        */
    case orange     /* Warm orange        */
    case graphite   /* Neutral graphite   */

    ///
    /// @fcn        ProfileAvatarColor.id
    /// @brief      Return the stable palette identity
    /// @details    Uses the Codable raw value for picker and persistence consistency
    ///
    /// @return     (String) stable avatar-color identifier
    ///
    var id: String { rawValue }   /* Picker identity */
}


// -------------------------------------- MARK: - Preferences ---------------------------------- //

///
/// Stores user-controlled local presentation and planning preferences
///
/// @section    Purpose
///     Keep personalization separate from identity and Board domain data
///
struct LocalProfilePreferences: Hashable, Codable {

    var defaultListID:       Int?   /* Preferred Today list   */
    var usesReducedContent:  Bool   /* Hide supporting copy   */
    var usesLargeControls:   Bool   /* Use taller key actions */
    var showsNavigationLabels: Bool /* Show labels beneath navigation icons */

    private enum CodingKeys: String, CodingKey {
        case defaultListID
        case usesReducedContent
        case usesLargeControls
        case showsNavigationLabels
    }

    ///
    /// @fcn        LocalProfilePreferences.init(defaultListID:usesReducedContent:usesLargeControls:showsNavigationLabels:)
    /// @brief      Initialize local planning and presentation preferences
    /// @details    Defaults preserve the current Today experience until the user chooses otherwise
    ///
    /// @param[in]  defaultListID       Optional preferred Board list for Today
    /// @param[in]  usesReducedContent  Whether supporting Today copy is hidden
    /// @param[in]  usesLargeControls   Whether primary Today controls use additional height
    /// @param[in]  showsNavigationLabels Whether primary navigation icons include text labels
    ///
    /// @return     (LocalProfilePreferences) configured personalization values
    ///
    init(
        defaultListID: Int? = nil,
        usesReducedContent: Bool = false,
        usesLargeControls: Bool = false,
        showsNavigationLabels: Bool = true
    ) {

        self.defaultListID      = defaultListID
        self.usesReducedContent = usesReducedContent
        self.usesLargeControls  = usesLargeControls
        self.showsNavigationLabels = showsNavigationLabels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self) /* Saved preference fields */
        self.init(
            defaultListID: try container.decodeIfPresent(Int.self, forKey: .defaultListID),
            usesReducedContent: try container.decodeIfPresent(Bool.self, forKey: .usesReducedContent) ?? false,
            usesLargeControls: try container.decodeIfPresent(Bool.self, forKey: .usesLargeControls) ?? false,
            showsNavigationLabels: try container.decodeIfPresent(Bool.self, forKey: .showsNavigationLabels) ?? true
        )
    }
}


// -------------------------------------- MARK: - Local Profile -------------------------------- //

///
/// Represents one local-only Plenact identity on the current installation
///
/// @section    Purpose
///     Provide avatar, profile information, and personalization without credentials, accounts,
///     network access, or ownership changes to existing Board data
///
struct LocalProfile: Identifiable, Hashable, Codable {

    let id:          UUID                      /* Stable local profile ID */
    let createdAt:   Date                      /* Profile creation date   */
    var displayName: String                    /* User-facing name        */
    var email:       String                    /* Optional local email    */
    var context:     String                    /* Optional planning role  */
    var avatarColor: ProfileAvatarColor        /* Avatar palette token    */
    var preferences: LocalProfilePreferences   /* Local personalization   */

    ///
    /// @fcn        LocalProfile.initials
    /// @brief      Build compact avatar initials from the display name
    /// @details    Uses at most the first two non-empty name components and falls back to P
    ///
    /// @return     (String) one or two uppercase avatar characters
    ///
    var initials: String {   /* Avatar text */

        let components = displayName.split(whereSeparator: \.isWhitespace)    /* Name components */
        let characters = components.prefix(2).compactMap(\.first)             /* Initial letters */
        let initials   = String(characters).uppercased()                      /* Avatar initials */

        return initials.isEmpty ? "P" : initials
    }

    ///
    /// @fcn        LocalProfile.init(id:createdAt:displayName:email:context:avatarColor:preferences:)
    /// @brief      Initialize a local Plenact profile
    /// @details    Stores user-entered identity and settings without authentication secrets
    ///
    /// @param[in]  id           Stable local profile identifier
    /// @param[in]  createdAt    Profile creation timestamp
    /// @param[in]  displayName  User-facing display name
    /// @param[in]  email        Optional locally stored email text
    /// @param[in]  context      Optional role or planning context
    /// @param[in]  avatarColor  Selected avatar palette token
    /// @param[in]  preferences  Local planning and presentation settings
    ///
    /// @return     (LocalProfile) configured local identity
    ///
    init(
        id:          UUID                    = UUID(),
        createdAt:   Date                    = .now,
        displayName: String                  = "",
        email:       String                  = "",
        context:     String                  = "",
        avatarColor: ProfileAvatarColor      = .teal,
        preferences: LocalProfilePreferences = LocalProfilePreferences()
    ) {

        self.id          = id
        self.createdAt   = createdAt
        self.displayName = displayName
        self.email       = email
        self.context     = context
        self.avatarColor = avatarColor
        self.preferences = preferences
    }
}