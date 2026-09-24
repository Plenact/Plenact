# Plenact Labels

Labels are reusable, categorized tags that can be attached to cards. The label catalog is shared across cards on this installation; removing a label from one card does not remove it from the library.

## Using Labels

1. Open a card and tap **Labels** in the **Details** section.
2. Browse the catalog by category. Tap a label to select or deselect it for the current card.
3. To add a label, use **Create label**, enter its name, choose an existing category or create a category, and select a color.
4. Tap **Create and add label** to add the new label to the current card.
5. Tap **Save** to save the card assignments and any new library entries. **Cancel** discards changes made in the sheet.

Selected labels appear as colored chips in the card Details view and on board cards. Board cards show up to three chips followed by a count when more labels are assigned.

## Design Model

- `KanbanLabelCategory` represents a reusable category with a stable ID and display name.
- `KanbanLabel` represents a reusable label with a stable ID, name, category ID, and palette color.
- `LabelLibrary` owns the category and label definitions shared by all cards.
- `KanbanCard.labelIDs` stores the ordered IDs of labels assigned to that card. Cards refer to label definitions by ID rather than copying label names or colors.
- `KanbanLabelColor` is a Codable palette token; the view layer maps each token to its display color.

Starter categories include Work, Home, Finance, Health & Fitness, Leisure, and Casual, with common starter labels in each. Sample cards receive deterministic starter-label assignments; divider rows do not receive labels.

## Persistence and Scope

`LabelLibraryStore` encodes the catalog to local `UserDefaults`, and `KanbanBoardPersistence` stores the board, including each card's label IDs, as JSON. The catalog and assignments therefore survive app restarts on this installation, but are not synced between users or devices.

Users can create labels and categories and select colors from the built-in palette. Renaming or deleting existing label definitions and automatically recommended labels are not implemented yet.
