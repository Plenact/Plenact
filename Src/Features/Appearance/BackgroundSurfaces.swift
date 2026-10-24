// --------------------------------------------------------------------------------------------------
// @file       BackgroundSurfaces.swift
// @brief      Appearance rendering and independent background storage
// @details    Resolves palette values, item visuals, and collection backgrounds while keeping
//             custom background photos separate from attachment pruning.
//
// --------------------------------------------------------------------------------------------------
import AVKit
import Foundation
import ImageIO
import PencilKit
import PhotosUI
import SwiftUI
import UIKit


///
/// Maps stored List tints to SwiftUI colors
///
/// @section    Purpose
///     Keeps model tint cases independent of presentation while supplying the muted List surface
///     colors.
///
extension KanbanListTint
{


    var color: Color
    {

        switch self
        {

        case .neutral:
            Color(.systemGray6)
        case .blue:
            Color.blue.opacity(0.12)
        case .green:
            Color.green.opacity(0.12)
        case .orange:
            Color.orange.opacity(0.12)
        case .red:
            Color.red.opacity(0.12)
        }

    }

}


///
/// Maps stored item accents to presentation colors
///
/// @section    Purpose
///     Supplies standard and dark-header variants without altering the persisted accent identity.
///
extension ItemAccent
{


    var color: Color
    {

        switch self
        {

        case .teal:
            .teal
        case .blue:
            .blue
        case .purple:
            .purple
        case .coral:
            ProfileColor.coral.color
        case .graphite:
            ProfileColor.graphite.color
        case .rose:
            .pink
        case .orange:
            .orange
        case .green:
            .green
        }

    }


    var darkHeaderColor: Color
    {

        switch self
        {

        case .teal:
            Color(red: 0.08, green: 0.28, blue: 0.28)
        case .blue:
            Color(red: 0.08, green: 0.20, blue: 0.36)
        case .purple:
            Color(red: 0.24, green: 0.12, blue: 0.32)
        case .coral:
            Color(red: 0.48, green: 0.13, blue: 0.16)
        case .graphite:
            Color(red: 0.32, green: 0.33, blue: 0.36)
        case .rose:
            Color(red: 0.34, green: 0.12, blue: 0.22)
        case .orange:
            Color(red: 0.34, green: 0.20, blue: 0.08)
        case .green:
            Color(red: 0.12, green: 0.28, blue: 0.14)
        }

    }


    ///
    /// @fcn        ItemAccent.bannerColor
    /// @brief      Resolve an accent's banner surface color
    /// @details    Uses the increased-contrast choice to select the appropriate opacity or treatment for the accent.
    ///
    /// @param[in]  increasedContrast  Whether the system requests increased visual contrast
    ///
    /// @return     (Color) accent banner color adjusted for the requested contrast setting
    ///
    func bannerColor(increasedContrast: Bool) -> Color
    {

        Color(
            uiColor: UIColor
            {
                traits in
                let tint = UIColor(self.color).resolvedColor(with: traits)
                let base = UIColor.systemBackground.resolvedColor(with: traits)
                var red: CGFloat = 0
                var green: CGFloat = 0
                var blue: CGFloat = 0
                var alpha: CGFloat = 0
                var baseRed: CGFloat = 0
                var baseGreen: CGFloat = 0
                var baseBlue: CGFloat = 0
                tint.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                base.getRed(&baseRed, green: &baseGreen, blue: &baseBlue, alpha: &alpha)
                let amount: CGFloat = increasedContrast ? 0.10 : 0.16
                return UIColor(
                    red: baseRed * (1 - amount) + red * amount,
                    green: baseGreen * (1 - amount) + green * amount,
                    blue: baseBlue * (1 - amount) + blue * amount,
                    alpha: 1
                )
            })
    }

}


///
/// Displays an item's optional appearance icon
///
/// @section    Purpose
///     Uses the configured icon tint with a secondary fallback and hides purely decorative artwork
///     from accessibility.
///
struct ItemAppearanceMark: View
{


    let appearance: ItemAppearance?

    var body: some View
    {

        if let icon = appearance?.icon
        {

            Image(systemName: icon.rawValue)
            .foregroundStyle(appearance?.iconColor?.color ?? Color.secondary)
            .accessibilityHidden(true)
        }

    }

}


///
/// Applies an item's decorative banner background
///
/// @section    Purpose
///     Resolves appearance and accessibility contrast while leaving content and mutation behavior
///     with the wrapped view.
///
struct ItemBannerBackground: ViewModifier
{


    let appearance: ItemAppearance?
    @Environment(\.colorSchemeContrast) private var contrast


    ///
    /// @fcn        ItemBannerBackground.body
    /// @brief      Apply a decorative item banner background
    /// @details    Uses the available item appearance and accessibility contrast context to render the banner
    ///             surface.
    ///
    /// @param[in]  content  View content to decorate with this modifier
    ///
    /// @return     (some View) a decorative item banner background
    ///
    func body(content: Content) -> some View
    {

        if let background = appearance?.background
        {

            content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background.bannerColor(increasedContrast: contrast == .increased))
        }
        else
        {

            content
        }

    }

}


///
/// Adds the shared appearance banner modifier to views
///
/// @section    Purpose
///     Keeps call sites independent of the modifier implementation and accepts absent appearance
///     overrides.
///
extension View
{


    ///
    /// @fcn        View.itemBannerBackground
    /// @brief      Attach the shared appearance-driven banner modifier
    /// @details    Wraps the view in ItemBannerBackground using the optional appearance supplied by its owner.
    ///
    /// @param[in]  appearance  Optional or explicit appearance overrides supplied by the caller
    ///
    /// @return     (some View) attach the shared appearance-driven banner modifier
    ///
    func itemBannerBackground(_ appearance: ItemAppearance?) -> some View
    {

        modifier(ItemBannerBackground(appearance: appearance))
    }

}


///
/// Displays a complete item picture preview
///
/// @section    Purpose
///     Reuses the thumbnail loader and preserves the selected image's natural aspect ratio.
///
struct ItemPicturePreview: View
{


    let attachment: KanbanAttachment?
    var title:      String? = nil

    private var accessibleDescription: String
    {

        let text = [title, attachment?.caption]
        .compactMap
        {
            $0?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter
        {
            !$0.isEmpty
        }
        .joined(separator: ", ")
        return text.isEmpty ? "Picture" : text
    }

    @State private var image: UIImage?
    @State private var unavailable = false

    var body: some View
    {

        Group
        {

            if let image
            {

                Image(uiImage: image)
                .resizable()
                .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
            }
            else
            {

                Label(
                    attachment == nil ? "Choose picture" : (unavailable ? "Picture unavailable" : "Loading picture…"),
                    systemImage: "photo"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(Color.secondary.opacity(0.08))
            }

        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibleDescription)
        .accessibilityValue(attachment == nil ? "Choose picture" : (unavailable ? "Picture unavailable" : ""))
        .accessibilityAddTraits(.isImage)
        .task(id: attachment)
        {

            image = nil
            unavailable = false
            guard let attachment else
            {
                return
            }

            let result = await Task.detached(priority: .utility)
            {

                Result
                {
                    try CardAttachmentStore.coverThumbnail(for: attachment)
                }

            } .value
            guard !Task.isCancelled else
            {
                return
            }

            switch result
            {

            case .success(let thumbnail):
                image = thumbnail
            case .failure:
                unavailable = true
            }

        }

    }

}


///
/// Presents canonical item display-format choices
///
/// @section    Purpose
///     Updates only display metadata through the supplied owner action without changing Card or
///     Note identity.
///
struct ItemDisplayFormatMenu: View
{


    let card:     KanbanCard
    let onUpdate: (KanbanCard) -> Void

    var body: some View
    {

        Menu
        {

            ForEach(ItemDisplayFormat.allCases)
            {
                format in
                Button
                {

                    var updated = card
                    updated.displayFormat = format
                    onUpdate(updated)
                }
                label:
                {

                    Label(format.title, systemImage: card.displayFormat == format ? "checkmark" : format.symbol)
                }

            }

        }
        label:
        {

            Label("Display as", systemImage: "rectangle.on.rectangle")
        }

    }

}


///
/// Edits an optional Card preview display profile
///
/// @section    Purpose
///     Stores Unchanged as no override so inherited presentation remains available.
///
struct CardDisplayProfilePicker: View
{


    @Binding var selection: BoardCardDetail?
    var body:               some View
    {

        Picker("Card display", selection: $selection)
        {

            Text("Unchanged").tag(Optional<BoardCardDetail>.none)
            Text("Detailed").tag(Optional(BoardCardDetail.detailed))
            Text("Compact").tag(Optional(BoardCardDetail.compact))
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("appearance.cardDisplay")
    }

}


///
/// Maps preview text palettes to adaptive colors
///
/// @section    Purpose
///     Uses separate light and dark component values so stored palette choices remain legible
///     across appearances.
///
extension ListPreviewTextColor
{


    var color: Color
    {

        let light: (CGFloat, CGFloat, CGFloat)
        let dark: (CGFloat, CGFloat, CGFloat)
        switch self
        {

        case .graphite:
            light = (0.22, 0.25, 0.29);
            dark = (0.78, 0.81, 0.85)
        case .blue:
            light = (0.16, 0.32, 0.56);
            dark = (0.59, 0.75, 0.98)
        case .teal:
            light = (0.12, 0.40, 0.42);
            dark = (0.52, 0.83, 0.83)
        case .green:
            light = (0.19, 0.39, 0.23);
            dark = (0.60, 0.84, 0.62)
        case .plum:
            light = (0.40, 0.26, 0.48);
            dark = (0.81, 0.67, 0.92)
        case .rose:
            light = (0.55, 0.25, 0.34);
            dark = (0.95, 0.65, 0.73)
        case .amber:
            light = (0.47, 0.34, 0.13);
            dark = (0.92, 0.78, 0.49)
        }

        return Color(
            uiColor: UIColor
            {
                traits in
                let rgb = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
            })
    }

}


// Board colors are a draft until Save; applying to all clears only List color overrides.


///
/// Stores custom collection background photos separately
///
/// @section    Purpose
///     Keeps background files outside Card attachment storage so ordinary attachment pruning cannot
///     remove a collection's image.
///
enum CollectionBackgroundPhotoStore
{


    private static let cache = NSCache<NSString, UIImage>()


    ///
    /// @fcn        CollectionBackgroundPhotoStore.directory
    /// @brief      Resolve the directory for collection background photos
    /// @details    Creates the application-owned storage directory when needed and propagates directory access
    ///             failures.
    ///
    /// @return     (URL) application-owned directory used for saved collection backgrounds
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    static func directory() throws -> URL
    {

        let root = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let url = root.appendingPathComponent("PlenactCollectionBackgrounds", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }


    ///
    /// @fcn        CollectionBackgroundPhotoStore.preparedPhoto
    /// @brief      Prepare a bounded JPEG collection background
    /// @details    Decodes the source with orientation correction, caps its thumbnail at 2048 pixels, and encodes
    ///             JPEG at 0.8 quality; invalid input throws.
    ///
    /// @param[in]  data  Encoded input or media bytes
    ///
    /// @return     (Data) orientation-corrected JPEG thumbnail bytes with a 2048-pixel bound
    /// @throws     Explicit failures include `CocoaError(.fileReadCorruptFile)`. Errors from throwing dependencies
    ///             propagate unless handled within this operation.
    ///
    static func preparedPhoto(_ data: Data) throws -> Data
    {

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
        let image = CGImageSourceCreateThumbnailAtIndex(
            source, 0,
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048
            ] as CFDictionary),
        let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.8)
        else
        {

            throw CocoaError(.fileReadCorruptFile)
        }

        return jpeg
    }


    ///
    /// @fcn        CollectionBackgroundPhotoStore.save
    /// @brief      Write prepared background-photo bytes under a fresh file name
    /// @details    Writes the supplied bytes atomically to a UUID-named .jpg file and returns the storage name; image
    ///             conversion is performed separately by preparedPhoto.
    ///
    /// @param[in]  data  Encoded input or media bytes
    ///
    /// @return     (String) newly written background photo's UUID-based .jpg file name
    /// @throws     Errors from throwing dependencies propagate unless handled within this operation.
    ///
    static func save(_ data: Data) throws -> String
    {

        let name = UUID().uuidString + ".jpg"
        try data.write(to: directory().appendingPathComponent(name), options: .atomic)
        return name
    }


    ///
    /// @fcn        CollectionBackgroundPhotoStore.image
    /// @brief      Load and cache a stored collection background photo
    /// @details    Requires a last-path-component .jpg name, reuses the image cache, and returns nil if storage or
    ///             image decoding is unavailable.
    ///
    /// @param[in]  name  Storage file name, symbol name, or accessible control name selected for this operation
    ///
    /// @return     (UIImage?) cached or decoded background image, or nil for invalid names or unavailable files
    ///
    static func image(named name: String?) -> UIImage?
    {

        guard let name, name == URL(fileURLWithPath: name).lastPathComponent, name.hasSuffix(".jpg") else
        {
            return nil
        }

        if let image = cache.object(forKey: name as NSString)
        {
            return image
        }

        guard let directory = try? directory(),
        let image = UIImage(contentsOfFile: directory.appendingPathComponent(name).path)
        else
        {
            return nil
        }

        cache.setObject(image, forKey: name as NSString, cost: Int(image.size.width * image.size.height * 4))
        cache.totalCostLimit = 32 * 1024 * 1024
        return image
    }


    ///
    /// @fcn        CollectionBackgroundPhotoStore.remove
    /// @brief      Remove a stored collection background photo and cached image
    /// @details    Accepts only a last-path-component name, attempts file removal when the directory is available,
    ///             and evicts its cache entry; file-removal errors are ignored.
    ///
    /// @param[in]  name  Storage file name, symbol name, or accessible control name selected for this operation
    ///
    /// @return     (Void) no return value
    ///
    static func remove(_ name: String)
    {

        guard name == URL(fileURLWithPath: name).lastPathComponent, let directory = try? directory() else
        {
            return
        }

        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        cache.removeObject(forKey: name as NSString)
    }

}


///
/// Renders offline collection background surfaces
///
/// @section    Purpose
///     Combines stationary procedural or photo backgrounds with the configured appearance behind
///     List content.
///
struct CollectionBackgroundSurface: View
{


    var background:     CollectionBackground? = nil
    var draftPhoto:     Data? = nil
    private var colors: [Color]
    {

        switch background?.preset
        {

        case .linen:
            [Color(red: 0.47, green: 0.39, blue: 0.31), Color(red: 0.64, green: 0.54, blue: 0.43)]
        case .sage:
            [Color(red: 0.19, green: 0.33, blue: 0.27), Color(red: 0.39, green: 0.52, blue: 0.38)]
        case .ocean:
            [Color(red: 0.08, green: 0.26, blue: 0.36), Color(red: 0.21, green: 0.49, blue: 0.53)]
        case .plum:
            [Color(red: 0.26, green: 0.18, blue: 0.31), Color(red: 0.49, green: 0.34, blue: 0.43)]
        case .sandstone:
            [Color(red: 0.43, green: 0.28, blue: 0.22), Color(red: 0.65, green: 0.47, blue: 0.34)]
        case .midnight:
            [Color(red: 0.10, green: 0.13, blue: 0.23), Color(red: 0.22, green: 0.27, blue: 0.38)]
        default:
            [Color(red: 0.10, green: 0.18, blue: 0.25), Color(red: 0.22, green: 0.34, blue: 0.38)]
        }

    }

    private var photo: UIImage?
    {

        switch background?.preset
        {

        case .tabletop:
            return UIImage(named: "DefaultListTable")
        case .forestPath:
            return UIImage(named: "DefaultListQueue")
        case .sunlitWall:
            return UIImage(named: "DefaultListScheduled")
        default:
            break
        }

        guard background?.preset == .photo else
        {
            return nil
        }

        if let draftPhoto
        {
            return UIImage(data: draftPhoto)
        }

        return CollectionBackgroundPhotoStore.image(named: background?.photoFileName)
    }

    var body: some View
    {

        GeometryReader
        {
            geometry in
            ZStack
            {

                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                if let photo
                {

                    Image(uiImage: photo).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    Color.black.opacity(0.30)
                    LinearGradient(colors: [.black.opacity(0.32), .clear], startPoint: .top, endPoint: .center)
                }
                else if let preset = background?.preset, preset != .photo, preset != .plain
                {

                    Canvas
                    {
                        context, size in
                        var grain = Path()
                        for row in stride(from: 0, through: Int(size.height), by: 7)
                        {

                            for column in stride(from: 0, through: Int(size.width), by: 7)
                            {

                                let shift = (row * 17 + column * 13) % 5
                                grain.addEllipse(
                                    in: CGRect(x: CGFloat(column + shift), y: CGFloat(row), width: 0.8, height: 0.8))
                            }

                        }

                        context.fill(grain, with: .color(.white.opacity(0.12)))
                        if preset == .linen || preset == .sandstone
                        {

                            var weave = Path()
                            for x in stride(from: 0, through: Int(size.width), by: 4)
                            {

                                weave.move(to: CGPoint(x: x, y: 0));

                                weave.addLine(to: CGPoint(x: CGFloat(x), y: size.height))
                            }

                            context.stroke(weave, with: .color(.white.opacity(0.045)), lineWidth: 0.5)
                        }

                    }
                    .allowsHitTesting(false)
                }

            }

        }
        .accessibilityHidden(true)
    }

}
