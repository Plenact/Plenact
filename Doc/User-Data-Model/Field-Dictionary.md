# Model 1.0 field dictionary

**Supported User Data Model versions:** 1.0; Version 0 is historical reference only.
**Status:** Final specification. Application/API integration is tracked separately.

The linked JSON Schemas define exact complete-value wire fields, nullability, bounds and nested definitions. Required means present; null, empty and inherited/absent override values remain distinct where allowed. No implicit source-name conversion is permitted.

All canonical documents carry `user_data_model_version`, `payload_schema_version`, `record_type`, `id`, `workspace_id` and `payload`. Server revision/provenance/deletion fields wrap documents in [server-record](Contracts/1.0/server-record.schema.json). See [Value types](Value-Types.md), [Specification](Specification.md) and the separate [source-field mapping](Source-Field-Catalogue.md).

## `account`

Schema: [account.schema.json](Contracts/1.0/account.schema.json).

| Payload field | Presence | Schema constraint |
| --- | --- | --- |
| `display_name` | required | `{"type": "string"}` |
| `account_kind` | required | `{"const": "personal"}` |
| `created_at_utc` | required | `urn:plenact:user-data:1.0:content-types#/$defs/utc_timestamp` |

## `asset`

Schema: [asset.schema.json](Contracts/1.0/asset.schema.json).

| Payload field | Presence | Schema constraint |
| --- | --- | --- |
| `account_id` | required | `urn:plenact:user-data:1.0:content-types#/$defs/uuid` |
| `kind` | required | `{"enum": ["image", "video", "audio", "drawing_original", "binary"]}` |
| `mime_type` | required | `{"type": "string"}` |
| `original_name` | required | `{}` |
| `content_state` | required | `{"enum": ["described", "unavailable"]}` |
| `byte_length` | required | `{}` |
| `sha256` | required | `{}` |
| `source_format` | required | `{}` |
| `derived_from_asset_id` | required | `{}` |
| `source_created_at_utc` | required | `{}` |
| `attribution` | required | `{}` |

## `calendar_index`

Schema: [calendar-index.schema.json](Contracts/1.0/calendar-index.schema.json).

| Payload field | Presence | Schema constraint |
| --- | --- | --- |
| `source_store_version` | required | `{"type": "integer", "minimum": 1, "maximum": 2147483647}` |
| `first_weekday` | required | `{"type": "integer", "minimum": 1, "maximum": 7}` |
| `current_week_start_date` | required | `{"type": "string"}` |
| `week_ids` | required | `{"type": "array"}` |
| `checklist_link_weeks` | required | `{"type": "array"}` |

## `calendar_week`

Schema: [calendar-week.schema.json](Contracts/1.0/calendar-week.schema.json).

| Payload field | Presence | Schema constraint |
| --- | --- | --- |
| `start_date` | required | `{"type": "string"}` |
| `collection_id` | required | `urn:plenact:user-data:1.0:content-types#/$defs/uuid` |
| `first_weekday` | required | `{"type": "integer", "minimum": 1, "maximum": 7}` |
| `time_zone` | required | `{"type": "string", "maxLength": 100}` |
| `time_zone_source` | required | `{"enum": ["source_context", "template", "user_confirmed"]}` |
| `day_lists` | required | `{"type": "array"}` |
| `explicitly_saved` | required | `{"type": "boolean"}` |

## `card`

Schema: [card.schema.json](Contracts/1.0/card.schema.json).

| Payload field | Presence | Schema constraint |
| --- | --- | --- |
| `list_id` | required | `urn:plenact:user-data:1.0:content-types#/$defs/uuid` |
| `archived` | required | `{"type": "boolean"}` |
| `title` | required | `{"type": "string"}` |
| `is_divider` | required | `{"type": "boolean"}` |
| `completed` | required | `{"type": "boolean"}` |
| `editing_locked` | required | `{"type": "boolean"}` |
| `presentation` | required | `{"enum": ["card", "note"]}` |
| `display_format` | required | `{}` |
| `description_override` | required | `{}` |
| `subtitle_override` | required | `{}` |
| `location` | required | `{}` |
| `start` | required | `{}` |
| `start_kind` | required | `{"enum": ["date", "time", "date_and_time"]}` |
| `due` | required | `{}` |
| `due_kind` | required | `{"enum": ["date", "time", "date_and_time"]}` |
| `shows_due_date_in_list` | required | `{"type": "boolean"}` |
| `source_created_at_utc` | required | `{}` |
| `checklists` | required | `{"type": "array"}` |
| `members` | required | `{"type": "array"}` |
| `label_ids` | required | `{"type": "array"}` |
| `comments` | required | `{"type": "array"}` |
| `reactions` | required | `{}` |
| `shows_reactions_in_previews` | required | `{}` |
| `attachments` | required | `{}` |
| `cover_attachment_id` | required | `{}` |
| `dismissed_activity_ids` | required | `{"type": "array"}` |
| `appearance` | required | `{}` |
| `section_layout` | required | `{}` |
| `edit_history` | required | `{}` |

## `collection`

Schema: [collection.schema.json](Contracts/1.0/collection.schema.json).

| Payload field | Presence | Schema constraint |
| --- | --- | --- |
| `title` | required | `{"type": "string"}` |
| `kind` | required | `{"enum": ["list", "board"]}` |
| `icon` | required | `{"type": "string", "maxLength": 200}` |
| `color` | required | `urn:plenact:user-data:1.0:content-types#/$defs/color` |
| `description` | required | `{}` |
| `archived` | required | `{"type": "boolean"}` |
| `board_appearance` | required | `{}` |
| `preferred_focused_list_id` | required | `{}` |
| `list_ids` | required | `{"type": "array"}` |

## `content_selection`

Schema: [content-selection.schema.json](Contracts/1.0/content-selection.schema.json).

| Payload field | Presence | Schema constraint |
| --- | --- | --- |
| `account_id` | required | `{"type": "string"}` |
| `card_id` | required | `{"type": "string"}` |
| `bookmarked` | required | `{"type": "boolean"}` |
| `importance` | required | `{"type": "integer", "minimum": 0, "maximum": 5}` |

## `daily_plan`

Schema: [daily-plan.schema.json](Contracts/1.0/daily-plan.schema.json).

| Payload field | Presence | Schema constraint |
| --- | --- | --- |
| `date` | required | `{"type": "string"}` |
| `time_zone` | required | `{"type": "string", "maxLength": 100}` |
| `intention` | required | `{"type": "string"}` |
| `constraints` | required | `{"type": "string"}` |
| `concerns` | required | `{"type": "string"}` |
| `priorities` | required | `{"type": "array"}` |
| `updated_at_utc` | required | `{}` |
| `check_in` | required | `{}` |
| `check_ins` | required | `{}` |
| `evening_review` | required | `{}` |
| `vision_step` | required | `{}` |
| `vision_completed_at_utc` | required | `{}` |

## `label_category`

Schema: [label-category.schema.json](Contracts/1.0/label-category.schema.json).

| Payload field | Presence | Schema constraint |
| --- | --- | --- |
| `name` | required | `{"type": "string"}` |

## `label`

Schema: [label.schema.json](Contracts/1.0/label.schema.json).

| Payload field | Presence | Schema constraint |
| --- | --- | --- |
| `name` | required | `{"type": "string"}` |
| `category_id` | required | `urn:plenact:user-data:1.0:content-types#/$defs/uuid` |
| `color` | required | `{"enum": ["mint", "yellow", "orange", "coral", "pink", "purple", "blue", "green", "red", "gray"]}` |

## `list`

Schema: [list.schema.json](Contracts/1.0/list.schema.json).

| Payload field | Presence | Schema constraint |
| --- | --- | --- |
| `collection_id` | required | `urn:plenact:user-data:1.0:content-types#/$defs/uuid` |
| `title` | required | `{"type": "string"}` |
| `subtitle_override` | required | `{}` |
| `archived` | required | `{"type": "boolean"}` |
| `default_item_presentation` | required | `{}` |
| `appearance` | required | `{}` |
| `card_ids` | required | `{"type": "array"}` |
| `archived_card_ids` | required | `{"type": "array"}` |

## `periodic_review`

Schema: [periodic-review.schema.json](Contracts/1.0/periodic-review.schema.json).

| Payload field | Presence | Schema constraint |
| --- | --- | --- |
| `title` | required | `{"type": "string"}` |
| `start_date` | required | `{"type": "string"}` |
| `end_date` | required | `{"type": "string"}` |
| `time_zone` | required | `{"type": "string", "maxLength": 100}` |
| `step` | required | `{"type": "integer", "minimum": 0, "maximum": 2}` |
| `highlights` | required | `{"type": "string"}` |
| `learned` | required | `{"type": "string"}` |
| `direction` | required | `{"type": "string"}` |
| `risks` | required | `{"type": "string"}` |
| `starting_objectives` | required | `{"type": "array"}` |
| `objectives` | required | `{"type": "array"}` |
| `priorities` | required | `{"type": "array"}` |
| `updated_at_utc` | required | `{}` |
| `completed_at_utc` | required | `{}` |

## `planning_template`

Schema: [planning-template.schema.json](Contracts/1.0/planning-template.schema.json).

| Payload field | Presence | Schema constraint |
| --- | --- | --- |
| `name` | required | `{"type": "string"}` |
| `kind` | required | `{"enum": ["day", "week"]}` |
| `anchor_date` | required | `{"type": "string"}` |
| `time_zone` | required | `{"type": "string", "maxLength": 100}` |
| `first_weekday` | required | `{"type": "integer", "minimum": 1, "maximum": 7}` |
| `collection_id` | required | `urn:plenact:user-data:1.0:content-types#/$defs/uuid` |
| `weekdays` | required | `{"type": "array"}` |
| `example_focus` | required | `{}` |

## `review_rhythm`

Schema: [review-rhythm.schema.json](Contracts/1.0/review-rhythm.schema.json).

| Payload field | Presence | Schema constraint |
| --- | --- | --- |
| `daily_invitations` | required | `{"type": "boolean"}` |
| `weekly_invitations` | required | `{"type": "boolean"}` |
| `daily_minutes` | required | `{"type": "integer", "minimum": 0, "maximum": 1439}` |
| `weekly_minutes` | required | `{"type": "integer", "minimum": 0, "maximum": 1439}` |
| `weekly_weekday` | required | `{"type": "integer", "minimum": 1, "maximum": 7}` |
| `daily_notifications` | required | `{"type": "boolean"}` |
| `weekly_notifications` | required | `{"type": "boolean"}` |

## `studio_artwork`

Schema: [studio-artwork.schema.json](Contracts/1.0/studio-artwork.schema.json).

| Payload field | Presence | Schema constraint |
| --- | --- | --- |
| `name` | required | `{"type": "string"}` |
| `surface` | required | `urn:plenact:user-data:1.0:content-types#/$defs/surface` |
| `header` | required | `{}` |
| `italic_subtitle` | required | `{}` |
| `title_color` | required | `{}` |
| `text_color` | required | `{}` |

## `studio_settings`

Schema: [studio-settings.schema.json](Contracts/1.0/studio-settings.schema.json).

| Payload field | Presence | Schema constraint |
| --- | --- | --- |
| `account_id` | required | `urn:plenact:user-data:1.0:content-types#/$defs/uuid` |
| `views` | required | `{"type": "array"}` |
| `default_card_surface` | required | `{}` |
| `default_note_surface` | required | `{}` |
| `varies_new_surfaces` | required | `{"type": "boolean"}` |
| `varies_new_headers` | required | `{"type": "boolean"}` |
| `palette` | required | `{"type": "array"}` |

## `template_library`

Schema: [template-library.schema.json](Contracts/1.0/template-library.schema.json).

| Payload field | Presence | Schema constraint |
| --- | --- | --- |
| `source_store_version` | required | `{"type": "integer", "minimum": 1, "maximum": 2147483647}` |
| `template_ids` | required | `{"type": "array"}` |
| `default_week_id` | required | `{}` |
| `bundled_routine_revision` | required | `{}` |

## `today_shortcuts`

Schema: [today-shortcuts.schema.json](Contracts/1.0/today-shortcuts.schema.json).

| Payload field | Presence | Schema constraint |
| --- | --- | --- |
| `items` | required | `{"type": "array", "maxItems": 6}` |

## `unavailable_reference`

Schema: [unavailable-reference.schema.json](Contracts/1.0/unavailable-reference.schema.json).

| Payload field | Presence | Schema constraint |
| --- | --- | --- |
| `target_type` | required | `{"enum": ["card", "collection", "list", "label", "label_category", "asset"]}` |
| `target_id` | required | `urn:plenact:user-data:1.0:content-types#/$defs/uuid` |
| `reason` | required | `{"const": "legacy_unresolved"}` |
| `display_text` | required | `{"type": ["string", "null"]}` |

## `user_preferences`

Schema: [user-preferences.schema.json](Contracts/1.0/user-preferences.schema.json).

| Payload field | Presence | Schema constraint |
| --- | --- | --- |
| `account_id` | required | `urn:plenact:user-data:1.0:content-types#/$defs/uuid` |
| `preferences` | required | `{"type": "object"}` |

## `user_profile`

Schema: [user-profile.schema.json](Contracts/1.0/user-profile.schema.json).

| Payload field | Presence | Schema constraint |
| --- | --- | --- |
| `account_id` | required | `urn:plenact:user-data:1.0:content-types#/$defs/uuid` |
| `source_profile_id` | required | `urn:plenact:user-data:1.0:content-types#/$defs/uuid` |
| `source_created_at_utc` | required | `urn:plenact:user-data:1.0:content-types#/$defs/utc_timestamp` |
| `display_name` | required | `{"type": "string"}` |
| `email` | required | `{"type": "string"}` |
| `context` | required | `{"type": "string"}` |
| `avatar_color` | required | `urn:plenact:user-data:1.0:content-types#/$defs/color` |
| `avatar_icon` | required | `{"type": "string"}` |
| `avatar_foreground_color` | required | `urn:plenact:user-data:1.0:content-types#/$defs/color` |
| `avatar_asset_id` | required | `{}` |

## `weekly_review`

Schema: [weekly-review.schema.json](Contracts/1.0/weekly-review.schema.json).

| Payload field | Presence | Schema constraint |
| --- | --- | --- |
| `source_review_key` | required | `{"type": "string"}` |
| `start_date` | required | `{"type": "string"}` |
| `time_zone` | required | `{"type": "string", "maxLength": 100}` |
| `first_weekday` | required | `{"type": "integer", "minimum": 1, "maximum": 7}` |
| `step` | required | `{"type": "integer", "minimum": 0, "maximum": 2}` |
| `highlights` | required | `{"type": "string"}` |
| `learned` | required | `{"type": "string"}` |
| `direction` | required | `{"type": "string"}` |
| `constraints` | required | `{"type": "string"}` |
| `risks` | required | `{"type": "string"}` |
| `priorities` | required | `{"type": "array"}` |
| `decisions` | required | `{"type": "array"}` |
| `updated_at_utc` | required | `{}` |
| `completed_at_utc` | required | `{}` |

## `workspace_display_preferences`

Schema: [workspace-display-preferences.schema.json](Contracts/1.0/workspace-display-preferences.schema.json).

| Payload field | Presence | Schema constraint |
| --- | --- | --- |
| `board_presentation` | required | `{}` |
| `card_covers_enabled` | required | `{}` |
| `activity_shows_covers` | required | `{}` |
| `activity_recent_square_cards` | required | `{}` |
| `library_shows_collection_previews` | required | `{}` |
| `library_scrolls_collection_previews` | required | `{}` |

## `workspace`

Schema: [workspace.schema.json](Contracts/1.0/workspace.schema.json).

| Payload field | Presence | Schema constraint |
| --- | --- | --- |
| `owner_account_id` | required | `urn:plenact:user-data:1.0:content-types#/$defs/uuid` |
| `display_name` | required | `{"type": "string"}` |
| `calendar_system` | required | `{"const": "gregorian"}` |
| `state` | required | `{"enum": ["active", "deleting"]}` |
