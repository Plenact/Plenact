// --------------------------------------------------------------------------------------------------
// @file       ProfileModels.swift
// @brief      Local profile identity and personalization models
// @details    Defines user-controlled local identity and settings without online authentication
//
// @notes      Profile data remains separate from Board persistence and never stores passwords
//
// --------------------------------------------------------------------------------------------------
import Foundation


// -------------------------------------- MARK: - Avatar Color --------------------------------- //

///
/// Stores an avatar color as sRGB components and supports legacy palette-token decoding
///
/// @section    Purpose
///     Keep profile color data Codable while allowing users to select colors beyond the built-in
///     palette
///
struct ProfileColor: Hashable, Codable {

    var red: Double /* sRGB red component */
    var green: Double /* sRGB green component */
    var blue: Double /* sRGB blue component */
    var legacyToken: String? /* Legacy palette token retained for compatible encoding */

    ///
    /// Maps the keyed RGB representation used for custom profile colors
    ///
    /// @section    Purpose
    ///     Restrict component-based color encoding to the persisted RGB fields
    ///
    private enum CodingKeys: String, CodingKey {
        case red
        case green
        case blue
    }

    ///
    /// @fcn        ProfileColor.init(red:green:blue:)
    /// @brief      Create a profile color from sRGB components
    /// @details    Stores the component values and marks the color as a custom RGB value
    ///
    /// @param[in]  red    sRGB red component
    /// @param[in]  green  sRGB green component
    /// @param[in]  blue   sRGB blue component
    ///
    /// @return     (ProfileColor) configured RGB color
    ///
    /// @post       The color has no legacy palette token
    ///
    init(red: Double, green: Double, blue: Double) {

        self.red = red
        self.green = green
        self.blue = blue
        legacyToken = nil
    }

    ///
    /// @fcn        ProfileColor.init(hue:saturation:brightness:)
    /// @brief      Create an sRGB profile color from HSB components
    /// @details    Clamps saturation and brightness to their supported unit interval before
    ///             converting the color to RGB
    ///
    /// @param[in]  hue         Hue value, wrapped to one full turn
    /// @param[in]  saturation  Saturation value, clamped to 0 through 1
    /// @param[in]  brightness Brightness value, clamped to 0 through 1
    ///
    /// @return     (ProfileColor) converted RGB color
    ///
    init(hue: Double, saturation: Double, brightness: Double) {

        let hue = (hue - floor(hue)) * 6
        let saturation = min(max(saturation, 0), 1)
        let brightness = min(max(brightness, 0), 1)
        let chroma = brightness * saturation
        let intermediate = chroma * (1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1))
        let components: (Double, Double, Double)

        switch Int(floor(hue)) {

            case 0: components = (chroma, intermediate, 0)
            case 1: components = (intermediate, chroma, 0)
            case 2: components = (0, chroma, intermediate)
            case 3: components = (0, intermediate, chroma)
            case 4: components = (intermediate, 0, chroma)
            default: components = (chroma, 0, intermediate)
        }

        let offset = brightness - chroma

        self.init(
            red: components.0 + offset,
            green: components.1 + offset,
            blue: components.2 + offset
        )
    }

    static let teal = Self(red: 0, green: 0.5, blue: 0.5, legacyToken: "teal") /* Teal palette color */
    static let blue = Self(red: 0, green: 0.478, blue: 1, legacyToken: "blue") /* Blue palette color */
    static let green = Self(red: 0, green: 0.65, blue: 0.3, legacyToken: "green") /* Green palette color */
    static let orange = Self(red: 1, green: 0.5, blue: 0, legacyToken: "orange") /* Orange palette color */
    static let graphite = Self(red: 0.5, green: 0.5, blue: 0.5, legacyToken: "graphite") /* Graphite palette color */
    static let white = Self(red: 1, green: 1, blue: 1, legacyToken: "white") /* White palette color */
    static let charcoal = Self(red: 0.12, green: 0.15, blue: 0.17, legacyToken: "charcoal") /* Charcoal palette color */
    static let lemon = Self(red: 1, green: 0.82, blue: 0.22, legacyToken: "lemon") /* Lemon palette color */
    static let sky = Self(red: 0.27, green: 0.72, blue: 0.94, legacyToken: "sky") /* Sky palette color */
    static let coral = Self(red: 0.96, green: 0.37, blue: 0.31, legacyToken: "coral") /* Coral palette color */

    ///
    /// @fcn        ProfileColor.init(red:green:blue:legacyToken:)
    /// @brief      Create a profile color associated with a legacy palette token
    /// @details    Stores the RGB components and token so compatible encoding can preserve the
    ///             older string representation
    ///
    /// @param[in]  red         sRGB red component
    /// @param[in]  green       sRGB green component
    /// @param[in]  blue        sRGB blue component
    /// @param[in]  legacyToken Known palette token for this color
    ///
    /// @return     (ProfileColor) configured palette color
    ///
    private init(red: Double, green: Double, blue: Double, legacyToken: String) {

        self.red = red
        self.green = green
        self.blue = blue
        self.legacyToken = legacyToken
    }

    ///
    /// @fcn        ProfileColor.hueSaturationBrightness
    /// @brief      Convert the stored RGB components to HSB values
    /// @details    Derives hue, saturation, and brightness from the maximum and minimum
    ///             component values
    ///
    /// @return     (tuple) hue, saturation, and brightness components
    ///
    /// @pre        RGB components contain the color to convert
    /// @post       The stored RGB components remain unchanged
    ///
    var hueSaturationBrightness: (hue: Double, saturation: Double, brightness: Double) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        let hue: Double

        if delta == 0 {

            hue = 0
        } else if maximum == red {
            hue = ((green - blue) / delta + (green < blue ? 6 : 0)) / 6
        } else if maximum == green {
            hue = ((blue - red) / delta + 2) / 6
        } else {
            hue = ((red - green) / delta + 4) / 6
        }

        return (hue, maximum == 0 ? 0 : delta / maximum, maximum)
    }

    ///
    /// @fcn        ProfileColor.init(from:)
    /// @brief      Decode a profile color from legacy or component-based data
    /// @details    Accepts known legacy palette strings or keyed sRGB component values
    ///
    /// @param[in]  decoder Source of the encoded color
    ///
    /// @return     (ProfileColor) decoded color
    ///
    /// @throws     DecodingError for an unknown legacy token; keyed-value decoder failures propagate
    ///
    init(from decoder: Decoder) throws {

        if let container = try? decoder.singleValueContainer(),
           let token = try? container.decode(String.self) {
            guard let color = Self.legacyColor(token) else {

                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown legacy profile color: \(token)"
                ))
            }

            self = color

            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            red: try container.decode(Double.self, forKey: .red),
            green: try container.decode(Double.self, forKey: .green),
            blue: try container.decode(Double.self, forKey: .blue)
        )
    }

    ///
    /// @fcn        ProfileColor.encode(to:)
    /// @brief      Encode a profile color using its compatible representation
    /// @details    Preserves recognized legacy palette tokens and encodes custom colors by RGB
    ///
    /// @param[in]  encoder  Destination for the encoded color
    ///
    /// @return     (Void) writes the color representation to the encoder
    ///
    /// @throws     Error when the encoder cannot represent the stored color value
    ///
    func encode(to encoder: Encoder) throws {

        if let legacyToken {

            var container = encoder.singleValueContainer()

            try container.encode(legacyToken)
        } else {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(red, forKey: .red)
            try container.encode(green, forKey: .green)
            try container.encode(blue, forKey: .blue)
        }
    }

    ///
    /// @fcn        ProfileColor.legacyColor(_:)
    /// @brief      Resolve a known legacy palette token
    /// @details    Maps tokens supported by older profile snapshots to their color constants
    ///
    /// @param[in]  token  Previously encoded palette name
    ///
    /// @return     (ProfileColor?) matching color, or nil for an unsupported token
    ///
    private static func legacyColor(_ token: String) -> Self? {

        switch token {

            case "teal": teal
            case "blue": blue
            case "green": green
            case "orange": orange
            case "graphite": graphite
            case "white": white
            case "charcoal": charcoal
            case "lemon": lemon
            case "sky": sky
            case "coral": coral
            default: nil
        }
    }
}

///
/// Names the profile color model for avatar backgrounds
///
/// @section    Purpose
///     Clarify the role of ProfileColor when used for an avatar's background
///
typealias ProfileAvatarColor = ProfileColor

///
/// Names the profile color model for avatar icon and initials foregrounds
///
/// @section    Purpose
///     Clarify the role of ProfileColor when used for avatar foreground content
///
typealias ProfileAvatarForegroundColor = ProfileColor


// -------------------------------------- MARK: - Avatar Icon ---------------------------------- //

///
/// Identifies a stable built-in icon choice for the local profile avatar
///
/// @section    Purpose
///     Persist icon selections using stable tokens independent of their display symbols
///
enum ProfileAvatarIcon: String, CaseIterable, Codable, Identifiable {

    case initials
    case person
    case personCircle
    case smilingFace
    case leaf
    case sun
    case moon
    case sparkles
    case bolt
    case heart
    case star
    case cloud

    ///
    /// @fcn        ProfileAvatarIcon.id
    /// @brief      Expose the icon token as its stable identity
    /// @details    Reuses the persisted raw value for identifiable icon choices
    ///
    /// @return     (String) icon identifier
    ///
    var id: String { rawValue }
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

    ///
    /// Maps local planning and presentation preference keys
    ///
    /// @section    Purpose
    ///     Keep the Codable preference field names explicit
    ///
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
    /// @post       Stored values match the provided preference selections
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

    ///
    /// @fcn        LocalProfilePreferences.init(from:)
    /// @brief      Decode profile preferences with defaults for newer fields
    /// @details    Preserves compatibility with saved preference snapshots that omit optional
    ///             values introduced by later app versions
    ///
    /// @param[in]  decoder Source of the encoded preference values
    ///
    /// @return     (LocalProfilePreferences) decoded settings
    ///
    /// @throws     DecodingError when a present value cannot be decoded
    ///
    /// @post       Missing supported preference keys receive their declared defaults
    ///
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
    var avatarColor: ProfileColor              /* Avatar background color */
    var avatarIcon:  ProfileAvatarIcon         /* Avatar icon token       */
    var avatarForegroundColor: ProfileColor   /* Icon and initials color */
    var avatarPhotoFileName: String?         /* Filename for the separately stored avatar photo */
    var preferences: LocalProfilePreferences   /* Local personalization   */

    ///
    /// Maps the local profile properties used in saved snapshots
    ///
    /// @section    Purpose
    ///     Keep the Codable profile field names explicit
    ///
    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case displayName
        case email
        case context
        case avatarColor
        case avatarIcon
        case avatarForegroundColor
        case avatarPhotoFileName
        case preferences
    }

    ///
    /// @fcn        LocalProfile.init(from:)
    /// @brief      Decode a local profile snapshot
    /// @details    Restores stable identity and local fields while applying defaults for avatar
    ///             properties absent from older profile data
    ///
    /// @param[in]  decoder Source of the encoded profile
    ///
    /// @return     (LocalProfile) decoded local profile
    ///
    /// @throws     DecodingError when required profile values cannot be decoded
    ///
    /// @post       Missing optional avatar values receive the current profile defaults
    ///
    init(from decoder: Decoder) throws {

        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            displayName: try container.decode(String.self, forKey: .displayName),
            email: try container.decode(String.self, forKey: .email),
            context: try container.decode(String.self, forKey: .context),
            avatarColor: try container.decode(ProfileColor.self, forKey: .avatarColor),
            avatarIcon: try container.decodeIfPresent(ProfileAvatarIcon.self, forKey: .avatarIcon) ?? .initials,
            avatarForegroundColor: try container.decodeIfPresent(ProfileColor.self, forKey: .avatarForegroundColor) ?? .white,
            avatarPhotoFileName: try container.decodeIfPresent(String.self, forKey: .avatarPhotoFileName),
            preferences: try container.decode(LocalProfilePreferences.self, forKey: .preferences)
        )
    }

    ///
    /// @fcn        LocalProfile.initials
    /// @brief      Build compact avatar initials from the display name
    /// @details    Uses at most the first two non-empty name components and falls back to P
    ///
    /// @return     (String) one or two uppercase avatar characters
    ///
    /// @pre        displayName contains the name text to summarize
    /// @post       Profile data remains unchanged
    ///
    var initials: String {   /* Avatar text */

        let components = displayName.split(whereSeparator: \.isWhitespace)    /* Name components */
        let characters = components.prefix(2).compactMap(\.first)             /* Initial letters */
        let initials   = String(characters).uppercased()                      /* Avatar initials */

        return initials.isEmpty ? "P" : initials
    }

    ///
    /// @fcn        LocalProfile.init(id:createdAt:displayName:email:context:avatarColor:avatarIcon:avatarForegroundColor:avatarPhotoFileName:preferences:)
    /// @brief      Initialize a local Plenact profile
    /// @details    Stores user-entered identity and settings without authentication secrets
    ///
    /// @param[in]  id           Stable local profile identifier
    /// @param[in]  createdAt    Profile creation timestamp
    /// @param[in]  displayName  User-facing display name
    /// @param[in]  email        Optional locally stored email text
    /// @param[in]  context      Optional role or planning context
    /// @param[in]  avatarColor  Selected avatar background color
    /// @param[in]  avatarIcon   Selected avatar icon token
    /// @param[in]  avatarForegroundColor Selected initials and icon foreground token
    /// @param[in]  avatarPhotoFileName Filename of the separately stored avatar photo
    /// @param[in]  preferences  Local planning and presentation settings
    ///
    /// @return     (LocalProfile) configured local identity
    ///
    /// @post       Stored values match the supplied profile fields
    ///
    init(
        id:          UUID                    = UUID(),
        createdAt:   Date                    = .now,
        displayName: String                  = "",
        email:       String                  = "",
        context:     String                  = "",
        avatarColor: ProfileColor            = .teal,
        avatarIcon:  ProfileAvatarIcon       = .initials,
        avatarForegroundColor: ProfileColor  = .white,
        avatarPhotoFileName: String? = nil,
        preferences: LocalProfilePreferences = LocalProfilePreferences()
    ) {

        self.id          = id
        self.createdAt   = createdAt
        self.displayName = displayName
        self.email       = email
        self.context     = context
        self.avatarColor = avatarColor
        self.avatarIcon  = avatarIcon
        self.avatarForegroundColor = avatarForegroundColor
        self.avatarPhotoFileName = avatarPhotoFileName
        self.preferences = preferences
    }
}