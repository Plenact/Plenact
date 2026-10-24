// --------------------------------------------------------------------------------------------------
// @file       StarterContent.swift
// @brief      Deterministic Week starters and built-in List guidance
// @details    Provides authored examples and conservative legacy welcome-card recognition without
//             adding persisted guides during ordinary List visits.
//
// --------------------------------------------------------------------------------------------------
import Foundation


// -------------------------------------- MARK: - Sample Data ----------------------------------- //


///
/// Provides deterministic sample content used by the board and previews
///
/// @section    Purpose
///     Construct seven weekday lists with realistic planning cards and representative divider rows
///     without requiring persistence
///
enum SampleData
{


    /// Titles assigned to the seven horizontally navigable Board lists.
    static let listTitles = [ /* Weekday list ordering for the starter Board */
            "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
    ]

    /// Planning-oriented card titles aligned with each weekday list.
    static let cardTitlesByDay: [[String]] = [ /* Synthetic activity titles grouped by weekday */
        [
                    "Review the week ahead",
                    "Set three priorities",
                    "Prepare for focused work",
                    "Laundry session",
                    "Take a movement break",
                    "Evening reset"
        ],
        [
                    "Review today's schedule",
                    "Focus session",
                    "Reply to important messages",
                    "Plan groceries",
                    "Capture a new idea",
                    "Prepare for tomorrow"
        ],
        [
                    "Midweek check-in",
                    "Project work session",
                    "Review daily finances",
                    "Reset the home space",
                    "Take a walk",
                    "Review recent notes"
        ],
        [
                    "Choose today's focus",
                    "Deep work block",
                    "Make an important call",
                    "Complete errands",
                    "Make time for creativity",
                    "Evening review"
        ],
        [
                    "Close weekly priorities",
                    "Finish the current task",
                    "Tidy the workspace",
                    "Complete personal admin",
                    "Plan the weekend",
                    "Weekly reflection"
        ],
        [
                    "Plan a slower morning",
                    "Work on a home project",
                    "Laundry and linens",
                    "Spend time outdoors",
                    "Connect with someone",
                    "Prepare for Sunday"
        ],
        [
                    "Weekly reflection",
                    "Review the upcoming calendar",
                    "Plan Monday priorities",
                    "Prepare meals",
                    "Rest and recharge",
                    "Capture notes and ideas"
        ]
    ]


    ///
    /// @fcn        SampleData.actionDetail(title:description:steps:comment:)
    /// @brief      Build one deterministic reduced-detail demonstration
    /// @details    Creates standard nested actions and one respectful sample comment without
    ///             introducing recursive linked or detailed actions
    ///
    /// @param[in]  title        Nested checklist title
    /// @param[in]  description  Supporting Action Detail text
    /// @param[in]  steps        Standard nested action titles
    /// @param[in]  comment      Sample comment body
    ///
    /// @return     (KanbanChecklistActionDetail) configured demonstration detail
    ///
    private static func actionDetail(title: String, description: String, steps: [String], comment: String)
    -> KanbanChecklistActionDetail
    {


        let nestedItems = steps.map
        {
            KanbanChecklistItem(title: $0)
        }  /* Standard nested actions */

        let checklist = KanbanChecklist(title: title, items: nestedItems)  /* Nested checklist   */
        let sampleDate = Date(timeIntervalSince1970: 1_790_467_200)        /* Stable sample date */
        let comments = [
            KanbanComment(author: "Plenact Demo", body: comment, createdAt: sampleDate)
        ] /* Sample discussion       */

        return KanbanChecklistActionDetail(
            description: description,
            checklists: [checklist],
            comments: comments
        )
    }


    ///
    /// @fcn        SampleData.enrichedChecklists(for:linkedCard:)
    /// @brief      Add linked-card and Action Detail demonstrations to one starter card
    /// @details    Appends one Board-card link and two reduced details to the first seeded
    ///             checklist while preserving all existing standard actions and checklist groups
    ///
    /// @param[in]  card        Starter card receiving demonstration actions
    /// @param[in]  linkedCard  Existing starter card used as the navigation target
    ///
    /// @return     ([KanbanChecklist]) enriched checklist collection
    ///
    private static func enrichedChecklists(for card: KanbanCard, linkedCard: KanbanCard) -> [KanbanChecklist]
    {


        guard let firstChecklist = card.checklists.first else
        {  /* Initial checklist used to seed example actions */


            return card.checklists
        }


        let linkedAction = KanbanChecklistItem( /* Existing card link */
            title: "Open \(linkedCard.word) card",
            content: .linkedCard(cardID: linkedCard.id)
        )
        let planningDetail = actionDetail( /* Planning subcard */
            title: "Prepare",
            description: "Collect the context needed before starting the \(card.word) activity.",
            steps: ["Choose the next clear step", "Gather anything needed"],
            comment: "This detail stays with the checklist action."
        )
        let reviewDetail = actionDetail( /* Review subcard */
            title: "Review",
            description: "Capture what worked and what should happen next for \(card.word).",
            steps: ["Note the result", "Choose a follow-up action"],
            comment: "A short review can make the next session easier."
        )
        let detailActions = [ /* Owned subcard actions */
            KanbanChecklistItem(
                title: "Prepare \(card.word) details",
                content: .actionDetail(planningDetail)
            ),
            KanbanChecklistItem(
                title: "Review \(card.word) outcome",
                content: .actionDetail(reviewDetail)
            )
        ]
        let enrichedFirstChecklist = KanbanChecklist( /* Demonstration checklist */
            id: firstChecklist.id,
            title: firstChecklist.title,
            items: firstChecklist.items + [linkedAction] + detailActions
        )

        return [enrichedFirstChecklist] + card.checklists.dropFirst()
    }


    /// Complete starter Board generated from weekday lists and planning cards.
    static let lists: [KanbanList] =
    {  /* Deterministic seven-day starter Board */


        var globalIndex = 0 /* Board-wide list/card seed identity counter */

        var initializedLists = listTitles.enumerated().map
        {
        listIndex, title in /* Seed one list per weekday */

            let cards = cardTitlesByDay[listIndex].map
            {
            cardTitle -> KanbanCard in /* Seed the day's activities */

                var card = KanbanCard( /* Construct one synthetic starter card */
                    id: globalIndex,
                    word: cardTitle,
                    listTitle: title,
                    isTitleChecked: globalIndex % 3 == 0,
                    members: ["Justin Reina"],
                    labelIDs: [LabelLibrary.starterLabelIDs[globalIndex % LabelLibrary.starterLabelIDs.count]]
                )

                if listIndex < 3 && cardTitle == cardTitlesByDay[listIndex].first
                {


                    let illustration = ExampleCoverImage.allCases[
                    listIndex] /* Bundled cover selected for this example list */
                    let attachment = KanbanAttachment(
                        mediaKind: .photo, exampleImage: illustration) /* Photo record referencing the bundled cover   */

                    card.attachments = [attachment]
                    card.coverAttachmentID = attachment.id
                }


                let gallery: [(ExampleCoverImage, String?)]
                switch cardTitle
                {

                case "Review the week ahead":
                    gallery = [
                        (.calendarPlan, "Make room for what matters"),
                        (.projectPlanning, "A few clear priorities"),
                        (.workspace, "A calm place to begin")
                    ]
                case "Plan the weekend":
                    gallery = [
                        (.camping, "A little adventure together"),
                        (.travelBag, "Bring only what we need"),
                        (.picnic, "Time to pause and enjoy")
                    ]
                case "Spend time outdoors":
                    gallery = [
                        (.forestPath, "Follow a quieter path"),
                        (.coastalWalk, "Room to breathe"),
                        (.mountains, nil)
                    ]
                default:
                    gallery = []
                }

                if !gallery.isEmpty
                {

                    card.attachments =
                    (card.attachments ?? [])
                    + gallery.map
                    {
                        image, caption in
                        KanbanAttachment(mediaKind: .photo, exampleImage: image, caption: caption)
                    }

                }


                // A few local Picture rows demonstrate mixed Lists without replacing activity content.
                let picture: ExampleCoverImage?
                switch (listIndex, cardTitle)
                {

                case (1, "Capture a new idea"):
                    picture = .writingNotes
                case (2, "Take a walk"):
                    picture = .forestPath
                case (6, "Capture notes and ideas"):
                    picture = .flowerBouquet
                default:
                    picture = nil
                }

                if let picture
                {

                    let photo = KanbanAttachment(mediaKind: .photo, exampleImage: picture)
                    card.attachments = (card.attachments ?? []) + [photo]
                    card.coverAttachmentID = photo.id
                    card.displayFormat = .picture
                }


                globalIndex += 1

                return card
            }


            return KanbanList(id: listIndex, title: title, cards: cards)
        }


        // Positions at which divider rows should be inserted for each list
        let dividerPositionsByList = Array(repeating: [3], count: listTitles.count) /* Daily focus divider */

        // Insert divider rows into the initialized lists at the specified positions
        for listIndex in dividerPositionsByList.indices
        {


            // Insert dividers for the current list
            for (dividerOffset, cardPosition) in dividerPositionsByList[listIndex].enumerated()
            {


                // Insert a divider card at the calculated position within the current list
                initializedLists[listIndex].cards.insert(
                    KanbanCard(
                        id: globalIndex,
                        word: "---",
                        listTitle: initializedLists[listIndex].title,
                        isDivider: true
                    ),
                    at: cardPosition + dividerOffset
                )

                globalIndex += 1
            }

        }


        let baseLists = initializedLists /* Unmodified link-target snapshot */

        for listIndex in initializedLists.indices
        {


            let targetListIndex = (listIndex + 1) % initializedLists.count /* Next Board list */
            let targetCards = baseLists[targetListIndex].cards.filter
            {
                !$0.isSectionDivider
            }  /* Link targets    */


            for cardIndex in initializedLists[listIndex].cards.indices
            {


                let sourceCard = initializedLists[listIndex].cards[cardIndex] /* Card being enriched */

                guard !sourceCard.isSectionDivider, !targetCards.isEmpty else
                {


                    continue
                }


                let linkedCard = targetCards[sourceCard.id % targetCards.count] /* Stable target card */

                initializedLists[listIndex].cards[cardIndex].checklists = enrichedChecklists(
                    for: sourceCard,
                    linkedCard: linkedCard
                )
            }

        }


        return initializedLists
    }()
}


///
/// Provides built-in List starter and session guidance content
///
/// @section    Purpose
///     Creates empty Lists by default, supplies read-only session guide snapshots, and
///     conservatively removes untouched legacy welcome Cards.
///
enum DefaultListTutorial
{


    ///
    /// @fcn        DefaultListTutorial.guidance(for:)
    /// @brief      Build transient read-only guidance for a built-in List
    /// @details    Returns no record for ordinary Lists. The caller presents this value outside
    ///             stored content, counts, search, and progress.
    ///
    /// @param[in]  title  Built-in List title
    ///
    /// @return     (KanbanCard?) read-only guidance snapshot
    ///
    static func guidance(for title: String) -> KanbanCard?
    {

        guard var card = makeStarter(title: title, includesWelcomeCard: true).lists.first?.cards.first else
        {

            return nil
        }

        card.descriptionOverride = card.descriptionOverride?.replacingOccurrences(
            of:
                                "This welcome card is yours to edit, archive, or delete. It will not return when the List becomes empty.",
            with: "This guide stays here for this visit. Your Cards and Notes are separate from this guidance.")
        card.presentation = .note
        card.isEditingLocked = true
        return card
    }


    ///
    /// @fcn        DefaultListTutorial.removingUntouchedWelcomeCards(from:)
    /// @brief      Replace pristine legacy welcome records with session guidance
    /// @details    Requires an exact original snapshot apart from generated checklist identities.
    ///             Edited, completed, archived, copied, or otherwise customized records are retained.
    ///
    /// @param[in]  collection  Saved owner being loaded
    ///
    /// @return     (PersonalCollection) owner preserving all user-created or changed content
    ///
    static func removingUntouchedWelcomeCards(from collection: PersonalCollection) -> PersonalCollection
    {

        guard collection.kind == .list else
        {
            return collection
        }

        var result = collection
        for index in result.lists.indices
        {

            let list = result.lists[index]
            guard !list.isArchived,
            let template = makeStarter(title: list.title, includesWelcomeCard: true).lists.first?.cards.first
            else
            {
                continue
            }

            result.lists[index].cards.removeAll
            {
                card in
                guard card.id == template.id, card.checklists.count == 1,
                let checklist = card.checklists.first, let expected = template.checklists.first,
                checklist.title == expected.title, checklist.completed == expected.completed,
                checklist.items.count == expected.items.count,
                zip(checklist.items, expected.items).allSatisfy(
                    {
                        actual, expected in
                        actual.title == expected.title && actual.isCompleted == expected.isCompleted
                        && actual.content == expected.content
                    })
                else
                {
                    return false
                }

                var comparable = template
                comparable.checklists = card.checklists
                return card == comparable && !collection.savedCardIDs.contains(card.id)
            }

        }

        return result
    }


    ///
    /// @fcn        DefaultListTutorial.defaultBanner
    /// @brief      Choose the tutorial banner accent for a special list
    /// @details    Recognizes the built-in list names and returns nil for titles without a tutorial accent.
    ///
    /// @param[in]  title  Display title or proposed title text
    ///
    /// @return     (ItemAccent?) tutorial accent for a recognized special list, or nil for other titles
    ///
    static func defaultBanner(for title: String) -> ItemAccent?
    {

        switch title
        {

        case "On the Table":
            .coral
        case "In the Queue":
            .teal
        case "Scheduled":
            .graphite
        default:
            nil
        }

    }


    ///
    /// @fcn        DefaultListTutorial.makeStarter
    /// @brief      Create the initial special-list tutorial collection
    /// @details    Builds the welcome content and default appearance for the requested list; callers control when a
    ///             starter is installed.
    ///
    /// @param[in]  title                Display title or proposed title text
    /// @param[in]  includesWelcomeCard  Internal legacy fixture generation; new Lists start empty
    ///
    /// @return     (PersonalCollection) fresh special-list collection with default appearance
    ///
    static func makeStarter(title: String, includesWelcomeCard: Bool = false) -> PersonalCollection
    {

        let icon: PersonalCollectionIcon
        let color: ProfileColor
        switch title
        {

        case "On the Table":
            icon = .tasks;
            color = .coral
        case "In the Queue":
            icon = .project;
            color = .teal
        case "Scheduled":
            icon = .upcoming;
            color = .graphite
        case "Shopping":
            icon = .shopping;
            color = .teal
        case "Reminders":
            icon = .reminders;
            color = .teal
        default:
            icon = .tasks;
            color = .teal
        }

        var collection = PersonalCollection(title: title, kind: .list, icon: icon, color: color)
        if KanbanList.defaultHeaderIcon(for: title) != nil
        {

            collection.lists[0].appearance = ItemAppearance(showsIconInHeader: true)
        }

        switch title
        {

        case "On the Table":
            collection.boardAppearance = BoardAppearance(bannerBackground: .coral, addItemTextColor: .white)
        case "In the Queue":
            collection.boardAppearance = BoardAppearance(bannerBackground: .teal, addItemTextColor: .white)
        case "Scheduled":
            collection.boardAppearance = BoardAppearance(bannerBackground: .graphite, addItemTextColor: .white)
        default:
            break
        }

        let heading: String
        let body: String
        let steps: [String]
        switch title
        {

        case "On the Table":
            heading = "Make room for today"
            body =
                                "This is a place for things you hope to accomplish today, time permitting. Choose what matters most, work through what you can, and let the rest wait without pressure.\n\nAdd a Card for something to do or a Note for something to remember. Move an item here from In the Queue when you are ready to give it attention. Mark tasks complete as you go; move anything that can wait back to In the Queue.\n\nThis welcome card is yours to edit, archive, or delete. It will not return when the List becomes empty."
            steps = [
                                "Add one thing you hope to accomplish today", "Move an item here from In the Queue",
                                "Mark a task complete when it is finished"
            ]
        case "In the Queue":
            heading = "Keep it for another day"
            body =
                                "Keep ideas, unfinished tasks, and backburner items here, including things that keep getting delayed. They still matter, even when today has no room for them.\n\nAdd a Card or Note whenever something is worth keeping. Review this List when planning your day, then move an item to On the Table when you are ready to give it attention. If it needs a particular date or time, move it to Scheduled or to a day in your calendar.\n\nThis welcome card is yours to edit, archive, or delete. It will not return when the List becomes empty."
            steps = [
                                "Capture one idea or backburner task", "Move a ready item to On the Table",
                                "Mark a task complete when it is finished"
            ]
        case "Scheduled":
            heading = "Give it a place in time"
            body =
                                "Keep commitments and tasks with a planned date or time here. Use this List for things you want to return to at the right moment.\n\nAdd a Card, open it, and set its Start date or Due date in Details. Include a time when it matters. You can also move the item to a specific day in your calendar. Adding an item to this List alone does not assign a date or create a notification.\n\nWhen the time comes, work on the item here or move it to On the Table. Mark it complete when it is finished.\n\nThis welcome card is yours to edit, archive, or delete. It will not return when the List becomes empty."
            steps = [
                                "Add a task and set its Start date or Due date", "Try moving a planned item to a day in your calendar",
                                "Mark a task complete when it is finished"
            ]
        default:
            return collection
        }

        let list = collection.lists[0]
        let card = KanbanCard(
            id: 0, word: heading, listTitle: list.title,
            checklists: [KanbanChecklist(title: "Try it", items: steps.map
                    {
                        KanbanChecklistItem(title: $0)
                    })],
            comments: [], members: [], labelIDs: [LabelLibraryStore.load().referenceLabelID], attachments: [],
            descriptionOverride: body,
            subtitleOverride: "'\(title)', A quick guide to this List", presentation: .card)
        if includesWelcomeCard
        {
            collection.lists[0].cards = [card]
        }

        return collection
    }

}
