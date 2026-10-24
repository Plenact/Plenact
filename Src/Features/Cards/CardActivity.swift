// --------------------------------------------------------------------------------------------------
// @file       CardActivity.swift
// @brief      Card comments, generated activity, and emoji controls
// @details    Presents retained and derived activity while delegating mutations and authored
//             reactions to the current item owner.
//
// --------------------------------------------------------------------------------------------------
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers


// --------------------------------------- MARK: - Activity ------------------------------------- //


///
/// Displays one activity event associated with the card
///
/// @section    Purpose
///     Render a compact activity entry with actor styling, event text, and timestamp
///
struct ActivityRow: View
{


    let text:       String      /* The main text content of the activity row */
    let actorColor: Color       /* The icon color for the activity actor     */
    let onDelete:   () -> Void  /* Activity deletion callback                */


    ///
    /// @fcn        ActivityRow.body
    /// @brief      Build the activity event row
    /// @details    Places generated activity copy beside the actor symbol inside a shared swipe-delete row
    ///
    /// @return     (some View) rendered activity row
    /// @post       Deletion delegates to onDelete rather than removing a stored event directly
    /// @note       Today at 7:00 AM is fixed display copy, not a timestamp from persisted activity
    ///
    var body: some View
    {  /* Generated activity text and timestamp */


        ActivitySwipeRow(onDelete: onDelete)
        {


            HStack(alignment: .top, spacing: 10)
            {


                Image(systemName: "person.crop.circle.fill")
                .foregroundStyle(actorColor)

                VStack(alignment: .leading, spacing: 3)
                {


                    Text(text)
                    .font(.subheadline)

                    Text("Today at 7:00 AM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

            }

        }

    }

}


///
/// Renders a posted card comment and its authoring time in the activity feed
///
/// @section    Purpose
///     Present comment text and author context with a consistent activity timestamp
///
struct CommentActivityRow: View
{


    let comment:     KanbanComment  /* The comment data rendered by the row           */
    let memberColor: Color          /* The assigned icon color for the comment author */
    let onDelete:    () -> Void     /* The action invoked when the comment is deleted */

    ///
    /// @fcn        CommentActivityRow.body
    /// @brief      Present a stored comment with author styling and creation time
    /// @details    Combines author/body text and formats the persisted timestamp using abbreviated
    ///             date and shortened time inside the shared swipe-delete container
    ///
    /// @return     (some View) deletable comment activity row
    /// @post       Rendering does not modify the comment; deletion delegates to onDelete
    ///
    var body: some View
    {  /* Posted comment and authoring time */

        ActivitySwipeRow(onDelete: onDelete)
        {


            HStack(alignment: .top, spacing: 10)
            {


                Image(systemName: "person.crop.circle.fill")
                .foregroundStyle(memberColor)

                VStack(alignment: .leading, spacing: 3)
                {


                    (Text(comment.author).fontWeight(.semibold) + Text(" ") + Text(PlanRichText.display(comment.body)))
                    .font(.subheadline)

                    Text(comment.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

            }

        }

    }

}


// -------------------------------------- MARK: - Previews -------------------------------------- //


///
/// Adds a trailing delete action revealed by swiping an activity row
///
/// @section    Purpose
///     Reuse one accessible swipe-to-delete presentation for card activity entries
///
struct ActivitySwipeRow<Content: View>: View
{


    let onDelete:                        () -> Void     /* The action invoked when the row is deleted     */
    let deletionAccessibilityLabel:      String         /* Accessibility label for the swipe action       */
    @ViewBuilder let content:            () -> Content  /* The content view rendered inside the swipe row */
    @State private var horizontalOffset: CGFloat = 0    /* The current horizontal offset of the swipe row */


    ///
    /// @fcn        ActivitySwipeRow.init(onDelete:deletionAccessibilityLabel:content:)
    /// @brief      Configure a reusable trailing destructive action
    /// @details    Retains the deletion callback, accessibility label, and content builder
    ///
    /// @param[in]  onDelete                    Delete action invoked by the exposed button or a full left swipe
    /// @param[in]  deletionAccessibilityLabel  Accessible description for the delete action
    /// @param[in]  content                     Row content shown above the destructive background
    ///
    /// @return     (ActivitySwipeRow) configured activity row
    /// @post       Content construction and deletion are deferred until rendering/interaction
    ///
    init(
        onDelete: @escaping () -> Void,
        deletionAccessibilityLabel: String = "Delete activity",
        @ViewBuilder content: @escaping () -> Content
    )
    {


        self.onDelete = onDelete
        self.deletionAccessibilityLabel = deletionAccessibilityLabel
        self.content = content
    }


    ///
    /// @fcn        ActivitySwipeRow.body
    /// @brief      Wrap content in a custom horizontal swipe-to-delete surface
    /// @details    Clamps leftward translation to a 72-point button width and ignores vertical-dominant
    ///             gestures. Release beyond 36 points reveals the button; beyond 120 points deletes directly
    ///
    /// @return     (some View) clipped content over an accessible destructive button
    /// @post       Deletion invokes onDelete without a separate confirmation dialog;
    ///             smaller horizontal releases animate closed or open according to the threshold
    ///
    var body: some View
    {  /* Swipe-to-delete activity container */


        ZStack(alignment: .trailing)
        {


            Button(role: .destructive, action: onDelete)
            {


                Image(systemName: "trash")
                .foregroundStyle(.white)
                .frame(width: 72)
                .frame(maxHeight: .infinity)
                .background(.red)
            }

            .buttonStyle(.plain)
            .accessibilityLabel(deletionAccessibilityLabel)

            content()
            .padding(.vertical, 7)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background)
            .offset(x: horizontalOffset)
            .simultaneousGesture(

                DragGesture(minimumDistance: 12)
                .onChanged
                {
                    value in
                    guard abs(value.translation.width) > abs(value.translation.height) else
                    {


                        return
                    }

                    horizontalOffset = min(0, max(-72, value.translation.width))
                }

                .onEnded
                {
                    value in
                    guard abs(value.translation.width) > abs(value.translation.height) else
                    {


                        return
                    }

                    withAnimation(.easeOut(duration: 0.2))
                    {

                        if value.translation.width < -120
                        {


                            onDelete()
                        }
                        else
                        {

                            horizontalOffset = value.translation.width < -36 ? -72 : 0
                        }

                    }

                }
            )
        }

        .clipped()
    }

}


///
/// Presents authored emoji reactions and reaction actions
///
/// @section    Purpose
///     Groups matching emoji for display and delegates toggling or adding to the owner using the
///     current author identity.
///
struct ItemReactionStrip: View
{


    let reactions:      [ItemEmojiReaction]
    let authorID:       UUID?
    let onToggle:       (String) -> Void
    let onAdd:          () -> Void
    private var emojis: [String]
    {
        reactions.reduce(into: [])
        {
            if !$0.contains($1.emoji)
            {
                $0.append($1.emoji)
            }

        }

    }

    var body: some View
    {

        ScrollView(.horizontal)
        {

            HStack(spacing: 8)
            {

                ForEach(emojis, id: \.self)
                {
                    emoji in
                    let matching = reactions.filter
                    {
                        $0.emoji == emoji
                    }

                    let mine = matching.contains
                    {
                        $0.authorID == authorID
                    }

                    Button
                    {

                        onToggle(emoji)
                    }
                    label:
                    {

                        HStack(spacing: 4)
                        {

                            Text(emoji).font(.title3)
                            if matching.count > 1
                            {
                                Text("\(matching.count)").font(.caption)
                            }

                        }
                        .padding(.horizontal, 10).frame(minHeight: 44)
                        .background(
                            mine ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(emoji), \(matching.count) reaction\(matching.count == 1 ? "" : "s")")
                    .accessibilityHint(mine ? "Remove your reaction" : "Add your reaction")
                }

                Button(action: onAdd)
                {

                    Label("Add reaction", systemImage: "face.smiling").font(.subheadline).frame(minHeight: 44)
                }
                .buttonStyle(.plain).foregroundStyle(.tint)
                .accessibilityIdentifier("item.addReaction")
            }

        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

}


///
/// Presents suggested and custom emoji choices
///
/// @section    Purpose
///     Reports a selected reaction through the callback and dismisses without writing Card state
///     directly.
///
struct ItemReactionPicker: View
{


    let selected: Set<String>
    let onChoose: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var custom = ""
    private let choices = [
            "❤️", "👍", "🎉", "😊", "✨", "💪", "🔥", "🙌", "🤔", "🙏", "👏", "😂", "😍", "🥰", "🌱", "☀️", "😅", "😮", "😔", "💡", "🎯", "🫶",
            "😎", "✅"
    ]


    ///
    /// @fcn        ItemReactionPicker.choose
    /// @brief      Submit a chosen emoji and close the picker
    /// @details    Invokes the supplied emoji callback and then dismisses; validation and persistence belong to the
    ///             callback's owner.
    ///
    /// @param[in]  emoji  Emoji text proposed for a reaction or check-in mood
    ///
    /// @return     (Void) no return value
    ///
    private func choose(_ emoji: String)
    {
        onChoose(emoji);
        dismiss()
    }

    var body: some View
    {

        NavigationStack
        {

            Form
            {

                Section
                {

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 12)
                    {

                        ForEach(choices, id: \.self)
                        {
                            emoji in
                            Button
                            {

                                choose(emoji)
                            }
                            label:
                            {

                                Text(emoji).font(.largeTitle).frame(width: 48, height: 48)
                                .background(
                                    selected.contains(emoji) ? Color.accentColor.opacity(0.15) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(emoji)
                            .accessibilityHint(selected.contains(emoji) ? "Remove your reaction" : "Add your reaction")
                        }

                    }

                }
                footer:
                {

                    Text(
                                                            "Choose what feels right. Tap one of your reactions again to remove it. Reactions do not change importance, bookmarks, or completion."
                    )
                }

                Section("Another emoji")
                {

                    TextField("Type or paste one emoji", text: $custom).textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    Button("Use emoji")
                    {
                        if let emoji = ItemEmojiReaction.validatedEmoji(custom)
                        {
                            choose(emoji)
                        }

                    }
                    .disabled(ItemEmojiReaction.validatedEmoji(custom) == nil)
                }

            }
            .navigationTitle("Add reaction").navigationBarTitleDisplayMode(.inline)
            .toolbar
            {
                ToolbarItem(placement: .cancellationAction)
                {
                    Button("Cancel")
                    {
                        dismiss()
                    }

                }

            }

        }
        .presentationDetents([.medium, .large])
    }

}


///
/// Displays a noninteractive reaction summary
///
/// @section    Purpose
///     Keeps Card preview opening, reordering, and swipe gestures available rather than adding
///     reaction mutation controls.
///
struct ItemReactionPreview: View
{


    let card:           KanbanCard
    private var emojis: [String]
    {

        card.previewReactions.reduce(into: [])
        {
            if !$0.contains($1.emoji)
            {
                $0.append($1.emoji)
            }

        }

    }

    var body: some View
    {

        if !emojis.isEmpty
        {

            ViewThatFits(in: .horizontal)
            {

                summary(emojis)
                summary(Array(emojis.prefix(3)), remaining: max(0, emojis.count - 3))
                Text("😊 \(card.previewReactions.count)").font(.caption)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                                    "Reactions: "
                                    + emojis.map
                                    {
                                        emoji in
                                                                            "\(emoji), \(card.previewReactions.filter { $0.emoji == emoji } .count)"
                                    } .joined(separator: ", "))
        }

    }


    ///
    /// @fcn        ItemReactionPreview.summary
    /// @brief      Build a compact emoji and reaction-count preview
    /// @details    Displays each distinct visible emoji, its count when greater than one, and an additional-emoji
    ///             count when the supplied remaining value is positive.
    ///
    /// @param[in]  values     Values to summarize in their supplied order
    /// @param[in]  remaining  Number of additional reactions omitted from the visible emoji summary
    ///
    /// @return     (some View) a compact emoji and reaction-count preview
    ///
    private func summary(_ values: [String], remaining: Int = 0) -> some View
    {

        HStack(spacing: 6)
        {

            ForEach(values, id: \.self)
            {
                emoji in
                HStack(spacing: 2)
                {

                    Text(emoji)
                    let count = card.previewReactions.filter
                    {
                        $0.emoji == emoji
                    } .count
                    if count > 1
                    {
                        Text("\(count)").font(.caption2).foregroundStyle(.secondary)
                    }

                }

            }

            if remaining > 0
            {
                Text("+\(remaining)").font(.caption).foregroundStyle(.secondary)
            }

        } .font(.subheadline).fixedSize()
    }

}
