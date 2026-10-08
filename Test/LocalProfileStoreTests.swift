// --------------------------------------------------------------------------------------------------
// @file       LocalProfileStoreTests.swift
// @brief      Local profile persistence tests
// @details    Exercises local profile round trips, legacy preference/color decoding, avatar
//             file storage, and synthetic photo cropping. Profile values use isolated preferences;
//             the avatar-file test creates and removes its own fixture through the photo store
//
// @notes      Local identity is not authentication. These tests do not contact a remote service
//
// --------------------------------------------------------------------------------------------------
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
    /// @fcn        LocalProfileStoreTests.setUp()
    /// @brief      Create an empty isolated preference suite
    /// @details    Prevents profile tests from reading or changing application preferences
    ///
    /// @return     (Void) create an empty isolated preference suite
    ///
    override func setUp() {

        super.setUp()

        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }


    ///
    /// @fcn        LocalProfileStoreTests.tearDown()
    /// @brief      Remove isolated profile-test preferences
    /// @details    Leaves no profile fixture data after each test
    ///
    /// @return     (Void) remove isolated profile-test preferences
    ///
    override func tearDown() {

        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil

        super.tearDown()
    }


    ///
    /// @fcn        LocalProfileStoreTests.testProfileRoundTripPreservesPersonalization()
    /// @brief      Round-trip local identity and settings
    /// @details    Verifies every user-controlled field survives encoding and decoding
    ///
    /// @return     (Void) succeeds when the loaded profile equals the saved profile
    ///
    /// @throws     Propagates fixture setup, unwrap, or operation errors to XCTest
    ///
    func testProfileRoundTripPreservesPersonalization() throws {

        let profile = LocalProfile(   /* Complete profile fixture */
            id:          UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
            createdAt:             Date(timeIntervalSince1970: 1_790_467_200),
            displayName:           "Jamie Rivera",
            email:                 "jamie@example.com",
            context:               "Personal planning",
            avatarColor:           ProfileColor(hue: 0.37, saturation: 0.72, brightness: 0.88),
            avatarIcon:            .sparkles,
            avatarForegroundColor: ProfileColor(hue: 0.94, saturation: 0.58, brightness: 0.91),
            avatarPhotoFileName:   "profile-photo.jpg",
            preferences:           LocalProfilePreferences(
                defaultListID:         3,
                usesReducedContent:    true,
                usesLargeControls:     true,
                showsNavigationLabels: false
            )
        )

        LocalProfileStore.save(profile, to: defaults)

        XCTAssertEqual(LocalProfileStore.load(from: defaults), profile)
    }


    ///
    /// @fcn        LocalProfileStoreTests.testOlderPreferencesDefaultToShowingNavigationLabels()
    /// @brief      Preserve navigation captions for older preference snapshots
    /// @details    Decodes JSON without the caption field and checks the compatibility default
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     JSON decoding errors
    ///
    func testOlderPreferencesDefaultToShowingNavigationLabels() throws {

        let legacyPreferencesJSON = Data(
            #"{"defaultListID":3,"usesReducedContent":false,"usesLargeControls":false}"#.utf8
        ) /* Preferences snapshot without navigation-caption field */

        let preferences = try JSONDecoder().decode(LocalProfilePreferences.self, from: legacyPreferencesJSON) /* Preferences decoded without navigation-label settings */

        XCTAssertTrue(preferences.showsNavigationLabels)
    }


    ///
    /// @fcn        LocalProfileStoreTests.testOlderProfilesDefaultToInitialsAvatar()
    /// @brief      Supply avatar defaults for profiles saved before avatar options existed
    /// @details    Checks initials, white foreground, and the absence of a photo reference
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     JSON decoding errors
    ///
    func testOlderProfilesDefaultToInitialsAvatar() throws {

        let legacyProfileJSON = Data( /* Legacy profile JSON without avatar options */
            #"{"id":"EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE","createdAt":0,"displayName":"Jamie Rivera","email":"","context":"","avatarColor":"teal","preferences":{}}"#.utf8
        )

        let profile = try JSONDecoder().decode(LocalProfile.self, from: legacyProfileJSON) /* Profile decoded with initials-avatar defaults */

        XCTAssertEqual(profile.avatarIcon,            .initials)
        XCTAssertEqual(profile.avatarForegroundColor, .white)
        XCTAssertNil(profile.avatarPhotoFileName)
    }


    ///
    /// @fcn        LocalProfileStoreTests.testLegacyAvatarColorTokensStillDecode()
    /// @brief      Retain named-color compatibility in saved profiles
    /// @details    Verifies legacy teal/coral tokens and the leaf icon decode together
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     JSON decoding errors
    ///
    func testLegacyAvatarColorTokensStillDecode() throws {

        let legacyProfileJSON = Data( /* Legacy profile JSON with named-color tokens */
            #"{"id":"EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE","createdAt":0,"displayName":"Jamie Rivera","email":"","context":"","avatarColor":"teal","avatarIcon":"leaf","avatarForegroundColor":"coral","preferences":{}}"#.utf8
        )

        let profile = try JSONDecoder().decode(LocalProfile.self, from: legacyProfileJSON) /* Profile decoded with legacy named colors */

        XCTAssertEqual(profile.avatarColor,           .teal)
        XCTAssertEqual(profile.avatarIcon,            .leaf)
        XCTAssertEqual(profile.avatarForegroundColor, .coral)
    }


    ///
    /// @fcn        LocalProfileStoreTests.testRemoveClearsOnlyProfileValue()
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
    /// @fcn        LocalProfileStoreTests.testInitialsUseTwoNameComponents()
    /// @brief      Build compact avatar text from a local display name
    /// @details    Verifies the avatar avoids exposing full profile information on Today
    ///
    /// @return     (Void) succeeds when initials are compact and uppercase
    ///
    func testInitialsUseTwoNameComponents() {

        XCTAssertEqual(LocalProfile(displayName: "Jamie Lee Rivera").initials, "JL")
        XCTAssertEqual(LocalProfile(displayName: "").initials,                 "P")
    }


    ///
    /// @fcn        LocalProfileStoreTests.testAvatarPhotoFileRoundTripAndRemoval()
    /// @brief      Verify avatar bytes can be saved, loaded, and removed
    /// @details    Uses synthetic bytes, rejects a traversal filename, and cleans up its own file
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Avatar file creation errors
    ///
    func testAvatarPhotoFileRoundTripAndRemoval() throws {

        let data = Data([1, 2, 3, 4]) /* Synthetic avatar-image bytes */
        let fileName = try ProfileAvatarPhotoStore.save(data) /* Stored avatar filename */

        defer {

            ProfileAvatarPhotoStore.remove(fileName)
        }

        XCTAssertEqual(ProfileAvatarPhotoStore.load(fileName), data)
        XCTAssertNil(ProfileAvatarPhotoStore.load("../outside.jpg"))

        ProfileAvatarPhotoStore.remove(fileName)

        XCTAssertNil(ProfileAvatarPhotoStore.load(fileName))
    }


    ///
    /// @fcn        LocalProfileStoreTests.testAvatarCropConstrainsPanToImageEdges()
    /// @brief      Bound photo panning at different aspect ratios and zoom levels
    /// @details    Compares clamped offsets against exact horizontal and vertical limits
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
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


    ///
    /// @fcn        LocalProfileStoreTests.testAvatarCropExportsSelectedRegionAsBoundedJPEG()
    /// @brief      Verify crop dimensions and the selected region of a synthetic image
    /// @details    Renders red/blue halves, exports the offset crop, and measures its average color
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     XCTest unwrap failures if image export or decoding fails
    ///
    func testAvatarCropExportsSelectedRegionAsBoundedJPEG() throws {

        let format = UIGraphicsImageRendererFormat() /* Image-rendering configuration */

        format.scale = 1

        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100), format: format).image { context in /* Synthetic two-color crop source */
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
        }

        let data = try XCTUnwrap(AvatarPhotoCrop.jpeg( /* Encoded cropped-avatar JPEG bytes */
            image: image, side: 100, zoom: 1, offset: CGSize(width: 50, height: 0)
        ))
        let croppedImage = try XCTUnwrap(UIImage(data: data)) /* Decoded square avatar crop */

        XCTAssertEqual(croppedImage.size, CGSize(width: 512, height: 512))

        let colorImage = try XCTUnwrap(CIImage(data: data)) /* Core Image representation of the avatar crop */
        let average = try XCTUnwrap(colorImage.applyingFilter("CIAreaAverage", parameters: [ /* Average color sample for the exported crop */
            kCIInputExtentKey: CIVector(cgRect: colorImage.extent)
        ]).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)) as CIImage?)
        var pixel = [UInt8](repeating: 0, count: 4) /* RGBA buffer for the average crop color */
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
