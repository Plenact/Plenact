Plenact cards can hold local photos, local videos, and web links. Attachment controls are presented from card details.

## User Experience

Users can choose supported media through the system photo picker, add a valid `http` or `https` link, and view attachments associated with a card. Removing a card or attachment may remove local media after it is no longer referenced anywhere on the board.

### Card covers

Card detail's **Card Cover** section provides a visual chooser for attached photos, **Add Photo as Cover**, and **Remove Cover**. Photo thumbnail menus also offer **Set as Cover**. Selection is explicit: attaching a photo normally never creates a cover. Removing a cover keeps the attachment and bytes; removing the selected attachment clears the cover without choosing a fallback.

Covers reuse the selected attachment UUID; no second image file is saved. Videos and links are not cover choices. The device-only **Board Settings → Show card covers** switch hides row previews without altering content. Original bundled example photos use an optional typed `exampleImage` reference instead of a Documents filename, so canceled example drafts create no files and cleanup never treats these app resources as user media.

`CardCoverPreview` downscales local/bundled photos off the main actor before displaying bounded, decorative previews. Its decode path applies image orientation and limits the longest edge to 960 pixels. Missing images show a visible unavailable notice. It does not fetch images from external links.

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
- Legacy broad orphan-pruning paths still ignore cleanup errors; confirmed deletion uses candidate-only cleanup and reports failures.

Developers changing attachment Codable fields or paths must preserve existing metadata and file references.