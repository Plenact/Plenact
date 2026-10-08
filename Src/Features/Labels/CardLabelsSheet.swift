// --------------------------------------------------------------------------------------------------
// @file       CardLabelsSheet.swift
// @brief      Categorized label browser and card assignment editor
// @details    Lets users browse a shared label catalog, toggle card assignments, and create labels
//             or categories from the card detail flow
//
// @notes      Catalog and assignment edits remain local to this sheet until the user saves
//
// --------------------------------------------------------------------------------------------------
import SwiftUI


///
/// Presents the persistent label library and current card label assignments
///
/// @section    Purpose
///     Let users browse labels by category, attach or detach them from a card, and add labels to
///     the shared library
///
/// @details    Maintains a draft catalog and selected label IDs until Save returns them to the
///             owning card detail view
///
/// @note       Cancel dismisses the sheet without applying draft catalog or assignment changes
///
struct CardLabelsSheet: View {

    let onSave: (LabelLibrary, [String]) -> Void /* Callback returning the edited catalog and assignments */

    @Environment(\.dismiss) private var dismiss                     /* Dismiss action for sheet   */
    @State private var library: LabelLibrary                        /* Draft label library        */
    @State private var selectedLabelIDs: [String]                   /* Currently selected IDs     */
    @State private var labelNameDraft                  = ""         /* Draft name for new label   */
    @State private var categorySelection               = ""         /* Currently selected cat.    */
    @State private var newCategoryDraft                = ""         /* Draft name for new cat.    */
    @State private var selectedColor: KanbanLabelColor = .yellow    /* Currently selected color   */

    private let newCategoryID = "__new_category__" /* Picker sentinel for creating a category */

    ///
    /// @fcn        CardLabelsSheet.trimmedLabelName
    /// @brief      Return the proposed label name without surrounding whitespace
    /// @details    Trims spaces and newline characters before label validation and creation
    ///
    /// @return     (String) normalized label-name draft
    ///
    private var trimmedLabelName: String { /* Normalized new-label name */
        labelNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    ///
    /// @fcn        CardLabelsSheet.trimmedCategoryName
    /// @brief      Return the proposed category name without surrounding whitespace
    /// @details    Trims spaces and newline characters before category creation
    ///
    /// @return     (String) normalized category-name draft
    ///
    private var trimmedCategoryName: String { /* Normalized new-category name */
        newCategoryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    ///
    /// @fcn        CardLabelsSheet.canCreateLabel
    /// @brief      Determine whether the current label draft is valid to create
    /// @details    Requires a non-empty label name and either an existing category or a non-empty
    ///             new category name
    ///
    /// @return     (Bool) true when the current form can create a label
    ///
    private var canCreateLabel: Bool { /* Form validity for label creation */
        guard !trimmedLabelName.isEmpty else {

            return false
        }

        if categorySelection == newCategoryID {

            return !trimmedCategoryName.isEmpty
        }

        return library.categories.contains(where: { $0.id == categorySelection })
    }


    ///
    /// @fcn        CardLabelsSheet.init(library:selectedLabelIDs:onSave:)
    /// @brief      Initialize the card label editor
    /// @details    Creates local drafts from the shared catalog and this card's current label
    ///             assignments
    ///
    /// @param[in]  library          Shared category and label definitions
    /// @param[in]  selectedLabelIDs Stable IDs currently assigned to the card
    /// @param[in]  onSave           Callback receiving the edited library and assignments
    ///
    /// @return     (CardLabelsSheet) configured label browser and assignment editor
    ///
    /// @pre        library contains the definitions available to this card
    /// @post       The sheet's draft state starts with the provided catalog and assignments
    ///
    init(library: LabelLibrary, selectedLabelIDs: [String], onSave: @escaping (LabelLibrary, [String]) -> Void) {

        self.onSave = onSave
        _library = State(initialValue: library)
        _selectedLabelIDs = State(initialValue: selectedLabelIDs)
        _categorySelection = State(initialValue: library.categories.first?.id ?? "__new_category__")
    }


    ///
    /// @fcn        CardLabelsSheet.toggleLabel(_:)
    /// @brief      Toggle one label's assignment to the current card
    /// @details    Adds the stable label ID when unselected or removes it when already selected
    ///
    /// @param[in]  labelID  Stable identifier of the label being toggled
    ///
    /// @return     (Void) updates the sheet's local selected-label draft
    ///
    /// @pre        labelID identifies a label displayed by the current catalog
    /// @post       The label's selected state is inverted in the local draft
    ///
    private func toggleLabel(_ labelID: String) {

        if selectedLabelIDs.contains(labelID) {

            selectedLabelIDs.removeAll { $0 == labelID }
        } else {

            selectedLabelIDs.append(labelID)
        }
    }


    ///
    /// @fcn        CardLabelsSheet.createLabel()
    /// @brief      Create a reusable label and assign it to the current card
    /// @details    Validates the drafts, reuses a case-insensitive matching category or creates
    ///             one, then appends the label and selects its stable ID
    ///
    /// @return     (Void) updates the local catalog and card-assignment drafts
    ///
    /// @pre        canCreateLabel is true for the current form state
    /// @post       The new label appears in the catalog and is selected for this card
    /// @note       The shared catalog is committed only when Save invokes onSave
    ///
    private func createLabel() {

        guard canCreateLabel else {

            return
        }

        let categoryID: String /* Category assigned to the new label */

        if categorySelection == newCategoryID {

            let normalizedName = trimmedCategoryName.lowercased() /* Case-insensitive category lookup key */

            if let existingCategory = library.categories.first(where: {

                $0.name.lowercased() == normalizedName
            }) { /* Reuse the category matching the normalized name */
                categoryID = existingCategory.id
            } else {

                categoryID = UUID().uuidString
                library.categories.append(KanbanLabelCategory(id: categoryID, name: trimmedCategoryName))
            }
        } else {

            categoryID = categorySelection
        }

        let label = KanbanLabel(                                               /* New reusable label definition */
            id:         UUID().uuidString,
            name:       trimmedLabelName,
            categoryID: categoryID,
            color:      selectedColor
        )
        library.labels.append(label)
        selectedLabelIDs.append(label.id)
        labelNameDraft = ""
        newCategoryDraft = ""
    }

    ///
    /// @fcn        CardLabelsSheet.body
    /// @brief      Build the categorized label assignment interface
    /// @details    Lists labels by category, indicates current selections, and provides
    ///             label/category creation fields
    ///
    /// @return     (some View) card label editor with Save and Cancel actions
    ///
    /// @pre        The catalog and selected label IDs have been initialized
    /// @post       Save returns the edited catalog and assignments; Cancel discards them
    ///
    var body: some View { /* Categorized label browser and editor */
        
        NavigationStack {
            
            List {
                
                ForEach(library.categories) { category in
                    
                    Section(category.name) {
                        
                        let categoryLabels = library.labels.filter { $0.categoryID == category.id } /* Labels in this category */

                        if categoryLabels.isEmpty {
                            
                            Text("No labels yet")
                                .foregroundStyle(.secondary)
                            
                        } else {
                            
                            ForEach(categoryLabels) { label in
                                
                                Button {
                                    toggleLabel(label.id)
                                    
                                } label: {
                                    
                                    HStack(spacing: 10) {
                                        
                                        Circle()
                                            .fill(label.color.color)
                                            .frame(width: 10, height: 10)
                                        
                                        Text(label.name)
                                            .foregroundStyle(.primary)
                                        
                                        Spacer()
                                        
                                        if selectedLabelIDs.contains(label.id) {
                                            
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.tint)
                                        }
                                    }

                                    .contentShape(Rectangle())
                                }

                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("Create label") {
                    TextField("Label name", text: $labelNameDraft)
                        .textInputAutocapitalization(.words)

                    Picker("Category", selection: $categorySelection) {
                        ForEach(library.categories) { category in
                            Text(category.name).tag(category.id)
                        }

                        Text("New category...").tag(newCategoryID)
                    }

                    if categorySelection == newCategoryID {

                        TextField("New category name", text: $newCategoryDraft)
                            .textInputAutocapitalization(.words)
                    }

                    Picker("Color", selection: $selectedColor) {
                        ForEach(KanbanLabelColor.allCases) { color in
                            Label {
                                Text(color.title)
                            } icon: {
                                Circle()
                                    .fill(color.color)
                            }

                            .tag(color)
                        }
                    }

                    .pickerStyle(.menu)

                    Button(action: createLabel) {
                        Label("Create and add label", systemImage: "plus")
                    }

                    .disabled(!canCreateLabel)
                }
            }

            .navigationTitle("Card labels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(library, selectedLabelIDs)
                        dismiss()
                    }
                }
            }
        }

        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
