Plenact cards can hold local photos, local videos, and web links. Attachment controls are presented from card details.

## User Experience

Users can choose supported media through the system photo picker, add a valid `http` or `https` link, and view attachments associated with a Card or Note. Removal uses the existing save-first, retained-reference cleanup; media retained by Week, personal collections, archives, or undo snapshots must not be deleted.

### Photo Gallery

Cards and Notes share a horizontal **Gallery** of their existing photo attachments. The selected cover is shown separately, once; videos and links retain their own **Attachments** grid. Use the existing Add Attachment entry for the first photo, then **Add photos** in the Gallery for more.

Each photo's options menu offers **Add/Edit caption**, **Move earlier/later**, **Set as Cover**, and confirmed **Remove photo**. Drag a photo onto another Gallery photo to reorder it, or use **Arrange** and the native reorder handles. Menu movement is an alternative to drag gestures. Removal can be canceled and removes only the current item's reference; it does not directly delete image bytes.

Captions are optional text over the bottom of each photo. The overlay shows up to three lines; the full caption is available to VoiceOver, in its editor, and in the scrollable full-photo preview (also when the image is unavailable). Caption **Cancel** preserves the record; **Save** trims surrounding whitespace, and clearing the field removes the caption.

The optional `KanbanAttachment.caption` field is additive Codable metadata: older records without it still decode and nil captions omit the key. Gallery order reuses the canonical attachment array, rearranging only non-cover photo slots while preserving cover, video, and link positions. Photo UUIDs, filenames, added dates, bundled references, and captions stay together. No second photo store, file renaming, destructive migration, upload, or synchronization is introduced.

### Card covers

Open **Card/Note actions → Appearance → Card Cover**, in its own section below Banner background, for a visual chooser of attached photos, **Add Photo as Cover**, and **Remove Cover**. Cover changes apply immediately, separately from the Appearance icon/background draft; Done returns to Appearance. Photo thumbnail menus also offer **Set as Cover**. Selection is explicit: attaching a photo normally never creates a cover. Removing a cover keeps the attachment and bytes; removing the selected attachment clears the cover without choosing a fallback.

Covers reuse the selected attachment UUID; no second image file is saved. Videos and links are not cover choices. The device-only **Board Settings → Show card covers** switch hides row previews without altering content. Original bundled example photos use an optional typed `exampleImage` reference instead of a Documents filename, so canceled example drafts create no files and cleanup never treats these app resources as user media.

`CardCoverPreview` downscales local/bundled photos off the main actor before displaying bounded, decorative previews. Its decode path applies image orientation and limits the longest edge to 960 pixels. Missing images show a visible unavailable notice. It does not fetch images from external links.

### Offline Cover Library

Open **Card detail → Appearance → Card Cover → Browse Cover Library**. The chooser starts with **All Covers**, and its category menu offers six groups of eight illustrations. Tap a named preview to attach/select it; **Cancel** leaves the card unchanged. The current library cover is marked with a check and an accessible label. Accessibility text sizes use a single column, and labels wrap.

The [bundled cover images](../../CardCoverImages/) now contain **48 original illustrations**, including all 27 previously prepared images unchanged and 21 additions. Each uses the same 960-by-480 canvas, muted palette, simple geometric shapes, and no embedded text.

| Category | Eight illustrations |
| --- | --- |
| Home & Everyday | Reading corner, Tidy home, Laundry day, Home repairs, Cozy sofa, Clean kitchen, Pet care, Desk lamp |
| Nature & Garden | Garden, Watering plants, Forest path, Flower bouquet, Sunrise, Herb pots, Rainy day, Butterfly |
| Work & Learning | Workspace, Study books, Writing notes, Project planning, Learning, Calendar plan, Coding, Goal steps |
| Food & Shopping | Fresh produce, Cooking, Grocery bag, Coffee break, Baking, Breakfast, Pantry, Market |
| Travel & Outdoors | Mountains, Camping, Coastal walk, Cycling, Travel bag, Train trip, Sailboat, Picnic |
| Creativity & Connection | Painting, Music, Conversation, Shared meal, Photography, Crafting, Gift, Game night |

The artwork was drawn programmatically from original shapes, without stock imagery, remote downloads, paid image-generation calls, or personal content. PNG filenames use lowercase hyphenated versions of these titles. The existing folder resource reference includes the new files in the app bundle; no additional target entries are needed.

Measured PNG payload: **978,105 bytes for all 48 images** (about 955 KiB). This is the image-file total, not an App Store download-size measurement.

Selection creates lightweight attachment metadata referencing the bundled image through the existing `exampleImage` field. Repeated selection reuses a matching attachment UUID rather than adding duplicates. Changing covers preserves personal photos and earlier illustration attachments, which can be reused or removed in the normal gallery. **Remove Cover** clears only the selected cover; **Show card covers** remains the device-only row visibility switch.

Existing demo selections, attachment formats, storage keys, and user covers remain unchanged. Categories organize artwork, not cards. Nothing is automatically applied, no card text is analyzed or transmitted, and canceled browsing creates no files. Color customization, search, and recommendations remain future work.

## Implementation

[`PhotoAttachments.swift`](PhotoAttachments.swift) contains:

- `KanbanAttachment` and `KanbanAttachmentKind` metadata models.
- `CardAttachmentStore` for local media files and link validation.
- Photo/video picker transfer handling.
- Shared Card/Note photo Gallery, caption/arrangement sheets, preview, and source-selection UI.

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

### Picture display

**Appearance → Display as → Picture → Save** displays the existing selected Card Cover as the item’s image in Board/focused Today rows. Picture rows show the full image at its natural proportions using the same background thumbnail decoder. A missing selection shows **Choose picture**; missing image bytes show **Picture unavailable**. The image fills the rounded List row with no internal padding, visible title/footer, or ellipsis. The stored title and caption identify it to VoiceOver, and tapping opens the same record for editing. In detail, tap the picture/placeholder to open Appearance and Card Cover. Switching formats retains all photo identities, captions, filenames, cover selection, and other content. Save a Divider’s new Picture format before choosing a cover. Cover selection remains immediate and separate from the cancelable format/icon/background draft.
