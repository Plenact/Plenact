// --------------------------------------------------------------------------------------------------
// @file       BoardHeader.swift
// @brief      Board header, options, and display settings
// @details    Presents navigation and appearance capabilities supplied by the owner, with local
//             confirmation and settings state.
//
// --------------------------------------------------------------------------------------------------
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers


///
/// Carries Board preview badge visibility settings
///
/// @section    Purpose
///     Keeps checklist progress, comment counts, and due-date visibility independent of the Cards'
///     retained data.
///
struct BoardDisplaySettings
{


    /// Whether cards show checklist completion progress.
    var showChecklistProgress = true /* Display checklist progress on cards */
    /// Whether cards show their comment count.
    var showCommentCounts = true /* Display comment counts on cards     */
    /// Whether cards show due-date badges.
    var showDueDateBadges = true /* Display due date badges on cards    */
}


///
/// Selects the density and width behavior of Board columns
///
/// @section    Purpose
///     Offer a readable Standard layout and a compact Overview layout
///
enum BoardPresentation: String, CaseIterable, Identifiable
{


    case standard
    case overview

    /// User-defaults key for the locally stored Board presentation selection.
    static let storageKey = "Plenact.BoardPresentation.v1" /* Versioned Board layout preference key */

    ///
    /// @fcn        BoardPresentation.id
    /// @brief      Identify a Board presentation option
    /// @details    Uses the stable raw case value for SwiftUI selection identity
    ///
    /// @return     (String) presentation identity
    /// @post       No presentation preference is changed
    ///
    var id: String
    {
        rawValue
    }  /* Stable Board layout identity */


    ///
    /// @fcn        BoardPresentation.title
    /// @brief      Provide the user-facing name of a presentation option
    /// @details    Maps each layout case to its menu label
    ///
    /// @return     (String) Standard or Overview
    /// @post       The selected presentation remains unchanged
    ///
    var title: String
    {
        self == .standard ? "Standard" : "Overview"
    }  /* User-facing Board layout label */


    ///
    /// @fcn        BoardPresentation.minimumCardHeight
    /// @brief      Provide the minimum card height for this layout
    /// @details    Standard cards retain more vertical space than Overview cards
    ///
    /// @return     (CGFloat) minimum card height in points
    /// @post       No view or preference state is modified
    ///
    var minimumCardHeight: CGFloat
    {
        self == .standard ? 112 : 80
    }  /* Minimum row height for the selected layout */


    ///
    /// @fcn        BoardPresentation.columnWidth(viewportWidth:accessibilitySize:)
    /// @brief      Calculate the column width for this presentation
    /// @details    Accessibility text sizing receives all usable width; other sizes use a
    ///             layout-specific maximum. Standard reserves equal neighboring-list previews
    ///
    /// @param[in]  viewportWidth        Available viewport width in points
    /// @param[in]  accessibilitySize    Whether the current text size is an accessibility size
    /// @param[in]  fillsAvailableWidth  Whether a Standard single-list collection uses all usable width
    ///
    /// @return     (CGFloat) column width in points
    ///
    /// @pre        Widths at or below the horizontal inset are treated as invalid
    /// @post       No Board state is modified
    ///
    func columnWidth(viewportWidth: CGFloat, accessibilitySize: Bool, fillsAvailableWidth: Bool = false) -> CGFloat
    {


        guard viewportWidth.isFinite, viewportWidth > 28 else
        {


            return 1
        }


        let available = viewportWidth - 28 /* Viewport width after outer list margins */

        if accessibilitySize || (self == .standard && fillsAvailableWidth)
        {


            return available
        }


        if self == .standard
        {

            // Reserve a 15-point neighbor preview and the 17-point gap on each side.
            return min(available, 360, max(172, viewportWidth - 64))
        }


        return min(available, 240)
    }

}


///
/// Collects measured card heights from list-card views
///
/// @section    Purpose
///     Let a list calculate its vertical card-collection size from rendered content
///
struct BoardCardHeightPreferenceKey: PreferenceKey
{


    /// Current card-height reports keyed by card identity.
    static var defaultValue: [Int: CGFloat] = [:] /* Empty list-center measurements before layout */


    ///
    /// @fcn        BoardCardHeightPreferenceKey.reduce(value:nextValue:)
    /// @brief      Merge card-height reports from child views
    /// @details    The latest value replaces an earlier report for the same card identity
    ///
    /// @param[in,out] value      Accumulated card-height map
    /// @param[in]     nextValue  Provider of the next child height map
    ///
    /// @return     (Void) merges the next report into value
    ///
    /// @post       Card identities not reported by nextValue remain in the map
    ///
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat])
    {


        value.merge(nextValue(), uniquingKeysWith:
            {
                _, latest in
                latest
            })
    }

}


// -------------------------------------- MARK: - Board Header ---------------------------------- //


///
/// Displays the board title and board-level actions
///
/// @section    Purpose
///     Establish the visual identity of the board and expose board-level controls
///
struct BoardHeader: View
{


    @Environment(\.layoutDirection) private var headerLayoutDirection
    @Binding var settings: BoardDisplaySettings /* Board display settings                              */
    /// Shared Standard/Overview selection displayed in the Board options menu.
    @Binding var presentation: BoardPresentation         /* Shared Standard or Overview layout selection */
    let activeMembers:         [String]                  /* Unique users assigned to active cards        */
    let memberColors:          [String: Color]           /* Icon colors keyed by normalized member name  */
    let onRenameMember:        (String, String) -> Void  /* Rename a member across all card assignments  */
    let onDeleteMember:        (String) -> Void          /* Remove a member from all card assignments    */
    let onSetMemberColor:      (String, Color) -> Void   /* Update a member's shared icon color          */
    /// Opens the calendar view for the current board.
    let onOpenCalendar: () -> Void /* Presents the Board's calendar browser */
    /// Board name shown in the header.
    let title: String /* Board heading displayed in the header */
    /// Supporting board description shown in the header.
    let subtitle: String /* Supporting Board header text */
    /// Whether to expose list creation in the header.
    let allowsAddingLists: Bool /* Whether list creation is offered on the board */
    /// Optional action returning to the owning collection.
    let onClose: (() -> Void)? /* Optional return action to the collection directory */
    /// Opens the archived-list browser.
    let onViewArchivedLists: () -> Void /* Presents this Board's archived lists */
    /// Optional callback that archives the board after confirmation.
    let onArchiveBoard:   (() -> Void)?  /* Optional whole-Board archive action                    */
    let onDeleteBoard:    (() -> Void)?  /* Confirmed parent-owned Board removal                   */
    let deleteBoardTitle: String         /* Week content clearing or personal Board deletion label */
    /// Navigates to the first active list when more than one list exists.
    let onJumpToFirstList: (() -> Void)? /* Optional navigation action revealing the first active list */
    /// Navigates to the last active list when more than one list exists.
    let onJumpToLastList: (() -> Void)? /* Optional navigation action revealing the last active list */

    var listViewMode:    Binding<SingleListViewMode>? = nil
    var titleAppearance: ItemAppearance? = nil
    var onAppearance:    (() -> Void)? = nil
    var onListActions:   (() -> Void)? = nil
    var onSearch:        (() -> Void)? = nil
    var onToggleZoom:    (() -> Void)? = nil
    var onToggleGallery: (() -> Void)? = nil
    var isGallery = false
    var isPanoramic: Bool = false
    var zoomPercentage = 62
    var onResetZoom:                (() -> Void)? = nil
    var onAdjustZoom:               ((AccessibilityAdjustmentDirection) -> Void)? = nil
    var calendarAccessibilityTitle: String = "Open this month"
    var onSubtitleTap:              (() -> Void)? = nil
    let onAddList:                  () -> Void /* Callback for adding a new list                      */

    @State private var titleOverflows = false
    @State private var subtitleOverflows = false
    @State private var showsBoardOptions = false
    @State private var pendingBoardAction: BoardOptionsAction?
    @State private var showingSettings = false /* Controls the visibility of the board settings sheet */
    /// Controls confirmation before archiving the complete board.
    @State private var confirmsArchiveBoard = false  /* Whole-Board archive confirmation state */
    @State private var confirmsDeleteBoard = false   /* Permanent Board deletion confirmation  */


    ///
    /// @fcn        BoardHeader.performPendingBoardAction()
    /// @brief      Execute one deferred Board options choice
    /// @details    Consumes the pending action before dispatching navigation, gallery, appearance,
    ///             or settings callbacks. Destructive choices raise their existing confirmation
    ///             state instead of deleting immediately.
    ///
    /// @return     (Void) consumes the pending option and updates the appropriate presentation
    ///
    private func performPendingBoardAction()
    {

        guard let action = pendingBoardAction else
        {
            return
        }

        pendingBoardAction = nil
        switch action
        {

        case .resetZoom:
            onResetZoom?()
        case .gallery:
            onToggleGallery?()
        case .first:
            onJumpToFirstList?()
        case .last:
            onJumpToLastList?()
        case .appearance:
            onAppearance?()
        case .listActions:
            onListActions?()
        case .settings:
            showingSettings = true
        case .archived:
            onViewArchivedLists()
        case .archive:
            confirmsArchiveBoard = true
        case .delete:
            confirmsDeleteBoard = true
        }

    }


    var titleSwipeArea: some View
    {  /* Header heading surface accepting boundary-navigation swipes */


        VStack(alignment: .leading, spacing: 2)
        {


            HStack(spacing: 8)
            {

                ItemAppearanceMark(appearance: titleAppearance)
                .font(.title2)
                SlideableHeaderText(text: title, onOverflowChange:
                    {
                        titleOverflows = $0
                    })
                .font(onClose == nil ? .largeTitle.weight(.bold) : .title2.weight(.bold))
                .foregroundStyle(.white)
            }


            if !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {

                SlideableHeaderText(
                    text: subtitle, onTap: onSubtitleTap,
                    onOverflowChange:
                    {
                        subtitleOverflows = $0
                    }
                )
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .accessibilityIdentifier(onSubtitleTap == nil ? "board.subtitle" : "board.weekSelector")
                .onDisappear
                {
                    subtitleOverflows = false
                }

            }

        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 24)
            .onEnded
            {
                value in

                guard
                let boundary = BoardListReordering.boundary(
                    forHorizontalSwipe: value.translation), /* Board edge selected by the horizontal swipe  */
                let action = boundary == .first ? onJumpToFirstList : onJumpToLastList
                else
                {  /* Available callback for the selected boundary */


                    return
                }


                action()
            },
            including: titleOverflows || subtitleOverflows ? .subviews : .all
        )
        .accessibilityHint(
            titleOverflows || subtitleOverflows
            ? "Slide long text to read it. Board options has first and last list actions."
            : onJumpToFirstList == nil
            ? ""
            : "Swipe left to jump to the last list, or right to the first list. Board options also has these actions."
        )
    }


    ///
    /// @fcn        BoardHeader.body
    /// @brief      Present Board identity and global actions
    /// @details    Composes optional back/list-creation controls, calendar access, settings,
    ///             archived-list browsing, and an optional confirmed full-board archive action
    ///
    /// @return     (some View) Board title/action row and settings presentation
    /// @post       User actions invoke supplied callbacks; archive is requested only after confirmation.
    ///             Display settings change through the shared binding, not a separate persisted draft
    ///
    var body: some View
    {  /* Board header and global actions */


        AdaptiveWorkspaceHeaderLayout(regularSpacing: 8, layoutDirection: headerLayoutDirection)
        {


            if let onClose
            {  /* Available return action shown beside the Board heading */


                Button(action: onClose)
                {

                    Image(systemName: "chevron.left")
                    .frame(width: 32, height: 44)
                }

                .foregroundStyle(.white)
                .accessibilityLabel("Back to previous view")
            }


            titleSwipeArea
            .layoutValue(key: WorkspaceHeaderTitleKey.self, value: true)

            if let onSearch
            {

                Button(action: onSearch)
                {

                    WorkspaceHeaderIcon(systemName: "magnifyingglass").foregroundStyle(.white)
                }
                .accessibilityLabel("Search Plenact")
            }

            Button(action: onOpenCalendar)
            {

                WorkspaceHeaderIcon(systemName: "calendar").foregroundStyle(.white)
            }

            .buttonStyle(.plain)
            .accessibilityLabel(calendarAccessibilityTitle)

            if let onToggleZoom
            {

                Button(action: onToggleZoom)
                {

                    WorkspaceHeaderIcon(
                        systemName: isPanoramic
                        ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPanoramic ? "Reset to Normal zoom" : "Reset to Panoramic zoom")
                .accessibilityValue("\(isPanoramic ? "Panoramic" : "Normal"), \(zoomPercentage) percent")
                .accessibilityHint(
                                                "Pinch the board to adjust zoom. Tap to reset to the other zoom preset, or adjust this control."
                )
                .accessibilityAdjustableAction
                {
                    direction in
                    onAdjustZoom?(direction)
                }
                .accessibilityIdentifier("board.zoom")
            }


            Button
            {

                showsBoardOptions = true
            }
            label:
            {

                WorkspaceHeaderIcon(systemName: "ellipsis.circle.fill").foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(onListActions == nil ? "Board options" : "List options")
            .popover(isPresented: $showsBoardOptions, arrowEdge: .top)
            {

                BoardOptionsPopover(
                    canJumpFirst: onJumpToFirstList != nil,
                    canJumpLast: onJumpToLastList != nil, hasAppearance: onAppearance != nil,
                    canArchive: onArchiveBoard != nil, canDelete: onDeleteBoard != nil,
                    deleteTitle: deleteBoardTitle, hasGallery: onToggleGallery != nil, isGallery: isGallery,
                    canResetZoom: onResetZoom != nil, hasListActions: onListActions != nil, listViewMode: listViewMode
                )
                {
                    action in
                    pendingBoardAction = action
                    showsBoardOptions = false
                }
                .presentationCompactAdaptation(.popover)
                .onDisappear
                {
                    performPendingBoardAction()
                }

            }

        }

        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .confirmationDialog("Archive this board?", isPresented: $confirmsArchiveBoard, titleVisibility: .visible)
        {

            Button("Archive Board")
            {
                onArchiveBoard?()
            }

            Button("Cancel", role: .cancel)
            {

            }

        }
        message:
        {

            Text("All lists and cards will be kept on this device. Restore the board from Saved.")
        }

        .confirmationDialog(deleteBoardTitle + "?", isPresented: $confirmsDeleteBoard, titleVisibility: .visible)
        {

            Button(deleteBoardTitle, role: .destructive)
            {
                onDeleteBoard?()
            }

            Button("Cancel", role: .cancel)
            {

            }

        }
        message:
        {

            Text(
                                    "Permanently removes all active and archived lists, cards, and bookmarks in this board. This cannot be undone. Other boards and retained archive copies are unchanged."
            )
        }

        .sheet(isPresented: $showingSettings)
        {


            BoardSettingsView(
                settings: $settings,
                presentation: $presentation,
                activeMembers: activeMembers,
                memberColors: memberColors,
                onRenameMember: onRenameMember,
                onDeleteMember: onDeleteMember,
                onSetMemberColor: onSetMemberColor
            )
        }

    }

}


///
/// Presents controls for Board card metadata and layout preferences
///
/// @section    Purpose
///     Let the user control which metadata badges appear on board cards
///
/// @note   Settings are bound to ContentView and take effect immediately
///
struct BoardSettingsView: View
{


    @AppStorage("Plenact.CardCovers.enabled") private var showsCardCovers =
    true                                         /* Device-only visibility                   */
    @Binding var settings: BoardDisplaySettings  /* Bound to the board's display preferences */
    /// Shared presentation choice updated immediately from Board settings.
    @Binding var presentation: BoardPresentation /* Shared Board layout selection edited by this menu */

    @Environment(\.dismiss) private var dismiss /* Dismiss action for the settings sheet           */

    let activeMembers:    [String]                  /* Active assigned users in board order        */
    let memberColors:     [String: Color]           /* Member icon colors keyed by normalized name */
    let onRenameMember:   (String, String) -> Void  /* Rename a member across all assigned cards   */
    let onDeleteMember:   (String) -> Void          /* Remove a member from all assigned cards     */
    let onSetMemberColor: (String, Color) -> Void   /* Update a member's shared icon color         */

    @State private var memberNameDraft = ""      /* Draft name for renaming a member             */
    @State private var isRenamingMember = false  /* Flag indicating if member rename in progress */

    @State private var editingMember:       String?             /* Currently edited member name      */
    @State private var memberToDelete:      String?             /* Member slated for deletion        */
    @State private var selectedMemberColor: MemberColorTarget?  /* Target member for color selection */


    ///
    /// @fcn        BoardSettingsView.trimmedMemberNameDraft
    /// @brief      Normalize the proposed member name for validation
    /// @details    Removes surrounding whitespace/newlines without changing the editable draft
    ///
    /// @return     (String) trimmed name, which may be empty
    /// @post       Member assignments and draft text remain unchanged
    ///
    private var trimmedMemberNameDraft: String
    {  /* Normalized member rename input */

        memberNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }


    ///
    /// @fcn        BoardSettingsView.body
    /// @brief      Build the board settings form
    /// @details    Presents immediate badge-visibility toggles and member color/rename/removal controls.
    ///             Rename validates a nonblank name; removal requires confirmation and preserves comments
    ///
    /// @return     (some View) settings sheet content with a Done action
    ///
    /// @pre        settings is bound to the board's display preferences
    /// @post       Toggle changes update the binding; member actions invoke parent callbacks.
    ///             Done dismisses without reverting already applied settings
    ///
    var body: some View
    {  /* Board settings and member management form */


        NavigationStack
        {


            Form
            {


                Section("Card badges")
                {

                    Toggle("Checklist progress", isOn: $settings.showChecklistProgress)
                    Toggle("Comment counts", isOn: $settings.showCommentCounts)
                    Toggle("Due-date badges", isOn: $settings.showDueDateBadges)
                }

                Section
                {

                    Toggle("Show card covers", isOn: $showsCardCovers)
                }
                footer:
                {

                    Text(
                                                            "Applies to Board and Today card rows on this device. Turning this off keeps every cover selection and attachment."
                    )
                }


                Section("Members")
                {


                    if activeMembers.isEmpty
                    {


                        Text("No active members")
                        .foregroundStyle(.secondary)
                    }
                    else
                    {


                        ForEach(activeMembers, id: \.self)
                        {
                            member in

                            HStack(spacing: 12)
                            {


                                let memberColor =
                                memberColors[member.lowercased()]
                                ?? .accentColor /* Fallback to accent color if no custom color is set */

                                Button
                                {

                                    selectedMemberColor = MemberColorTarget(member: member, color: memberColor)
                                }
                                label:
                                {


                                    Image(systemName: "person.crop.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(memberColor)
                                    .frame(width: 36, height: 36)
                                    .contentShape(Rectangle())
                                }

                                .buttonStyle(.plain)
                                .accessibilityLabel("Change icon color for \(member)")

                                Text(member)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Button
                                {

                                    editingMember = member
                                    memberNameDraft = member
                                    isRenamingMember = true
                                }
                                label:
                                {

                                    Image(systemName: "pencil")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                                }

                                .buttonStyle(.plain)
                                .accessibilityLabel("Edit \(member)")
                            }

                            .swipeActions(edge: .trailing, allowsFullSwipe: false)
                            {


                                Button(role: .destructive)
                                {

                                    memberToDelete = member
                                }
                                label:
                                {

                                    Label("Remove", systemImage: "person.crop.circle.badge.minus")
                                }

                            }

                        }

                    }

                }

            }

            .navigationTitle("Board Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {

                ToolbarItem(placement: .topBarTrailing)
                {

                    Button("Done")
                    {

                        dismiss()
                    }

                }

            }

            .alert("Edit member", isPresented: $isRenamingMember)
            {


                TextField("Name or email", text: $memberNameDraft).textInputAutocapitalization(.sentences)

                Button("Cancel", role: .cancel)
                {

                }


                Button("Save")
                {

                    guard let editingMember else
                    {  /* Assignee currently being renamed */


                        return
                    }


                    onRenameMember(editingMember, trimmedMemberNameDraft)
                }

                .disabled(trimmedMemberNameDraft.isEmpty)
            }
            message:
            {


                Text("This updates the member name on every assigned card.")
            }

            .confirmationDialog(

                                    "Remove \(memberToDelete ?? "member") from the board?",

                                    isPresented: Binding(
                                        get:
                                        {
                                            memberToDelete != nil
                                        },
                                        set:
                                        {
                                            if !$0
                                            {
                                                memberToDelete = nil
                                            }

                                        }
                                    ),
                                    titleVisibility: .visible
            )
            {

                Button("Remove member", role: .destructive)
                {


                    guard let memberToDelete else
                    {  /* Assignee selected for removal */


                        return
                    }


                    onDeleteMember(memberToDelete)

                    self.memberToDelete = nil
                }


                Button("Cancel", role: .cancel)
                {

                    memberToDelete = nil
                }

            }
            message:
            {

                Text("This removes the member from all card assignments. Existing comments are kept.")
            }

            .sheet(item: $selectedMemberColor)
            {
                target in

                MemberColorEditorSheet(memberName: target.member, initialColor: target.color)
                {
                    color in
                    onSetMemberColor(target.member, color)
                }

            }

        }

        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

}


///
/// Carries the selected member and current color while the color editor sheet is presented
///
/// @section    Purpose
///     Provide a stable identifiable sheet item containing the values needed to edit a member icon color
///
/// @details    The member's lowercased name is used as the sheet identity, and the current color seeds the editor
///
/// @note       This is transient presentation state; saving is handled by MemberColorEditorSheet
///
struct MemberColorTarget: Identifiable
{


    let member: String  /* The name of the member whose color is being edited */
    let color:  Color   /* The current color of the member's icon             */

    ///
    /// @fcn        MemberColorTarget.id
    /// @brief      Identify the member's color-edit presentation
    /// @details    Uses a lowercased member name for case-insensitive sheet identity
    ///
    /// @return     (String) normalized presentation identity
    /// @post       The member name and seed color remain unchanged
    ///
    var id: String
    {
        member.lowercased()
    }  /* Use the lowercased member name as the unique identifier for the sheet */

}


///
/// Presents the system color picker for one member's icon
///
/// @section    Purpose
///     Let the user preview, change, save, or cancel a member's shared icon color
///
/// @details    Holds the selected color locally until Save invokes onSave; Cancel dismisses without applying changes
///
/// @note       Opacity selection is disabled so the icon remains fully visible
///
///
/// Presents the color editor for one Board member
///
/// @section    Purpose
///     Let the user preview and save a member's icon color
///
struct MemberColorEditorSheet: View
{


    let memberName: String           /* The name of the member whose color is being edited         */
    let onSave:     (Color) -> Void  /* The closure to call when the user saves the selected color */

    @Environment(\.dismiss) private var dismiss  /* Dismiss action for the color editor */
    @State private var selectedColor: Color      /* Draft member icon color             */


    ///
    /// @fcn        MemberColorEditorSheet.init(memberName:initialColor:onSave:)
    /// @brief      Seed a member-icon color editing draft
    /// @details    Holds the initial color in local State and installs the submission callback
    ///
    /// @param[in]  memberName    Member whose icon color is being edited
    /// @param[in]  initialColor  Current color shown when the editor opens
    /// @param[in]  onSave        Callback receiving the selected color
    ///
    /// @return     (MemberColorEditorSheet) configured editor
    /// @post       No shared member color is changed until Save invokes onSave
    ///
    init(memberName: String, initialColor: Color, onSave: @escaping (Color) -> Void)
    {


        self.memberName = memberName
        self.onSave = onSave
        _selectedColor = State(initialValue: initialColor)
    }


    ///
    /// @fcn        MemberColorEditorSheet.body
    /// @brief      Present a non-opacity color picker for one member icon
    /// @details    Save submits the draft color and dismisses; Cancel only dismisses
    ///
    /// @return     (some View) medium-sheet member color form
    /// @post       Applying/persisting the chosen color belongs to the onSave caller
    ///
    var body: some View
    {  /* Member icon color editor */


        NavigationStack
        {


            Form
            {

                Section(memberName)
                {

                    ColorPicker("Icon color", selection: $selectedColor, supportsOpacity: false)
                }

            }

            .navigationTitle("Member icon")
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

                        onSave(selectedColor)
                        dismiss()
                    }

                }

            }

        }

        .presentationDetents([.medium])
    }

}


///
/// Identifies actions available in a Board options popover
///
/// @section    Purpose
///     Keeps navigation, gallery, appearance, archive, and deletion choices separate from their
///     execution callbacks.
///
enum BoardOptionsAction
{

    case first, last, gallery, resetZoom, appearance, listActions, settings, archived, archive, delete
}


///
/// Presents available Board options
///
/// @section    Purpose
///     Adapts its controls to supplied capabilities and text size while reporting the selected
///     action to the owner.
///
struct BoardOptionsPopover: View
{


    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let canJumpFirst:  Bool
    let canJumpLast:   Bool
    let hasAppearance: Bool
    let canArchive:    Bool
    let canDelete:     Bool
    let deleteTitle:   String
    var hasGallery = false
    var isGallery = false
    var canResetZoom = false
    var hasListActions = false
    var listViewMode: Binding<SingleListViewMode>? = nil
    let onAction:     (BoardOptionsAction) -> Void


    ///
    /// @fcn        BoardOptionsPopover.icon
    /// @brief      Build an accessible board-option icon button
    /// @details    Provides a forty-four-point target, disabled styling, an accessibility name, and the selected
    ///             action callback.
    ///
    /// @param[in]  symbol   SF Symbol name used by the control
    /// @param[in]  name     Storage file name, symbol name, or accessible control name selected for this operation
    /// @param[in]  action   Explicit review, toolbar, or contextual action selected by the caller
    /// @param[in]  color    Requested icon, accent, or formatting color
    /// @param[in]  enabled  Whether this optional behavior is enabled
    ///
    /// @return     (some View) an accessible board-option icon button
    ///
    private func icon(
        _ symbol: String, name: String, action: BoardOptionsAction,
        color: Color = .primary, enabled: Bool = true
    ) -> some View
    {

        Button
        {

            onAction(action)
        }
        label:
        {

            Image(systemName: symbol)
            .font(.system(size: 20, weight: .regular))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .foregroundStyle(enabled ? color : Color.secondary.opacity(0.4))
        }
        .disabled(!enabled)
        .accessibilityLabel(name)
        .help(name)
    }


    var body: some View
    {

        VStack(spacing: 0)
        {

            if let listViewMode
            {

                Picker("View as", selection: listViewMode)
                {

                    ForEach(SingleListViewMode.allCases)
                    {
                        Text($0.title).tag($0)
                    }

                }
                .pickerStyle(.segmented)
                .padding(12)
                .accessibilityIdentifier("list.viewMode")
                Divider()
            }

            HStack
            {

                icon("backward.end", name: "Jump to First List", action: .first, enabled: canJumpFirst)
                Spacer()
                icon("forward.end", name: "Jump to Last List", action: .last, enabled: canJumpLast)
            }

            Divider()
            if canResetZoom
            {

                Button
                {

                    onAction(.resetZoom)
                }
                label:
                {

                    Label("Reset board zoom", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                } .padding(.horizontal, 8)
            }

            if hasGallery
            {

                Button
                {

                    onAction(.gallery)
                }
                label:
                {

                    Label(
                        isGallery ? "Board view" : "Gallery view",
                        systemImage: isGallery ? "rectangle.split.3x1" : "square.grid.2x2"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                } .padding(.horizontal, 8)
            }

            if hasListActions
            {

                Button
                {

                    onAction(.listActions)
                }
                label:
                {

                    Label("List actions", systemImage: "list.bullet.rectangle")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                } .padding(.horizontal, 8)
            }

            if hasAppearance
            {

                Button
                {

                    onAction(.appearance)
                }
                label:
                {

                    HStack(spacing: 12)
                    {

                        Image(systemName: "paintpalette")
                        .font(.system(size: 20, weight: .regular))
                        .frame(width: 24)
                        Text("Appearance").lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .padding(.horizontal, 8)
            }

            Button
            {

                onAction(.settings)
            }
            label:
            {

                HStack(spacing: 12)
                {

                    Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .regular))
                    .frame(width: 24)
                    Text("Board Settings").lineLimit(2).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .padding(.horizontal, 8)
            Divider()
            HStack(spacing: 8)
            {

                icon("archivebox", name: "Archived Lists", action: .archived, color: .accentColor)
                if canArchive
                {

                    Spacer(minLength: 0)
                    icon("archivebox", name: "Archive Board", action: .archive)
                }

                if canDelete
                {

                    Spacer(minLength: 0)
                    icon("trash", name: deleteTitle, action: .delete, color: .red)
                }

            }

        }
        .font(.body)
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
        .padding(12)
        .frame(width: dynamicTypeSize.isAccessibilitySize ? 320 : nil)
        .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
    }

}
