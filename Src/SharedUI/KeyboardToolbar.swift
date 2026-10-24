// --------------------------------------------------------------------------------------------------
// @file       KeyboardToolbar.swift
// @brief      Shared native editing context and accessory controls
// @details    Coordinates Card navigation, formatting, Undo, and toolbar visibility for the
//             currently active native text input.
//
// --------------------------------------------------------------------------------------------------
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers


///
/// Defines the workspace Note-visibility reporting callback
///
/// @section    Purpose
///     Uses an inert default so standalone editors can report appearance without requiring a root
///     toolbar owner.
///
struct WorkspaceNoteVisibilityKey: EnvironmentKey
{


    static let defaultValue: (UUID, Bool) -> Void =
    {
        _, _ in
    }

}


///
/// Exposes Note visibility reporting to nested editors
///
/// @section    Purpose
///     Passes editor identity and visibility to the injected owner so workspace chrome can follow
///     the active presentation.
///
extension EnvironmentValues
{


    var workspaceNoteVisibility: (UUID, Bool) -> Void
    {

        get
        {
            self[WorkspaceNoteVisibilityKey.self]
        }

        set
        {
            self[WorkspaceNoteVisibilityKey.self] = newValue
        }

    }

}


///
/// Defines the workspace bottom-bar height environment value
///
/// @section    Purpose
///     Defaults to zero when content is hosted outside the main workspace chrome.
///
struct WorkspaceBottomBarHeightKey: EnvironmentKey
{


    static let defaultValue: CGFloat = 0
}


///
/// Exposes reserved bottom-bar space to workspace content
///
/// @section    Purpose
///     Lets descendants account for the owning toolbar's height without querying a particular
///     native view hierarchy.
///
extension EnvironmentValues
{


    var workspaceBottomBarHeight: CGFloat
    {

        get
        {
            self[WorkspaceBottomBarHeightKey.self]
        }

        set
        {
            self[WorkspaceBottomBarHeightKey.self] = newValue
        }

    }

}


// Shared accessory actions are scoped to the visible editor, never persisted.


///
/// Carries optional previous and next Card navigation actions
///
/// @section    Purpose
///     Leaves unavailable neighbors nil so keyboard controls can reflect the current owner's
///     navigable content.
///
struct CardKeyboardNavigation
{


    var previous: (() -> Void)? = nil
    var next:     (() -> Void)? = nil
}


///
/// Defines default Card keyboard navigation in the environment
///
/// @section    Purpose
///     Uses empty actions until an owning List supplies valid neighboring destinations.
///
struct CardKeyboardNavigationKey: EnvironmentKey
{

    static let defaultValue = CardKeyboardNavigation()
}


///
/// Exposes owner-supplied Card keyboard navigation
///
/// @section    Purpose
///     Passes previous and next actions to detail editors without giving them ownership of List
///     ordering.
///
extension EnvironmentValues
{


    var cardKeyboardNavigation: CardKeyboardNavigation
    {

        get
        {
            self[CardKeyboardNavigationKey.self]
        }

        set
        {
            self[CardKeyboardNavigationKey.self] = newValue
        }

    }

}


///
/// Resolves neighboring Cards in display order
///
/// @section    Purpose
///     Flattens eligible active List content and finds adjacent identities without modifying the
///     Board.
///
enum CardKeyboardNeighbors
{


    ///
    /// @fcn        CardKeyboardNeighbors.resolve
    /// @brief      Find navigable neighbors around the current card
    /// @details    Flattens eligible active list content in display order and resolves previous and next cards by
    ///             identity without modifying the lists.
    ///
    /// @param[in]  card   Card or note being inspected or changed
    /// @param[in]  lists  Lists participating in the operation
    ///
    /// @return     ((previous: KanbanCard?, next: KanbanCard?)) optional previous and next navigable cards around the
    ///             supplied card
    ///
    static func resolve(_ card: KanbanCard, in lists: [KanbanList]) -> (previous: KanbanCard?, next: KanbanCard?)
    {

        guard
        let list = lists.first(where:
            {

                !$0.isArchived && $0.cards.contains(where:
                    {
                        $0.id == card.id && $0.createdAt == card.createdAt
                    })
            })
        else
        {
            return (nil, nil)
        }

        let items = list.cards.filter
        {
            !$0.isSectionDivider
        }

        guard let index = items.firstIndex(where:
            {
                $0.id == card.id
            }) else
        {
            return (nil, nil)
        }

        return (index > 0 ? items[index - 1] : nil, index + 1 < items.count ? items[index + 1] : nil)
    }

}


///
/// Carries context-specific keyboard toolbar actions
///
/// @section    Purpose
///     Keeps exit, Card navigation, attachment, checklist, and border choices optional for
///     different editing surfaces.
///
struct KeyboardCardActions
{


    var exit:             (() -> Void)? = nil
    var previous:         (() -> Void)? = nil
    var next:             (() -> Void)? = nil
    var attachment:       (() -> Void)? = nil
    var checklist:        (() -> Void)? = nil
    var showsUpperBorder: Bool? = nil
}


///
/// Carries rich-text formatting callbacks for a native input
///
/// @section    Purpose
///     Separates trait, color, and font changes from toolbar construction and underlying text
///     storage.
///
struct KeyboardFormatting
{


    let toggle: (UIFontDescriptor.SymbolicTraits) -> Void
    let color:  (String) -> Void
    let font:   (String?, Double?) -> Void
}


///
/// Coordinates keyboard actions for active editing contexts
///
/// @section    Purpose
///     Retains an ordered context stack and a weak native input so toolbar actions follow the
///     current Card or capture editor.
///
@MainActor
final class PlenactKeyboard
{


    static let shared = PlenactKeyboard()
    private var observers:        [NSObjectProtocol] = []
    private var contexts:         [(UUID, KeyboardCardActions)] = []
    private weak var activeInput: UIView?
    var actions:                  KeyboardCardActions
    {
        contexts.last?.1 ?? KeyboardCardActions()
    }


    ///
    /// @fcn        PlenactKeyboard.setContext
    /// @brief      Register the active card or capture keyboard actions
    /// @details    Retains the context identity and action set and refreshes available controls for the active
    ///             editor.
    ///
    /// @param[in]  id       Stable draft or objective identity
    /// @param[in]  actions  Action lines or contextual keyboard actions supplied by the caller
    ///
    /// @return     (Void) no return value
    ///
    func setContext(_ id: UUID, actions: KeyboardCardActions)
    {

        contexts.removeAll
        {
            $0.0 == id
        }
        ;
        contexts.append((id, actions));
        refreshActive()
    }


    ///
    /// @fcn        PlenactKeyboard.removeContext
    /// @brief      Remove keyboard actions only for the matching context
    /// @details    Prevents an older departing editor from clearing a newer context and refreshes controls when
    ///             removal applies.
    ///
    /// @param[in]  id  Stable draft or objective identity
    ///
    /// @return     (Void) no return value
    ///
    func removeContext(_ id: UUID)
    {
        contexts.removeAll
        {
            $0.0 == id
        }
        ;
        refreshActive()
    }


    ///
    /// @fcn        PlenactKeyboard.install
    /// @brief      Install shared native keyboard focus observation
    /// @details    Registers the notifications needed to track active text inputs and maintain the common keyboard
    ///             accessory.
    ///
    /// @return     (Void) no return value
    ///
    func install()
    {

        guard observers.isEmpty else
        {
            return
        }

        for name in [UITextField.textDidBeginEditingNotification, UITextView.textDidBeginEditingNotification]
        {

            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main)
                {
                    [weak self] notice in
                    MainActor.assumeIsolated
                    {

                        guard let view = notice.object as? UIView else
                        {
                            return
                        }

                        self?.activate(view)
                    }

                })
        }

        for name in [
            UITextField.textDidChangeNotification, UITextView.textDidChangeNotification,
            .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange,
            .NSUndoManagerDidCloseUndoGroup
        ]
        {

            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main)
                {
                    [weak self] _ in
                    MainActor.assumeIsolated
                    {
                        self?.refreshActive()
                    }

                })
        }

    }


    ///
    /// @fcn        PlenactKeyboard.activate
    /// @brief      Track a native text input as the active keyboard target
    /// @details    Associates the view with the shared keyboard toolbar and updates its available actions.
    ///
    /// @param[in]  view  Native view inspected or synchronized by the operation
    ///
    /// @return     (Void) no return value
    ///
    private func activate(_ view: UIView)
    {

        activeInput = view
        if let field = view as? UITextField
        {

            if !(field.inputAccessoryView is PlenactKeyboardToolbar)
            {

                field.inputAccessoryView = PlenactKeyboardToolbar(input: field)
            }
            (field.inputAccessoryView as? PlenactKeyboardToolbar)?.rebuild()
            field.reloadInputViews()
        }
        else if let text = view as? UITextView
        {

            if !(text.inputAccessoryView is PlenactKeyboardToolbar)
            {

                text.inputAccessoryView = PlenactKeyboardToolbar(input: text)
            }
            (text.inputAccessoryView as? PlenactKeyboardToolbar)?.rebuild()
            text.reloadInputViews()
        }

    }


    ///
    /// @fcn        PlenactKeyboard.refreshActive
    /// @brief      Refresh controls for the currently active text input
    /// @details    Updates the retained toolbar's actions and Undo availability from the latest editor context.
    ///
    /// @return     (Void) no return value
    ///
    func refreshActive()
    {

        let toolbar =
        (activeInput as? UITextField)?.inputAccessoryView ?? (activeInput as? UITextView)?.inputAccessoryView
        (toolbar as? PlenactKeyboardToolbar)?.updateAvailability()
    }

}


///
/// Renders the native Plenact keyboard accessory toolbar
///
/// @section    Purpose
///     Connects contextual navigation, Undo, and optional rich-text formatting to the active input
///     without retaining it strongly.
///
@MainActor
final class PlenactKeyboardToolbar: UIView
{


    private weak var input: UIView?
    private let formatting: KeyboardFormatting?
    private let keyboardBackdrop = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let upperEdge = CAShapeLayer()
    private var buttonViews:       [(UIBarButtonItem, UIButton)] = []
    private var undoButton:        UIBarButtonItem?
    private var redoButton:        UIBarButtonItem?
    private var contextualButtons: [(UIBarButtonItem, KeyPath<KeyboardCardActions, (() -> Void)?>)] = []


    ///
    /// @fcn        PlenactKeyboardToolbar.init
    /// @brief      Create the shared native keyboard accessory toolbar
    /// @details    Retains its input and optional formatting actions, configures a forty-four-point flexible-width
    ///             surface with an extended backdrop, and builds its controls.
    ///
    /// @param[in]  input       Native text input served by the shared keyboard accessory
    /// @param[in]  formatting  Optional rich-text formatting actions available to the toolbar
    ///
    /// @return     (PlenactKeyboardToolbar) initialized instance
    ///
    init(input: UIView, formatting: KeyboardFormatting? = nil)
    {

        self.input = input;
        self.formatting = formatting
        super.init(frame: CGRect(x: 0, y: 0, width: 390, height: 44))
        autoresizingMask = [.flexibleWidth]
        backgroundColor = .clear
        // Extend only the background beneath the system keyboard; controls remain in 44pt.
        clipsToBounds = false
        keyboardBackdrop.isUserInteractionEnabled = false
        keyboardBackdrop.accessibilityElementsHidden = true
        addSubview(keyboardBackdrop)
        upperEdge.fillColor = UIColor.clear.cgColor
        upperEdge.lineWidth = 1
        layer.addSublayer(upperEdge)
        rebuild()
    }


    ///
    /// @fcn        PlenactKeyboardToolbar.init
    /// @brief      Create the shared native keyboard accessory toolbar
    /// @details    Retains its input and optional formatting actions, configures a forty-four-point flexible-width
    ///             surface with an extended backdrop, and builds its controls.
    ///
    /// @param[in]  coder  Decoder required by the UIKit initialization protocol
    ///
    /// @return     (PlenactKeyboardToolbar) does not return; coder initialization terminates with fatalError
    ///
    required init?(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }


    ///
    /// @fcn        PlenactKeyboardToolbar.layoutSubviews
    /// @brief      Refresh toolbar layout and surface-dependent styling
    /// @details    Runs native layout first, then updates the toolbar for its current hierarchy and available width.
    ///
    /// @return     (Void) no return value
    ///
    override func layoutSubviews()
    {

        super.layoutSubviews()
        let radius: CGFloat = 24
        keyboardBackdrop.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height + radius)
        let shape = CAShapeLayer()
        shape.path =
        UIBezierPath(
            roundedRect: keyboardBackdrop.bounds,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: radius, height: radius)
        ).cgPath
        keyboardBackdrop.layer.mask = shape
        let edge = UIBezierPath()
        edge.move(to: CGPoint(x: 0.25, y: radius))
        edge.addArc(
            withCenter: CGPoint(x: radius, y: radius), radius: radius - 0.25,
            startAngle: .pi, endAngle: .pi * 1.5, clockwise: true)
        edge.addLine(to: CGPoint(x: bounds.width - radius, y: 0.25))
        edge.addArc(
            withCenter: CGPoint(x: bounds.width - radius, y: radius), radius: radius - 0.25,
            startAngle: .pi * 1.5, endAngle: .pi * 2, clockwise: true)
        upperEdge.path = edge.cgPath
        upperEdge.strokeColor = UIColor.label.resolvedColor(with: traitCollection).withAlphaComponent(0.22).cgColor
        upperEdge.isHidden = !overlaysLightNeutralSurface()
    }


    ///
    /// @fcn        PlenactKeyboardToolbar.overlaysLightNeutralSurface
    /// @brief      Decide whether the keyboard toolbar needs a light-surface upper border
    /// @details    Returns false in dark appearance, honors an explicit context choice, and otherwise uses the
    ///             presence of a modal presentation as the neutral-surface fallback.
    ///
    /// @return     (Bool) true when the toolbar's hierarchy indicates a light neutral underlying surface
    ///
    private func overlaysLightNeutralSurface() -> Bool
    {

        guard traitCollection.userInterfaceStyle != .dark else
        {
            return false
        }

        if let explicit = PlenactKeyboard.shared.actions.showsUpperBorder
        {
            return explicit
        }

        // Standard modal forms use neutral surfaces; Today and the workspace keep
        // their unoutlined edge. No screen snapshots or pixel sampling are needed.
        return input?.window?.rootViewController?.presentedViewController != nil
    }


    ///
    /// @fcn        PlenactKeyboardToolbar.action
    /// @brief      Create an accessible keyboard toolbar item
    /// @details    Uses the requested title, symbol, and callback for a single action.
    ///
    /// @param[in]  title   Display title or proposed title text
    /// @param[in]  symbol  SF Symbol name used by the control
    /// @param[in]  run     Action executed when the native toolbar item is selected
    ///
    /// @return     (UIBarButtonItem) toolbar button wired to the supplied accessible action
    ///
    private func action(_ title: String, symbol: String, run: @escaping () -> Void) -> UIBarButtonItem
    {

        let item = UIBarButtonItem(
            image: UIImage(systemName: symbol), primaryAction: UIAction(title: title)
            {
                _ in
                run()
            })
        item.accessibilityLabel = title
        item.width = 30
        return item
    }


    ///
    /// @fcn        PlenactKeyboardToolbar.contextual
    /// @brief      Build a toolbar action backed by the active card context
    /// @details    Resolves the requested optional callback from the current action set so unavailable contextual
    ///             actions can remain disabled.
    ///
    /// @param[in]  title   Display title or proposed title text
    /// @param[in]  symbol  SF Symbol name used by the control
    /// @param[in]  key     Key path selecting the editable preference or optional contextual callback
    ///
    /// @return     (UIBarButtonItem) toolbar button backed by the requested optional context callback
    ///
    private func contextual(_ title: String, symbol: String, key: KeyPath<KeyboardCardActions, (() -> Void)?>)
    -> UIBarButtonItem
    {

        let item = action(title, symbol: symbol)
        {
            PlenactKeyboard.shared.actions[keyPath: key]?()
        }

        contextualButtons.append((item, key))
        return item
    }


    ///
    /// @fcn        PlenactKeyboardToolbar.rebuild
    /// @brief      Rebuild keyboard controls for the current editor context
    /// @details    Arranges navigation, editing, formatting, and dismissal actions from the active capabilities.
    ///
    /// @return     (Void) no return value
    ///
    func rebuild()
    {

        contextualButtons = []
        let exit = contextual("Return from Card or Note", symbol: "chevron.left", key: \.exit)
        let previous = contextual("Previous item in this list", symbol: "arrow.left", key: \.previous)
        let next = contextual("Next item in this list", symbol: "arrow.right", key: \.next)
        let undo = action("Undo text edit", symbol: "arrow.uturn.backward")
        {
            [weak self] in
            self?.performUndo(redo: false)
        }

        let redo = action("Redo text edit", symbol: "arrow.uturn.forward")
        {
            [weak self] in
            self?.performUndo(redo: true)
        }

        undoButton = undo;
        redoButton = redo
        let attachment = contextual("Add attachment", symbol: "paperclip", key: \.attachment)
        let checklist = contextual("Add checklist", symbol: "checklist", key: \.checklist)
        let format = UIBarButtonItem(image: UIImage(systemName: "textformat"), menu: formattingMenu())
        format.accessibilityLabel = "Font and formatting";
        format.width = 30;
        format.isEnabled = formatting != nil
        let done = action("Hide keyboard", symbol: "chevron.down")
        {
            [weak input] in
            input?.resignFirstResponder()
        }

        let models = [exit, previous, next, undo, redo, attachment, checklist, format, done]
        buttonViews = models.map
        {
            item in
            let button = UIButton(type: .system, primaryAction: item.primaryAction)
            button.setTitle(nil, for: .normal)
            button.setImage(item.image, for: .normal)
            button.menu = item.menu;
            button.showsMenuAsPrimaryAction = item.menu != nil
            button.accessibilityLabel = item.accessibilityLabel
            button.widthAnchor.constraint(equalToConstant: 44).isActive = true
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
            return (item, button)
        }

        let middle = UIStackView(arrangedSubviews: buttonViews.dropFirst().dropLast().map
            {
                $0.1
            })
        let scroll = UIScrollView();
        scroll.showsHorizontalScrollIndicator = false
        scroll.accessibilityLabel = "Editor actions"
        scroll.accessibilityHint = "Scroll horizontally for additional keyboard actions"
        if #available(iOS 26.0, *)
        {

            // A 44pt accessory has no space for automatic scroll-edge blur.
            scroll.topEdgeEffect.isHidden = true;
            scroll.bottomEdgeEffect.isHidden = true
            scroll.leftEdgeEffect.isHidden = true;
            scroll.rightEdgeEffect.isHidden = true
        }

        scroll.addSubview(middle);
        middle.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
                middle.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
                middle.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
                middle.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
                middle.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
                middle.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
            ])
        let strip = UIStackView(arrangedSubviews: [buttonViews[0].1, scroll, buttonViews[8].1])
        subviews.filter
        {
            $0 !== keyboardBackdrop
        } .forEach
        {
            $0.removeFromSuperview()
        }

        addSubview(strip);
        strip.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
                strip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                strip.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
                strip.topAnchor.constraint(equalTo: topAnchor),
                strip.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        updateAvailability()
    }

    override var intrinsicContentSize: CGSize
    {
        CGSize(width: UIView.noIntrinsicMetric, height: 44)
    }


    ///
    /// @fcn        PlenactKeyboardToolbar.updateAvailability
    /// @brief      Refresh enabled states without replacing the toolbar
    /// @details    Rechecks native Undo and Redo and the current optional contextual actions.
    ///
    /// @return     (Void) no return value
    ///
    func updateAvailability()
    {

        setNeedsLayout()
        undoButton?.isEnabled = input?.undoManager?.canUndo == true
        redoButton?.isEnabled = input?.undoManager?.canRedo == true
        for (button, key) in contextualButtons
        {

            button.isEnabled = PlenactKeyboard.shared.actions[keyPath: key] != nil
        }

        for (item, button) in buttonViews
        {
            button.isEnabled = item.isEnabled
        }

    }


    ///
    /// @fcn        PlenactKeyboardToolbar.performUndo
    /// @brief      Run Undo or Redo and publish the native text change
    /// @details    Uses the input's undo manager, notifies the appropriate text-view delegate or text-field change
    ///             channels, and refreshes toolbar action availability.
    ///
    /// @param[in]  redo  Whether to execute Redo instead of Undo
    ///
    /// @return     (Void) no return value
    ///
    private func performUndo(redo: Bool)
    {

        if redo
        {
            input?.undoManager?.redo()
        }
        else
        {
            input?.undoManager?.undo()
        }

        if let view = input as? UITextView
        {
            view.delegate?.textViewDidChange?(view)
        }

        if let field = input as? UITextField
        {

            field.sendActions(for: .editingChanged)
            NotificationCenter.default.post(name: UITextField.textDidChangeNotification, object: field)
        }

        updateAvailability()
    }


    ///
    /// @fcn        PlenactKeyboardToolbar.formattingMenu
    /// @brief      Build the native rich-text formatting menu
    /// @details    Exposes the supported trait, font, size, and color choices through the installed formatting
    ///             callbacks.
    ///
    /// @return     (UIMenu) native menu of the formatting actions supported by the active editor
    ///
    private func formattingMenu() -> UIMenu
    {

        let style = UIMenu(
            title: "Style", options: .displayInline,
            children: [
                UIAction(title: "Bold", image: UIImage(systemName: "bold"))
                {
                    [weak self] _ in
                    self?.formatting?.toggle(.traitBold)
                },
                UIAction(title: "Italic", image: UIImage(systemName: "italic"))
                {
                    [weak self] _ in
                    self?.formatting?.toggle(.traitItalic)
                }
            ])
        let fonts = UIMenu(
            title: "Font",
            children: [
                ("System", "System"), ("Serif", "Georgia"), ("Sans serif", "AvenirNext-Regular"),
                ("Monospaced", "Menlo-Regular")
            ].map
            {
                title, name in
                UIAction(title: title)
                {
                    [weak self] _ in
                    self?.formatting?.font(name, nil)
                }

            })
        let sizes = UIMenu(
            title: "Size",
            children: [12.0, 14, 17, 20, 24, 28, 34].map
            {
                size in
                UIAction(title: "\(Int(size)) pt")
                {
                    [weak self] _ in
                    self?.formatting?.font(nil, size)
                }

            })
        let colors = UIMenu(
            title: "Color",
            children: PlanRichText.colors.map
            {
                name, color in
                UIAction(
                    title: name,
                    image: UIImage(systemName: "circle.fill")?.withTintColor(color, renderingMode: .alwaysOriginal)
                )
                {
                    [weak self] _ in
                    self?.formatting?.color(name)
                }

            })
        return UIMenu(title: "Text formatting", children: [style, fonts, sizes, colors])
    }

}
