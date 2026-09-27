# Card Attachments

Plenact cards can hold local photos, local videos, and web links. Attachment controls are presented from card details.

## User Experience

Users can choose supported media through the system photo picker, add a valid `http` or `https` link, and view attachments associated with a card. Removing a card or attachment may remove local media after it is no longer referenced anywhere on the board.

## Implementation

[`PhotoAttachments.swift`](PhotoAttachments.swift) contains:

- `KanbanAttachment` and `KanbanAttachmentKind` metadata models.
- `CardAttachmentStore` for local media files and link validation.
- Photo/video picker transfer handling.
- Attachment gallery, preview, and source-selection UI.

Board JSON stores lightweight attachment metadata. Imported media bytes are written atomically under unique filenames in the app's private `Documents/CardAttachments` directory.

## Data and Privacy

Attachments are local to this app installation. This feature does not upload, synchronize, share, encrypt, or back up media. Links may open external websites, whose own privacy practices apply.

Do not present private-container storage as guaranteed secure sharing or backup. Never delete attachment files without first checking all card metadata references.

## Limitations

- No cloud or multi-device attachment synchronization.
- No collaborative attachment permissions.
- No external document-provider workflow.
- File cleanup errors are currently ignored rather than shown to the user.

Developers changing attachment Codable fields or paths must preserve existing metadata and file references.