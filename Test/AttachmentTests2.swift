// --------------------------------------------------------------------------------------------------
// @file       AttachmentTests2.swift
// @brief      Attachment regression tests2
// @details    Verifies related workspace behavior with synthetic fixtures and the shared
//             PlenactBoardDocumentTests helpers. Retains original test identities and checked
//             assertions while separating this coverage from unrelated feature tests.
//
// --------------------------------------------------------------------------------------------------
@testable import Plenact
import AVFoundation
import PencilKit
import SwiftUI
import UserNotifications
import XCTest


///
/// Attachment regression coverage for the shared workspace test suite
///
/// @section    Purpose
///     Verify related model and presentation contracts with isolated synthetic fixtures.
///
extension PlenactBoardDocumentTests
{


    ///
    /// @fcn        PlenactBoardDocumentTests.testLargeLocalCoverIsDownsampledAndRemovalKeepsItsMedia()
    /// @brief      Verify actual large-photo decoding and non-destructive cover disabling
    /// @details    Creates one synthetic PNG; cleans only its uniquely named fixture file
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Media creation, decoding, validation, or cleanup errors
    ///
    func testLargeLocalCoverIsDownsampledAndRemovalKeepsItsMedia() throws
    {


        let format = UIGraphicsImageRendererFormat() /* Image-rendering configuration */

        format.scale = 1

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: 2400, height: 1600), format: format) /* Synthetic image renderer                   */
        let bytes = renderer.pngData
        {
        context in /* Rendered PNG bytes for the oversized cover */
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1600))
        }


        let photo = try CardAttachmentStore.saveMedia(
            bytes, kind: .photo, fileExtension: "png")  /* Synthetic photo fixture */
        let fileName = try XCTUnwrap(photo.fileName)    /* Stored avatar filename  */

        defer
        {


            try? CardAttachmentStore.removeDeletedFiles([fileName], keeping: [])
        }


        var card = KanbanCard(
            id: 1, word: "Synthetic", listTitle: "Local", checklists: [], attachments: [photo]) /* Card value under verification */

        try card.setCover(photo.id)

        let image = try XCTUnwrap(
            try CardAttachmentStore.coverThumbnail(for: photo).cgImage) /* Synthetic image fixture */

        XCTAssertEqual(image.width, 960)
        XCTAssertEqual(image.height, 640)

        try card.setCover(nil)

        XCTAssertEqual(card.attachments, [photo])
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: try XCTUnwrap(CardAttachmentStore.fileURL(for: photo)).path))
        XCTAssertThrowsError(
            try CardAttachmentStore.coverThumbnail(for: KanbanAttachment(fileName: fileName, mediaKind: .video)))
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testCoverRowsRemainBoundedAndCanBeDisabledWithoutContentChanges()
    /// @brief      Measure cover visibility in actual Standard/Overview card rows
    /// @details    Uses isolated display preferences and rejects mutation callbacks during layout
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     Preference suite setup errors
    ///
    @MainActor
    func testCoverRowsRemainBoundedAndCanBeDisabledWithoutContentChanges() throws
    {


        let suite = "Plenact.CoverLayoutTests.\(UUID().uuidString)"   /* Isolated preferences-suite key */
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))  /* Isolated test preferences      */

        defer
        {


            defaults.removePersistentDomain(forName: suite)
        }


        let photo = KanbanAttachment(mediaKind: .photo, exampleImage: .garden) /* Synthetic photo fixture       */
        let card = KanbanCard(
            id: 1, word: "Garden", listTitle: "Local", checklists: [], /* Card value under verification */
            attachments: [photo], coverAttachmentID: photo.id, subtitleOverride: "",
            appearance: ItemAppearance(accent: .green, icon: .home, background: .teal))


        ///
        /// @fcn        PlenactBoardDocumentTests.testCoverRowsRemainBoundedAndCanBeDisabledWithoutContentChanges.measure(_:enabled:)
        /// @brief      Host a synthetic card at a fixed width with isolated cover visibility
        /// @details    Proposes ample height to verify intrinsic content fitting
        ///
        /// @param[in]  preset   Board density
        /// @param[in]  enabled  Cover display preference
        ///
        /// @return     (CGFloat) hosted row height
        ///
        func measure(_ preset: BoardPresentation, enabled: Bool) -> CGFloat
        {


            defaults.set(enabled, forKey: "Plenact.CardCovers.enabled")

            let row = KanbanCardView( /* Rendered collection row */
                card: card, height: preset.minimumCardHeight, displaySettings: BoardDisplaySettings(),
                presentation: preset, labelLibrary: .starter,
                onUpdateCard:
                {
                    _ in
                    XCTFail("Layout must not change covers")
                },
                onDeleteCard:
                {
                    XCTFail("Layout must not delete")
                },
                onArchiveCard:
                {
                    XCTFail("Layout must not archive")
                },
                onToggle:
                {
                    XCTFail("Layout must not toggle")
                }
            ).defaultAppStorage(defaults)
            return UIHostingController(rootView: row).sizeThatFits(in: CGSize(width: 320, height: 10_000)).height
        }


        let standard = measure(.standard, enabled: true)  /* Standard Card baseline      */
        let overview = measure(.overview, enabled: true)  /* Overview layout measurement */

        XCTAssertGreaterThan(standard, overview)
        XCTAssertGreaterThan(standard, measure(.standard, enabled: false) + 100)
        XCTAssertGreaterThan(overview, measure(.overview, enabled: false) + 50)
        XCTAssertLessThan(standard, 350)
        XCTAssertEqual(card.coverAttachmentID, photo.id)
        XCTAssertEqual(card.attachments, [photo])
    }


    ///
    /// @fcn        PlenactBoardDocumentTests.testDeletionMediaCleanupPreservesRetainedCopiesAndUnrelatedFiles()
    /// @brief      Remove only explicit deletion candidates with no remaining references
    /// @details    Creates synthetic media files; protects archive/undo references and an unrelated
    ///             file
    ///
    /// @return     (Void) records assertion failures for the behavior described above
    ///
    /// @throws     File creation or cleanup failures
    ///
    func testDeletionMediaCleanupPreservesRetainedCopiesAndUnrelatedFiles() throws
    {


        let candidate = try CardAttachmentStore.saveMedia(
            Data([1, 2, 3]), kind: .photo, fileExtension: "jpg") /* Candidate value for validation */
        let unrelated = try CardAttachmentStore.saveMedia(
            Data([4, 5, 6]), kind: .photo, fileExtension: "jpg")  /* Unrelated retained value */
        let candidateName = try XCTUnwrap(candidate.fileName)     /* Candidate display name   */
        let unrelatedName = try XCTUnwrap(unrelated.fileName)     /* Unrelated display name   */

        defer
        {


            try? CardAttachmentStore.removeDeletedFiles([candidateName, unrelatedName], keeping: [])
        }


        var card = KanbanCard(
            id: 1, word: "Retained", listTitle: "Archive", checklists: []) /* Card value under verification */

        card.attachments = [candidate]

        var archived = KanbanList(
            id: 1, title: "Archive", cards: [], archivedCards: [card]) /* Archived value for restoration checks */

        archived.isArchived = true

        let retainedNames = CardAttachmentStore.fileNames(in: [archived]) /* Names preserved by filtering */

        try CardAttachmentStore.removeDeletedFiles([candidateName], keeping: retainedNames)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: try XCTUnwrap(CardAttachmentStore.fileURL(for: candidate)).path))

        try CardAttachmentStore.removeDeletedFiles([candidateName], keeping: [])

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: try XCTUnwrap(CardAttachmentStore.fileURL(for: candidate)).path))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: try XCTUnwrap(CardAttachmentStore.fileURL(for: unrelated)).path))

        for invalidName in ["", ".", "..", "../outside.jpg"]
        {


            XCTAssertThrowsError(try CardAttachmentStore.removeDeletedFiles([invalidName], keeping: []))
        }

    }

}
