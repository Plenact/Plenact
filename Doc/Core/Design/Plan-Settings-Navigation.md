# Modular Plan Settings

Plan Settings opens a compact directory instead of one long form. The primary pages aim for one screen, allowing up to about 1.5 screens on a normal-size iPhone. Native scrolling remains available for smaller devices and larger accessibility text. Artwork editors, personal libraries and backup/recovery workflows keep their existing content-driven layouts.

| Area | Controls |
| --- | --- |
| Appearance & Studio | Studio entry; random new-Card header/background colors |
| Today’s Focus | Preview rows, Day List time order, Focus order, grouping and fallback List; Included Items opens separate filter controls |
| Planning | Week boundary, new-Card due date visibility and Planning Templates |
| Review & Reminders | Existing independent review-rhythm editor |
| Navigation & Shortcuts | My shortcuts, navigation labels and lower-corner Back shortcut |
| Display & Accessibility | Reduced supporting content, larger controls, title scrolling and importance-star style |
| Maps | Preferred maps application |
| Your Data | Local backup and existing export/recovery tools |

Studio has its own small directory: My art, New item backgrounds, Coordinated variety and View wallpapers. Each wallpaper destination has a focused page rather than seven expanded sections on one screen.

## Saving

Plan preference pages share one draft owned by `PlanSettingsView`. Back retains the draft. Save from any preference page commits the preferences and checked calendar boundary once, then closes Plan Settings. Cancel on the main directory discards unsaved Plan preference changes. A rejected calendar boundary change leaves the draft open.

Studio, reminders, shortcuts and templates retain independent Save/Cancel or Done behavior. They do not require a second parent Save. Studio’s focused pages share its original draft; Save commits the Studio session, while Back retains edits within it. Opening Templates in Library retains the existing save/discard/keep-editing choice for unsaved Plan preferences. No preference keys, defaults, portable schemas, ownership rules or cloud behavior change.

## Validation

Fourteen focused native tests passed: new page-height and native-toggle draft tests, existing profile/preference persistence tests, settings rendering and the root navigation size guard. Screenshots were reviewed from the automated Simulator. At the tested 393×852-point size and normal Dynamic Type, the main directory measures about 626 points, Studio about 573, and reminders about 935. Other focused preference pages range from about 225 to 668 points. These are content measurements, not fixed frame limits.

Manual acceptance: open Today → gear, browse the directory, change a preference, return with Back and revisit it, then Save and reopen to confirm persistence. Repeat a small change with Cancel to confirm discard. Check Studio’s focused pages and its independent Save. No backup/import round trip is needed.
