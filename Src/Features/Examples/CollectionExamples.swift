// --------------------------------------------------------------------------------------------------
// @file       CollectionExamples.swift
// @brief      Offline personal List and Board example drafts
// @details    Constructs mixed-format synthetic content with independent identities and leaves
//             publication to an explicit checked save.
//
// --------------------------------------------------------------------------------------------------
import Foundation


///
/// Defines optional synthetic examples for personal lists
///
/// @section    Purpose
///     Demonstrate organizing contexts without replacing existing content or introducing note records
///
enum PersonalListExample: String, CaseIterable, Identifiable
{


    case onTheTable = "On the Table"
    case inTheQueue = "In the Queue"
    case scheduled = "Scheduled"
    case shopping = "Shopping"
    case upForBrew = "Up for Brew"
    case miscellaneous = "Misc"

    ///
    /// @fcn        PersonalListExample.id
    /// @brief      Identify an example in the chooser
    /// @details    Uses the fixed display name; saved collections receive independent UUIDs
    /// @return     (String) example identity
    ///
    var id: String
    {
        rawValue
    }  /* Stable personal List example identity */


    ///
    /// @fcn        PersonalListExample.coverIllustration
    /// @brief      Identify the optional original illustration for the first example card
    /// @details    Only three examples demonstrate covers; the remaining cards stay text-only
    /// @return     (ExampleCoverImage?) bundled illustration without creating attachment files
    ///
    var coverIllustration: ExampleCoverImage?
    {  /* Offline illustration featured on the example's first card */

        switch self
        {


        case .onTheTable:
            .garden
        case .inTheQueue:
            .workspace
        case .upForBrew:
            .mountains
        default:
            nil
        }

    }


    ///
    /// @fcn        PersonalListExample.summary
    /// @brief      Explain the example's organizing intent
    /// @details    Describes optional use rather than assigning dates or required lifecycle states
    /// @return     (String) chooser explanation
    ///
    var summary: String
    {  /* Brief description shown in the example picker */


        switch self
        {


        case .onTheTable:
                    "Things you would like to get to today."
        case .inTheQueue:
                    "Things you got started with this week but weren’t able to finish yet."
        case .scheduled:
                    "Something with an assigned date to complete. Add the date that applies to your plan."
        case .shopping:
                    "Groceries, supplies, and purchases to consider."
        case .upForBrew:
                    "Things that were in other lists but got put off, but are still of interest."
        case .miscellaneous:
                    "Miscellaneous content you just want to keep track of."
        }

    }


    ///
    /// @fcn        PersonalListExample.cards
    /// @brief      Supply synthetic card titles and supporting details
    /// @details    Fixtures contain no real personal records, user-media references, assignments, or dates
    /// @return     ([(String, String)]) ordered title/detail pairs
    ///
    var cards: [(String, String)]
    {  /* Seeded example card headings and descriptions */


        switch self
        {


        case .onTheTable:
            [
                ("Water the garden", "Check the soil before watering the pots and garden beds."),
                ("Call Dad", "Make time for a relaxed catch-up."),
                ("Clean the kitchen", "Clear the counters, wash dishes, and wipe the stovetop."),
                ("Take a short walk", "Choose a nearby route and enjoy some time outside."),
                ("Prepare dinner", "Check what is already in the fridge before choosing a meal."),
                ("Reply to a friend", "Send the message you have been meaning to write."),
                ("Tidy the desk", "Put away loose papers and make room for the next task."),
                ("Choose tomorrow's first step", "Write down one useful starting point, without planning every hour.")
            ]
        case .inTheQueue:
            [
                ("Review household accounts", "Gather recent statements and note any questions."),
                ("Call the accountant", "Prepare a short list of questions before getting in touch."),
                ("Research a software release", "Read the release notes and compatibility requirements."),
                ("Update the coding project", "Choose a small change, run tests, and review the result."),
                ("Book a vehicle service", "Check the maintenance record and compare available appointments."),
                ("Sort the hallway cupboard", "Start with one shelf and set aside items to donate."),
                ("Plan meals for the week", "Choose a few flexible meals and check pantry supplies."),
                ("Return a borrowed book", "Arrange a convenient time with its owner.")
            ]
        case .scheduled:
            [
                ("Church this Sunday", "Confirm the service time and travel plan yourself."),
                ("Prepare to file taxes", "Check applicable deadlines and gather the documents you need."),
                ("Parents coming into town", "Confirm their travel details and discuss plans together."),
                ("Dinner with friends", "Agree on a place, time, and any food preferences."),
                ("Library workshop", "Check the organizer's current listing and registration details."),
                ("Home maintenance visit", "Confirm access arrangements with the service provider."),
                ("Birthday gathering", "Discuss the date and guest plans before making arrangements."),
                ("Community garden session", "Check the group's schedule and what to bring.")
            ]
        case .shopping:
            [
                ("Fresh vegetables", "Choose seasonal vegetables for the meals you plan to cook."),
                ("Fruit for the week", "Check what is already at home and buy a useful amount."),
                ("Bread and oats", "Compare pantry supplies before adding quantities."),
                ("Milk or a preferred alternative", "Choose the type and amount that suits your household."),
                ("Dish soap", "Check whether a refill is available."),
                ("Light bulbs", "Confirm the fitting and brightness before buying."),
                ("Charging cable", "Check connector compatibility and the length you need."),
                ("Garden supplies", "Measure the space and compare soil or pot options.")
            ]
        case .upForBrew:
            [
                ("Visit Grandma for her birthday", "Explore travel options and ask what she would enjoy."),
                ("Explore a Tanzania trip", "Research seasons, costs, and official travel guidance before deciding."),
                ("Plan time together as a couple", "Talk about activities you would both enjoy."),
                ("Try a new hobby", "Browse a few possibilities without committing to equipment yet."),
                ("Start a small herb garden", "Consider sunlight, space, and a few easy-to-use herbs."),
                ("Build a personal coding tool", "Capture the problem it could solve and a small first experiment."),
                ("Host a neighborhood meal", "Explore interest, venue options, and a manageable format."),
                ("Learn a new language", "Think about why it interests you and sample an introductory resource.")
            ]
        case .miscellaneous:
            [
                ("A friend's favorite band", "Synthetic reference: Derek enjoys Incubus."),
                ("Museum showtimes", "Keep the official listing link here and check it before a visit."),
                (
                                        "Conversation notes from a walk",
                                        "Example reflection: we talked about gardens and possible weekend plans."
                ),
                ("A book recommendation", "Synthetic reference: a friend suggested exploring a local history book."),
                ("A meal worth making again", "Example: roasted vegetables with rice; add your own recipe details."),
                ("Gift ideas", "Keep possibilities here and check preferences before purchasing."),
                ("Project reference links", "Collect documentation links and explain why each is useful."),
                ("A thought to revisit", "Example: make more room for unhurried afternoons.")
            ]
        }

    }


    ///
    /// @fcn        PersonalListExample.makeCollection(existingTitles:)
    /// @brief      Build an independent example-list draft
    /// @details    Creates a fresh collection UUID, collision-safe title, and collection-local card
    ///             IDs. Explicit empty checklists and descriptions avoid the generic sample-card
    ///             defaults
    ///
    /// @param[in]  existingTitles  Current and retained collection names
    ///
    /// @return     (PersonalCollection) unsaved list draft with eight synthetic cards
    ///
    /// @post       No persistence, network operation, or existing record mutation occurs
    ///
    func makeCollection(existingTitles: [String]) -> PersonalCollection
    {


        let icon: PersonalCollectionIcon  /* Collection symbol selected for this example */
        let color: ProfileColor           /* Collection accent selected for this example */

        switch self
        {


        case .onTheTable:
            (icon, color) = (.tasks, .coral)
        case .inTheQueue:
            (icon, color) = (.project, .teal)
        case .scheduled:
            (icon, color) = (.upcoming, .graphite)
        case .shopping:
            (icon, color) = (.shopping, .orange)
        case .upForBrew:
            (icon, color) = (.home, .green)
        case .miscellaneous:
            (icon, color) = (.notes, .blue)
        }


        let title = PersonalCollection.uniqueTitle(
            rawValue, existingTitles: existingTitles) /* Example name made unique within the directory */
        var collection = PersonalCollection(title: title, kind: .list, icon: icon, color: color)
        if KanbanList.defaultHeaderIcon(for: title) != nil
        {

            collection.lists[0].appearance = ItemAppearance(showsIconInHeader: true)
        }  /* New personal List populated from the example */

        collection.collectionDescription = summary

        collection.lists[0].cards = cards.enumerated().map
        {
            index, content in

            var card = KanbanCard( /* Seeded record receiving example content and optional cover */
                id: index, word: content.0, listTitle: title, checklists: [],
                descriptionOverride: content.1, subtitleOverride: "Example"
            )
            if index == 0, let illustration = coverIllustration
            {  /* Featured offline image for the first seeded card */


                let attachment = KanbanAttachment(
                    mediaKind: .photo, exampleImage: illustration) /* Photo record referencing the bundled example image */

                card.attachments = [attachment]
                card.coverAttachmentID = attachment.id
            }


            return card
        }


        return collection
    }

}


///
/// Builds offline mixed-format Board examples
///
/// @section    Purpose
///     Returns synthetic unsaved collection drafts without writing collections or personal
///     preference storage.
///
enum PersonalBoardExample: String, CaseIterable, Identifiable
{


    case garden = "Garden seasons"
    case home = "A home to love"
    case travel = "Travel dreams"
    case life = "Life in Motion · Zoom playground"
    var id: String
    {
        rawValue
    }

    var summary: String
    {

        switch self
        {

        case .garden:
                    "Planting ideas, growing plans, seasonal care, and garden reflections."
        case .home:
                    "Room inspiration, practical projects, recipes, and a calmer home."
        case .travel:
                    "Dream destinations, research notes, preparations, and memories."
        case .life:
                        "A rich 12-list board for exploring Normal, Panoramic, and Gallery views. Its busiest lists contain 30, 28, and 26 items."
        }

    }

    private var topics: [(String, CoverCategory, [String])]
    {

        let garden: (String, CoverCategory, [String]) = (
                        "Garden", .nature,
                        [
                                            "Plan the herb bed", "Choose pollinator flowers", "Check the soil", "Water the seedlings",
                                            "Prepare a compost corner", "Sketch a garden path", "Harvest something fresh", "Record what is growing"
                        ]
        )
        let home: (String, CoverCategory, [String]) = (
                        "Home", .home,
                        [
                                            "Refresh the reading corner", "Organize the entryway", "Measure the desk space", "Choose a warm lamp",
                                            "Clear the kitchen counter", "Make room for plants", "Repair the loose shelf",
                                            "Capture room inspiration"
                        ]
        )
        let travel: (String, CoverCategory, [String]) = (
                        "Travel", .travel,
                        [
                                            "Choose a dream destination", "Explore a walking route", "Compare places to stay",
                                            "Plan a quiet weekend", "Prepare the packing list", "Collect local discoveries", "Map a scenic stop",
                                            "Write a travel memory"
                        ]
        )
        let food: (String, CoverCategory, [String]) = (
                        "Kitchen", .food,
                        [
                                            "Save a seasonal recipe", "Plan a simple dinner", "Prepare a market list", "Try a new breakfast",
                                            "Share a meal", "Stock the pantry", "Bake something comforting", "Record a favorite flavor"
                        ]
        )
        let learning: (String, CoverCategory, [String]) = (
                        "Learning", .work,
                        [
                                            "Choose a useful book", "Explore a new skill", "Collect one reference", "Make a study plan",
                                            "Practice for twenty minutes", "Organize research notes", "Write down a discovery",
                                            "Review the next step"
                        ]
        )
        let health: (String, CoverCategory, [String]) = (
                        "Wellbeing", .health,
                        [
                                            "Take a morning walk", "Prepare for a stretch", "Plan an outdoor break", "Choose a gentle workout",
                                            "Make time to recharge", "Reflect on energy", "Build a small routine", "Celebrate steady progress"
                        ]
        )
        let creative: (String, CoverCategory, [String]) = (
                        "Creative projects", .creativity,
                        [
                                            "Collect a color palette", "Sketch a small idea", "Capture a photograph", "Write a short story",
                                            "Make a handmade gift", "Try a creative experiment", "Share a work in progress",
                                            "Keep an inspiration note"
                        ]
        )
        let rest: (String, CoverCategory, [String]) = (
                        "Reflection", .rest,
                        [
                                            "Notice a small win", "Write a gratitude note", "Make space for quiet", "Reflect on the week",
                                            "Record a meaningful moment", "Choose what to carry forward", "Let an idea rest",
                                            "Plan an unhurried evening"
                        ]
        )
        switch self
        {

        case .garden:
            return [
                ("Inspiration", garden.1, garden.2), ("To plant", garden.1, garden.2), ("Growing", garden.1, garden.2),
                ("Seasonal care", garden.1, garden.2), ("Garden journal", garden.1, garden.2)
            ]
        case .home:
            return [
                ("Room inspiration", home.1, home.2), ("Planning", home.1, home.2), ("In progress", home.1, home.2),
                food, ("Finished and learned", home.1, home.2)
            ]
        case .travel:
            return [
                ("Destinations", travel.1, travel.2), ("Research", travel.1, travel.2),
                ("Preparing", travel.1, travel.2), ("On the journey", travel.1, travel.2),
                ("Memories", travel.1, travel.2), ("Someday", travel.1, travel.2)
            ]
        case .life:
            return [
                garden, home, travel, food, learning, health, creative, rest,
                (
                                        "Family and friends", .creativity,
                                        [
                                                                    "Plan a birthday visit", "Write a thoughtful message", "Arrange a shared meal",
                                                                    "Make a memory together"
                                        ]
                ),
                ("Weekend ideas", .travel, travel.2), ("Small victories", .rest, rest.2), ("Someday", .nature, garden.2)
            ]
        }

    }

    var listSummaries: [(title: String, count: Int)]
    {

        topics.enumerated().map
        {
            index, topic in
            (topic.0, self == .life ? ([30, 28, 26] + Array(repeating: 12, count: 9)) [index] : 12)
        }

    }


    ///
    /// @fcn        PersonalBoardExample.makeCollection
    /// @brief      Instantiate a personal board example
    /// @details    Uses the supplied date and calendar for dated content and avoids title collisions with existing
    ///             collections.
    ///
    /// @param[in]  existingTitles  Collection titles to avoid when choosing a new name
    /// @param[in]  now             Reference time used instead of an implicit clock read
    /// @param[in]  calendar        Calendar supplying local-day, time-zone, and week-boundary rules
    ///
    /// @return     (PersonalCollection) new example board collection with an available title and generated date
    ///             context
    ///
    func makeCollection(existingTitles: [String], now: Date = .now, calendar: Calendar = .current) -> PersonalCollection
    {

        var board = PersonalCollection(
            title: PersonalCollection.uniqueTitle(rawValue, existingTitles: existingTitles), kind: .board,
            icon: self == .garden ? .home : .project, color: self == .garden ? .green : .teal)
        board.collectionDescription = summary
        board.boardAppearance = BoardAppearance(
            bannerBackground: .teal, listBackground: .neutral, cardBackground: .neutral,
            cardDetail: self == .life ? .compact : .detailed)
        let accents: [ItemAccent] = [.green, .blue, .orange, .purple, .rose, .teal]
        let tints: [KanbanListTint] = [.green, .blue, .orange, .neutral, .red]
        var nextID = 0
        board.lists = topics.enumerated().map
        {
            listIndex, topic in
            var list = KanbanList(
                id: listIndex, title: topic.0, cards: [], newItemPresentation: listIndex % 3 == 0 ? .note : .card)
            list.subtitleOverride = "Ideas, useful next steps, and discoveries for " + topic.0.lowercased()
            list.appearance = ItemAppearance(
                accent: accents[listIndex % accents.count], icon: .project,
                background: listIndex % 2 == 0 ? accents[listIndex % accents.count] : nil,
                listBackground: listIndex % 2 == 0 ? tints[listIndex % tints.count] : nil)
            let images = topic.1.images
            for index in 0 ..< listSummaries[listIndex].count
            {

                let id = nextID;
                nextID += 1
                if index % 10 == 0
                {

                    list.cards.append(
                        list.makeItem(id: id, title: "--- " + ["Ideas", "This week", "Later"] [min(index / 10, 2)]))
                    continue
                }

                let action = topic.2 [(index - 1) % topic.2.count]
                let prefix =
                index > topic.2.count
                ? ["Review: ", "Explore: ", "Reflect: "] [((index - 1) / topic.2.count - 1) % 3] : ""
                var card = KanbanCard(
                    id: id, word: prefix + action, listTitle: topic.0, checklists: [],
                    descriptionOverride:
                                                        "An example for your \(topic.0.lowercased()) workspace. Make this idea your own.\n\nNotice what interests you, collect the context, and choose one useful next step.",
                    subtitleOverride: "A small step with room to grow", createdAt: now,
                    appearance: ItemAppearance(
                        accent: accents[(listIndex + index) % accents.count], icon: index % 2 == 0 ? .notes : .project))
                switch index % 10
                {

                case 1:
                    card.displayFormat = .title
                case 2:
                    card.displayFormat = .text
                case 3, 8:
                    card.displayFormat = .picture
                case 4, 7:
                    card.displayFormat = .note
                default:
                    card.displayFormat = .card
                }

                if card.displayFormat == .picture || index % 3 == 0 || index % 10 == 4
                {

                    let image = KanbanAttachment(
                        mediaKind: .photo, addedAt: now,
                        exampleImage: images[(listIndex * 7 + index) % images.count],
                        caption: "Inspiration for " + topic.0.lowercased())
                    card.attachments = [image];
                    card.coverAttachmentID = image.id
                    if index % 10 == 3
                    {

                        card.attachments?.append(
                            KanbanAttachment(
                                mediaKind: .photo, addedAt: now,
                                exampleImage: images[(listIndex * 7 + index + 11) % images.count],
                                caption: "Another direction to explore"))
                    }

                }

                if card.displayFormat == .card
                {

                    card.isTitleChecked = index % 9 == 0
                    card.startDate = calendar.date(byAdding: .day, value: -2, to: now)
                    card.dueDate = calendar.date(byAdding: .day, value: (index + listIndex) % 9 - 1, to: now)
                    card.dueDateKind = index % 2 == 0 ? .dateAndTime : .date
                    card.showsDueDateInList = index % 4 != 0
                    let detail = KanbanChecklistActionDetail(
                        description: "Prepare the context before taking this step.",
                        checklists: [
                            KanbanChecklist(title: "Prepare", items: ["Gather a reference", "Choose the next step"])
                        ],
                        comments: [
                            KanbanComment(
                                author: "Example planner", body: "Keep it small enough to begin.", createdAt: now)
                        ])
                    card.checklists = [
                        KanbanChecklist(
                            title: "Next steps",
                            items: [
                                KanbanChecklistItem(title: "Choose one useful step", isCompleted: true),
                                KanbanChecklistItem(title: "Prepare the details", content: .actionDetail(detail)),
                                KanbanChecklistItem(
                                    title: "Explore a reference",
                                    content: .webLink(URL(string: "https://en.wikipedia.org/wiki/Gardening")!))
                            ])
                    ]
                    card.comments = [
                        KanbanComment(
                            author: "Example planner",
                            body: "Example content: adjust the dates and steps to fit your life.", createdAt: now)
                    ]
                    card.members = [CardAssignee(kind: .manual, displayName: "Example planner")]
                    card.labelIDs = [
                        LabelLibrary.starterLabelIDs[(listIndex + index) % LabelLibrary.starterLabelIDs.count]
                    ]
                    card.sectionLayout = CardSectionLayout(
                        order: [.checklists, .description, .details, .media, .activity, .quickActions],
                        hidden: index % 2 == 0 ? [.activity] : [])
                }

                if index % 10 == 4
                {
                    card.labelIDs = ["leisure-hobby"];
                    board.savedCardIDs.insert(id)
                }

                list.cards.append(card)
            }

            return list
        }

        // Internal references stay in the draft's own identity space, including across lists.
        for listIndex in board.lists.indices
        {

            let nextList = board.lists[(listIndex + 1) % board.lists.count]
            guard let target = nextList.cards.first(where:
                {
                    $0.displayFormat == .note
                }),
            let source = board.lists[listIndex].cards.firstIndex(where:
                {
                    !$0.checklists.isEmpty
                })
            else
            {
                continue
            }

            var item = KanbanChecklistItem(title: "Open a related note", content: .linkedCard(cardID: target.id))
            item.linkedCollectionID = board.id
            let checklist = board.lists[listIndex].cards[source].checklists[0]
            board.lists[listIndex].cards[source].checklists[0] = KanbanChecklist(
                id: checklist.id, title: checklist.title, items: checklist.items + [item])
        }

        var archived = KanbanCard(
            id: nextID, word: "An earlier idea kept for reference", listTitle: board.lists[0].title,
            checklists: [], descriptionOverride: "This example demonstrates restoring an archived card.", createdAt: now
        )
        archived.labelIDs = ["leisure-hobby"]
        board.lists[0].archivedCards = [archived]
        let archiveList = KanbanList(
            id: board.lists.count, title: "Past season",
            cards: [
                KanbanCard(
                    id: nextID + 1, word: "A completed chapter", listTitle: "Past season", checklists: [],
                    descriptionOverride: "Restore this archived list to revisit its content.")
            ])
        var retained = archiveList;
        retained.isArchived = true;
        board.lists.append(retained)
        return board
    }

}


///
/// Defines mixed-format starter List drafts
///
/// @section    Purpose
///     Provides authored planning, exploration, and project examples without saving a collection
///     until the user accepts the draft.
///
enum MixedListTemplate: String, CaseIterable, Identifiable
{


    case planDay = "Plan a day"
    case exploreIdea = "Explore an idea"
    case startProject = "Start a project"
    var id: String
    {
        rawValue
    }

    var summary: String
    {

        switch self
        {

        case .planDay:
                    "Make room for what matters, then choose a few useful next steps."
        case .exploreIdea:
                    "Collect inspiration, ask questions, and try one small experiment."
        case .startProject:
                    "Define the outcome, gather context, and turn it into action."
        }

    }

    var illustration: ExampleCoverImage
    {

        switch self
        {

        case .planDay:
            .garden;

        case .exploreIdea:
            .mountains;

        case .startProject:
            .workspace
        }

    }

    var items: [(String, String, ItemDisplayFormat)]
    {

        switch self
        {

        case .planDay:
            [
                ("Make room for today", "A heading for your day.", .title),
                (
                                        "A little inspiration", "Replace this picture with something that sets the tone for your day.",
                                        .picture
                ),
                ("A little space, a clear intention, and one useful next step.", "Set the tone for your day.", .text),
                ("Take action", "Your next steps.", .divider),
                ("What matters today?", "Write one thing you want to make room for today.", .note),
                ("Choose your first small step", "Make it something you can begin without extra preparation.", .card),
                ("Make time for a pause", "Choose a moment to rest, walk, or reconnect.", .card),
                ("Reflect", "A place to look back.", .divider),
                ("What went well?", "Capture a small win or a moment you enjoyed.", .note),
                ("Carry forward", "Leave yourself one useful thought for tomorrow.", .note)
            ]
        case .exploreIdea:
            [
                ("Something worth exploring", "A heading for your idea.", .title),
                ("Gather inspiration", "Replace this picture with an image that sparks your idea.", .picture),
                (
                                        "Follow your curiosity before deciding what this idea should become.",
                                        "A little context for your exploration.", .text
                ),
                ("Explore", "Questions and experiments.", .divider),
                ("The idea in a sentence", "What could this be, and why does it interest you?", .note),
                ("Find one useful reference", "Collect a source, example, or conversation that could help.", .card),
                ("Try a small experiment", "Choose a quick way to learn something before committing.", .card),
                ("Keep learning", "Your discoveries and open questions.", .divider),
                ("Questions to revisit", "What are you curious or uncertain about?", .note),
                ("What did you discover?", "Keep the parts worth exploring further.", .note)
            ]
        case .startProject:
            [
                ("Computer Desk", "A heading for your project workspace.", .title),
                (
                                        "Picture the outcome", "Replace this picture with a sketch, reference, or vision for your project.",
                                        .picture
                ),
                ("Clean office up so we can start the project", "A little context before taking action.", .text),
                ("First steps", "Turn your plan into action.", .divider),
                ("What does success look like?", "Describe the result, who it helps, and what is in scope.", .note),
                ("Gather what you need", "Identify the resources, references, or people that will help.", .card),
                ("Complete the first milestone", "Define one small result you can finish and review.", .card),
                ("Project context", "Keep useful details together.", .divider),
                ("Decisions and references", "Record choices and links with a little context.", .note),
                ("Progress and next steps", "Capture what changed and where to go next.", .note)
            ]
        }

    }


    ///
    /// @fcn        MixedListTemplate.makeCollection
    /// @brief      Instantiate the mixed-presentation list template
    /// @details    Creates a fresh collection whose title avoids existing names and whose items retain the template's
    ///             intended presentation.
    ///
    /// @param[in]  existingTitles  Collection titles to avoid when choosing a new name
    ///
    /// @return     (PersonalCollection) new mixed-presentation collection with a collision-free title
    ///
    func makeCollection(existingTitles: [String]) -> PersonalCollection
    {

        let title = PersonalCollection.uniqueTitle(rawValue, existingTitles: existingTitles)
        var collection = PersonalCollection(title: title, kind: .list, icon: .notes, color: .teal)
        collection.collectionDescription = summary
        collection.lists[0].cards = items.enumerated().map
        {
            index, item in
            var card = KanbanCard(
                id: index, word: item.0, listTitle: title, checklists: [],
                descriptionOverride: item.1, subtitleOverride: "", listDisplayFormat: item.2)
            if item.2 == .note
            {
                card.presentation = .note
            }

            if item.2 == .picture
            {

                let image = KanbanAttachment(mediaKind: .photo, exampleImage: illustration)
                card.attachments = [image]
                card.coverAttachmentID = image.id
            }

            return card
        }

        return collection
    }

}


///
/// Builds personal collections from bundled examples
///
/// @section    Purpose
///     Allocates an available title and copies sample content without replacing the active calendar
///     Week.
///
extension PersonalCollection
{


    ///
    /// @fcn        PersonalCollection.exampleWeek
    /// @brief      Create a personal collection from the example week
    /// @details    Uses an available title and the example week's lists rather than replacing the active planning
    ///             week.
    ///
    /// @param[in]  existingTitles  Collection titles to avoid when choosing a new name
    ///
    /// @return     (PersonalCollection) new personal example-week collection with an available title
    ///
    static func exampleWeek(existingTitles: [String]) -> PersonalCollection
    {

        let title = uniqueTitle("Week View", existingTitles: existingTitles)
        var draft = PersonalCollection(title: title, kind: .board, icon: .project, color: .teal)
        draft.collectionDescription = "A week of plans, everyday actions, and room for reflection."
        draft.lists = SampleData.lists
        return draft
    }

}
