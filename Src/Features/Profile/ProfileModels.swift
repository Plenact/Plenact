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

/// Stores an arbitrary sRGB color while decoding palette tokens from older profiles
struct ProfileColor: Hashable, Codable {

    var red: Double
    var green: Double
    var blue: Double
    var legacyToken: String?

    private enum CodingKeys: String, CodingKey {
        case red
        case green
        case blue
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        legacyToken = nil
    }

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

    static let teal = Self(red: 0, green: 0.5, blue: 0.5, legacyToken: "teal")
    static let blue = Self(red: 0, green: 0.478, blue: 1, legacyToken: "blue")
    static let green = Self(red: 0, green: 0.65, blue: 0.3, legacyToken: "green")
    static let orange = Self(red: 1, green: 0.5, blue: 0, legacyToken: "orange")
    static let graphite = Self(red: 0.5, green: 0.5, blue: 0.5, legacyToken: "graphite")
    static let white = Self(red: 1, green: 1, blue: 1, legacyToken: "white")
    static let charcoal = Self(red: 0.12, green: 0.15, blue: 0.17, legacyToken: "charcoal")
    static let lemon = Self(red: 1, green: 0.82, blue: 0.22, legacyToken: "lemon")
    static let sky = Self(red: 0.27, green: 0.72, blue: 0.94, legacyToken: "sky")
    static let coral = Self(red: 0.96, green: 0.37, blue: 0.31, legacyToken: "coral")

    private init(red: Double, green: Double, blue: Double, legacyToken: String) {
        self.red = red
        self.green = green
        self.blue = blue
        self.legacyToken = legacyToken
    }

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

typealias ProfileAvatarColor = ProfileColor
typealias ProfileAvatarForegroundColor = ProfileColor


// -------------------------------------- MARK: - Avatar Icon ---------------------------------- //

/// Identifies a stable built-in icon choice for the local profile avatar
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
    var avatarColor: ProfileColor              /* Avatar background color */
    var avatarIcon:  ProfileAvatarIcon         /* Avatar icon token       */
    var avatarForegroundColor: ProfileColor   /* Icon and initials color */
    var preferences: LocalProfilePreferences   /* Local personalization   */

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case displayName
        case email
        case context
        case avatarColor
        case avatarIcon
        case avatarForegroundColor
        case preferences
    }

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
    var initials: String {   /* Avatar text */

        let components = displayName.split(whereSeparator: \.isWhitespace)    /* Name components */
        let characters = components.prefix(2).compactMap(\.first)             /* Initial letters */
        let initials   = String(characters).uppercased()                      /* Avatar initials */

        return initials.isEmpty ? "P" : initials
    }

    ///
    /// @fcn        LocalProfile.init(id:createdAt:displayName:email:context:avatarColor:avatarIcon:avatarForegroundColor:preferences:)
    /// @brief      Initialize a local Plenact profile
    /// @details    Stores user-entered identity and settings without authentication secrets
    ///
    /// @param[in]  id           Stable local profile identifier
    /// @param[in]  createdAt    Profile creation timestamp
    /// @param[in]  displayName  User-facing display name
    /// @param[in]  email        Optional locally stored email text
    /// @param[in]  context      Optional role or planning context
    /// @param[in]  avatarColor  Selected avatar palette token
    /// @param[in]  avatarIcon   Selected avatar icon token
    /// @param[in]  avatarForegroundColor Selected initials and icon foreground token
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
        avatarColor: ProfileColor            = .teal,
        avatarIcon:  ProfileAvatarIcon       = .initials,
        avatarForegroundColor: ProfileColor  = .white,
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
        self.preferences = preferences
    }
}