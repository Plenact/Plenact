// --------------------------------------------------------------------------------------------------
// @file       CardPreview.swift
// @brief      Shared Card, Note, and picture List previews
// @details    Resolves display metadata, completion badges, importance, and preview content
//             without converting canonical records.
//
// --------------------------------------------------------------------------------------------------
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers


///
/// Adds completion status to picture and icon Card previews
///
/// @section    Purpose
///     Retains the visual preview, overlays a completion badge, and disables mutations when the
///     Card is locked.
///
struct CardVisualCompletion: ViewModifier
{


    let card:     KanbanCard
    let onToggle: () -> Void


    ///
    /// @fcn        CardVisualCompletion.body(content:)
    /// @brief      Add completion interaction and a contrasting badge to a checkable visual
    /// @details    Preserves Notes as ordinary previews. Completed Cards retain their image with
    ///             a lower-right checkmark; editing locks disable the completion action.
    ///
    /// @param[in]  content  Existing picture or icon preview
    ///
    /// @return     (some View) original visual with accessible completion when applicable
    ///
    @ViewBuilder
    func body(content: Content) -> some View
    {

        if card.presentation == .card && !card.isSectionDivider
        {

            Button
            {

                guard !card.isEditingLocked else
                {
                    return
                }

                onToggle()
            }
            label:
            {

                content
                .overlay(alignment: .bottomTrailing)
                {

                    if card.isTitleChecked
                    {

                        Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .green)
                        .padding(2)
                        .background(Circle().fill(Color(.systemBackground)))
                        .padding(2)
                        .accessibilityHidden(true)
                    }

                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(card.isEditingLocked)
            .accessibilityLabel(card.isTitleChecked ? "Mark \(card.word) unfinished" : "Mark \(card.word) complete")
            .accessibilityValue(card.isTitleChecked ? "Completed" : "Not completed")
            .accessibilityIdentifier("card.visualCompletion")
        }
        else
        {

            content
        }

    }

}


///
/// Displays a compact summary of a kanban card
///
/// @section    Purpose
///     Present the title, supporting copy, and compact metadata used to scan cards on the board
///
struct KanbanCardView: View
{


    @AppStorage("Plenact.CardCovers.enabled") private var showsCardCovers =
    true                                            /* Shared display-only preference                                */
    let card:                KanbanCard             /* The kanban card being displayed                               */
    let height:              CGFloat                /* Minimum card height; content may grow                         */
    let displaySettings:     BoardDisplaySettings   /* Settings controlling which elements of the card are displayed */
    var cardBackground:      KanbanListTint? = nil  /* Board-scoped tint, independent of item banner metadata        */
    var compactCards:        Bool = false
    var titleColor:          ListPreviewTextColor? = nil
    var supportingTextColor: ListPreviewTextColor? = nil
    var listedOnDate:        Date? = nil // Assigned day from the list, independent of its editable title.
    /// Layout preset used to select compact card dimensions.
    var presentation: BoardPresentation = .standard  /* Board layout controlling the card row's density     */
    let labelLibrary: LabelLibrary                   /* Shared label catalog used to resolve card label IDs */
    let onUpdateCard: (KanbanCard) -> Void           /* The action invoked when card details are updated    */
    let onDeleteCard: () -> Void                     /* The action invoked when this card is deleted        */
    /// Requests archival of the displayed card.
    let onArchiveCard: () -> Void  /* Archives this card through its containing list             */
    let onToggle:      () -> Void  /* Callback invoked when the card's title checkbox is toggled */

    /// Plain writing keeps previews readable without changing the stored rich note.
    private var noteExcerpt: String
    {

        PlanRichText.plain(card.descriptionOverride ?? "")
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }


    @State private var renameDraft = ""            /* Draft text for the rename operation                        */
    @State private var isRenaming = false          /* Flag indicating if the rename operation is active          */
    @State private var isEditingInfo = false       /* Flag indicating if the card info editing mode is active    */
    @State private var isConfirmingDelete = false  /* Flag indicating if the delete confirmation dialog is shown */
    /// Current Dynamic Type size used to adapt the compact card layout.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize /* Text-size category used for adaptive card content */


    ///
    /// @fcn        KanbanCardView.trimmedRenameDraft
    /// @brief      Normalize the proposed card name
    /// @details    Trims outer whitespace/newlines for validation and submission without editing the draft
    ///
    /// @return     (String) normalized rename text
    /// @post       Card content and draft state remain unchanged
    ///
    private var trimmedRenameDraft: String
    {  /* Normalized rename input */

        renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }


    ///
    /// @fcn        KanbanCardView.cardLabels
    /// @brief      Resolve assigned label identities into display definitions
    /// @details    Preserves card label-ID order and omits IDs absent from the supplied library
    ///
    /// @return     ([KanbanLabel]) resolved labels for card badges
    /// @post       Unresolved IDs are not removed from the card
    ///
    private var cardLabels: [KanbanLabel]
    {  /* Resolved labels shown on this card */

        card.labelIDs.compactMap
        {
            labelID in
            labelLibrary.labels.first(where:
                {
                    $0.id == labelID
                })
        }

    }


    ///
    /// @fcn        KanbanCardView.cardUpdated(title:subtitle:description:)
    /// @brief      Create a card snapshot containing edited display information
    /// @details    Replaces the title, subtitle, and description while preserving the card's
    ///             identity and other state
    ///
    /// @param[in]  title        Updated card title
    /// @param[in]  subtitle     Optional board subtitle override
    /// @param[in]  description  Updated detail description
    ///
    /// @return     (KanbanCard) updated card retaining its dates, checklist, comments, completion,
    ///             and activity state
    ///
    /// @pre        Values come from the current card edit operation
    /// @post       The original card remains unchanged; the returned snapshot contains the
    ///             requested display values
    ///
    private func cardUpdated(title: String, subtitle: String?, description: String?) -> KanbanCard
    {


        KanbanCard(
            id: card.id,
            word: title,
            listTitle: card.listTitle,
            isDivider: card.isDivider,
            isTitleChecked: card.isTitleChecked,
            startDate: card.startDate,
            dueDate: card.dueDate,
            checklists: card.checklists,
            comments: card.comments,
            members: card.members,
            labelIDs: card.labelIDs,
            attachments: card.attachments,
            coverAttachmentID: card.coverAttachmentID,
            dismissedActivityIDs: card.dismissedActivityIDs,
            descriptionOverride: description,
            subtitleOverride: subtitle,
            presentation: card.presentation,
            createdAt: card.createdAt,
            appearance: card.appearance,
            listDisplayFormat: card.listDisplayFormat,
            sectionLayout: card.sectionLayout,
            showsDueDateInList: card.showsDueDateInList,
            startDateKind: card.startDateKind,
            dueDateKind: card.dueDateKind,
            reactions: card.reactions,
            showsReactionsInPreviews: card.showsReactionsInPreviews
        )
    }


    ///
    /// @fcn        KanbanCardView.renameCard()
    /// @brief      Submit the renamed card title
    /// @details    Trims the title draft, ignores an empty result, and sends the updated card to
    ///             the board callback
    ///
    /// @return     (Void) requests a card update when the trimmed title is not empty
    ///
    /// @pre        renameDraft contains the title entered in the Rename Card alert
    /// @post       A valid title is synchronized to board state; an empty title causes no change
    ///
    private func renameCard()
    {


        guard !trimmedRenameDraft.isEmpty else
        {


            return
        }


        onUpdateCard(
            cardUpdated(
                title: trimmedRenameDraft,
                subtitle: card.subtitleOverride,
                description: card.descriptionOverride
            ))
    }


    ///
    /// @fcn        KanbanCardView.body
    /// @brief      Render a content-fitting card summary and card action menu
    /// @details    Shows completion, supporting text, up to three label chips plus overflow,
    ///             and preference-controlled metadata badges. Provides archive, confirmed delete,
    ///             validated rename, and full display-text editing
    ///
    /// @return     (some View) card summary with alerts and information-editor presentation
    /// @post       All card mutations delegate to parent callbacks; local state controls presentations only
    /// @note       Due-date badges require a stored date and this card's saved visibility setting
    ///
    private var showsHeaderTimes: Bool
    {

        displaySettings.showDueDateBadges && card.showsDueDateInList && card.usesTimeOnlySchedule(on: listedOnDate)
    }


    private var headerTimes: some View
    {

        VStack(alignment: .trailing, spacing: 2)
        {

            ForEach(Array(card.scheduleBadges(on: listedOnDate).enumerated()), id: \.offset)
            {
                _, badge in
                Text(badge.value)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityLabel(badge.title + ", " + badge.value)
                .modifier(CardPreviewDateEditor(card: card, isStart: badge.title.hasPrefix("Start"), onUpdate: onUpdateCard))
            }

        }
        .fixedSize()
    }


    var body: some View
    {  /* Compact card summary and card actions */


        VStack(alignment: .leading, spacing: compactCards ? 2 : 9)
        {

            if (card.displayFormat == .title || card.displayFormat == .text) && !compactCards
            {

                HStack(alignment: .top, spacing: 8)
                {

                    Text(card.word)
                    .font(card.displayFormat == .title ? .title2.weight(.bold) : .body)
                    .foregroundStyle((card.appearance?.cardTitleColor ?? titleColor)?.color ?? .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(card.displayFormat == .title ? .isHeader : [])
                    HStack(alignment: .top, spacing: 4)
                    {

                        cardActions
                        ImportantItemIndicator(cardID: card.id)
                    }

                }

            }
            else if card.displayFormat == .picture && !compactCards
            {

                ItemPicturePreview(attachment: card.coverAttachment, title: card.word)
                .modifier(CardVisualCompletion(card: card, onToggle: onToggle))
                .overlay(alignment: .topTrailing)
                {

                    ImportantItemIndicator(cardID: card.id).padding(10)
                }

            }
            else
            {


                if !compactCards && showsCardCovers, let cover = card.coverAttachment
                {  /* Featured attachment allowed by the current display settings */


                    CardCoverPreview(attachment: cover, height: presentation == .overview ? 72 : 128)
                }


                HStack(alignment: .top, spacing: 8)
                {


                    if card.displayFormat == .picture
                    {

                        Group
                        {

                            if let attachment = card.coverAttachment
                            {

                                CardCoverPreview(attachment: attachment, height: 44)
                            }
                            else
                            {

                                Image(systemName: "photo").foregroundStyle(.secondary)
                            }

                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .modifier(CardVisualCompletion(card: card, onToggle: onToggle))
                    }
                    else if card.presentation == .note
                    {


                        Image(systemName: "note.text")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("Note")
                    }
                    else
                    {


                        Button
                        {

                            onToggle()
                        }
                        label:
                        {

                            Image(systemName: card.isTitleChecked ? "checkmark.square.fill" : "square")
                            .font(.headline)
                            .foregroundStyle(card.isTitleChecked ? .green : .secondary)
                            .frame(width: 44, height: 44)
                        }

                        .buttonStyle(.plain)
                        .accessibilityLabel(card.isTitleChecked ? "Uncheck card title" : "Check card title")
                        .disabled(card.isEditingLocked)
                    }


                    ItemAppearanceMark(appearance: card.appearance)
                    Text(card.word)
                    .font(.headline)
                    .foregroundStyle((card.appearance?.cardTitleColor ?? titleColor)?.color ?? .primary)
                    .lineLimit(
                        dynamicTypeSize.isAccessibilitySize
                        ? nil : (compactCards ? 1 : (presentation == .overview ? 2 : 3))
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                    VStack(alignment: .trailing, spacing: 4)
                    {

                        HStack(alignment: .top, spacing: 4)
                        {

                            if compactCards
                            {
                                cardActions
                            }

                            ImportantItemIndicator(cardID: card.id)
                        }

                        if showsHeaderTimes
                        {
                            headerTimes
                        }

                    }

                }
                .itemBannerBackground(card.appearance)

                if !compactCards && presentation == .standard && card.presentation == .note
                {


                    if !noteExcerpt.isEmpty
                    {

                        Text(noteExcerpt)
                        .font(.subheadline)
                        .foregroundStyle(
                            (card.appearance?.cardTextColor ?? supportingTextColor)?.color ?? .secondary
                        )
                        .lineSpacing(3)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                }
                else if !compactCards && presentation == .standard && !card.subtitle.isEmpty
                {


                    Text(card.subtitle)
                    .font(.subheadline)
                    .foregroundStyle((card.appearance?.cardTextColor ?? supportingTextColor)?.color ?? .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                }


                if !compactCards && presentation == .standard && !cardLabels.isEmpty
                {


                    ViewThatFits(in: .horizontal)
                    {

                        HStack(spacing: 5)
                        {

                            ForEach(cardLabels.prefix(3))
                            {
                                label in
                                KanbanLabelChip(label: label)
                            }


                            if cardLabels.count > 3
                            {


                                Text("+\(cardLabels.count - 3)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                            }

                        }

                        .fixedSize(horizontal: true, vertical: false)
                        Text("\(cardLabels.count) labels")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                }


                HStack(alignment: .center, spacing: 4)
                {

                    ViewThatFits(in: .horizontal)
                    {

                        if !dynamicTypeSize.isAccessibilitySize
                        {


                            HStack(spacing: 10)
                            {
                                cardBadges
                            }
                            .fixedSize(horizontal: true, vertical: false)
                        }


                        VStack(alignment: .leading, spacing: 4)
                        {

                            cardBadges
                        }

                    }

                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !compactCards
                    {
                        cardActions
                    }

                }

            }

            ItemReactionPreview(card: card)
        }

        .fixedSize(horizontal: false, vertical: true)
        .padding(
            .horizontal,
            card.displayFormat == .picture && !compactCards ? 0 : (compactCards || presentation == .overview ? 8 : 12)
        )
        .padding(
            .vertical,
            card.displayFormat == .picture && !compactCards
            ? 0 : (compactCards ? 4 : (presentation == .overview ? 8 : 12))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(
            minHeight: ([.title, .text].contains(card.displayFormat)
                || (card.displayFormat == .picture && !compactCards)
                || (!compactCards && card.presentation == .note && noteExcerpt.isEmpty)) ? 0 : height, alignment: .top
        )
        .background
        {

            ZStack
            {

                if card.displayFormat != .title && card.displayFormat != .text
                {

                    Color(.systemBackground)
                }

                if ![.title, .text].contains(card.displayFormat) && (compactCards || card.displayFormat != .picture),
                let tint = card.appearance?.cardBackground ?? cardBackground, tint != .neutral
                {

                    tint.color
                }

            }

        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(
            color: .black.opacity(card.displayFormat == .title || card.displayFormat == .text ? 0 : 0.10), radius: 3,
            y: 2
        )
        .padding(.horizontal, 4)
        .alert("Rename \(card.displayFormat.title)", isPresented: $isRenaming)
        {


            TextField("\(card.displayFormat.title) title", text: $renameDraft).textInputAutocapitalization(.sentences)

            Button("Cancel", role: .cancel)
            {

            }


            Button("Rename", action: renameCard)
            .disabled(trimmedRenameDraft.isEmpty)
        }
        message:
        {


            Text("Enter a new title for this \(card.displayFormat.title.lowercased()).")
        }

        .confirmationDialog("Delete \(card.word)?", isPresented: $isConfirmingDelete, titleVisibility: .visible)
        {


            Button("Delete \(card.displayFormat.title)", role: .destructive, action: onDeleteCard)
            Button("Cancel", role: .cancel)
            {

            }

        }

        .sheet(isPresented: $isEditingInfo)
        {

            CardInfoEditorSheet(card: card)
            {
                title, subtitle, description in
                onUpdateCard(cardUpdated(title: title, subtitle: subtitle, description: description))
            }

            .databaseActivityOverlay()
        }

    }


    ///
    /// @fcn        KanbanCardView.cardActions
    /// @brief      Provide the card's archive, delete, rename, and edit actions
    /// @details    Builds the ellipsis menu and delegates each operation to the card callbacks
    ///
    /// @return     (some View) accessible card-action menu
    /// @post       Card state changes only after a selected action is invoked
    ///
    private var cardActions: some View
    {  /* Item-kind, cover, archive, deletion, and editing menu */

        Menu
        {

            ItemDisplayFormatMenu(card: card, onUpdate: onUpdateCard)
            CardDestinationMenu(card: card)
            if !card.isSectionDivider
            {

                Toggle(
                                                "Show reactions in previews",
                                                isOn: Binding(
                                                    get:
                                                    {
                                                        card.showsReactionsInPreviews != false
                                                    },
                                                    set:
                                                    {
                                                        visible in
                                                        var updated = card
                                                        updated.showsReactionsInPreviews = visible
                                                        onUpdateCard(updated)
                                                    }))
                Toggle(
                                                "Show due date in lists",
                                                isOn: Binding(
                                                    get:
                                                    {
                                                        card.showsDueDateInList
                                                    },
                                                    set:
                                                    {
                                                        visible in
                                                        var updated = card
                                                        updated.showsDueDateInList = visible
                                                        onUpdateCard(updated)
                                                    }))
            }


            if card.coverAttachmentID != nil
            {


                Button("Remove Cover", systemImage: "photo.badge.minus")
                {

                    var updated = card /* Card snapshot clearing the featured cover without removing attachments */

                    updated.coverAttachmentID = nil
                    onUpdateCard(updated)
                }

            }


            Button(action: onArchiveCard)
            {

                Label("Archive \(card.displayFormat.title)", systemImage: "archivebox")
            }


            Button(role: .destructive)
            {

                isConfirmingDelete = true
            }
            label:
            {

                Label("Delete \(card.displayFormat.title)", systemImage: "trash")
            }

            Button
            {

                renameDraft = card.word
                isRenaming = true
            }
            label:
            {

                Label("Rename \(card.displayFormat.title)", systemImage: "pencil")
            }

            Button
            {

                isEditingInfo = true
            }
            label:
            {

                Label("Update \(card.displayFormat.title) Info", systemImage: "slider.horizontal.3")
            }

        }
        label:
        {

            Image(systemName: "ellipsis")
            .foregroundStyle(.secondary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }

        .buttonStyle(.plain)
        .accessibilityLabel("\(card.displayFormat.title) actions")
        .disabled(card.isEditingLocked)
    }


    ///
    /// @fcn        KanbanCardView.cardBadges
    /// @brief      Build the card metadata badges selected in Board settings
    /// @details    Conditionally presents comment count, checklist progress, and due-date indicators
    ///
    /// @return     (some View) zero or more enabled card badges
    /// @post       Card data and display settings remain unchanged
    ///
    @ViewBuilder
    private var cardBadges: some View
    {  /* Enabled discussion, checklist-progress, and due-date indicators */

        if card.isEditingLocked
        {

            Label("Read-only", systemImage: "lock.fill")
        }

        if displaySettings.showCommentCounts && (!compactCards || card.commentCount > 0)
        {


            Label("\(card.commentCount)", systemImage: "text.bubble")
        }


        if displaySettings.showChecklistProgress && (!compactCards || !card.checklists.isEmpty)
        {


            Label("\(card.completedChecklistItems)/\(card.checklistItems.count)", systemImage: "checklist")
        }


        if displaySettings.showDueDateBadges && !showsHeaderTimes
        {

            ForEach(Array(card.scheduleBadges(on: listedOnDate).enumerated()), id: \.offset)
            {
                _, badge in
                Label(badge.label, systemImage: badge.systemImage)
                .foregroundStyle(
                    badge.systemImage == "calendar" ? Color.secondary : Color(red: 0.25, green: 0.60, blue: 0.90)
                )
                .padding(.horizontal, badge.systemImage == "calendar" ? 0 : 6)
                .padding(.vertical, badge.systemImage == "calendar" ? 0 : 3)
                .background(
                    badge.systemImage == "calendar" ? Color.clear : Color(red: 0.90, green: 0.96, blue: 1.0),
                    in: RoundedRectangle(cornerRadius: 5))
                .modifier(CardPreviewDateEditor(card: card, isStart: badge.title.hasPrefix("Start"), onUpdate: onUpdateCard))
            }

        }

    }

}


///
/// Presents a Card or Note in a denser focused List row
///
/// @section    Purpose
///     Changes visual density without converting the canonical record or replacing its metadata.
///
struct SingleListNoteRow: View
{


    let card:      KanbanCard
    let onToggle:  () -> Void
    var onArchive: (() -> Void)? = nil
    var onDelete:  (() -> Void)? = nil
    let onUpdateCard: (KanbanCard) -> Void
    @State private var confirmsDelete = false
    private var preview: String
    {

        let subtitle = card.subtitleOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !subtitle.isEmpty
        {
            return subtitle
        }

        return PlanRichText.plain(card.descriptionOverride ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }


    ///
    /// @fcn        SingleListNoteRow.dateText
    /// @brief      Format a note date according to its date kind
    /// @details    Shows a calendar date, a time, or both without adding components absent from the stored kind.
    ///
    /// @param[in]  date  Represented date for the operation
    /// @param[in]  kind  Date, review, or collection kind selecting this operation's behavior
    ///
    /// @return     (String) date-only, time-only, or combined label matching the stored date kind
    ///
    private func dateText(_ date: Date, kind: CardDateKind) -> String
    {

        switch kind
        {

        case .date:
            date.formatted(date: .abbreviated, time: .omitted)
        case .time:
            date.formatted(date: .omitted, time: .shortened)
        case .dateAndTime:
            date.formatted(date: .abbreviated, time: .shortened)
        }

    }

    var body: some View
    {

        VStack(spacing: 0)
        {

            HStack(alignment: .top, spacing: 10)
            {

                if card.displayFormat == .note
                {

                    Image(systemName: "note.text").foregroundStyle(.secondary)
                    .frame(width: 36, height: 44).accessibilityHidden(true)
                }
                else
                {

                    Button(action:
                        {
                            if !card.isEditingLocked
                            {
                                onToggle()
                            }

                        })
                    {

                        Image(systemName: card.isTitleChecked ? "checkmark.square.fill" : "square")
                        .font(.title3).foregroundStyle(card.isTitleChecked ? Color.green : .secondary)
                        .frame(width: 36, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        card.isTitleChecked ? "Mark \(card.word) unfinished" : "Mark \(card.word) complete")
                }

                VStack(alignment: .leading, spacing: 5)
                {

                    Text(card.word).font(.body.weight(.medium)).foregroundStyle(.primary)
                    .lineLimit(2).strikethrough(card.isTitleChecked)
                    if !preview.isEmpty
                    {
                        Text(preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }

                    ItemReactionPreview(card: card)
                    if card.showsDueDateInList
                    {

                        if let start = card.startDate
                        {

                            Text("Start · " + dateText(start, kind: card.startDateKind)).font(.caption).foregroundStyle(
                                .secondary)
                            .modifier(CardPreviewDateEditor(card: card, isStart: true, onUpdate: onUpdateCard))
                        }

                        if let due = card.dueDate
                        {

                            Text("Due · " + dateText(due, kind: card.dueDateKind)).font(.caption).foregroundStyle(
                                .secondary)
                            .modifier(CardPreviewDateEditor(card: card, isStart: false, onUpdate: onUpdateCard))
                        }

                    }

                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                if let cover = card.coverAttachment,
                let url = CardAttachmentStore.imageURL(for: cover),
                let image = UIImage(contentsOfFile: url.path)
                {

                    Image(uiImage: image).resizable().scaledToFill().frame(width: 64, height: 64)
                    .clipped().clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityHidden(true)
                }

            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            Divider().padding(.leading, 58)
        }
        .contentShape(Rectangle())
        .contextMenu
        {

            if let onArchive
            {
                Button("Archive", systemImage: "archivebox", action: onArchive)
            }

            if onDelete != nil
            {
                Button("Delete", systemImage: "trash", role: .destructive)
                {
                    confirmsDelete = true
                }

            }

        }
        .confirmationDialog("Delete \(card.word)?", isPresented: $confirmsDelete, titleVisibility: .visible)
        {

            Button("Delete", role: .destructive)
            {
                onDelete?()
            }

            Button("Cancel", role: .cancel)
            {

            }

        }
        message:
        {

            Text("Permanently deletes this item and its details. This cannot be undone.")
        }

    }

}
