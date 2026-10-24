// --------------------------------------------------------------------------------------------------
// @file       RichTextEditor.swift
// @brief      Rich-text serialization and native editing bridge
// @details    Preserves attributed runs and plain-text access while coordinating focus and
//             selection through the active editor bindings.
//
// --------------------------------------------------------------------------------------------------
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers


// Rich text remains in the existing string fields, with a versioned, portable run representation.
// Ordinary text stays ordinary text; legacy descriptions and comments need no migration.


///
/// Encodes and decodes Plenact's retained rich text
///
/// @section    Purpose
///     Converts between stored runs, attributed editing content, and plain text while supporting
///     the versioned string prefix.
///
enum PlanRichText
{


    static let prefix = "plenact-rich-v1:"


    ///
    /// Represents one stored run of rich text
    ///
    /// @section    Purpose
    ///     Retains writing and optional font, color, bold, and italic attributes independently of
    ///     UIKit editor state.
    ///
    struct Run: Codable, Equatable
    {


        var text:     String
        var bold:     Bool = false
        var italic:   Bool = false
        var color:    String? = nil
        var fontName: String? = nil
        var fontSize: Double? = nil
    }

    static let colors: [(String, UIColor)] = [
        ("Default", .label), ("Blue", .systemBlue), ("Green", .systemGreen),
        ("Orange", .systemOrange), ("Purple", .systemPurple), ("Red", .systemRed)
    ]


    ///
    /// @fcn        PlanRichText.runs
    /// @brief      Decode Plenact's optional rich-text run representation
    /// @details    Requires the stored prefix and valid base64 JSON; ordinary text or invalid encoded data returns
    ///             nil.
    ///
    /// @param[in]  value  Stored or user-entered text to decode, inspect, or display
    ///
    /// @return     ([Run]?) decoded formatting runs, or nil for ordinary text or an invalid encoded representation
    ///
    static func runs(_ value: String) -> [Run]?
    {

        guard value.hasPrefix(prefix), let data = Data(base64Encoded: String(value.dropFirst(prefix.count))) else
        {

            return nil
        }

        return try? JSONDecoder().decode([Run].self, from: data)
    }


    ///
    /// @fcn        PlanRichText.plain
    /// @brief      Return the plain text represented by a stored rich-text value
    /// @details    Concatenates decoded runs when present and otherwise returns the original value unchanged.
    ///
    /// @param[in]  value  Stored or user-entered text to decode, inspect, or display
    ///
    /// @return     (String) concatenated run text, or the original value when no rich-text representation decodes
    ///
    static func plain(_ value: String) -> String
    {
        runs(value)?.map(\.text).joined() ?? value
    }


    ///
    /// @fcn        PlanRichText.attributed
    /// @brief      Build UIKit attributed text from the stored representation
    /// @details    Applies supported font traits, bounded sizes, and named colors while retaining metadata needed for
    ///             later round-trip encoding.
    ///
    /// @param[in]  value  Stored or user-entered text to decode, inspect, or display
    ///
    /// @return     (NSAttributedString) UIKit text carrying supported formatting and round-trip metadata
    ///
    static func attributed(_ value: String) -> NSAttributedString
    {

        let result = NSMutableAttributedString(string: "")
        for run in runs(value) ?? [Run(text: value)]
        {

            var traits: UIFontDescriptor.SymbolicTraits = []
            if run.bold
            {
                traits.insert(.traitBold)
            }

            if run.italic
            {
                traits.insert(.traitItalic)
            }

            let base = UIFont.preferredFont(forTextStyle: .body)
            let size = run.fontSize.map
            {
                CGFloat(min(48, max(10, $0)))
            }
            ?? base.pointSize
            let font =
            run.fontName == "System"
            ? UIFont.systemFont(ofSize: size)
            : (run.fontName.flatMap
                {
                    UIFont(name: $0, size: size)
                }
                ?? base.withSize(size))
            let styledFont = UIFont(
                descriptor: font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor, size: font.pointSize)
            var attributes: [NSAttributedString.Key: Any] = [.font: styledFont, .foregroundColor: UIColor.label]
            if let name = run.color, let color = colors.first(where:
                {
                    $0.0 == name
                })?.1
            {

                attributes[.foregroundColor] = color
                attributes[NSAttributedString.Key("PlenactColor")] = name
            }

            if let name = run.fontName
            {
                attributes[NSAttributedString.Key("PlenactFontName")] = name
            }

            if let size = run.fontSize
            {
                attributes[NSAttributedString.Key("PlenactFontSize")] = size
            }

            result.append(NSAttributedString(string: run.text, attributes: attributes))
        }

        return result
    }


    ///
    /// @fcn        PlanRichText.encode
    /// @brief      Encode supported attributed formatting for persistence
    /// @details    Enumerates attribute runs and uses sorted-key base64 JSON only when formatting exists; plain text
    ///             and failed encoding fall back to the original string.
    ///
    /// @param[in]  value  Attributed content whose supported formatting should be encoded
    ///
    /// @return     (String) prefixed base64 run JSON when formatting is present, otherwise the plain string
    ///
    static func encode(_ value: NSAttributedString) -> String
    {

        var runs: [Run] = []
        value.enumerateAttributes(in: NSRange(location: 0, length: value.length))
        {
            attributes, range, _ in
            let traits = (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
            runs.append(
                Run(
                    text: (value.string as NSString).substring(with: range), bold: traits.contains(.traitBold),
                    italic: traits.contains(.traitItalic),
                    color: attributes[NSAttributedString.Key("PlenactColor")] as? String,
                    fontName: attributes[NSAttributedString.Key("PlenactFontName")] as? String,
                    fontSize: attributes[NSAttributedString.Key("PlenactFontSize")] as? Double))
        }

        guard
        runs.contains(where:
            {
                $0.bold || $0.italic || $0.color != nil || $0.fontName != nil || $0.fontSize != nil
            }
        )
        else
        {
            return value.string
        }

        let encoder = JSONEncoder();
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(runs) else
        {
            return value.string
        }

        return prefix + data.base64EncodedString()
    }


    ///
    /// @fcn        PlanRichText.display
    /// @brief      Build SwiftUI attributed text from persisted rich-text runs
    /// @details    Applies supported family, size, bold, italic, and named colors, with plain-text fallback when no
    ///             runs decode.
    ///
    /// @param[in]  value  Stored or user-entered text to decode, inspect, or display
    ///
    /// @return     (AttributedString) SwiftUI attributed text with the supported persisted run styling
    ///
    static func display(_ value: String) -> AttributedString
    {

        var result = AttributedString(plain(value))
        if let runs = runs(value)
        {

            result = AttributedString()
            for run in runs
            {

                var part = AttributedString(run.text)
                let family = run.fontName == "System" ? nil : run.fontName
                var font: Font =
                family.map
                {
                    .custom($0, size: run.fontSize ?? 17)
                }

                ?? run.fontSize.map
                {
                    .system(size: $0)
                }
                ?? .body
                if run.bold
                {
                    font = font.bold()
                }

                if run.italic
                {
                    font = font.italic()
                }

                part.font = font
                if let name = run.color, let color = colors.first(where:
                    {
                        $0.0 == name
                    })?.1
                {

                    part.foregroundColor = Color(uiColor: color)
                }

                result.append(part)
            }

        }

        return result
    }

}


///
/// Bridges rich-text editing into SwiftUI
///
/// @section    Purpose
///     Binds the stored text representation to a native text view with configurable focus,
///     placeholder, and minimum height.
///
struct RichTextEditor: UIViewRepresentable
{


    let placeholder:   String
    @Binding var text: String
    var focus:         Binding<Bool>? = nil
    var minimumHeight: CGFloat = 80
    var verticalInset: CGFloat = 6


    ///
    /// @fcn        RichTextEditor.makeCoordinator
    /// @brief      Create the native bridge coordinator
    /// @details    Creates the coordinator retained by SwiftUI for RichTextEditor so its delegate or observation
    ///             state can span view updates.
    ///
    /// @return     (Coordinator) retained native bridge coordinator
    ///
    func makeCoordinator() -> Coordinator
    {
        Coordinator(self)
    }


    ///
    /// @fcn        RichTextEditor.makeUIView
    /// @brief      Create the native rich-text editor and keyboard controls
    /// @details    Configures dynamic type, the placeholder, delegate, supported formatting toolbar, and initial
    ///             attributed content.
    ///
    /// @param[in]  context  Framework-supplied update context and coordinator access
    ///
    /// @return     (UITextView) native rich-text view configured with its delegate, placeholder, and formatting
    ///             accessory
    ///
    func makeUIView(context: Context) -> UITextView
    {

        let view = UITextView()
        view.autocapitalizationType = .sentences
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: verticalInset, left: 0, bottom: verticalInset, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.attributedText = PlanRichText.attributed(text)
        view.typingAttributes = [.font: UIFont.preferredFont(forTextStyle: .body), .foregroundColor: UIColor.label]
        view.accessibilityLabel = placeholder
        view.delegate = context.coordinator
        context.coordinator.view = view
        let hint = UILabel()
        hint.text = placeholder
        hint.font = .preferredFont(forTextStyle: .body)
        hint.textColor = .placeholderText
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)
        NSLayoutConstraint.activate([
                hint.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hint.topAnchor.constraint(equalTo: view.topAnchor, constant: verticalInset)
            ])
        context.coordinator.hint = hint
        hint.isHidden = !PlanRichText.plain(text).isEmpty
        let coordinator = context.coordinator
        view.inputAccessoryView = PlenactKeyboardToolbar(
            input: view,
            formatting: KeyboardFormatting(
                toggle:
                {
                    [weak coordinator] in
                    coordinator?.toggle($0)
                },
                color:
                {
                    [weak coordinator] in
                    coordinator?.color($0)
                },
                font:
                {
                    [weak coordinator] name, size in
                    coordinator?.font(name: name, size: size)
                }
            ))
        return view
    }


    ///
    /// @fcn        RichTextEditor.updateUIView
    /// @brief      Synchronize retained rich-text content without losing selection
    /// @details    Refreshes the coordinator's parent, replaces only changed attributed content, clamps the insertion
    ///             position, and defers UIKit focus reconciliation until after the SwiftUI update.
    ///
    /// @param[in]  view     Native view inspected or synchronized by the operation
    /// @param[in]  context  Framework-supplied update context and coordinator access
    ///
    /// @return     (Void) no return value
    ///
    func updateUIView(_ view: UITextView, context: Context)
    {

        context.coordinator.parent = self
        if PlanRichText.encode(view.attributedText) != text
        {

            let selection = view.selectedRange
            view.attributedText = PlanRichText.attributed(text)
            view.selectedRange = NSRange(location: min(selection.location, view.textStorage.length), length: 0)
        }

        context.coordinator.hint?.isHidden = !PlanRichText.plain(text).isEmpty
        // UIKit focus changes must happen after SwiftUI finishes its current view update.
        context.coordinator.scheduleFocusUpdate(view)
    }


    ///
    /// @fcn        RichTextEditor.sizeThatFits
    /// @brief      Measure the rich editor using its proposed width
    /// @details    Returns nil without a width proposal and otherwise fits native text height above the configured
    ///             minimum.
    ///
    /// @param[in]  proposal  Parent layout proposal, including an optional available width
    /// @param[in]  uiView    Native editor whose fitting size is being measured
    /// @param[in]  context   Framework-supplied update context and coordinator access
    ///
    /// @return     (CGSize?) proposed width and fitted text height, or nil when the proposal has no width
    ///
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize?
    {

        guard let width = proposal.width else
        {
            return nil
        }

        return CGSize(
            width: width,
            height: max(
                minimumHeight, uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height))
    }


    ///
    /// Synchronizes native rich-text changes and focus
    ///
    /// @section    Purpose
    ///     Retains current bindings, tracks the text view and placeholder weakly, and guards
    ///     deferred focus updates against re-entry.
    ///
    class Coordinator: NSObject, UITextViewDelegate
    {


        var parent:    RichTextEditor
        weak var view: UITextView?
        weak var hint: UILabel?
        private var focusUpdatePending = false
        private var applyingFocus = false


        ///
        /// @fcn        RichTextEditor.Coordinator.init
        /// @brief      Retain the rich-text representable for native delegate callbacks
        /// @details    Stores the parent value that supplies the text and optional focus bindings; later
        ///             representable updates refresh that value.
        ///
        /// @param[in]  parent  Representable value supplying the delegate's current bindings and callbacks
        ///
        /// @return     (Coordinator) initialized instance
        ///
        init(_ parent: RichTextEditor)
        {
            self.parent = parent
        }


        ///
        /// @fcn        RichTextEditor.Coordinator.scheduleFocusUpdate
        /// @brief      Reconcile requested editor focus after the current view update
        /// @details    Coalesces main-queue work, rereads the latest binding, requires an attached view, and
        ///             suppresses delegate feedback during programmatic focus changes.
        ///
        /// @param[in]  view  Native view inspected or synchronized by the operation
        ///
        /// @return     (Void) no return value
        ///
        func scheduleFocusUpdate(_ view: UITextView)
        {

            guard let focus = parent.focus, focus.wrappedValue != view.isFirstResponder,
            !focusUpdatePending
            else
            {
                return
            }

            focusUpdatePending = true
            DispatchQueue.main.async
            {
                [weak self, weak view] in
                guard let self else
                {
                    return
                }

                self.focusUpdatePending = false
                guard let view, view.window != nil, let focus = self.parent.focus,
                focus.wrappedValue != view.isFirstResponder
                else
                {
                    return
                }

                // Read the latest request: a user may have tapped another field while this was queued.
                self.applyingFocus = true
                defer
                {
                    self.applyingFocus = false
                }

                if focus.wrappedValue
                {
                    view.becomeFirstResponder()
                }
                else
                {
                    view.resignFirstResponder()
                }

            }

        }


        ///
        /// @fcn        RichTextEditor.Coordinator.textViewDidChange
        /// @brief      Publish native rich-text edits back to the binding
        /// @details    Encodes supported formatting, updates placeholder visibility, and refreshes the shared
        ///             keyboard controls.
        ///
        /// @param[in]  textView  Native rich-text editor delivering the delegate callback
        ///
        /// @return     (Void) no return value
        ///
        func textViewDidChange(_ textView: UITextView)
        {

            parent.text = PlanRichText.encode(textView.attributedText)
            hint?.isHidden = !textView.text.isEmpty
            PlenactKeyboard.shared.refreshActive()
        }


        ///
        /// @fcn        RichTextEditor.Coordinator.textViewDidBeginEditing
        /// @brief      Reflect user-driven rich-editor focus in SwiftUI
        /// @details    Sets the parent focus binding only when the change was not initiated by the coordinator's
        ///             focus reconciliation.
        ///
        /// @param[in]  textView  Native rich-text editor delivering the delegate callback
        ///
        /// @return     (Void) no return value
        ///
        func textViewDidBeginEditing(_ textView: UITextView)
        {

            if !applyingFocus, parent.focus?.wrappedValue == false
            {
                parent.focus?.wrappedValue = true
            }

        }


        ///
        /// @fcn        RichTextEditor.Coordinator.textViewDidEndEditing
        /// @brief      Reflect user-driven rich-editor blur in SwiftUI
        /// @details    Clears the parent focus binding while avoiding a feedback loop from programmatic focus
        ///             changes.
        ///
        /// @param[in]  textView  Native rich-text editor delivering the delegate callback
        ///
        /// @return     (Void) no return value
        ///
        func textViewDidEndEditing(_ textView: UITextView)
        {

            if !applyingFocus, parent.focus?.wrappedValue == true
            {
                parent.focus?.wrappedValue = false
            }

        }


        ///
        /// @fcn        RichTextEditor.Coordinator.restore
        /// @brief      Restore attributed text, selection, and typing attributes
        /// @details    Registers the inverse state with Undo, clamps the restored selection to valid bounds, and
        ///             republishes the resulting text change.
        ///
        /// @param[in]  text       Attributed or plain text to restore or display
        /// @param[in]  selection  Text selection or resolved navigation selection to retain
        /// @param[in]  typing     Typing attributes to restore with the text and selection
        ///
        /// @return     (Void) no return value
        ///
        func restore(_ text: NSAttributedString, selection: NSRange, typing: [NSAttributedString.Key: Any])
        {

            guard let view else
            {
                return
            }

            let previous = NSAttributedString(attributedString: view.attributedText)
            let oldSelection = view.selectedRange
            let oldTyping = view.typingAttributes
            view.undoManager?.registerUndo(withTarget: self)
            {

                $0.restore(previous, selection: oldSelection, typing: oldTyping)
            }

            view.attributedText = text
            view.selectedRange = NSRange(
                location: min(selection.location, text.length),
                length: min(selection.length, max(0, text.length - selection.location)))
            view.typingAttributes = typing
            textViewDidChange(view)
        }


        ///
        /// @fcn        RichTextEditor.Coordinator.apply
        /// @brief      Apply a formatting transform with Undo support
        /// @details    Registers the previous content and selection, transforms typing attributes for an insertion
        ///             point, or rewrites selected attributed runs while preserving selection.
        ///
        /// @param[in]  change  Transform from the current attributed-text attributes to their edited values
        ///
        /// @return     (Void) no return value
        ///
        func apply(_ change: ([NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any])
        {

            guard let view else
            {
                return
            }

            let previous = NSAttributedString(attributedString: view.attributedText)
            let selection = view.selectedRange
            let typing = view.typingAttributes
            view.undoManager?.registerUndo(withTarget: self)
            {

                $0.restore(previous, selection: selection, typing: typing)
            }

            if selection.length == 0
            {
                view.typingAttributes = change(view.typingAttributes);
                return
            }

            let copy = NSMutableAttributedString(attributedString: view.attributedText)
            copy.enumerateAttributes(in: selection)
            {
                attributes, range, _ in
                copy.setAttributes(change(attributes), range: range)
            }

            view.attributedText = copy
            view.selectedRange = selection
            textViewDidChange(view)
        }


        ///
        /// @fcn        RichTextEditor.Coordinator.toggle
        /// @brief      Toggle one font trait for the current editing context
        /// @details    Derives the requested trait state from the caret or selection and applies it through the
        ///             shared undoable attribute transform.
        ///
        /// @param[in]  trait  UIFont symbolic trait to toggle in the current selection or typing attributes
        ///
        /// @return     (Void) no return value
        ///
        func toggle(_ trait: UIFontDescriptor.SymbolicTraits)
        {

            guard let view else
            {
                return
            }

            let attributes =
            view.selectedRange.length == 0
            ? view.typingAttributes
            : view.textStorage.attributes(at: view.selectedRange.location, effectiveRange: nil)
            let enabled = !((attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(trait) ?? false)
            apply
            {
                attributes in
                var attributes = attributes
                let font = (attributes[.font] as? UIFont) ?? .preferredFont(forTextStyle: .body)
                var traits = font.fontDescriptor.symbolicTraits
                if enabled
                {
                    traits.insert(trait)
                }
                else
                {
                    traits.remove(trait)
                }

                attributes[.font] = UIFont(
                    descriptor: font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor,
                    size: font.pointSize)
                return attributes
            }

        }


        ///
        /// @fcn        RichTextEditor.Coordinator.font
        /// @brief      Apply a font family or size without discarding traits
        /// @details    Keeps existing symbolic traits and unspecified settings while retaining Plenact font metadata
        ///             for persistence.
        ///
        /// @param[in]  name  Requested font family; nil retains the current family
        /// @param[in]  size  Requested font size; nil retains the current size
        ///
        /// @return     (Void) no return value
        ///
        func font(name: String?, size: Double?)
        {

            apply
            {
                attributes in
                var attributes = attributes
                let old = (attributes[.font] as? UIFont) ?? .preferredFont(forTextStyle: .body)
                let pointSize = size.map
                {
                    CGFloat($0)
                }
                ?? old.pointSize
                let base =
                name == "System"
                ? UIFont.systemFont(ofSize: pointSize)
                : (name.flatMap
                    {
                        UIFont(name: $0, size: pointSize)
                    }
                    ?? old.withSize(pointSize))
                attributes[.font] = UIFont(
                    descriptor: base.fontDescriptor.withSymbolicTraits(old.fontDescriptor.symbolicTraits)
                    ?? base.fontDescriptor, size: pointSize)
                if let name
                {
                    attributes[NSAttributedString.Key("PlenactFontName")] = name
                }

                if let size
                {
                    attributes[NSAttributedString.Key("PlenactFontSize")] = size
                }

                return attributes
            }

        }


        ///
        /// @fcn        RichTextEditor.Coordinator.color
        /// @brief      Apply a named rich-text foreground color
        /// @details    Uses the shared color catalog and removes explicit stored color metadata when the Default
        ///             color is selected.
        ///
        /// @param[in]  name  Named rich-text color; Default clears the explicit color override
        ///
        /// @return     (Void) no return value
        ///
        func color(_ name: String)
        {

            apply
            {
                attributes in
                var attributes = attributes
                attributes[.foregroundColor] = PlanRichText.colors.first(where:
                    {
                        $0.0 == name
                    })?.1 ?? UIColor.label
                attributes[NSAttributedString.Key("PlenactColor")] = name == "Default" ? nil : name
                return attributes
            }

        }

    }

}
