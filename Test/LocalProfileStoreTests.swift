// -------------------------------------------------------------------------------------------------
// @file       LocalProfileStoreTests.swift
// @brief      Local profile persistence tests
// @details    Verifies profile round trips and removal without using production preferences
//
// -------------------------------------------------------------------------------------------------
import XCTest
import UIKit
import CoreImage
@testable import Plenact


///
/// Verifies local profile identity and personalization persistence
///
/// @section    Purpose
///     Protect the local-only session boundary before UI or future authentication integrations
///
final class LocalProfileStoreTests: XCTestCase {

    private var defaults: UserDefaults!   /* Isolated test preferences */
    private let suiteName = "Plenact.LocalProfileStoreTests"   /* Test suite key */

    ///
    /// @fcn        LocalProfileStoreTests.setUp
    /// @brief      Create an empty isolated preference suite
    /// @details    Prevents profile tests from reading or changing application preferences
    ///
    override func setUp() {
        super.setUp()

        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    ///
    /// @fcn        LocalProfileStoreTests.tearDown
    /// @brief      Remove isolated profile-test preferences
    /// @details    Leaves no profile fixture data after each test
    ///
    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil

        super.tearDown()
    }

    ///
    /// @fcn        LocalProfileStoreTests.testProfileRoundTripPreservesPersonalization
    /// @brief      Round-trip local identity and settings
    /// @details    Verifies every user-controlled field survives encoding and decoding
    ///
    /// @return     (Void) succeeds when the loaded profile equals the saved profile
    ///
    func testProfileRoundTripPreservesPersonalization() throws {

        let profile = LocalProfile(   /* Complete profile fixture */
            id:          UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
            createdAt:   Date(timeIntervalSince1970: 1_790_467_200),
            displayName: "Jamie Rivera",
            email:       "jamie@example.com",
            context:     "Personal planning",
            avatarColor: ProfileColor(hue: 0.37, saturation: 0.72, brightness: 0.88),
            avatarIcon:  .sparkles,
            avatarForegroundColor: ProfileColor(hue: 0.94, saturation: 0.58, brightness: 0.91),
            avatarPhotoFileName: "profile-photo.jpg",
            preferences: LocalProfilePreferences(
                defaultListID:      3,
                usesReducedContent: true,
                usesLargeControls:  true,
                showsNavigationLabels: false
            )
        )

        LocalProfileStore.save(profile, to: defaults)

        XCTAssertEqual(LocalProfileStore.load(from: defaults), profile)
    }

    /// Verify profiles saved before navigation-label preference was added keep labels visible
    func testOlderPreferencesDefaultToShowingNavigationLabels() throws {

        let legacyPreferencesJSON = Data(
            #"{"defaultListID":3,"usesReducedContent":false,"usesLargeControls":false}"#.utf8
        ) /* Preferences snapshot without navigation-caption field */
        let preferences = try JSONDecoder().decode(LocalProfilePreferences.self, from: legacyPreferencesJSON)

        XCTAssertTrue(preferences.showsNavigationLabels)
    }

    func testOlderProfilesDefaultToInitialsAvatar() throws {

        let legacyProfileJSON = Data(
            #"{"id":"EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE","createdAt":0,"displayName":"Jamie Rivera","email":"","context":"","avatarColor":"teal","preferences":{}}"#.utf8
        )
        let profile = try JSONDecoder().decode(LocalProfile.self, from: legacyProfileJSON)

        XCTAssertEqual(profile.avatarIcon, .initials)
        XCTAssertEqual(profile.avatarForegroundColor, .white)
        XCTAssertNil(profile.avatarPhotoFileName)
    }

    func testLegacyAvatarColorTokensStillDecode() throws {

        let legacyProfileJSON = Data(
            #"{"id":"EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE","createdAt":0,"displayName":"Jamie Rivera","email":"","context":"","avatarColor":"teal","avatarIcon":"leaf","avatarForegroundColor":"coral","preferences":{}}"#.utf8
        )
        let profile = try JSONDecoder().decode(LocalProfile.self, from: legacyProfileJSON)

        XCTAssertEqual(profile.avatarColor, .teal)
        XCTAssertEqual(profile.avatarIcon, .leaf)
        XCTAssertEqual(profile.avatarForegroundColor, .coral)
    }

    ///
    /// @fcn        LocalProfileStoreTests.testRemoveClearsOnlyProfileValue
    /// @brief      Remove a local profile from isolated preferences
    /// @details    Confirms the store returns no profile after deletion
    ///
    /// @return     (Void) succeeds when the profile value is absent
    ///
    func testRemoveClearsOnlyProfileValue() {

        let profile = LocalProfile(displayName: "Jamie Rivera")   /* Saved profile */

        LocalProfileStore.save(profile, to: defaults)
        LocalProfileStore.remove(from: defaults)

        XCTAssertNil(LocalProfileStore.load(from: defaults))
    }

    ///
    /// @fcn        LocalProfileStoreTests.testInitialsUseTwoNameComponents
    /// @brief      Build compact avatar text from a local display name
    /// @details    Verifies the avatar avoids exposing full profile information on Today
    ///
    /// @return     (Void) succeeds when initials are compact and uppercase
    ///
    func testInitialsUseTwoNameComponents() {
        XCTAssertEqual(LocalProfile(displayName: "Jamie Lee Rivera").initials, "JL")
        XCTAssertEqual(LocalProfile(displayName: "").initials, "P")
    }

    func testAvatarPhotoFileRoundTripAndRemoval() throws {
        let data = Data([1, 2, 3, 4])
        let fileName = try ProfileAvatarPhotoStore.save(data)
        defer { ProfileAvatarPhotoStore.remove(fileName) }

        XCTAssertEqual(ProfileAvatarPhotoStore.load(fileName), data)
        XCTAssertNil(ProfileAvatarPhotoStore.load("../outside.jpg"))
        ProfileAvatarPhotoStore.remove(fileName)
        XCTAssertNil(ProfileAvatarPhotoStore.load(fileName))
    }

    func testAvatarCropConstrainsPanToImageEdges() {
        XCTAssertEqual(
            AvatarPhotoCrop.constrainedOffset(
                CGSize(width: 500, height: -500),
                imageSize: CGSize(width: 200, height: 100), side: 100, zoom: 1
            ),
            CGSize(width: 50, height: 0)
        )
        XCTAssertEqual(
            AvatarPhotoCrop.constrainedOffset(
                CGSize(width: -500, height: 500),
                imageSize: CGSize(width: 100, height: 200), side: 100, zoom: 2
            ),
            CGSize(width: -50, height: 150)
        )
    }

    func testAvatarCropExportsSelectedRegionAsBoundedJPEG() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
        }
        let data = try XCTUnwrap(AvatarPhotoCrop.jpeg(
            image: image, side: 100, zoom: 1, offset: CGSize(width: 50, height: 0)
        ))
        let croppedImage = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(croppedImage.size, CGSize(width: 512, height: 512))
        let colorImage = try XCTUnwrap(CIImage(data: data))
        let average = try XCTUnwrap(colorImage.applyingFilter("CIAreaAverage", parameters: [
            kCIInputExtentKey: CIVector(cgRect: colorImage.extent)
        ]).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)) as CIImage?)
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            CIContext().render(
                average, toBitmap: buffer.baseAddress!, rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }
        XCTAssertGreaterThan(pixel[0], 240)
        XCTAssertLessThan(pixel[2], 15)
        XCTAssertNil(AvatarPhotoCrop.image(from: Data([1, 2, 3])))
    }
}