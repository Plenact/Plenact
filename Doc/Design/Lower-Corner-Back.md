# Lower-left corner Back shortcut

> **Data-model context — October 24, 2026:** The [current application/data plan](../Application-Data-Plan.md) supersedes older cloud, ownership and cross-device assumptions below. Model 1.0 is published for iOS/web/Windows; runtime synchronization remains unimplemented. Dated feature/design evidence below retains its original scope.

An optional invisible power-user shortcut, disabled by default. Enable it in Plan
Settings → Display or Account & Settings → Accessibility, then Save. It persists
in the shared local preferences and needs no account. Legacy preferences decode
the flag as false.

Supported views are focused Day/List, standalone List/Board views with an explicit
Back callback, Card detail with an upper Back control, and Calendar. Root Week
has no return action and receives no target. Notes retain their existing visible
lower Back control instead of getting a duplicate shortcut. This is not a global
screen-corner interceptor for every system sheet or native navigation stack.

A visually transparent 88-point-wide target occupies a reserved 44-point-high lower-left inset,
above the app’s bottom-toolbar allowance. The reserved row keeps the target off
list items, Add buttons, and existing toolbar controls. It uses a tap gesture;
drags are not Back commands. Keyboard show/hide removes the reserved target while editing, so it does not
introduce a blank band above the keyboard. Left remains physical left in RTL layouts.

Activation invokes the same callback as that view’s upper Back button, preserving
its navigation/save/dismissal semantics. It never invents a new destination or
selects Today. VoiceOver exposes the enabled target as a Back button.

Checks cover off-by-default legacy decoding, persistence without a profile,
reserved-space behavior with/without Back and a toolbar, and no action on render.
Finger tapping, scrolling through the region, keyboard transitions, and returning
from each supported owner should be checked in the simulator/device trial.

Full-screen pinned lists opened from Today (including On the Table, In the Queue, and Scheduled) clear the underlying toolbar height, just as full-screen destinations opened from Plans do. Their Back target stays at the lower-left corner of the presented view.

The invisible touch region is 88 points wide. In full-screen destinations it includes the bottom safe area beneath the reserved 44-point row, reaching the physical lower-left corner. When a workspace toolbar is present, the target stays above it.
