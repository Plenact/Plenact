// --------------------------------------------------------------------------------------------------
// @file       GenerateCovers.swift
// @brief      Offline illustration generation from authored cover metadata
// @details    Decodes the supplied cover catalog and renders semantic artwork with AppKit into the
//             requested output directory. Provides deterministic palettes, supported glyphs, raster
//             encoding, and command-line generation; this utility is separate from the iOS
//             application target.
//
// --------------------------------------------------------------------------------------------------

import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Rebuild the 352 expanded offline covers from semantic metadata. Existing covers stay untouched.


///
/// Decodes one authored cover-library entry
///
/// @section    Purpose
///     Carries catalog identity, category, artwork symbol, tags, and optional context for offline
///     cover asset generation.
///
struct Cover: Decodable
{

    let name:     String;
    let category: String;
    let symbol:   String;
    let tags:     [String];
    let context:  String?
}

let source = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let covers = try JSONDecoder().decode([Cover].self, from: Data(contentsOf: source))
let categories = ["home", "nature", "work", "food", "travel", "creativity", "health", "rest"]
let palettes: [[String]] = [
    ["F4E5D3", "CA7459", "4D7778"], ["E2F0E6", "45966D", "E5B454"],
    ["E0EAF3", "476A89", "75B0B1"], ["F8EBD6", "D98745", "649672"],
    ["DFEEF3", "428D9C", "C88663"], ["F0E3EF", "A26C99", "D39A61"],
    ["E1F0EE", "408F8D", "CE887B"], ["ECE8F4", "837EA6", "CDAE71"]
]
let contextSymbols = ["house", "leaf", "book.closed", "fork.knife", "map", "paintpalette", "heart", "moon.stars"]


///
/// @fcn        color
/// @brief      Convert authored hexadecimal RGB text into an AppKit color
/// @details    Force-parses the hexadecimal value, separates its RGB components, and applies the requested alpha;
///             this generator expects valid authored color text.
///
/// @param[in]  hex    Hexadecimal RGB color text
/// @param[in]  alpha  Requested color opacity
///
/// @return     (NSColor) AppKit color with the decoded RGB components and requested opacity
/// @pre        hex must be valid hexadecimal text representable as UInt32.
///
func color(_ hex: String, alpha: CGFloat = 1) -> NSColor
{

    let value = UInt32(hex, radix: 16)!
    return NSColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: alpha)
}


///
/// @fcn        glyph
/// @brief      Draw a supported cover symbol or custom glyph
/// @details    Handles the generator's custom vector shapes first and otherwise draws the configured system symbol,
///             propagating unavailable-symbol failures.
///
/// @param[in]  name    Storage file name, symbol name, or accessible control name selected for this operation
/// @param[in]  rect    Destination drawing rectangle
/// @param[in]  colors  Palette colors used when drawing the symbol
///
/// @return     (Void) no return value
/// @throws     Errors from throwing dependencies propagate unless handled within this operation.
///
func glyph(_ name: String, rect: CGRect, colors: [NSColor]) throws
{

    if name == "butterfly" || name == "dragonfly"
    {

        colors[0].setFill()
        for side: CGFloat in [-1, 1]
        {

            let wingX = rect.midX + (side < 0 ? -110 : 10)
            NSBezierPath(ovalIn: CGRect(x: wingX, y: rect.midY, width: 100, height: 100)).fill()
            NSBezierPath(ovalIn: CGRect(x: wingX + 10, y: rect.midY - 75, width: 80, height: 80)).fill()
        }

        colors[1].setFill()
        NSBezierPath(roundedRect: CGRect(x: rect.midX - 12, y: rect.midY - 90, width: 24, height: name == "dragonfly" ? 220 : 180), xRadius: 12, yRadius: 12).fill()
        return
    }

    if name == "bowl"
    {

        colors[0].setFill()
        let bowl = NSBezierPath()
        bowl.move(to: CGPoint(x: rect.minX + 20, y: rect.midY + 20))
        bowl.curve(to: CGPoint(x: rect.maxX - 20, y: rect.midY + 20), controlPoint1: CGPoint(x: rect.midX - 80, y: rect.minY), controlPoint2: CGPoint(x: rect.midX + 80, y: rect.minY))
        bowl.close();
        bowl.fill()
        colors[1].setFill()
        NSBezierPath(ovalIn: CGRect(x: rect.minX + 20, y: rect.midY + 5, width: rect.width - 40, height: 38)).fill()
        return
    }

    if name == "apple"
    {

        colors[0].setFill()
        NSBezierPath(ovalIn: CGRect(x: rect.midX - 100, y: rect.minY + 20, width: 130, height: 175)).fill()
        NSBezierPath(ovalIn: CGRect(x: rect.midX - 30, y: rect.minY + 20, width: 130, height: 175)).fill()
        colors[1].setFill()
        NSBezierPath(roundedRect: CGRect(x: rect.midX - 6, y: rect.minY + 170, width: 12, height: 70), xRadius: 4, yRadius: 4).fill()
        NSBezierPath(ovalIn: CGRect(x: rect.midX + 6, y: rect.minY + 205, width: 65, height: 28)).fill()
        return
    }

    if name == "cactus"
    {

        colors[0].setStroke()
        let plant = NSBezierPath()
        plant.move(to: CGPoint(x: rect.midX, y: rect.minY + 30))
        plant.line(to: CGPoint(x: rect.midX, y: rect.maxY - 20))
        plant.move(to: CGPoint(x: rect.midX, y: rect.minY + 100))
        plant.line(to: CGPoint(x: rect.midX - 70, y: rect.minY + 100))
        plant.line(to: CGPoint(x: rect.midX - 70, y: rect.minY + 175))
        plant.move(to: CGPoint(x: rect.midX, y: rect.minY + 145))
        plant.line(to: CGPoint(x: rect.midX + 65, y: rect.minY + 145))
        plant.line(to: CGPoint(x: rect.midX + 65, y: rect.minY + 210))
        plant.lineWidth = 32;
        plant.lineCapStyle = .round;
        plant.lineJoinStyle = .round;
        plant.stroke()
        colors[1].setFill()
        NSBezierPath(roundedRect: CGRect(x: rect.midX - 58, y: rect.minY, width: 116, height: 48), xRadius: 8, yRadius: 8).fill()
        return
    }

    if name == "shovel"
    {

        colors[0].setFill()
        NSBezierPath(roundedRect: CGRect(x: rect.midX - 12, y: rect.minY + 90, width: 24, height: 125), xRadius: 8, yRadius: 8).fill()
        let blade = NSBezierPath()
        blade.move(to: CGPoint(x: rect.midX - 55, y: rect.minY + 100))
        blade.line(to: CGPoint(x: rect.midX + 55, y: rect.minY + 100))
        blade.line(to: CGPoint(x: rect.midX + 42, y: rect.minY + 35))
        blade.line(to: CGPoint(x: rect.midX, y: rect.minY))
        blade.line(to: CGPoint(x: rect.midX - 42, y: rect.minY + 35))
        blade.close();
        blade.fill()
        colors[1].setStroke()
        let handle = NSBezierPath(roundedRect: CGRect(x: rect.midX - 32, y: rect.maxY - 55, width: 64, height: 48), xRadius: 12, yRadius: 12)
        handle.lineWidth = 14;
        handle.stroke()
        return
    }


    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else
    {

        throw NSError(domain: "CoverGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unavailable symbol: \(name)"])
    }

    let configuration = NSImage.SymbolConfiguration(pointSize: rect.height, weight: .regular)
    .applying(NSImage.SymbolConfiguration(paletteColors: colors))
    (symbol.withSymbolConfiguration(configuration) ?? symbol).draw(in: rect)
}

for (index, cover) in covers.enumerated()
{

    let category = categories.firstIndex(of: cover.category)!
    let palette = palettes[category]
    let background = color(palette[0]);
    let primary = color(palette[1]);
    let accent = color(palette[2])
    guard let context = CGContext(data: nil, width: 960, height: 480, bitsPerComponent: 8, bytesPerRow: 960 * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else
    {
        fatalError("Bitmap allocation failed")
    }

    context.setFillColor(background.cgColor);
    context.fill(CGRect(x: 0, y: 0, width: 960, height: 480))
    context.setFillColor(accent.withAlphaComponent(0.18).cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 960, height: 78))
    let centerX: CGFloat = [480, 440, 520] [index % 3]
    context.setFillColor(NSColor.white.withAlphaComponent(0.65).cgColor)
    context.fillEllipse(in: CGRect(x: centerX - 168, y: 92, width: 336, height: 336))
    // Surrounding objects add scene context without text baked into the artwork.
    context.setFillColor(primary.withAlphaComponent(0.16).cgColor)
    for n in 0 ..< 3
    {

        let x = CGFloat(105 + n * 64 + (index % 4) * 6)
        context.fillEllipse(in: CGRect(x: x, y: CGFloat(160 + n * 38), width: 22, height: 22))
    }

    context.setFillColor(accent.withAlphaComponent(0.25).cgColor)
    context.fillEllipse(in: CGRect(x: 752, y: 328, width: 55, height: 55))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    try glyph(cover.symbol, rect: CGRect(x: centerX - 130, y: 126, width: 260, height: 260), colors: [primary, accent])
    try glyph(cover.context ?? contextSymbols[category], rect: CGRect(x: 720, y: 128, width: 90, height: 90), colors: [accent, primary])
    NSGraphicsContext.restoreGraphicsState()
    let target = output.appendingPathComponent(cover.name).appendingPathExtension("png")
    guard let image = context.makeImage(), let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil) else
    {
        fatalError("PNG output failed")
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else
    {
        fatalError("PNG write failed")
    }

}

print("Generated \(covers.count) expanded covers")
