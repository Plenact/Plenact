# Windows demo handoff

The first Windows demo can load a synthetic Plenact workspace locally, show a Board, and let someone open a Card and see its details. Use C++ with Qt, with Qt Quick/QML as the initial UI direction. The [platform decision](../../Lessons/Platform-Languages-and-Desktop-Architecture.md) and [connected roadmap](Connected-Multiplatform-Roadmap.md#10-step-4-desktop-web-and-android) explain how this fits into the shared desktop application.

## First demo

1. Load the [Model 1.0 synthetic workspace](User-Data-Model/Doc/Examples/1.0/complete-workspace.json) from disk. Use its record IDs and membership references to resolve the Board, Lists, and Cards. Render the saved order, labels, and date values.
2. Open a Card from the Board and show its title and body, plus supported checklist and label information. Keep the first demo read-only so it can use the fixture as-is. For a smoke check, open **Synthetic board → Today → Gym — synthetic sample**, confirm its details match the fixture, and return to the same List.
3. Keep fixture loading and record decoding separate from QML. When private staging is available, the next milestone is to load a synthetic workspace from an authenticated snapshot, then prove a supported Card edit round trip with iOS.

Use the checked-in synthetic fixture for the demo. The accepted iOS migration checkpoint and recovery archives contain private workspace data and belong outside demo assets.

## References

| Reference | What to use it for |
| --- | --- |
| [Model specification](User-Data-Model/Specification.md), [date rules](User-Data-Model/Date-and-Compatibility-Rules.md), and [conformance fixtures](User-Data-Model/Conformance.md) | Record identities, ordered membership, date and time interpretation, and test cases. Use the published Model 1.0 contract for the first demo. |
| [Board presentation](../../Design/Board-Presentation.md), [Card detail view](../../../Src/Features/Cards/CardDetailView.swift), and [Card model](../../../Src/Models/KanbanCard.swift) | iOS interaction and terminology. Adapt the layout and input to Windows and use the published model for portable records. |
| [Plenact app icon](../../../Design/AppIcons/README.md) | Brand artwork and source asset information. |
| [Protocol 1.0](User-Data-Model/Synchronization.md), [OpenAPI](User-Data-Model/Contracts/1.0/openapi.json), and [Windows capability example](User-Data-Model/Contracts/1.0/Fixtures/windows-capabilities.json) | Future private staging integration. Connect over authenticated HTTPS when it is available. The current Bluehost deployment is the historical [Version 0 shared demo](../../../Server/README.md). |

The workspace fixture is a portable export with asset metadata. The [example guide](User-Data-Model/Doc/Examples/README.md) identifies the separate server-frame example and its independent IDs. Keep demo attachment presentation optional until the client has verified original bytes.
