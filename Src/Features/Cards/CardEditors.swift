// --------------------------------------------------------------------------------------------------
// @file       CardEditors.swift
// @brief      Explicit Card metadata editing drafts
// @details    Edits titles, members, dates, layout, and action destinations through the owner's
//             accepted save callbacks.
//
// --------------------------------------------------------------------------------------------------
import PhotosUI
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers


///
/// Presents the names assigned to a card and lets the user maintain that list
///
/// @section    Purpose
///     Provide one interface for viewing, editing, adding, and removing users assigned to a card
///
/// @details    Keeps draft edits local until Save, trims names, removes case-insensitive duplicates,
///             and supports swipe-to-remove
///
/// @note       Member entries are stored as names or email strings; no separate user directory is required
///
struct CardMembersSheet: View
{


    let onSave:       ([CardAssignee]) -> Void  /* Save typed card assignments                        */
    let memberColors: [String: Color]           /* Shared icon colors keyed by normalized member name */

    @Environment(\.dismiss) private var dismiss  /* Dismiss action for the sheet               */
    @State private var members: [CardAssignee]   /* Local typed assignments being edited       */
    @State private var memberDraft = ""          /* Current text input for adding a new member */

    ///
    /// @fcn        CardMembersSheet.trimmedMemberDraft
    /// @brief      Normalize a proposed manual assignment name
    /// @details    Trims outer whitespace/newlines without editing the input field
    ///
    /// @return     (String) normalized member draft, potentially empty
    /// @post       Draft text and existing assignments remain unchanged
    ///
    private var trimmedMemberDraft: String
    {  /* Normalized manual-assignee input */


        memberDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }


    ///
    /// @fcn        CardMembersSheet.canAddMember
    /// @brief      Validate whether the manual-assignment draft can be added
    /// @details    Requires a nonblank normalized draft that does not match any current display name
    ///             by localized case-insensitive comparison, regardless of assignment kind
    ///
    /// @return     (Bool) whether Add or implicit draft inclusion on Save is permitted
    /// @post       No assignment is added by validation
    ///
    private var canAddMember: Bool
    {  /* Draft is non-empty and not already assigned */


        !trimmedMemberDraft.isEmpty
        && !members.contains
        {

            $0.displayName.localizedCaseInsensitiveCompare(trimmedMemberDraft) == .orderedSame
        }

    }


    ///
    /// @fcn        CardMembersSheet.normalizedMembers
    /// @brief      Prepare the assignment snapshot for explicit Save
    /// @details    Includes a valid pending manual draft, trims names, omits blanks, and deduplicates
    ///             manual names separately from registered-user IDs (falling back to assignment UUID)
    ///
    /// @return     ([CardAssignee]) normalized assignments preserving first-occurrence order and identity
    /// @post       Local drafts remain unchanged; a valid unsubmitted name can be included in the result
    ///
    private var normalizedMembers: [CardAssignee]
    {  /* Deduplicated assignments prepared for saving */


        var seenAssignments: Set<String> = [] /* Identity keys already emitted */

        let manualDraft =
        canAddMember ? [CardAssignee.manual(trimmedMemberDraft)] : []  /* Optional new manual assignment        */
        let membersToSave = members + manualDraft                      /* Existing assignments plus valid draft */

        return membersToSave.compactMap
        {
            assignee in
            let trimmedName = assignee.displayName.trimmingCharacters(
                in: .whitespacesAndNewlines) /* Normalized display name   */
            let identityKey =
            assignee.kind == .registeredUser /* Stable identity namespace */
            ? "user:\(assignee.userID ?? assignee.id.uuidString)"
            : "manual:\(trimmedName.lowercased())"

            guard !trimmedName.isEmpty, seenAssignments.insert(identityKey).inserted else
            {


                return nil
            }


            return CardAssignee(
                id: assignee.id,
                kind: assignee.kind,
                userID: assignee.userID,
                displayName: trimmedName
            )
        }

    }


    ///
    /// @fcn        CardMembersSheet.init(members:memberColors:onSave:)
    /// @brief      Seed an isolated card-assignment editing draft
    /// @details    Copies typed assignments into local State and retains display colors and submission action
    ///
    /// @param[in]  members       Initial manual/registered assignments
    /// @param[in]  memberColors  Shared icon colors keyed by lowercased display name
    /// @param[in]  onSave        Callback receiving normalized assignments
    /// @return     (CardMembersSheet) configured assignment editor
    /// @post       No assignment normalization or parent update occurs during initialization
    ///
    init(members: [CardAssignee], memberColors: [String: Color], onSave: @escaping ([CardAssignee]) -> Void)
    {


        self.onSave = onSave
        self.memberColors = memberColors
        _members = State(initialValue: members)
    }


    ///
    /// @fcn        CardMembersSheet.addMember()
    /// @brief      Add the current member draft to the assigned-user list
    /// @details    Appends trimmed draft & clears input when non-empty & not already assigned
    ///
    /// @return     (Void) updates the sheet's member draft and local assignment list
    ///
    /// @pre        memberDraft contains the current text entered in the Add user field
    /// @post       A valid unique name is appended and memberDraft is cleared; invalid or duplicate
    ///             drafts are unchanged
    /// @note       Duplicate detection is case-insensitive
    ///
    private func addMember()
    {


        guard canAddMember else
        {


            return
        }


        members.append(.manual(trimmedMemberDraft))
        memberDraft = ""
    }


    ///
    /// @fcn        CardMembersSheet.body
    /// @brief      Present manual assignment editing and typed-member removal
    /// @details    Registered display names are read-only; manual names are editable.
    ///             Supports swipe removal, validated manual addition, and normalized Save/Cancel
    ///
    /// @return     (some View) member draft navigation list
    /// @post       Save submits normalizedMembers, including a valid pending draft, then dismisses.
    ///             Cancel discards local changes without invoking onSave
    ///
    var body: some View
    {  /* Member assignment editor */


        NavigationStack
        {


            List
            {


                Section("Assigned users")
                {


                    if members.isEmpty
                    {


                        Text("No users assigned")
                        .foregroundStyle(.secondary)
                    }


                    ForEach(members.indices, id: \.self)
                    {
                        index in

                        HStack(spacing: 10)
                        {


                            Image(
                                systemName: members[index].kind == .registeredUser
                                ? "person.crop.circle.fill" : "person.crop.circle"
                            )
                            .foregroundStyle(memberColors[members[index].displayName.lowercased()] ?? .accentColor)

                            if members[index].kind == .manual
                            {


                                TextField(
                                                                                                "Name or email",
                                                                                                text: Binding(
                                                                                                    get:
                                                                                                    {
                                                                                                        members[index].displayName
                                                                                                    },
                                                                                                    set:
                                                                                                    {
                                                                                                        members[index].displayName = $0
                                                                                                    }
                                                                                                )
                                ).textInputAutocapitalization(.sentences)
                            }
                            else
                            {

                                Text(members[index].displayName)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                        }

                        .swipeActions(edge: .trailing, allowsFullSwipe: true)
                        {


                            Button(role: .destructive)
                            {

                                members.remove(at: index)
                            }
                            label:
                            {

                                Label("Remove", systemImage: "trash")
                            }

                        }

                    }

                }


                Section("Add user")
                {


                    HStack
                    {


                        TextField("Name or email", text: $memberDraft).textInputAutocapitalization(.sentences)
                        .onSubmit(addMember)

                        Button(action: addMember)
                        {

                            Image(systemName: "plus.circle.fill")
                        }

                        .disabled(!canAddMember)
                        .accessibilityLabel("Add member")
                    }

                }

            }

            .navigationTitle("Card members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {

                ToolbarItem(placement: .cancellationAction)
                {


                    Button("Cancel")
                    {

                        dismiss()
                    }

                }


                ToolbarItem(placement: .confirmationAction)
                {


                    Button("Save")
                    {

                        onSave(normalizedMembers)
                        dismiss()
                    }

                }

            }

        }

        .presentationDragIndicator(.visible)
    }

}


///
/// Edits the visibility and ordering of Card sections
///
/// @section    Purpose
///     Keeps layout changes in local state and saves through a checked callback without deleting
///     hidden section content.
///
struct CardLayoutEditor: View
{


    @State var layout: CardSectionLayout
    let onSave:        (CardSectionLayout) -> Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View
    {

        NavigationStack
        {

            List
            {

                Section
                {

                    ForEach(layout.order)
                    {
                        section in
                        Toggle(
                            section.title,
                            isOn: Binding(
                                get:
                                {
                                    !layout.hidden.contains(section)
                                },
                                set:
                                {
                                    if $0
                                    {
                                        layout.hidden.remove(section)
                                    }
                                    else
                                    {
                                        layout.hidden.insert(section)
                                    }

                                }
                            ))
                    }
                    .onMove
                    {
                        layout.order.move(fromOffsets: $0, toOffset: $1)
                    }

                }
                footer:
                {

                    Text("Drag to reorder sections. Turn a section off to hide it. Its content is kept.")
                }

                Button("Reset layout")
                {
                    layout = CardSectionLayout()
                }

            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Card Layout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {

                ToolbarItem(placement: .cancellationAction)
                {
                    Button("Cancel")
                    {
                        dismiss()
                    }

                }

                ToolbarItem(placement: .confirmationAction)
                {
                    Button("Save")
                    {
                        if onSave(layout)
                        {
                            dismiss()
                        }

                    }

                }

            }

        }

    }

}


///
/// Edits scheduling values as an explicit draft
///
/// @section    Purpose
///     Allows calendar and clock choices to change together and publishes them only when the user
///     saves.
///
struct CardDateEditorSheet: View
{


    let title:            String
    let hasExistingValue: Bool
    let onSave:           (Date?, CardDateKind) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var kind: CardDateKind


    ///
    /// @fcn        CardDateEditorSheet.init
    /// @brief      Initialize an optional schedule-value editor
    /// @details    Tracks whether a value already exists, seeds a missing value with the current time, and retains
    ///             its precision and checked save callback.
    ///
    /// @param[in]  title   Display title or proposed title text
    /// @param[in]  date    Represented date for the operation
    /// @param[in]  kind    Date, review, or collection kind selecting this operation's behavior
    /// @param[in]  onSave  Save callback returning true only when the owner accepts the edited value
    ///
    /// @return     (CardDateEditorSheet) initialized instance
    ///
    init(title: String, date: Date?, kind: CardDateKind, onSave: @escaping (Date?, CardDateKind) -> Bool)
    {

        self.title = title
        self.hasExistingValue = date != nil
        self.onSave = onSave
        _date = State(initialValue: date ?? .now)
        _kind = State(initialValue: kind)
    }

    var body: some View
    {

        NavigationStack
        {

            ScrollView
            {

                VStack(spacing: 16)
                {

                    Picker("Set", selection: $kind)
                    {

                        ForEach(CardDateKind.allCases)
                        {
                            kind in
                            Text(kind.title).tag(kind)
                        }

                    }
                    .pickerStyle(.segmented)
                    if kind.includesDate
                    {

                        DatePicker("Date", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                    }

                    if kind.includesTime
                    {

                        DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                        .frame(maxHeight: 180)
                    }

                    if hasExistingValue
                    {

                        Button("Remove", role: .destructive)
                        {

                            if onSave(nil, .date)
                            {
                                dismiss()
                            }

                        }

                    }

                } .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {

                ToolbarItem(placement: .cancellationAction)
                {
                    Button("Cancel")
                    {
                        dismiss()
                    }

                }

                ToolbarItem(placement: .confirmationAction)
                {

                    Button("Save")
                    {
                        if onSave(kind.normalized(date), kind)
                        {
                            dismiss()
                        }

                    }

                }

            }

        }

    }

}


///
/// Edits a checklist item's action type as a draft
///
/// @section    Purpose
///     Selects plain, linked-Card, or URL behavior from available candidates and publishes the
///     resulting item only through checked saving.
///
struct ChecklistItemTypeEditor: View
{


    let item:                   KanbanChecklistItem
    let candidates:             [KanbanCard]
    let onSave:                 (KanbanChecklistItem) -> Bool
    @State private var type:    ChecklistItemType
    @State private var cardID:  Int?
    @State private var urlText: String
    @Environment(\.dismiss) private var dismiss


    ///
    /// @fcn        ChecklistItemTypeEditor.init
    /// @brief      Seed checklist type editing without losing retained content
    /// @details    Loads the selected type, retained linked-card identity, and retained URL into independent draft
    ///             state and keeps the available card candidates.
    ///
    /// @param[in]  item         Item supplied to this operation
    /// @param[in]  initialType  Checklist presentation initially selected in the editor
    /// @param[in]  candidates   Candidates supplied to this operation
    /// @param[in]  onSave       Save callback returning true only when the owner accepts the edited value
    ///
    /// @return     (ChecklistItemTypeEditor) initialized instance
    ///
    init(
        item: KanbanChecklistItem, initialType: ChecklistItemType, candidates: [KanbanCard],
        onSave: @escaping (KanbanChecklistItem) -> Bool
    )
    {

        self.item = item;
        self.candidates = candidates;
        self.onSave = onSave
        _type = State(initialValue: initialType)
        _cardID = State(initialValue: item.retainedCardID)
        _urlText = State(initialValue: item.retainedURL?.absoluteString ?? "")
    }

    private var url: URL?
    {

        let text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
        url.host?.isEmpty == false
        else
        {
            return nil
        }

        return url
    }

    var body: some View
    {

        NavigationStack
        {

            Form
            {

                Picker("Item type", selection: $type)
                {

                    ForEach(ChecklistItemType.allCases)
                    {
                        Text($0.title).tag($0)
                    }

                }

                if type == .linkedCard
                {

                    Section("Choose a card from this board")
                    {

                        Picker("Card", selection: $cardID)
                        {

                            Text("Choose a card").tag(Optional<Int>.none)
                            ForEach(candidates.filter
                                {
                                    !$0.isSectionDivider
                                } .sorted
                                {
                                    $0.word < $1.word
                                })
                            {
                                card in
                                Text(card.word + " · " + card.listTitle).tag(Optional(card.id))
                            }

                        }

                    }

                }
                else if type == .webLink
                {

                    TextField("https://example.com", text: $urlText).keyboardType(.URL).textInputAutocapitalization(
                        .never
                    ).autocorrectionDisabled()
                    Text("Enter a complete http or https website address.").font(.footnote).foregroundStyle(.secondary)
                }

            }
            .navigationTitle("Checklist item type").navigationBarTitleDisplayMode(.inline)
            .toolbar
            {

                ToolbarItem(placement: .cancellationAction)
                {
                    Button("Cancel")
                    {
                        dismiss()
                    }

                }

                ToolbarItem(placement: .confirmationAction)
                {

                    Button("Save")
                    {

                        var updated = item
                        switch type
                        {

                        case .standard:
                            updated.content = .standard
                        case .linkedCard:
                            if let cardID
                            {

                                if cardID != item.retainedCardID
                                {
                                    updated.linkedCollectionID = nil
                                }
                                ;

                                updated.content = .linkedCard(cardID: cardID)
                            }

                        case .actionDetail:
                            updated.content = .actionDetail(item.retainedDetail ?? KanbanChecklistActionDetail())
                        case .webLink:
                            if let url
                            {
                                updated.content = .webLink(url)
                            }

                        }

                        if onSave(updated)
                        {
                            dismiss()
                        }

                    }
                    .disabled(
                        (type == .linkedCard && !candidates.contains
                            {
                                $0.id == cardID
                            })
                        || (type == .webLink && url == nil))
                }

            }

        }

    }

}


/// Presents the full editor for a card's title, board subtitle, and detail description
///
/// @section    Purpose
///     Collect card display text and submit the completed values through the supplied save callback
///
/// @note   The parent card view owns persistence; cancel dismisses without invoking the callback
///
struct CardInfoEditorSheet: View
{


    let onSave:       (String, String, String) -> Void  /* Callback receiving the edited card text       */
    let presentation: ItemPresentation                  /* Item kind used for accessible creation labels */

    @Environment(\.dismiss) private var dismiss  /* Dismiss action for the sheet         */
    @State private var title:       String       /* Draft text for the title field       */
    @State private var subtitle:    String       /* Draft text for the subtitle field    */
    @State private var description: String       /* Draft text for the description field */


    ///
    /// @fcn        CardInfoEditorSheet.trimmedTitle
    /// @brief      Return the title draft without surrounding whitespace
    /// @details    Trims leading and trailing whitespace and newline characters before validation or saving
    ///
    /// @return     (String) normalized title draft; may be empty when the input contains only whitespace
    ///
    /// @pre        title contains the current text-field value
    /// @post       The stored title draft is unchanged
    ///
    private var trimmedTitle: String
    {  /* Normalized card title draft */

        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }


    ///
    /// @fcn        CardInfoEditorSheet.init(card:onSave:)
    /// @brief      Initialize the card information editor
    /// @details    Seeds the title, subtitle, and description fields from the selected card and
    ///             stores its save callback
    ///
    /// @param[in]  card    Card whose information will be edited
    /// @param[in]  onSave  Callback that applies the edited title, subtitle, and description
    ///
    /// @return     (CardInfoEditorSheet) configured card information form
    ///
    /// @pre        card contains the current values to present in the form
    /// @post       All editable fields begin with the selected card's current display values
    ///
    init(card: KanbanCard, onSave: @escaping (String, String, String) -> Void)
    {


        self.onSave = onSave
        self.presentation = card.presentation
        _title = State(initialValue: card.word)
        _subtitle = State(initialValue: card.subtitle)
        _description = State(
            initialValue: card.presentation == .note ? (card.descriptionOverride ?? "") : card.funParagraph)
    }


    ///
    /// @fcn        CardInfoEditorSheet.body
    /// @brief      Build the card information editing form
    /// @details    Presents title, subtitle, and description fields with Cancel and validated Save.
    ///             Only the title is trimmed; subtitle/description are submitted exactly as entered
    ///
    /// @return     (some View) modal form for updating card display information
    ///
    /// @pre        Editor state has been initialized from the selected card
    /// @post       Save invokes onSave with the edited values; Cancel dismisses without applying them
    ///
    var body: some View
    {  /* Card title, subtitle, and description form */


        NavigationStack
        {


            Form
            {

                Section("Card details")
                {


                    TextField("Title", text: $title).textInputAutocapitalization(.sentences)

                    TextField("Subtitle", text: $subtitle).textInputAutocapitalization(.sentences)
                }


                Section("Description")
                {

                    RichTextEditor(placeholder: "Description", text: $description)
                }

            }

            .navigationTitle("Update \(presentation.title) Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {

                ToolbarItem(placement: .cancellationAction)
                {

                    Button("Cancel")
                    {

                        dismiss()
                    }

                }


                ToolbarItem(placement: .confirmationAction)
                {

                    Button("Save")
                    {

                        onSave(trimmedTitle, subtitle, description)
                        dismiss()
                    }

                    .disabled(trimmedTitle.isEmpty)
                }

            }

        }

        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

}


///
/// Opens an existing preview schedule value without navigating into the Card
///
/// @section    Purpose
///     Reuses the Card date editor for start and due values and forwards an otherwise unchanged
///     record through the owning List's update callback. Locked records remain display-only.
///
struct CardPreviewDateEditor: ViewModifier
{

    let card:     KanbanCard
    let isStart:  Bool
    let onUpdate: (KanbanCard) -> Void
    @State private var isPresented = false


    ///
    /// @fcn        CardPreviewDateEditor.body(content:)
    /// @brief      Present a date editor from the preview's existing date label
    /// @details    Uses a plain button to consume date taps independently of row navigation.
    ///             Save and Remove change only the selected schedule value and its precision;
    ///             Cancel leaves the record unchanged. Rechecks the read-only lock on save.
    ///
    /// @param[in]  content  Existing date label retaining its preview styling
    /// @return     (some View) date control with a locally presented editor
    ///
    func body(content: Content) -> some View
    {

        Button
        {
            isPresented = true
        }
        label:
        {
            content.contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(card.isEditingLocked)
        .accessibilityLabel(isStart ? "Edit start date" : "Edit due date")
        .accessibilityValue(
            (isStart ? card.startDate : card.dueDate).map
            {
                (isStart ? card.startDateKind : card.dueDateKind).label(for: $0)
            } ?? "Not set"
        )
        .accessibilityIdentifier(isStart ? "card.preview.editStartDate" : "card.preview.editDueDate")
        .sheet(isPresented: $isPresented)
        {
            CardDateEditorSheet(
                title: isStart ? "Start date" : "Due date",
                date: isStart ? card.startDate : card.dueDate,
                kind: isStart ? card.startDateKind : card.dueDateKind
            )
            {
                value, kind in
                guard !card.isEditingLocked else
                {
                    return false
                }

                var updated = card
                if isStart
                {
                    updated.startDate = value
                    updated.startDateKind = value == nil ? .date : kind
                }
                else
                {
                    updated.dueDate = value
                    updated.dueDateKind = value == nil ? .date : kind
                }

                onUpdate(updated)
                return true
            }
            .presentationDetents([.large])
            .databaseActivityOverlay()
        }
    }
}
