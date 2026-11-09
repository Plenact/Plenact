// --------------------------------------------------------------------------------------------------
// @file       StudioSurfaces.swift
// @brief      Shared material rendering and independently retained personal artwork
// @details    Draws lightweight textures and canvases, renders credited online photographs, and
//             keeps imported images outside attachment pruning and individual Card lifecycles
// --------------------------------------------------------------------------------------------------
import SwiftUI
import UIKit


/// Resolves an ancestor's default Card and Note material
/// @section Purpose
///     Lets per-item surfaces override List and Board defaults without rewriting descendants
private struct StudioCardSurfaceKey: EnvironmentKey
{
    static let defaultValue: StudioSurface? = nil /* Fallback environment value */

}



/// Makes inherited preview and detail materials available to descendants
/// @section Purpose
///     Shares presentation metadata across navigation and sheet boundaries
extension EnvironmentValues
{
    var studioCardSurface: StudioSurface? /* Studio card surface */
    {
        get
        {
            self[StudioCardSurfaceKey.self]
        }

        set
        {
            self[StudioCardSurfaceKey.self] = newValue

        }

    }

}



/// Owns immutable imported artwork independently of attachments
/// @section Purpose
///     Reuses bounded image preparation and never deletes art because one item stops using it
enum StudioArtworkStore
{
    private static let cache = NSCache<NSString, UIImage>() /* Reusable lookup results */


    /// @fcn StudioArtworkStore.directory()
    /// @brief Resolve the dedicated artwork directory
    /// @details Creates local application-support storage only when needed
    /// @return (URL) artwork storage directory
    /// @throws Filesystem errors propagate to the importing editor
    static func directory() throws -> URL
    {
        let root = /* Workspace or view root */
            try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let url = /* Resolved file location */
            root.appendingPathComponent("PlenactStudioArtwork", isDirectory: true)

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }



    /// @fcn StudioArtworkStore.importImage(_:)
    /// @brief Store one orientation-corrected, bounded user image
    /// @details Uses immutable filenames and atomic writes; callers can reuse the returned reference
    /// @param[in] data Encoded image bytes supplied by Photos or Files
    /// @return (String) safe local filename
    /// @throws Image preparation or filesystem errors propagate without updating appearance
    static func importImage(_ data: Data) throws -> String
    {
        let prepared = /* Prepared operation input */
            try CollectionBackgroundPhotoStore.preparedPhoto(data)
        let name     = UUID().uuidString + ".jpg" /* Display or lookup name */

        try prepared.write(to: directory().appendingPathComponent(name), options: .atomic)
        return name
    }



    /// @fcn StudioArtworkStore.image(_:)
    /// @brief Read a valid locally owned artwork reference
    /// @details Rejects path traversal and caches decoded images across preview reuse
    /// @param[in] name Optional stored filename
    /// @return (UIImage?) image when available, otherwise nil for a readable fallback
    static func image(_ name: String?) -> UIImage?
    {
        guard let name, name == URL(fileURLWithPath: name).lastPathComponent,
        !name.contains(".."), let directory = try? directory() else
        {
            return nil
        }

        if let cached = cache.object(forKey: name as NSString)
        {
            return cached
        }

        guard let image = UIImage(contentsOfFile: directory.appendingPathComponent(name).path) else
        {
            return nil
        }

        cache.setObject(image, forKey: name as NSString)
        return image
    }

}



/// Provides bundled photographs through the existing portable local-artwork representation
/// @section Purpose
///     Copies a selected image into owned artwork storage before publishing its reference
///     Keeps the device-local Note rotation separate from saved appearance and shared content
enum CardBackgroundPortfolio
{
    static let rotationKey = "Plenact.NoteBackground.Next.v1" /* Next device-local selection */
    static let titles = /* Stable portfolio order; append new choices to preserve rotation */
        ["Mountain dawn", "Ocean morning", "Forest light", "Desert curves", "Alpine reflection",
         "Spring blossoms", "Wildflower meadow", "Evening coast", "Autumn glow", "Lavender fields",
         "Rainy window", "Twilight clouds", "Winter slopes", "Sunlit shadows", "Bamboo calm"]

    static func assetName(at index: Int) -> String
    {
        String(format: "CardBackground%02d", index + 1)
    }

    /// Materialize an immutable local photo so backups and portable exports include its bytes
    static func surface(at index: Int, directory: URL? = nil) throws -> StudioSurface
    {
        guard titles.indices.contains(index) else
        {
            throw CocoaError(.fileReadInvalidFileName)
        }

        let asset = assetName(at: index)                         /* Bundled image identity */
        let name  = asset + ".jpg"                              /* Portable local filename */
        let root  = try directory ?? StudioArtworkStore.directory() /* Owned artwork storage */
        let url   = root.appendingPathComponent(name)            /* Immutable image path */

        if !FileManager.default.fileExists(atPath: url.path)
        {
            guard let data = UIImage(named: asset)?.jpegData(compressionQuality: 0.86) else
            {
                throw CocoaError(.fileReadCorruptFile)
            }

            try data.write(to: url, options: .atomic)
        }

        return StudioSurface(material: .photo, strength: 1, readability: 0.35, photoFileName: name)
    }

    /// Advance only after a usable photo has been prepared; a saved Note keeps its chosen photo
    static func nextSurface(defaults: UserDefaults = .standard, directory: URL? = nil) throws -> StudioSurface
    {
        let index   = max(0, defaults.integer(forKey: rotationKey)) % titles.count /* Next image */
        let surface = try surface(at: index, directory: directory)               /* Owned photo */

        defaults.set((index + 1) % titles.count, forKey: rotationKey)
        return surface
    }

}


/// Draws a single material consistently across all supported surfaces
/// @section Purpose
///     Uses procedural textures instead of large repeated bitmaps and keeps content readable over artwork
struct StudioSurfaceView: View
{
    let surface: StudioSurface                     /* Artwork surface definition       */
    @Environment(\.colorScheme) private var scheme /* Current light or dark appearance */


    /// @fcn StudioSurfaceView.color(_:)
    /// @brief Decode a six-digit user palette color
    /// @details Falls back to a neutral color when persisted color text is malformed
    /// @param[in] hex RGB color representation
    /// @return (Color) opaque display color
    static func color(_ hex: String) -> Color
    {
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else
        {
            return Color(.secondarySystemBackground)
        }

        return Color(red: Double((value >> 16) & 255) / 255,
            green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }



    /// @fcn StudioSurfaceView.body
    /// @brief Render the selected material with bounded framing and a readability wash
    /// @details Artwork is decorative; remote photographs retain a visible linked credit
    /// @return (some View) opaque background with accessible provider attribution where required
    ///
    /// @fcn        StudioSurfaceView.body
    /// @brief      Compose the native personalization interface for this destination
    /// @details    Keeps editing state within its owning view and preserves existing behavior
    ///             when no material override is configured. Decorative art stays below controls
    ///
    /// @return     (some View) accessible surface controls or resolved workspace background
    ///
    var body: some View /* Studio Surface layout */
    {
        GeometryReader
        {
        geometry in
            ZStack(alignment: .bottomTrailing)
            {
                Color(.systemBackground)
                artwork(size: geometry.size)
                .opacity(min(1, max(0, surface.strength)))
                Color(scheme == .dark ? .black : .white)
                .opacity(min(1, max(0, surface.readability)))
                if surface.material == .unsplash, let remote = surface.remotePhoto
                {
                    HStack(spacing: 3)
                    {
                        Link(remote.photographer, destination: remote.profileURL)
                        Text("on")
                        Link("Unsplash", destination: URL(string: "https://unsplash.com/?utm_source=plenact&utm_medium=referral")!)
                    }
                    .font(.caption2).padding(4).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .padding(6)
                }

            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }

    }



    /// @fcn StudioSurfaceView.artwork(size:)
    /// @brief Draw a photo, gradient, canvas, or repeating texture
    /// @details Applies per-use zoom and vertical framing while preserving the original image
    /// @param[in] size Available background bounds
    /// @return (some View) selected artwork or neutral fallback
    @ViewBuilder
    private func artwork(size: CGSize) -> some View
    {
        let first  = Self.color(surface.color)          /* First comparison value  */
        let second = Self.color(surface.secondaryColor) /* Second comparison value */

        switch surface.material
        {
        case .plain:
            Color(.systemBackground)
        case .color:
            first
        case .gradient:
            LinearGradient(colors: [first, second], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .photo:
            if let image = StudioArtworkStore.image(surface.photoFileName)
            {
                Image(uiImage: image).resizable().scaledToFill()
                .frame(width: size.width, height: size.height)
                .scaleEffect(min(2, max(1, surface.zoom)))
                .offset(y: (0.5 - min(1, max(0, surface.verticalPosition))) * size.height * 0.3)
            }

        case .unsplash:
            if let remote = surface.remotePhoto
            {
                AsyncImage(url: remote.imageURL)
                {
                image in
                    image.resizable().scaledToFill()
                }

                placeholder:
                {
                    first
                }
                .frame(width: size.width, height: size.height)
                .scaleEffect(min(2, max(1, surface.zoom)))
                .offset(y: (0.5 - min(1, max(0, surface.verticalPosition))) * size.height * 0.3)
                .clipped()
            }

        default:
            first
            Canvas
            {
            context, bounds in

                let ink = second /* Drawing stroke content */

                if surface.material == .canvas
                {
                    var mountain = Path() /* Mountain operation value */

                    mountain.move(to: CGPoint(x: 0, y: bounds.height * 0.8))
                    mountain.addLine(to: CGPoint(x: bounds.width * 0.38, y: bounds.height * 0.28))
                    mountain.addLine(to: CGPoint(x: bounds.width, y: bounds.height * 0.7))
                    mountain.addLine(to: CGPoint(x: bounds.width, y: bounds.height))
                    mountain.addLine(to: CGPoint(x: 0, y: bounds.height))
                    context.fill(mountain, with: .color(ink.opacity(0.7)))
                    context.fill(Path(ellipseIn: CGRect(x: bounds.width * 0.7, y: 20, width: 65, height: 65)),
                        with: .color(.orange.opacity(0.25)))
                }

                else
                {
                    let step: CGFloat = /* Current review step */
                        surface.material == .linen ? 4 : 24

                    for x in stride(from: CGFloat(0), through: bounds.width, by: step)
                    {
                        for y in stride(from: CGFloat(0), through: bounds.height, by: step)
                        {
                            if surface.material == .dots
                            {
                                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(ink))
                            }

                        }

                        if [.grid, .linen].contains(surface.material)
                        {
                            var line = Path() /* Current text or drawing line */

                            line.move(to: CGPoint(x: x, y: 0));
                            line.addLine(to: CGPoint(x: x, y: bounds.height))
                            context.stroke(line, with: .color(ink.opacity(0.35)), lineWidth: 0.5)
                        }

                    }

                    if surface.material != .dots
                    {
                        for y in stride(from: CGFloat(0), through: bounds.height, by: step)
                        {
                            var line = Path() /* Current text or drawing line */

                            line.move(to: CGPoint(x: 0, y: y));
                            line.addLine(to: CGPoint(x: bounds.width, y: y))
                            context.stroke(line, with: .color(ink.opacity(0.5)), lineWidth: 0.5)
                        }

                    }

                }

            }

        }

    }

}



/// Resolves a Card or Note surface through owner defaults and saved global creation choices
/// @section Purpose
///     Keeps preview visibility independent of the full detail background
struct StudioItemBackground: View
{
    let appearance: ItemAppearance?                         /* Resolved appearance choices     */
    let isNote:     Bool                                    /* Note state                      */
    var preview = false                                     /* Prepared content preview        */
    @Environment(\.studioCardSurface) private var inherited /* Appearance inherited from owner */

    ///
    /// @fcn        StudioItemBackground.body
    /// @brief      Compose the native personalization interface for this destination
    /// @details    Keeps editing state within its owning view and preserves existing behavior
    ///             when no material override is configured. Decorative art stays below controls
    ///
    /// @return     (some View) accessible surface controls or resolved workspace background
    ///
    var body: some View /* Studio Item Background layout */
    {
        if let surface = appearance?.studioSurface ?? inherited,
        !preview || surface.showsInPreviews
        {
            StudioSurfaceView(surface: surface)
        }

    }

}

