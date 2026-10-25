// --------------------------------------------------------------------------------------------------
// @file       LegacyStoreValidation.swift
// @brief      Native decoder preflight for retained local workspace stores
// @details    Supports User Data Model 1.0 migration preparation; source backup format 1.
//             Preserves legacy storage without conversion, restoration, network access or fallback data.
// --------------------------------------------------------------------------------------------------
import CoreFoundation
import Foundation


/// Validates stored bytes without calling loaders that supply examples or repair data.
/// @section Purpose
///     Establish which legacy stores can be decoded before Model 1.0 conversion.
@MainActor
enum LegacyStoreValidation
{

    static let jsonKeys: Set<String> = [
        "Plenact.Board.v1", "Plenact.CalendarWeeks.v1", "Plenact.PersonalCollections.v1",
        "Plenact.LabelLibrary.v1", "Plenact.LocalProfile.v1", "Plenact.PlanPreferences.v1",
        "Plenact.PlanningTemplates.v1", "Plenact.DailyPlans.v1", "Plenact.WeeklyReviews.v1",
        "Plenact.PeriodicReviews.v1", "Plenact.ReviewRhythm.v1", "Plenact.Studio.Settings.v1",
        "Plenact.Studio.Artwork.v1", "Plenact.LibraryImportant.v1", "Plenact.WeekAppearance.v1",
        "Plenact.TodayListShortcuts.v1", "Plenact.LibraryRecents.v1", "Plenact.ActivityRecents.v1"
    ] /* Reviewed JSON-encoded source stores */

    static let nativeKeys: Set<String> = [
        "Plenact.SavedCardIDs.v1", "Plenact.RecentSearches.v1", "Plenact.LocalReactionAuthor.v1",
        "Plenact.BoardPresentation.v1", "Plenact.CardCovers.enabled", "Plenact.ActivityShowsCovers",
        "Plenact.ActivityRecentSquareCards", "Plenact.LibraryShowsCollectionPreviews",
        "Plenact.LibraryScrollsCollectionPreviews", "Plenact.LastViewedList.v1",
        "Plenact.Welcome.lastDeparture.v1", "Plenact.ReviewRhythmDismissals.v1"
    ] /* Reviewed property-list values */

    static let recoveryKeys: Set<String> = [
        "Plenact.DailyReviewTransaction.v1", "Plenact.ExampleLoadUndo.v1",
        "Plenact.ExampleCardLocations.Applied.v1", "Plenact.ExampleCardLocations.Backup.v1"
    ] /* Retained recovery evidence, never executed by export */


    /// @fcn LegacyStoreValidation.includes
    /// @brief Identify reviewed user, device and recovery values
    /// @details Unknown Plenact keys are reported separately, never guessed safe to export.
    /// @param[in] key Original preference name
    /// @return True for a known key or reviewed dynamic prefix
    static func includes(_ key: String) -> Bool
    {

        jsonKeys.contains(key) || nativeKeys.contains(key) || recoveryKeys.contains(key)
            || key.hasPrefix("Plenact.BoardViewport.v1.") || key.hasPrefix("plenact.creationDraft.")
    }


    /// @fcn LegacyStoreValidation.decode
    /// @brief Exercise the actual app decoder without reconstructing or saving its output
    /// @details The source bytes remain authoritative even if a legacy decoder normalizes values.
    /// @param[in] type Native source type
    /// @param[in] data Original stored JSON bytes
    /// @return Void after successful decoding
    /// @throws Native decoding errors
    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws
    {

        _ = try JSONDecoder().decode(type, from: data)
    }


    /// @fcn LegacyStoreValidation.mediaIssues
    /// @brief Locate unsafe or missing file references without altering retained JSON bytes
    /// @details Source paths stay private; diagnostic codes identify only the affected store.
    /// @param[in] value Decoded legacy JSON subtree
    /// @param[in] store Original source store name
    /// @param[in] files Exact relative paths included in the backup
    /// @return Review diagnostics for missing or unsafe referenced originals
    static func mediaIssues(_ value: Any, store: String, files: Set<String>) -> [String]
    {

        var issues: [String] = []
        if let object = value as? [String: Any]
        {
            for (key, child) in object
            {
                if ["fileName", "drawingFileName", "avatarPhotoFileName", "photoFileName"].contains(key),
                   let filename = child as? String
                {
                    if filename.isEmpty || filename == "." || filename == ".."
                        || filename.contains("/") || filename.contains("\\")
                    {
                        issues.append("unsafe_media_reference: " + store)
                    }
                    else
                    {
                        let candidates: [String]
                        switch key
                        {
                        case "fileName", "drawingFileName":
                            candidates = ["Documents/CardAttachments/" + filename]
                        case "avatarPhotoFileName":
                            candidates = ["Documents/ProfileAvatars/" + filename]
                        default:
                            candidates = ["Library/Application Support/PlenactStudioArtwork/" + filename,
                                "Library/Application Support/PlenactCollectionBackgrounds/" + filename]
                        }
                        if !candidates.contains(where: files.contains)
                        {
                            issues.append("missing_media: " + store)
                        }
                    }
                }
                issues.append(contentsOf: mediaIssues(child, store: store, files: files))
            }
        }
        else if let array = value as? [Any]
        {
            for child in array
            {
                issues.append(contentsOf: mediaIssues(child, store: store, files: files))
            }
        }
        return issues
    }


    /// @fcn LegacyStoreValidation.check
    /// @brief Preflight a present source value and return a stable review code if necessary
    /// @details Future versions and corrupt bytes are preserved, never replaced with empty stores.
    /// @param[in] key Original preference name
    /// @param[in] value Original property-list value
    /// @return Optional diagnostic code; nil means the checks available here passed
    static func check(key: String, value: Any) -> String?
    {

        if key == "Plenact.DailyReviewTransaction.v1"
        {
            return "pending_recovery_transaction"
        }

        guard jsonKeys.contains(key) else
        {
            let booleans: Set<String> = ["Plenact.CardCovers.enabled", "Plenact.ActivityShowsCovers",
                "Plenact.ActivityRecentSquareCards", "Plenact.LibraryShowsCollectionPreviews",
                "Plenact.LibraryScrollsCollectionPreviews", "Plenact.ExampleCardLocations.Applied.v1"]
            if booleans.contains(key)
            {
                guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else
                {
                    return "wrong_storage_type"
                }
            }
            return nil
        }

        guard let data = value as? Data else
        {
            return "wrong_storage_type"
        }

        do
        {
            let json = try JSONSerialization.jsonObject(with: data)
            if let object = json as? [String: Any], let version = object["version"] as? NSNumber,
               (CFGetTypeID(version) == CFBooleanGetTypeID() || version.doubleValue != 1)
            {
                return "unsupported_store_version"
            }

            switch key
            {
            case "Plenact.Board.v1": try decode([KanbanList].self, data)
            case "Plenact.CalendarWeeks.v1": try decode(PlanningCalendarDocument.self, data)
            case "Plenact.PersonalCollections.v1": try decode([PersonalCollection].self, data)
            case "Plenact.LabelLibrary.v1": try decode(LabelLibrary.self, data)
            case "Plenact.LocalProfile.v1": try decode(LocalProfile.self, data)
            case "Plenact.PlanPreferences.v1": try decode(LocalProfilePreferences.self, data)
            case "Plenact.PlanningTemplates.v1": try decode(PlanningRoutineLibrary.self, data)
            case "Plenact.DailyPlans.v1": try decode(DailyPlanStore.Document.self, data)
            case "Plenact.WeeklyReviews.v1": try decode(WeeklyReviewStore.Document.self, data)
            case "Plenact.PeriodicReviews.v1": try decode(PeriodicReviewStore.Document.self, data)
            case "Plenact.ReviewRhythm.v1": try decode(ReviewRhythmPreferences.self, data)
            case "Plenact.Studio.Settings.v1": try decode(StudioSettings.self, data)
            case "Plenact.Studio.Artwork.v1": try decode([StudioArtwork].self, data)
            case "Plenact.LibraryImportant.v1": try decode([LibraryImportanceItem].self, data)
            case "Plenact.WeekAppearance.v1": try decode(BoardAppearance.self, data)
            case "Plenact.TodayListShortcuts.v1": try decode([WorkspaceListReference].self, data)
            case "Plenact.LibraryRecents.v1", "Plenact.ActivityRecents.v1":
                try decode([LibraryRecentItem].self, data)
            default: return "unclassified_store"
            }
        }
        catch
        {
            return "native_decode_failed"
        }

        return nil
    }
}
