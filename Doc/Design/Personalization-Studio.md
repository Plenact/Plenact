# Plenact Studio

Studio adds optional, reusable artwork to the existing appearance system. Existing Cards, Notes, Lists, Boards, and view backgrounds retain their appearance until a user chooses an override.

## Finding Studio

- Open **Plan Settings → Personalization → Plenact Studio** for new-item defaults, coordinated color variety, My art, and primary-view wallpapers.
- Open a Card, Note, List, or Board's **Appearance → Background artwork** or **Board artwork** for a specific background.
- Lists and Boards also offer **Default Card and Note artwork**. An individual item's artwork overrides its inherited List/Board default. An explicit Plain material overrides inherited art; removing the override returns to inheritance.

## Materials and previews

The shared editor supports solid colors, two-color gradients, ruled paper, linen, dot grids, graph paper, a procedural landscape canvas, user images, and optional Unsplash photography. Native color pickers edit the palette; strength and readability controls soften artwork behind writing. Photo zoom and vertical position are stored per use. An item's preview visibility is independent of its detail background.

The editor previews representative writing before applying a choice. Done returns the draft to the owning appearance form; that form's existing Save/Cancel behavior remains authoritative. Complete looks retain the artwork, optional header color, subtitle style, and preview text colors. Title/supporting text color fields retain their existing preview-specific meaning.

## My art and image ownership

Photos and Files imports are prepared as orientation-corrected JPEGs capped at 2048 pixels. Input data is limited to 30 MB. Immutable artwork filenames live in `Application Support/PlenactStudioArtwork`, separate from Card attachments and existing collection background images. My art stores named reusable descriptors, not another copy of the photo for each use.

Explicit imports are retained in My art even if a subsequent appearance draft is cancelled. Cancelling does not apply that image to the item. Saved looks can be reused from an editor, renamed by tapping them in the standalone My art browser, or removed from the favorites list. Removing a favorite never deletes the source file, because existing items may still reference it. Automatic unused-artwork purging is intentionally not performed.

Imported files and the reusable library are local to the device. This feature does not add a cloud image-upload or cross-device artwork-transfer service. Synchronized metadata referencing an unavailable local file has a readable fallback rather than a forced network dependency.

## New items and inheritance

New Cards and new Notes have independently selected surface defaults. Optional color variation chooses from the configured six-digit RGB palette, and optional header variation uses the established header palette. Choices are made at creation and retained on the item. Explicit item artwork and header overrides are preserved. Section dividers are excluded.

A List or Board can define a default artwork for its descendant Cards and Notes without rewriting those records. Explicit per-item art takes precedence. Global new-item defaults do not retroactively recolor existing records. The existing apply-Board-style-to-Lists action clears List artwork overrides along with the other List appearance overrides when explicitly requested.

## View wallpapers

Studio provides independent choices for Today, Week, Plans, Activity, Calendar, Search, and Settings. Week applies to Week Boards; personal Boards inherit the Plans backdrop unless their own artwork overrides it. List and Board owner overrides continue to take precedence. Wallpaper drawing stays behind existing navigation and controls.

## Optional Unsplash integration

The picker requires an Unsplash developer application and **Access Key**, not its Secret Key. Enter the Access Key in the picker and select Save key. The key is stored in a device-only Keychain item, never in Card content, URLs, saved looks, or edit history. Clear and save the field to remove it.

Search is online and bounded to twenty results per query. Photographs use provider-supplied image URLs, retain linked photographer/Unsplash attribution, and are not copied into the offline artwork directory. Applying an online photograph, including a reused saved look, calls its provider download-tracking endpoint before updating the editor's owner draft. Failed or cancelled requests leave that owner draft unchanged. Credential-bearing requests require HTTPS and the exact `api.unsplash.com` host.

A configured access key, API availability/quota, and an approved integration consistent with the provider's current guidelines are needed for production use. Live provider search is not verified by the local regression tests. Reference: [Unsplash API guidelines](https://help.unsplash.com/en/articles/2511245-unsplash-api-guidelines).

## Validation

Focused tests cover material/appearance round trips, legacy defaults, explicit artwork preservation, creation defaults for Cards and Notes, isolated workspace preferences, immutable local image ownership and path validation, invalid provider credential destinations, and native-editor rendering. Existing random-color and subtitle-persistence regressions are included. A native editor screenshot is generated by the hosted rendering test for visual review.
