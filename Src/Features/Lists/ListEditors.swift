// --------------------------------------------------------------------------------------------------
// @file       ListEditors.swift
// @brief      Inline List naming and explicit metadata drafts
// @details    Coordinates title selection, keyboard submission, subtitle editing, and
//             owner-accepted saving without replacing current List content.
//
// --------------------------------------------------------------------------------------------------
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers


///
/// Edits a newly added List title in its Board column
///
/// @section    Purpose
///     Selects the generated title, requests keyboard focus, and commits through the owner while
///     keeping a fixed header height.
///
struct InlineBoardListTitle: View
{


    let list:                 KanbanList
    let onSave:               (String) -> Bool
    let onFinish:             () -> Void
    @State private var title: String
    @State private var focused = false
    @State private var finished = false
    @ScaledMetric(relativeTo: .headline) private var titleHeight: CGFloat = 36


    ///
    /// @fcn        InlineBoardListTitle.init(list:onSave:onFinish:)
    /// @brief      Seed the generated List name for immediate replacement
    /// @details    Owns only a title draft; the parent retains canonical Cards and other metadata.
    ///
    /// @param[in]  list      Newly created List
    /// @param[in]  onSave    Checked canonical rename callback
    /// @param[in]  onFinish  Ends the Board's inline naming session
    ///
    /// @return     (InlineBoardListTitle) selected, focusable header editor
    ///
    init(list: KanbanList, onSave: @escaping (String) -> Bool, onFinish: @escaping () -> Void)
    {

        self.list = list
        self.onSave = onSave
        self.onFinish = onFinish
        _title = State(initialValue: list.title)
    }


    var body: some View
    {

        ListTitleField(
            text: $title, focused: $focused, selectsInitialTitle: true,
            returnKeyType: .done, textStyle: .headline, identifier: "board.newListTitle", onNext: finish
        )
        .frame(height: titleHeight)
        .task
        {
            focused = true
        }
        .onChange(of: focused)
        {
            wasFocused, isFocused in
            if wasFocused && !isFocused
            {
                finish()
            }

        }
        .onDisappear
        {
            finish()
        }

    }


    ///
    /// @fcn        InlineBoardListTitle.finish()
    /// @brief      Commit a new List name and return its header to normal display
    /// @details    Trims typed text, retains the generated name for blank input, and keeps editing
    ///             on a rejected rename. Successful completion is idempotent across focus changes.
    ///
    /// @return     (Void) saves through the owner without opening another view
    ///
    private func finish()
    {

        guard !finished else
        {
            return
        }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard onSave(trimmed.isEmpty ? list.title : trimmed) else
        {
            focused = true;
            return
        }

        finished = true
        focused = false
        onFinish()
    }

}


///
/// Bridges List title selection and keyboard submission
///
/// @section    Purpose
///     Supports initial select-all, focus changes, and configurable return-key behavior without
///     expanding the surrounding header layout.
///
struct ListTitleField: UIViewRepresentable
{


    @Binding var text:       String
    @Binding var focused:    Bool
    let selectsInitialTitle: Bool
    var returnKeyType:       UIReturnKeyType = .next
    var textStyle:           UIFont.TextStyle = .body
    var identifier = "list-editor-title"
    let onNext: () -> Void


    ///
    /// @fcn        ListTitleField.makeCoordinator
    /// @brief      Create the delegate for list-title text and keyboard events
    /// @details    Retains the current bindings and tracks whether the initial generated title was selected.
    ///
    /// @return     (Coordinator) delegate retained across native view updates
    ///
    func makeCoordinator() -> Coordinator
    {
        Coordinator(self)
    }


    ///
    /// @fcn        ListTitleField.makeUIView
    /// @brief      Create the title input with its configured keyboard submission key
    /// @details    Uses native selection, Dynamic Type, and sentence capitalization. The caller
    ///             chooses header styling and Done or Next; creating the field never saves the List.
    ///
    /// @param[in]  context  SwiftUI lifecycle context containing the title delegate
    ///
    /// @return     (UITextField) accessible single-line list-title editor
    ///
    func makeUIView(context: Context) -> UITextField
    {

        let field = UITextField()
        field.placeholder = "List title"
        field.font = .preferredFont(forTextStyle: textStyle)
        field.adjustsFontForContentSizeCategory = true
        field.autocapitalizationType = .sentences
        field.returnKeyType = returnKeyType
        field.accessibilityLabel = "List title"
        field.accessibilityIdentifier = identifier
        field.setContentHuggingPriority(.required, for: .vertical)
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }


    ///
    /// @fcn        ListTitleField.updateUIView
    /// @brief      Synchronize draft text and requested title focus
    /// @details    Updates changed text only and defers first-responder reconciliation until after SwiftUI's update.
    ///             The deferred callback reads the coordinator's latest parent so Next cannot restore stale focus.
    ///
    /// @param[in]  field    Existing native title field
    /// @param[in]  context  SwiftUI lifecycle context containing the current delegate
    ///
    /// @return     (Void) no return value
    ///
    func updateUIView(_ field: UITextField, context: Context)
    {

        context.coordinator.parent = self
        if field.text != text
        {
            field.text = text
        }

        let coordinator = context.coordinator
        DispatchQueue.main.async
        {
            [weak field, weak coordinator] in
            guard let field, let coordinator, field.window != nil else
            {
                return
            }

            if coordinator.parent.focused, !field.isFirstResponder
            {

                field.becomeFirstResponder()
            }
            else if !coordinator.parent.focused, field.isFirstResponder
            {

                field.resignFirstResponder()
            }

        }

    }


    ///
    /// Handles native List title selection and keyboard submission
    ///
    /// @section    Purpose
    ///     Selects the initial title once, then publishes ordinary editing and focus changes
    ///     through the representable's current bindings.
    ///
    final class Coordinator: NSObject, UITextFieldDelegate
    {


        var parent: ListTitleField
        private var selectedInitialTitle = false


        ///
        /// @fcn        ListTitleField.Coordinator.init
        /// @brief      Retain the title editor's bindings and Next action
        /// @details    Later native updates replace this parent value with the latest SwiftUI state.
        ///
        /// @param[in]  parent  Title editor supplying draft and focus bindings
        ///
        /// @return     (Coordinator) initialized text-field delegate
        ///
        init(_ parent: ListTitleField)
        {
            self.parent = parent
        }


        ///
        /// @fcn        ListTitleField.Coordinator.changed
        /// @brief      Publish native title edits into the working draft
        /// @details    Normalizes an absent text-field value to an empty title; persistence still requires Save.
        ///
        /// @param[in]  field  Native title field delivering an editing-change event
        ///
        /// @return     (Void) no return value
        ///
        @objc func changed(_ field: UITextField)
        {
            parent.text = field.text ?? ""
        }


        ///
        /// @fcn        ListTitleField.Coordinator.textFieldDidBeginEditing
        /// @brief      Focus the title and select its initial generated name once
        /// @details    Only new-list editors request selection. Existing-list editing and subsequent focus changes
        ///             retain normal caret behavior; deferred selection requires the field to remain first responder.
        ///
        /// @param[in]  field  Native title field that began editing
        ///
        /// @return     (Void) no return value
        ///
        func textFieldDidBeginEditing(_ field: UITextField)
        {

            if !parent.focused
            {
                parent.focused = true
            }

            guard parent.selectsInitialTitle, !selectedInitialTitle else
            {
                return
            }

            selectedInitialTitle = true
            DispatchQueue.main.async
            {
                [weak field] in
                guard let field, field.isFirstResponder else
                {
                    return
                }

                field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
            }

        }


        ///
        /// @fcn        ListTitleField.Coordinator.textFieldDidEndEditing
        /// @brief      Clear title focus when native editing ends
        /// @details    Leaves the parent unchanged if it already advanced focus to the subtitle.
        ///
        /// @param[in]  field  Native title field that ended editing
        ///
        /// @return     (Void) no return value
        ///
        func textFieldDidEndEditing(_ field: UITextField)
        {

            if parent.focused
            {
                parent.focused = false
            }

        }


        ///
        /// @fcn        ListTitleField.Coordinator.textFieldShouldReturn
        /// @brief      Dispatch the parent editor's configured Return action
        /// @details    Metadata editing advances to the subtitle; inline Board naming commits.
        ///             Suppresses default Return behavior so the field remains single-line.
        ///
        /// @param[in]  field  Native title field whose Next key was pressed
        ///
        /// @return     (Bool) false to suppress the text field's default Return handling
        ///
        func textFieldShouldReturn(_ field: UITextField) -> Bool
        {

            parent.onNext()
            return false
        }

    }

}


///
/// Edits List title and subtitle as an explicit draft
///
/// @section    Purpose
///     Publishes display-text changes only when the owner accepts them and preserves current
///     content through the canonical save path.
///
struct ListInfoEditorSheet: View
{


    let onSave:                       (String, String, ItemPresentation) -> Bool
    private let focusesTitleOnAppear: Bool
    @State private var titleFocused = false
    @FocusState private var subtitleFocused: Bool
    @State private var defaultPresentation:  ItemPresentation
    @Environment(\.dismiss) private var dismiss
    @State private var title:    String
    @State private var subtitle: String


    ///
    /// @fcn        ListInfoEditorSheet.init
    /// @brief      Initialize list metadata editing with a save callback
    /// @details    Seeds editable values from the supplied list; the two-argument callback overload delegates to the
    ///             presentation-aware initializer. New-list callers can request initial title focus and selection.
    ///
    /// @param[in]  list                  List supplying the current content and metadata
    /// @param[in]  focusesTitleOnAppear  Whether to raise the keyboard and select the initial title on opening
    /// @param[in]  onSave                Save callback returning true only when the owner accepts the edited value
    ///
    /// @return     (ListInfoEditorSheet) initialized instance
    ///
    init(list: KanbanList, focusesTitleOnAppear: Bool = false, onSave: @escaping (String, String) -> Bool)
    {

        self.init(list: list, focusesTitleOnAppear: focusesTitleOnAppear)
        {
            title, subtitle, _ in
            onSave(title, subtitle)
        }

    }


    ///
    /// @fcn        ListInfoEditorSheet.init
    /// @brief      Initialize list metadata editing with a save callback
    /// @details    Seeds editable values from the supplied list; the two-argument callback overload delegates to the
    ///             presentation-aware initializer. New-list callers can request initial title focus and selection.
    ///
    /// @param[in]  list                  List supplying the current content and metadata
    /// @param[in]  focusesTitleOnAppear  Whether to raise the keyboard and select the initial title on opening
    /// @param[in]  onSave                Save callback returning true only when the owner accepts the edited value
    ///
    /// @return     (ListInfoEditorSheet) initialized instance
    ///
    init(
        list: KanbanList, focusesTitleOnAppear: Bool = false,
        onSave: @escaping (String, String, ItemPresentation) -> Bool
    )
    {

        self.focusesTitleOnAppear = focusesTitleOnAppear
        _defaultPresentation = State(initialValue: list.newItemPresentation)
        self.onSave = onSave
        _title = State(initialValue: list.title)
        _subtitle = State(initialValue: list.subtitle)
    }


    var body: some View
    {


        NavigationStack
        {

            Form
            {

                Section("Title")
                {

                    ListTitleField(
                        text: $title, focused: $titleFocused,
                        selectsInitialTitle: focusesTitleOnAppear,
                        onNext:
                        {

                            titleFocused = false;
                            subtitleFocused = true
                        })
                }

                Section
                {

                    TextField("Subtitle", text: $subtitle, axis: .vertical).textInputAutocapitalization(.sentences)
                    .lineLimit(2 ... 5)
                    .focused($subtitleFocused)
                    .accessibilityIdentifier("list-editor-subtitle")
                }
                header:
                {

                    Text("Subtitle")
                }
                footer:
                {

                    Text(
                                                            "Leave empty to hide the subtitle. Renaming a weekday list makes it an ordinary list; Today creates a new weekday list when needed."
                    )
                }

                Section("New item default")
                {

                    Picker("Display as", selection: $defaultPresentation)
                    {

                        ForEach(ItemPresentation.allCases)
                        {
                            format in
                            Text(format.title).tag(format)
                        }

                    }
                    .accessibilityIdentifier("list-editor-default")
                    Text("Applies only to new items. Existing items keep their display format.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

            }
            .task
            {

                if focusesTitleOnAppear
                {
                    titleFocused = true
                }

            }
            .onChange(of: titleFocused)
            {
                _, focused in
                if focused
                {
                    subtitleFocused = false
                }

            }
            .onChange(of: subtitleFocused)
            {
                _, focused in
                if focused
                {
                    titleFocused = false
                }

            }
            .navigationTitle("Edit list")
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

                        if onSave(
                            title.trimmingCharacters(in: .whitespacesAndNewlines),
                            subtitle.trimmingCharacters(in: .whitespacesAndNewlines), defaultPresentation)
                        {

                            dismiss()
                        }

                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

            }

        }

    }

}
