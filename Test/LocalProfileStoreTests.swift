// -------------------------------------------------------------------------------------------------
// @file       LocalProfileStoreTests.swift
// @brief      Local profile persistence tests
// @details    Verifies profile round trips and removal without using production preferences
//
// -------------------------------------------------------------------------------------------------
import XCTest
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
            avatarColor: .green,
            preferences: LocalProfilePreferences(
                defaultListID:      3,
                usesReducedContent: true,
                usesLargeControls:  true
            )
        )

        LocalProfileStore.save(profile, to: defaults)

        XCTAssertEqual(LocalProfileStore.load(from: defaults), profile)
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
}