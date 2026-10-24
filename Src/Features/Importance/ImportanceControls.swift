// --------------------------------------------------------------------------------------------------
// @file       ImportanceControls.swift
// @brief      Layered importance stars and deliberate gesture controls
// @details    Presents Tucked or Fanned styling, one-step tap and hold actions, and the native
//             geometry needed to avoid whole-Card lifting.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import ImageIO
import PhotosUI
import Speech
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers


///
/// Renders symbolic layers for an importance level
///
/// @section    Purpose
///     Uses a fixed Tucked footprint or wider Fanned arrangement, with overlapping gold stars
///     rather than a visible numeric rank.
///
struct ImportanceStarCluster: View
{


    let level:         Int
    var style:         ImportanceStarStyle = .tucked
    private var count: Int
    {
        min(5, max(0, level))
    }

    var body: some View
    {

        ZStack(alignment: .topLeading)
        {

            ForEach(Array((0 ..< count).reversed()), id: \.self)
            {
                depth in
                Image(systemName: "star.fill")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(
                    depth == 0
                    ? Color(red: 0.90, green: 0.69, blue: 0.27) : Color(red: 0.72, green: 0.55, blue: 0.25)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 0.4, x: 0, y: 0.4)
                .rotationEffect(.degrees(style == .fanned ? Double(depth) * -9 : 0))
                .offset(x: position(depth: depth).width, y: position(depth: depth).height)
            }

        }
        .frame(width: style == .tucked ? 24 : 28, height: 22, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Importance: \(count) of five")
    }


    ///
    /// @fcn        ImportanceStarCluster.position(depth:)
    /// @brief      Tuck layers into a bounded cluster or arrange a small fan
    /// @details    Front stars stay bright while rear points convey accumulated attention.
    ///
    /// @param[in]  depth  Rear layer depth; zero is the front star
    ///
    /// @return     (CGSize) symbol offset within the preview footprint
    ///
    private func position(depth: Int) -> CGSize
    {

        if count == 1
        {
            return CGSize(width: 5, height: 4)
        }

        if style == .fanned
        {
            return CGSize(width: 3 + Double(depth) * 3.1, height: 7 - Double(depth) * 1.5)
        }

        let positions: [CGSize] = [
            CGSize(width: 6, height: 8), CGSize(width: 0, height: 3),
            CGSize(width: 11, height: 2), CGSize(width: 3, height: 0), CGSize(width: 8, height: 0)
        ]
        return positions[depth]
    }

}


///
/// Provides incremental importance gestures
///
/// @section    Purpose
///     A tap increases one level up to five; a hold decreases one level to zero and excludes the
///     control from whole-Card lifting.
///
struct ImportantItemIndicator: View
{


    let cardID:  Int
    var ownerID: UUID? = nil
    @AppStorage("Plenact.LibraryImportant.v1") private var importantData = Data()
    @AppStorage(PlanPreferencesStore.key) private var preferencesData = Data()
    @AppStorage(LocalProfileStore.storageKey) private var profileData = Data()
    @Environment(\.cardMovementSource) private var source
    @Environment(\.libraryImportance) private var importance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var level: Int
    {

        if let owner = ownerID ?? source
        {

            return LibraryImportanceSelection.level(cardID: cardID, collectionID: owner, data: importantData)
        }

        return importance?.level(cardID) ?? 0
    }

    var body: some View
    {

        if level > 0
        {

            Button
            {

                adjustImportance(by: 1)
            }
            label:
            {

                ImportanceStarCluster(
                    level: level,
                    style: PlanPreferencesStore.resolved(
                        preferencesData: preferencesData, profileData: profileData
                    ).importanceStarStyle
                )
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: level)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(ImportanceInteractionRegion())
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.55, maximumDistance: 12)
                .exclusively(before: TapGesture())
                .onEnded
                {
                    result in
                    switch result
                    {

                    case .first(let completed):
                        if completed
                        {
                            adjustImportance(by: -1)
                        }

                    case .second:
                        adjustImportance(by: 1)
                    }

                }
            )
            .accessibilityHint("Tap to increase importance. Touch and hold to decrease it by one star.")
            .accessibilityLabel(level == 5 ? "Maximum importance" : "Increase importance")
            .accessibilityValue("\(level) of five")
            .accessibilityIdentifier("item.important")
            .accessibilityAction(named: "Decrease importance")
            {
                adjustImportance(by: -1)
            }

        }

    }


    ///
    /// @fcn        ImportantItemIndicator.adjustImportance(by:)
    /// @brief      Apply one mutually exclusive tap or hold gesture to the current importance
    /// @details    Shares owner-qualified persistence with menu actions. A successful hold gives
    ///             one selection haptic and never repeats while the finger remains down.
    ///
    /// @param[in]  direction  Positive adds a layer; negative removes one
    ///
    /// @return     (Void) changes importance by at most one bounded step
    ///
    private func adjustImportance(by direction: Int)
    {

        let previous = level
        guard direction > 0 ? previous < 5 : previous > 0 else
        {
            return
        }

        if let owner = ownerID ?? source
        {

            importantData = LibraryImportanceSelection.adjusting(
                cardID: cardID, collectionID: owner,
                direction: direction, data: importantData)
        }
        else
        {

            importance?.adjust(cardID, direction)
        }

        if direction < 0
        {
            UISelectionFeedbackGenerator().selectionChanged()
        }

    }

}


///
/// Marks importance controls for native drag exclusion
///
/// @section    Purpose
///     Supplies their mounted bounds so a star hold changes importance instead of lifting the
///     entire Card.
///
struct ImportanceInteractionRegion: UIViewRepresentable
{


    ///
    /// Marks the native bounds of an importance control
    ///
    /// @section    Purpose
    ///     Provides geometry for whole-Card drag exclusion while SwiftUI continues to own star tap
    ///     and hold gestures.
    ///
    final class Marker: UIView
    {

    }


    ///
    /// @fcn        ImportanceInteractionRegion.makeUIView(context:)
    /// @brief      Create a noninteractive native marker behind the star control
    /// @details    SwiftUI owns the importance gesture; this marker supplies only its bounds.
    ///
    /// @param[in]  context  SwiftUI bridge context
    ///
    /// @return     (Marker) transparent geometry marker
    ///
    func makeUIView(context: Context) -> Marker
    {

        let marker = Marker()
        marker.isUserInteractionEnabled = false
        return marker
    }


    ///
    /// @fcn        ImportanceInteractionRegion.updateUIView(_:context:)
    /// @brief      Keep the geometry marker free of touch handling
    /// @details    Layout follows the control automatically; no gesture is installed here.
    ///
    /// @param[in]  marker   Existing native marker
    /// @param[in]  context  SwiftUI bridge context
    ///
    /// @return     (Void) no persistent state changes
    ///
    func updateUIView(_ marker: Marker, context: Context)
    {

    }


    ///
    /// @fcn        ImportanceInteractionRegion.contains(_:from:in:)
    /// @brief      Determine whether a native drag starts over an importance control
    /// @details    Converts coordinates for visible marker descendants, including nested hosting
    ///             containers. Unmarked parts of the Card retain their ordinary drag behavior.
    ///
    /// @param[in]  point            Touch position supplied by the drag session
    /// @param[in]  coordinateSpace  View whose coordinates define the point
    /// @param[in]  root             Card content subtree hosting the drag interaction
    ///
    /// @return     (Bool) true only inside a visible importance marker
    ///
    static func contains(_ point: CGPoint, from coordinateSpace: UIView, in root: UIView) -> Bool
    {

        guard !root.isHidden, root.alpha > 0.01 else
        {
            return false
        }

        if root is Marker, root.bounds.contains(root.convert(point, from: coordinateSpace))
        {
            return true
        }

        return root.subviews.contains
        {
            contains(point, from: coordinateSpace, in: $0)
        }

    }

}


///
/// Edits the user's importance-star presentation
///
/// @section    Purpose
///     Previews Tucked and Fanned arrangements while changing only visual preference, never an
///     item's stored level.
///
struct ImportanceStarStylePicker: View
{


    @Binding var selection: ImportanceStarStyle
    var body:               some View
    {

        Picker("Importance stars", selection: $selection)
        {

            ForEach(ImportanceStarStyle.allCases)
            {
                style in
                HStack
                {

                    Text(style.title)
                    ImportanceStarCluster(level: 4, style: style)
                } .tag(style)
            }

        }
        .accessibilityIdentifier("settings.importanceStarStyle")
    }

}
