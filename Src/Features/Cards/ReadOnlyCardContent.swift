// --------------------------------------------------------------------------------------------------
// @file       ReadOnlyCardContent.swift
// @brief      Locked Card and Note reading surfaces
// @details    Displays retained writing, media, and nested checklist context without installing
//             content editing controls.
//
// --------------------------------------------------------------------------------------------------
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers


///
/// Presents locked Card and Note content for reading
///
/// @section    Purpose
///     Displays retained sections and attachments without editing controls and optionally explains
///     how an editable lock can be removed.
///
struct ReadOnlyCardContent: View
{

    @Environment(\.inheritedSubtitleItalic) private var inheritedSubtitleItalic


    let card:             KanbanCard
    let labels:           LabelLibrary
    let onOpenAttachment: (KanbanAttachment) -> Void
    var showsUnlockHint = true

    var body: some View
    {

        ScrollView
        {

            VStack(alignment: .leading, spacing: 18)
            {

                Label("Read-only", systemImage: "lock.fill")
                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .accessibilityIdentifier("card.editingLocked")
                if showsUnlockHint
                {

                    Text("Use Unlock editing in the actions menu to make changes.")
                    .font(.caption).foregroundStyle(.secondary)
                }

                SlideableHeaderText(text: card.word).font(.title2.bold())
                if !card.subtitle.isEmpty
                {
                    Text(card.subtitle)
                        .font((card.appearance?.subtitleItalic ?? inheritedSubtitleItalic) ? .body.italic() : .body)
                        .foregroundStyle(.secondary)
                }

                if let created = card.createdAt
                {
                    NoteCreationDateLabel(createdAt: created)
                }

                if let cover = card.coverAttachment
                {

                    Button
                    {

                        onOpenAttachment(cover)
                    }
                    label:
                    {

                        CardCoverPreview(attachment: cover)
                    }
                    .buttonStyle(.plain).accessibilityLabel("View cover")
                }

                let body = card.presentation == .note ? card.descriptionOverride ?? "" : card.funParagraph
                if !PlanRichText.plain(body).isEmpty
                {

                    Text(PlanRichText.display(body)).textSelection(.enabled)
                }

                CardLocationRow(location: card.location)

                if let start = card.startDate
                {

                    Label("Start: " + card.startDateKind.label(for: start), systemImage: "calendar")
                }

                if let due = card.dueDate
                {

                    Label("Due: " + card.dueDateKind.label(for: due), systemImage: "calendar.badge.clock")
                }

                if !card.checklists.isEmpty
                {

                    Divider()
                    ReadOnlyChecklistContent(checklists: card.checklists)
                }

                if !card.labelIDs.isEmpty
                {

                    Text("Labels").font(.headline)
                    ForEach(labels.labels.filter
                        {
                            card.labelIDs.contains($0.id)
                        })
                    {
                        KanbanLabelChip(label: $0)
                    }

                }

                if !card.members.isEmpty
                {

                    Text("Members").font(.headline)
                    ForEach(card.members)
                    {
                        Text($0.displayName)
                    }

                }

                if !(card.attachmentsExcludingCover).isEmpty
                {

                    Text("Attachments").font(.headline)
                    ScrollView(.horizontal)
                    {

                        HStack
                        {

                            ForEach(card.attachmentsExcludingCover)
                            {
                                attachment in
                                if let url = attachment.url
                                {

                                    Link(destination: url)
                                    {
                                        CardAttachmentThumbnail(attachment: attachment)
                                    }

                                }
                                else
                                {

                                    Button
                                    {

                                        onOpenAttachment(attachment)
                                    }
                                    label:
                                    {

                                        CardAttachmentThumbnail(attachment: attachment)
                                    }
                                    .buttonStyle(.plain).accessibilityLabel("View attachment")
                                }

                            }

                        }

                    }

                }

                ItemReactionPreview(card: card)
                if !card.comments.isEmpty
                {

                    Divider()
                    Text("Comments").font(.headline)
                    ForEach(card.comments)
                    {
                        comment in
                        VStack(alignment: .leading, spacing: 4)
                        {

                            Text(comment.author).font(.subheadline.bold())
                            Text(PlanRichText.display(comment.body)).textSelection(.enabled)
                        }

                    }

                }

            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("card.readOnlyContent")
    }

}


///
/// Renders nested checklist content without mutation controls
///
/// @section    Purpose
///     Keeps completion marks and expanded action details readable while respecting the Card's
///     editing lock.
///
struct ReadOnlyChecklistContent: View
{


    let checklists: [KanbanChecklist]

    var body: some View
    {

        ForEach(checklists)
        {
            checklist in
            VStack(alignment: .leading, spacing: 10)
            {

                Text(checklist.title).font(.headline)
                ForEach(Array(checklist.items.enumerated()), id: \.element.id)
                {
                    index, item in
                    VStack(alignment: .leading, spacing: 6)
                    {

                        HStack(alignment: .top)
                        {

                            Image(
                                systemName: checklist.completedItemIndices.contains(index)
                                ? "checkmark.square.fill" : "square"
                            )
                            .foregroundStyle(.secondary)
                            Text(item.title)
                        }

                        if case .webLink(let url) = item.content
                        {
                            Link(url.absoluteString, destination: url)
                        }

                        if case .actionDetail(let detail) = item.content
                        {

                            Text(PlanRichText.display(detail.description)).textSelection(.enabled)
                            AnyView(ReadOnlyChecklistContent(checklists: detail.checklists)).padding(.leading, 16)
                            ForEach(detail.comments)
                            {
                                comment in
                                Text(comment.author + ": " + PlanRichText.plain(comment.body))
                            }

                        }

                    }

                }

            }

        }

    }

}
