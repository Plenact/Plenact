// --------------------------------------------------------------------------------------------------
// @file       TodayShortcuts.swift
// @brief      Retained owner-qualified Today List shortcuts
// @details    Normalizes stored pins, edits their selection, and renders destinations against
//             currently available workspace owners.
//
// --------------------------------------------------------------------------------------------------
import AVFoundation
import PhotosUI
import Speech
import SwiftUI


///
/// Persists the user's Today List shortcuts
///
/// @section    Purpose
///     Loads, normalizes, and resolves owner-qualified pins against available workspace
///     collections.
///
enum TodayListPins
{


    static let key = "Plenact.TodayListShortcuts.v1"


    ///
    /// @fcn        TodayListPins.loadInitialCollections
    /// @brief      Load the initial collections needed by Today shortcuts
    /// @details    Reads the supplied preferences without discarding existing owner data and uses the established
    ///             starter path when appropriate.
    ///
    /// @param[in]  defaults  Preferences store used for this operation
    ///
    /// @return     ([PersonalCollection]) existing collections or successfully saved first-install tutorial owners
    ///
    /// @note       Seed only a fresh installation; saved empty collections or shortcut selections stay empty.
    ///
    static func loadInitialCollections(from defaults: UserDefaults = .standard) -> [PersonalCollection]
    {

        let existing = PersonalCollectionStore.load(from: defaults)
        let savedKeys = ["Plenact.PersonalCollections.v1", "Plenact.Board.v1", PlanningCalendarStore.key, key]
        guard savedKeys.allSatisfy(
            {
                defaults.object(forKey: $0) == nil
            }) else
        {
            return existing
        }


        let initial = ["On the Table", "In the Queue", "Scheduled"].map
        {
            DefaultListTutorial.makeStarter(title: $0)
        }


        do
        {

            try PersonalCollectionStore.saveChecked(initial, to: defaults)
            let pins = initial.map
            {
                WorkspaceListReference(ownerID: $0.id, listID: $0.lists[0].id)
            }

            defaults.set(encode(pins), forKey: key)
            return initial
        }
        catch
        {

            return existing
        }

    }


    ///
    /// @fcn        TodayListPins.normalized
    /// @brief      Deduplicate and limit Today shortcut references
    /// @details    Preserves the first occurrence of each owner-qualified list reference and retains at most six
    ///             pins.
    ///
    /// @param[in]  pins  Owner-qualified Today shortcut list references
    ///
    /// @return     ([WorkspaceListReference]) first occurrences of up to six unique shortcut references
    ///
    static func normalized(_ pins: [WorkspaceListReference]) -> [WorkspaceListReference]
    {

        var seen = Set<WorkspaceListReference>()
        return Array(pins.filter
            {
                seen.insert($0).inserted
            } .prefix(6))
    }


    ///
    /// @fcn        TodayListPins.decode
    /// @brief      Decode stored Today shortcut references
    /// @details    Returns the normalized decoded references or an empty selection if decoding fails; intentionally
    ///             empty saved choices remain empty.
    ///
    /// @param[in]  data  Encoded input or media bytes
    ///
    /// @return     ([WorkspaceListReference]) decoded normalized pins, or an empty array if the data is unreadable
    ///
    static func decode(_ data: Data) -> [WorkspaceListReference]
    {

        normalized((try? JSONDecoder().decode([WorkspaceListReference].self, from: data)) ?? [])
    }


    ///
    /// @fcn        TodayListPins.encode
    /// @brief      Encode normalized Today shortcut references
    /// @details    Serializes the normalized selection for preferences storage, using the helper's fallback bytes if
    ///             encoding fails.
    ///
    /// @param[in]  pins  Owner-qualified Today shortcut list references
    ///
    /// @return     (Data) encoded normalized pins, or empty Data if encoding fails
    ///
    static func encode(_ pins: [WorkspaceListReference]) -> Data
    {

        (try? JSONEncoder().encode(normalized(pins))) ?? Data()
    }

}


///
/// Edits the Today shortcut selection as a draft
///
/// @section    Purpose
///     Normalizes the initial pins and publishes the chosen references only through the caller's
///     save action.
///
struct TodayShortcutEditor: View
{


    @State private var pins: [WorkspaceListReference]
    let owners:              [PersonalCollection]
    let onSave:              ([WorkspaceListReference]) -> Void
    @Environment(\.dismiss) private var dismiss


    ///
    /// @fcn        TodayShortcutEditor.init
    /// @brief      Initialize the Today shortcut editor with normalized pins
    /// @details    Seeds the editable pin selection through the shared normalization helper and retains the available
    ///             owners and save callback.
    ///
    /// @param[in]  pins    Owner-qualified Today shortcut list references
    /// @param[in]  owners  Canonical collection owners participating in the operation
    /// @param[in]  onSave  Checked save callback; its result or thrown error determines whether editing can finish
    ///
    /// @return     (TodayShortcutEditor) initialized instance
    ///
    init(
        pins: [WorkspaceListReference], owners: [PersonalCollection],
        onSave: @escaping ([WorkspaceListReference]) -> Void
    )
    {

        _pins = State(initialValue: TodayListPins.normalized(pins))
        self.owners = owners;
        self.onSave = onSave
    }

    private var available: [WorkspaceListDestination]
    {
        WorkspaceBrowseIndex.lists(in: owners)
    }

    var body: some View
    {

        NavigationStack
        {

            List
            {

                Section
                {

                    ForEach(pins)
                    {
                        reference in
                        let destination = available.first
                        {
                            $0.reference == reference
                        }

                        VStack(alignment: .leading, spacing: 3)
                        {

                            Text(destination?.list.title ?? "Unavailable list")
                            Text(
                                destination?.owner.title ?? "Archived or removed; remove this shortcut to free a space"
                            )
                            .font(.caption).foregroundStyle(.secondary)
                        }

                    }
                    .onDelete
                    {
                        pins.remove(atOffsets: $0)
                    }
                    .onMove
                    {
                        pins.move(fromOffsets: $0, toOffset: $1)
                    }

                }
                header:
                {

                    Text("Pinned · \(pins.count) of 6")
                }
                footer:
                {

                    Text("Drag to reorder. Removing a shortcut keeps its list and cards.")
                }

                ForEach(owners.filter(\.isActive))
                {
                    owner in
                    Section(owner.title)
                    {

                        ForEach(owner.lists.filter
                            {
                                !$0.isArchived
                            })
                        {
                            list in
                            let reference = WorkspaceListReference(ownerID: owner.id, listID: list.id)
                            Button
                            {

                                guard pins.count < 6, !pins.contains(reference) else
                                {
                                    return
                                }

                                pins.append(reference)
                            }
                            label:
                            {

                                HStack
                                {

                                    Label(
                                        list.title, systemImage: list.appearance?.icon?.rawValue ?? owner.icon.rawValue)
                                    Spacer()
                                    Image(systemName: pins.contains(reference) ? "checkmark" : "plus.circle")
                                }
                                .frame(minHeight: 44)
                            }
                            .disabled(pins.contains(reference) || pins.count >= 6)
                        }

                    }

                }

            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("My shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {

                ToolbarItem(placement: .cancellationAction)
                {
                    Button("Cancel")
                    {
                        dismiss()
                    }

                }

                ToolbarItem(placement: .confirmationAction)
                {

                    Button("Done")
                    {

                        onSave(pins);
                        dismiss()
                    }

                }

            }

        }

    }

}


///
/// Presents pinned Lists as Today shortcuts
///
/// @section    Purpose
///     Uses a three-column grid and adapts icon size to the shortcut count while delegating
///     navigation to the caller.
///
struct TodayShortcutGrid: View
{


    let pinned:                 [WorkspaceListDestination]
    let onOpen:                 (WorkspaceListReference) -> Void
    private var usesLargeIcons: Bool
    {
        pinned.count <= 3
    }


    var body: some View
    {

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10)
        {

            ForEach(pinned)
            {
                destination in
                Button
                {

                    onOpen(destination.reference)
                }
                label:
                {

                    VStack(spacing: usesLargeIcons ? 12 : 8)
                    {

                        Image(
                            systemName: destination.list.appearance?.icon?.rawValue ?? destination.owner.icon.rawValue
                        )
                        .font(.system(size: usesLargeIcons ? 40 : 25, weight: .medium))
                        .foregroundStyle(
                            (destination.list.resolvedIconColor(collectionColor: destination.owner.color)?.color
                                ?? destination.owner.libraryIdentityColor)
                        )
                        .frame(width: usesLargeIcons ? 60 : 44, height: usesLargeIcons ? 60 : 44)
                        Text(destination.list.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        .foregroundStyle(.primary).multilineTextAlignment(.center)
                        Text("\(destination.list.cards.filter { !$0.isSectionDivider } .count) cards").font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12).padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, minHeight: usesLargeIcons ? 150 : 130, alignment: .top)
                } .buttonStyle(.plain)
                .accessibilityHint("Opens " + destination.owner.title + ", " + destination.list.title)
            }

        }

    }

}
