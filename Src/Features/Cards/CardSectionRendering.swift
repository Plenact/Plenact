// --------------------------------------------------------------------------------------------------
// @file       CardSectionRendering.swift
// @brief      Card detail toolbar and section rendering
// @details    Selects retained section content and contextual controls, using the existing scroll
//             and synchronization context.
//
// --------------------------------------------------------------------------------------------------
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers


///
/// CardDetailView behavior grouped separately from stored view state
///
/// @section    Purpose
///     Keep owner-scoped operations with the existing view while retaining its state and lifecycle.
///
extension CardDetailView
{


    ///
    /// @fcn        CardDetailView.noteToolbar(using:)
    /// @brief      Build the Note editor's persistent lower toolbar
    /// @details    Provides Back, Details, Attachments, text sharing, and Add actions while
    ///             retaining accessible labels and minimum touch targets
    ///
    /// @param[in]  scrollProxy  Scroll proxy used to reveal editor and Details content
    ///
    /// @return     (some View) accessible bottom toolbar for Note editing
    ///
    func noteToolbar(using scrollProxy: ScrollViewProxy) -> some View
    {

        HStack(spacing: 0)
        {

            Button
            {

                dismissEditing()
                dismiss()
            }
            label:
            {

                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Back to previous view")
            .accessibilityIdentifier("note.back")

            Spacer(minLength: 0)

            if !isEditingLocked
            {

                Button
                {

                    dismissEditing()
                    showsNoteDetails.toggle()
                    let target =
                    showsNoteDetails
                    ? "note.detailsStart"
                    : "plenact.noteEditor" /* Scroll anchor selected by Note detail visibility */
                    DispatchQueue.main.async
                    {

                        withAnimation(.easeInOut)
                        {

                            scrollProxy.scrollTo(target, anchor: .top)
                        }

                    }

                }
                label:
                {

                    Image(systemName: showsNoteDetails ? "info.circle.fill" : "info.circle")
                }
                .accessibilityLabel(showsNoteDetails ? "Hide Note details" : "Show Note details")
                .accessibilityIdentifier("note.details")

                Spacer(minLength: 0)

                Button
                {

                    dismissEditing()
                    activeSheet = .noteAttachments
                }
                label:
                {

                    Image(systemName: "paperclip")
                }
                .accessibilityLabel("Note attachments")
                .accessibilityValue("\(attachments.count) attachments")
                .accessibilityIdentifier("note.attachments")

                Spacer(minLength: 0)
            }


            ShareLink(item: NoteTextSharing.text(for: workingCardSnapshot), subject: Text(titleText))
            {

                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share Note text")
            .accessibilityHint(
                                    "Shares the title, body, and attached web links. Does not include photos, videos, or Details."
            )
            .accessibilityIdentifier("note.share")

            Spacer(minLength: 0)

            if !isEditingLocked
            {
                addMenu(using: scrollProxy)
            }

        }
        .font(.title2)
        .buttonStyle(NoteToolbarButtonStyle())
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top)
        {
            Divider()
        }
        .accessibilityIdentifier("note.bottomToolbar")
    }


    ///
    /// @fcn        CardDetailView.cardSection(_:using:)
    /// @brief      Render one configured Card detail section
    /// @details    Selects the section-specific content and actions from the current working
    ///             snapshot, using the scroll proxy when additions need to be revealed.
    ///
    /// @param[in]  section      Card section whose retained content and controls should be rendered
    /// @param[in]  scrollProxy  Detail scroll proxy used to reveal newly requested content
    ///
    /// @return     (some View) requested detail section
    ///
    @ViewBuilder
    func cardSection(_ section: CardSection, using scrollProxy: ScrollViewProxy) -> some View
    {

        switch section
        {

        case .quickActions:
            DetailSection(title: "Quick Actions", collapsible: true)
            {


                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8)
                {


                    ActionTile(
                        title: "Add Checklist", icon: "checklist", color: .green,
                        action:
                        {
                            addChecklist(using: scrollProxy)
                        })
                    ActionTile(
                        title: "Add Attachment", icon: "paperclip", color: .cyan,
                        action:
                        {
                            activeSheet = .attachmentSources
                        }
                    )
                    ActionTile(title: "Members", icon: "person.2", color: .purple, action:
                        {
                            activeSheet = .members
                        })
                }

            }


        case .media:
            if presentation == .card, displayFormat != .picture, let cover = workingCardSnapshot.coverAttachment
            {

                selectedCoverPreview(cover)
                .padding(16)
                .accessibilityIdentifier("card.selectedCoverPreview")
            }


            if presentation == .card
            {

                let visibleAttachments = workingCardSnapshot
                .attachmentsExcludingCover /* Gallery records excluding the featured cover */
                if !visibleAttachments.isEmpty
                {


                    attachmentGallery(visibleAttachments)
                }

            }


        //****************************************************************************//
        // SECTION: Description                                                       //
        //                                                                            //
        //          Presents humorous context assoc with selected card. Text expands  //
        //          vertically so the complete description remains readable           //
        //****************************************************************************//

        case .description:
            if presentation == .card
            {


                DetailSection(title: "Description", collapsible: true)
                {


                    RichTextEditor(
                        placeholder: "Description", text: descriptionEditingBinding,
                        focus: richTextFocusBinding(for: .description)
                    )
                    .onChange(of: descriptionText)
                    {
                        syncCardState()
                    }

                }

            }


        //****************************************************************************//
        // SECTION: Details                                                           //
        //                                                                            //
        //          Presents selected card's dates, labels & meta in aligned rows     //
        //****************************************************************************//

        case .details:
            DetailSection(title: "Details", collapsible: true)
            {


                if startDate != nil
                {


                    dateRow(for: .start)
                    Divider()
                }


                if dueDate != nil
                {


                    dateRow(for: .due)
                    Divider()
                }


                Button
                {

                    activeSheet = .labels
                }
                label:
                {


                    HStack(spacing: 10)
                    {


                        Image(systemName: "tag")
                        .frame(width: 22)
                        .foregroundStyle(.secondary)

                        Text("Labels")

                        Spacer()

                        if selectedLabels.isEmpty
                        {


                            Text("Add labels")
                            .foregroundStyle(.secondary)
                        }
                        else
                        {


                            ForEach(selectedLabels)
                            {
                                label in

                                KanbanLabelChip(label: label)
                            }

                        }

                    }

                    .font(.subheadline)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }

                .buttonStyle(.plain)
                .accessibilityLabel("Edit card labels")

                Divider()

                Button
                {

                    activeSheet = .members
                }
                label:
                {


                    HStack(spacing: 12)
                    {


                        if members.isEmpty
                        {


                            Image(systemName: "person")
                            .frame(width: 22)
                            .foregroundStyle(.secondary)
                        }
                        else
                        {


                            HStack(spacing: -5)
                            {


                                ForEach(Array(members.enumerated()), id: \.offset)
                                {
                                    _, member in

                                    Image(systemName: "person.crop.circle.fill")
                                    .foregroundStyle(memberIconColor(for: member.displayName))
                                }

                            }

                            .frame(minWidth: 22, alignment: .leading)
                        }


                        Text("Members")

                        Spacer()

                        Text(members.isEmpty ? "Add members" : members.map(\.displayName).joined(separator: ", "))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    }

                    .font(.subheadline)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }

                .buttonStyle(.plain)
                .accessibilityLabel("Edit assigned members")
            }


        //****************************************************************************//
        // SECTION: Checklists                                                        //
        //                                                                            //
        //          Presents card's checklist groups & completion state. Checklist    //
        //          creation & deletion update the local collection rendered here     //
        //****************************************************************************//

        case .checklists:
            DetailSection(
                title: "Checklists", collapsible: true, trailing: "plus",
                trailingAction:
                {
                    addChecklist(using: scrollProxy)
                }
            )
            {


                ForEach(checklists)
                {
                    checklist in
                    checklistBlock(for: checklist)
                }

            }


        //****************************************************************************//
        // SECTION: Activity                                                          //
        //                                                                            //
        //          Presents the recent events associated with the selected card      //
        //****************************************************************************//

        case .activity:
            VStack(alignment: .leading, spacing: 10)
            {


                HStack
                {


                    Text("Activity")
                    .font(.headline)

                    Spacer()

                    Menu
                    {

                        Picker("Show", selection: $activityFilter)
                        {

                            ForEach(ActivityFilter.allCases)
                            {
                                filter in
                                Text(filter.title).tag(filter)
                            }

                        }

                    }
                    label:
                    {

                        Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                    }

                    .accessibilityLabel("Activity options")
                    SectionCollapseButton(title: "Activity", isCollapsed: $isActivityCollapsed)
                }


                if !isActivityCollapsed
                {

                    if activityFilter != .cardActivity
                    {


                        ForEach(comments)
                        {
                            comment in
                            CommentActivityRow(
                                comment: comment,
                                memberColor: memberIconColor(for: comment.author)
                            )
                            {

                                deleteComment(with: comment.id)
                            }

                        }

                    }


                    if activityFilter != .comments
                    {


                        ForEach(GeneratedActivity.allCases.filter
                            {
                                !dismissedActivityIDs.contains($0.id)
                            })
                        {

                        activity in
                            ActivityRow(
                                text: activity.text(for: card, actorName: currentUserName),
                                actorColor: memberIconColor(for: currentUserName)
                            )
                            {

                                dismissGeneratedActivity(activity)
                            }

                        }

                    }

                }

            }
            .padding(16)
            .background(.background)
            .overlay(alignment: .bottom)
            {
                Divider()
            }


            HStack(alignment: .bottom, spacing: 10)
            {


                Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(memberIconColor(for: currentUserName))

                RichTextEditor(
                    placeholder: "Comment...", text: $commentDraft,
                    focus: richTextFocusBinding(for: .comment), minimumHeight: 24, verticalInset: 2
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button(action: postComment)
                {

                    Image(systemName: "paperplane.fill")
                    .font(.body.weight(.semibold))
                }

                .disabled(PlanRichText.plain(commentDraft).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Post comment")
            }

            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(height: isActivityCollapsed ? 0 : nil)
            .clipped()
            .opacity(isActivityCollapsed ? 0 : 1)
            .allowsHitTesting(!isActivityCollapsed)
            .accessibilityHidden(isActivityCollapsed)
        }

    }

}
