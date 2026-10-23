// --------------------------------------------------------------------------------------------------
// @file       LibraryHelp.swift
// @brief      Offline Library help catalog and article presentation
// @details    Defines grouped help articles and paragraph sections, shared catalog searching, and
//             Library discovery rows. Presents authored guidance with optional planning navigation
//             while leaving workspace content unchanged during reading.
//
// --------------------------------------------------------------------------------------------------

import SwiftUI


///
/// Represents one authored help section
///
/// @section    Purpose
///     Keeps a section heading and ordered paragraphs together with a title-derived display
///     identity.
///
struct PlenactHelpSection: Identifiable {

    let title:      String
    let paragraphs: [String]
    var id:         String { title }
}


///
/// Represents an offline Library help article
///
/// @section    Purpose
///     Combines search metadata, symbol, sections, and an optional planning entry point without
///     embedding mutable user content.
///
struct PlenactHelpArticle: Identifiable {

    let id:       String
    let group:    String
    let title:    String
    let summary:  String
    let symbol:   String
    let sections: [PlenactHelpSection]
    var opensPlan = false


    ///
    /// @fcn        PlenactHelpArticle.matches
    /// @brief      Match a help article against a search query
    /// @details    Uses the article's searchable text and normalized query without changing the help catalog.
    ///
    /// @param[in]  query  User-entered search text
    ///
    /// @return     (Bool) true when the help article matches the normalized query
    ///
    func matches(_ query: String) -> Bool {
        let text = ([group, title, summary] + sections.flatMap { [$0.title] + $0.paragraphs }).joined(separator: " ")
        return query.split(whereSeparator: \.isWhitespace).allSatisfy { text.localizedStandardContains(String($0)) }
    }
}


///
/// Provides the bundled help catalog and search rules
///
/// @section    Purpose
///     Organizes authored articles into groups and constructs paragraph-based sections for
///     consistent offline presentation.
///
enum PlenactHelpCatalog {

    static let groups = ["Plan a life that matters", "Make Plenact your own", "Your Planning Rhythm", "Your first week with v1.0"]


    ///
    /// @fcn        PlenactHelpCatalog.section
    /// @brief      Construct a help section from authored paragraphs
    /// @details    Splits the supplied text into the paragraph representation used by the article view.
    ///
    /// @param[in]  title       Display title or proposed title text
    /// @param[in]  paragraphs  Authored multiline paragraph text used to construct help content
    ///
    /// @return     (PlenactHelpSection) help section containing the supplied title and parsed paragraphs
    ///
    private static func section(_ title: String, _ paragraphs: String...) -> PlenactHelpSection { PlenactHelpSection(title: title, paragraphs: paragraphs) }
    static let articles: [PlenactHelpArticle] = [
        .init(id: "life", group: groups[0], title: "Use the planning system for your life", summary: "Turn what matters into a realistic next step", symbol: "sun.horizon", sections: [
            section("Begin with what matters", "Choose something you want to care for: your health, a relationship, your home, meaningful work, or a hope you have kept putting off. A useful plan makes room for your life, including rest.", "Ask: What would make this day meaningful? Choose a small enough step that you can actually begin. A priority is a choice of attention, not a promise to finish everything."),
            section("Give work a place", "On the Table holds things you hope to accomplish today, time permitting. In the Queue holds worthwhile ideas, unfinished work, and backburner items. Scheduled holds work you intend to return to at a particular time.", "A dated calendar List gives an item a place on a day. Moving an item there preserves its existing date fields; it does not rewrite them. Putting something in Scheduled alone does not assign a date or create a reminder."),
            section("Keep the plan realistic", "Start with one to three priorities if that feels manageable. Consider your available time, energy, commitments, and risks. Leave space for interruptions.", "If the day changes, use Today's Check-in to adjust. Keeping, pausing, or letting go of work can be a thoughtful decision. Success does not require empty Lists or a perfect streak."),
            section("Connect days to direction", "Use daily reviews to learn from experience. Weekly Review helps you see patterns and choose next week's direction. Periodic Review connects those weeks to objectives that matter over a longer period.")
        ]),
        .init(id: "quick-start", group: groups[1], title: "Your first useful plan", summary: "Capture something, choose a priority, and take a step", symbol: "sparkles", sections: [
            section("Browse templates and examples", "Use the selector beside Library to choose Templates or Examples. Templates brings together your Day/Week routines, List templates, and Card/Note starting points. Examples groups List, Board, Week, and full-month previews. Search looks within the selected catalog. Use opens a draft for review; replacing current Week content still asks for confirmation, and using an example month retains its backup/restore flow. The + menu's browse shortcuts open these same Library views."),
            section("Reuse a day or week", "Open Library → Templates (or + → Templates → Browse all templates). Jmr is the default for new weeks, with Work Week and Vacation Day starting points alongside it. Jmr includes timed weekday work routines and distinct weekend plans; its daily Gym entry also makes room for meditation, walking, or massage. Save any planned day or week as your own template, then edit, duplicate, or delete it here. Preview & apply lets you choose a destination and Add to existing or explicitly confirm Replace. Copies start unchecked and scheduled dates shift to the target; applied plans remain independent. Choose Empty week to turn automatic templates off. Existing weeks are never refilled automatically."),
            section("Capture in the form you need", "Below Today’s Quick capture input, choose Note, Checklist, Photo, Voice, or Drawing. Anything you already typed carries into the editor. Note gives you room to write; Checklist starts an editable action list. Photo offers Take photo or Photo library, with previews and removal before Add. A camera requires permission and supported hardware. Photos are attached only when you tap Add; cancelling returns your original typed title to Quick capture."),
            section("Capture a drawing", "Drawing opens a canvas for your finger or Apple Pencil. Existing Cards and Notes also offer Add Attachment → Drawing; Done attaches the drawing directly to that item. Use the drawing tools for pens, markers, an eraser, colors, and widths. The actions menu offers Undo, Redo, and Clear. Done inserts an editable preview into your draft; Add saves it in the Card or Note. Tap the saved image, then Edit drawing, to make changes. The Export drawing menu offers PNG with a white or transparent background and JPEG with a white background. Use the share sheet to Save to Files, Save Image, AirDrop, or share. Exporting does not flatten the original drawing."),
            section("Give a capture dates", "Open Start and stop dates in the capture editor to choose optional Start and Stop dates. You can choose either, both, or neither, and include times. Stop sets the item’s due date; it must be on or after Start. These dates use the same fields as Calendar and item details. Start and stop dates are also available within the other Today capture editors."),
            section("Capture a spoken thought", "Voice offers Audio, Text, or Both. Tap Record a thought, then Stop recording (up to 60 seconds). Review the recording and edit the transcript before Add. Audio keeps a playable attachment; Text adds your reviewed transcript to the item’s writing; Both saves each. Existing writing is retained. Recording again asks before replacing the draft recording and transcript.", "Microphone access is requested when you record. Speech access is requested when transcribing; Apple’s speech recognition may need a connection depending on device and language. If transcription is unavailable, retry, type the text, or choose Audio. Leaving the app stops recording, and cancelling the capture removes its temporary recording without adding an item."),
            section("1. Capture what is on your mind", "Use New in the bottom toolbar to create a Card for something to do or a Note for something to remember. Give it a clear title and choose its destination. Today also offers Quick capture for today's dated List."),
            section("2. Choose what deserves attention", "On Today, tap the date beneath the heading to open Today's Plan. Choose priorities links existing Cards or Notes. Add priority creates a new original item and selects it for the plan.", "Add saves the original item immediately. If you later discard the plan's unsaved link, that original item remains in its List."),
            section("3. Make a small start", "Write an optional intention, note constraints or concerns, and save. Open a priority from Today's Plan to work with the original item. Complete Cards as you finish tasks; Notes are supporting context, not unfinished tasks."),
            section("4. Return and adjust", "Use the Check-in when circumstances change and the evening Review when you are ready to close the day. You can begin any flow without having completed the earlier ones.")
        ], opensPlan: true),
        .init(id: "spaces", group: groups[1], title: "Cards, Notes, Lists, and Boards", summary: "Choose a simple home for your work", symbol: "rectangle.split.3x1", sections: [
            section("Cards and Notes", "Cards are useful for actions, with completion, details, dates, checklists, labels, and attachments. Notes hold writing and reference material. Choose the format that helps you understand the item."),
            section("Lists and Boards", "A List gathers related items. A Board groups multiple Lists, useful for a project or a way of organizing work. Library's All, Lists, and Boards filters help you find those spaces. Labels provide another way to find related content."),
            section("Start with the three working Lists", "Use On the Table for today's possibilities, In the Queue for later, and Scheduled for planned work. Their Reference Cards explain each List and include a short practice checklist.", "You can edit, archive, or delete those welcome Cards. They do not return just because a List becomes empty. Reference-labelled content stays out of automatic unfinished-work processing."),
            section("Personalize gradually", "Appearance settings let you adjust supported backgrounds, colors, and display profiles. Keep the structure simple until you know what helps you. Working roles currently recognize the default List names, so keep those names during this first testing week.")
        ]),
        .init(id: "organize", group: groups[1], title: "Find, save, and schedule your work", summary: "Use dates and labels deliberately", symbol: "magnifyingglass", sections: [
            section("Find and return", "Use search to find work across Plenact. Library filters narrow your collections; Labels groups related content. Activity helps you return to recent work and saved items."),
            section("Save and mark important", "Bookmark an item when you want to return to it. Marking it important shows a soft star on supported previews. A bookmark and an important flag serve different purposes; neither automatically makes an item a daily priority."),
            section("Use dates with intention", "Set Start date or Due date on a Card when a date matters. Include a time when needed. A dated List and the item's explicit date fields are separate: moving a Card preserves those fields.", "Planning rhythm on Today offers daily and weekly reviews. Optional review reminders can be enabled in Review invitations & reminders; these are general review invitations, not per-Card deadline alerts. Check item dates deliberately.")
        ]),
        .init(id: "rhythm", group: groups[2], title: "How the five reviews work together", summary: "Plan, adjust, reflect, and choose your direction", symbol: "arrow.triangle.2.circlepath", sections: [
            section("Find the Planning Rhythm", "Open Today and tap the date beneath its heading. Today's Plan contains Today's Vision, Today's Check-in, Today's Review, Weekly Review, and Periodic Review in that order."),
            section("A rhythm you can return to", "Morning: choose what matters. Midday: adapt to reality. Evening: notice progress and decide what comes next. Weekly: look for patterns and review the Queue. Periodically: step back and assess your objectives.", "These are invitations, not obligations. Skip a session, leave fields blank, or begin again whenever it is useful. Weekly and Periodic Reviews work with missing daily or weekly records."),
            section("One shared daily plan", "Vision, Check-in, and evening Review use the same day's plan. Changes to priorities, intention, constraints, and concerns are shared. Every saved Check-in retains a timestamped note, plan, and progress snapshot. Daily review shows these records for today or a previous day.", "Priorities link original items. Removing a priority link does not delete or move its source. Completion reflects the live source Card."),
            section("Save deliberately", "Use Save, Save progress, or Save and continue within the flow. Saved steps can be resumed. Text you have not saved is not guaranteed to survive closing the app.", "Confirmed item moves, completions, and archives take effect immediately. Leaving the flow does not undo a confirmed action.")
        ], opensPlan: true),
        .init(id: "vision", group: groups[2], title: "Today's Vision · begin the day", summary: "Choose priorities and leave room for real life", symbol: "sunrise", sections: [
            section("1. See what is ahead", "Open Today's Plan → Start today's vision. Review work assigned to today or matching today's dates. Completed and Reference-labelled items are excluded from suggestions.", "Where available, a Scheduled item can be moved to On the Table after confirmation. This is optional; you can choose priorities in their current locations."),
            section("2. Choose your priorities", "Choose existing Cards or Notes, or use Add priority if something new comes to mind. Use Edit to reorder or remove priority links. A short list can be enough."),
            section("3. Make a realistic plan", "Record an optional intention, available time or energy, and concerns. Save and continue keeps each step; Save today's vision finishes the flow. Return later to revise it.")
        ], opensPlan: true),
        .init(id: "check-in", group: groups[2], title: "Today's Check-in · reset your focus", summary: "Notice progress and choose what makes sense next", symbol: "sun.max", sections: [
            section("Pause whenever useful", "Open Today's Plan → Check in now. The progress count includes priority tasks, with Notes and unavailable links shown separately. You do not need a morning plan to begin."),
            section("Adjust your attention", "Use Edit to reorder or set a priority link aside. Choose or add priorities when new work matters. Focus on this next marks one unfinished Card or Note as your next focus; tap it again to clear the choice.", "The next focus appears in Today's Plan. It stops displaying when its source is completed, removed from priorities, or unavailable."),
            section("Notice your mood", "How are you feeling? is optional and starts unselected each time. Choose Great, Good, Okay, Low, or Struggling, or choose Custom… and enter one emoji using the emoji keyboard plus a feeling of up to 40 characters. Save check-in records the mood with this entry, even without a note. Daily review displays it beside the time. Earlier entries keep their own moods."),
            section("Review your day", "Open Today’s Plan → Daily review, immediately above Weekly review. See current priority progress, next focus, saved Check-ins, and evening reflections. Use Review day or Saved days to revisit earlier days. Historical Check-ins keep their original context even when priorities change. Older Check-ins retain their original note and focus; their progress snapshot is unavailable."),
            section("Save the plan that fits now", "Capture what changed and revisit your intention, constraints, and concerns. Save check-in adds a new record and updates the same daily plan used in the evening. Each new Check-in starts with an empty note while carrying forward your current plan and next focus. Save your note before leaving.")
        ], opensPlan: true),
        .init(id: "evening", group: groups[2], title: "Today's Review · close the day", summary: "Recognize progress and give unfinished work a decision", symbol: "moon.stars", sections: [
            section("1. Notice progress", "Open Today's Plan → Start today's review. Look at completed work and your chosen priorities. Learning, resting, or making room for something important can also be progress."),
            section("2. Decide what belongs next", "Review unfinished Cards from today and On the Table, plus deliberately selected priorities. Reference Cards are excluded; Notes enter processing only when selected as priorities.", "Leave an item in place, carry it to tomorrow, return it to In the Queue, choose a calendar day, mark a Card complete, or archive it. Each item action asks for confirmation and saves immediately.", "Keeping work is valid. You do not have to empty On the Table. Moves preserve existing dates and details; Archive keeps the item recoverable."),
            section("3. Leave yourself a starting point", "Record what helped, what was difficult, and a thought for tomorrow. Save today's review completes it. You can revisit today's saved review later.")
        ], opensPlan: true),
        .init(id: "weekly", group: groups[2], title: "Weekly Review · find your direction", summary: "Learn from the week and make room for the next", symbol: "calendar.badge.clock", sections: [
            section("1. Look back", "Open Today's Plan → Weekly review. Choose a date in the week you want or open a saved week. The app follows your calendar's week boundary. Save edits before switching weeks.", "Read available daily intentions, reflections, Check-in changes, and saved achievements. Missing days do not need catching up. Add highlights and lessons."),
            section("2. Review the Queue", "Decide which unfinished In the Queue Cards to keep, schedule on a chosen day, complete, or archive. Reference Cards, Notes, and completed Cards are not automatically processed. Confirmed actions save immediately.", "Even in a past-week review, this is the live Queue. Decisions affect the current item now. Keeping worthwhile items in the Queue is a valid outcome."),
            section("3. Look ahead", "Choose next week's direction and linked priorities. Note constraints and risks. Use Edit to order links. These priorities guide next week; they do not move items or automatically populate daily plans.", "Save progress keeps your current step. Save and continue advances, and Save weekly review marks completion. Open a saved week to return later.")
        ], opensPlan: true),
        .init(id: "periodic", group: groups[2], title: "Periodic Review · connect actions to your life", summary: "Review a month, quarter, or meaningful checkpoint", symbol: "flag.checkered", sections: [
            section("Choose a period", "Open Today's Plan → Periodic review. Name your checkpoint and choose From and Through dates. Use the same date for a single-day checkpoint. Dates stay fixed after you begin; start a new checkpoint for another range."),
            section("1. Look back", "Read saved weekly reflections overlapping your range, then capture highlights, achievements, and lessons. Overlapping weeks are included in full and use their current saved content. You can begin without any saved weekly reviews."),
            section("2. Assess your objectives", "New checkpoints carry objectives forward from the latest saved review ending before the new period. Earlier reviews keep their own objective records.", "For each objective, record progress and a next step. Choose Active, Achieved, Paused, or Let go. You can add new objectives. Previous evidence remains visible while the new period's progress begins blank. No objective is required."),
            section("3. Set direction", "Record direction for the next period, link useful priorities, and consider risks and constraints. Objectives and links do not automatically create or move Cards.", "Save progress or Save and continue, then Save periodic review to complete it. Open a saved checkpoint to revisit your reflections. This first version does not automatically schedule the next checkpoint.")
        ], opensPlan: true),
        .init(id: "first-week", group: groups[3], title: "Try a gentle first week", summary: "Learn what helps through real use", symbol: "leaf", sections: [
            section("For the next few days", "Morning: choose a small plan. Midday: open Check-in once, or whenever circumstances change. Evening: save a brief review. Try Weekly Review when useful, and create a Periodic checkpoint when you want to step back.", "Notice which prompts help you make a choice and which feel unclear. There is no need to fill every field, test every option at once, or complete missed sessions."),
            section("Capture useful feedback", "Note which screen or flow you used, what you expected, what happened, and roughly when. A screenshot can help explain a layout or navigation issue. Bring questions as often as they arise."),
            section("What is still developing", "Older daily plans are stored but do not yet have a direct date browser. Weekly and Periodic Reviews have saved-record selectors. Working roles currently use default List names.", "Morning transfers do not yet share the evening and weekly interruption-recovery journal. If a moved priority becomes unavailable after an interruption, find its original item at the destination and choose it again.", "Accessibility and physical-device behavior still need hands-on validation. Your experience during this first week will guide the next improvements.")
        ]),
        .init(id: "data", group: groups[3], title: "Your records, saves, and example data", summary: "Know what is kept and when changes take effect", symbol: "externaldrive", sections: [
            section("Stored on this device", "Daily plans, weekly reviews, and periodic checkpoints are saved locally inside Plenact. Cards and Notes remain in their own Lists and Boards. Planning Rhythm cloud sync and user-facing export are not implemented.", "Saving a review updates its latest record. This is not an immutable history of every edit. Unsaved text is not an automatic recovery draft."),
            section("Examples and restoring your data", "Full-month examples replace the currently loaded workspace after keeping a verified offline copy. While that backup is active, Library + → Examples → Restore User Data restores the original workspace, including saved Planning Rhythm records.", "Save current work before switching. Restoring the original workspace replaces edits made in the example workspace. Preview an example first when you only want to look."),
            section("Recovering unavailable links", "An archived, removed, or cross-Board moved source can leave an unavailable priority link. The saved title remains as context. Find the current original and choose it again; remove the old link when appropriate. Removing a link alone does not delete the source.")
        ])
    ]


    ///
    /// @fcn        PlenactHelpCatalog.results
    /// @brief      Filter the help catalog by the current query
    /// @details    Uses each article's shared matching rules and preserves catalog order.
    ///
    /// @param[in]  query  User-entered search text
    ///
    /// @return     ([PlenactHelpArticle]) matching articles in help-catalog order
    ///
    static func results(for query: String) -> [PlenactHelpArticle] { articles.filter { $0.matches(query) } }
}


///
/// Presents matching help articles in the Library
///
/// @section    Purpose
///     Uses the shared catalog search and delegates article opening to the surrounding Library
///     view.
///
struct LibraryHelpRows: View {

    let query:  String
    var onOpen: (PlenactHelpArticle) -> Void = { _ in }
    var body:   some View {
        let matches = PlenactHelpCatalog.results(for: query)
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("A little guidance, a useful next step", systemImage: "questionmark.circle").font(.headline)
                Text("Start with what matters to you. Build a rhythm that fits your life, and return whenever you need a reset.").foregroundStyle(.secondary)
            }.padding(.vertical, 6)
        }
        ForEach(PlenactHelpCatalog.groups, id: \.self) { group in
            let articles = matches.filter { $0.group == group }
            if !articles.isEmpty {
                Section(group) {
                    ForEach(articles) { article in
                        Button { onOpen(article) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: article.symbol).font(.title3).foregroundStyle(.teal).frame(width: 26)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(article.title).font(.headline).foregroundStyle(.primary)
                                    Text(article.summary).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 6)
                        }.buttonStyle(.plain).accessibilityHint("Opens the help article")
                        .listRowBackground(Color(.secondarySystemGroupedBackground).opacity(0.5))
                    }
                }
            }
        }
        if matches.isEmpty { Section { ContentUnavailableView.search(text: query) } }
    }
}


///
/// Displays a bundled help article
///
/// @section    Purpose
///     Renders its authored sections and optionally opens the planning destination using injected
///     workspace context.
///
struct PlenactHelpArticleView: View {

    let article: PlenactHelpArticle
    @Environment(\.dismiss) private var dismiss
    @Environment(\.planningCalendarAccess) private var access
    @State private var showsPlan = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(article.title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Text(article.summary).foregroundStyle(.secondary)
                }
                ForEach(article.sections) { section in
                    Section(section.title) {
                        ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in Text(paragraph).textSelection(.enabled).padding(.vertical, 3) }
                    }
                }
                if article.opensPlan {
                    Section { Button("Open Today's Plan", systemImage: "sun.max") { showsPlan = true }.disabled(access == nil) }
                }
            }
            .navigationTitle("Help").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showsPlan) { TodayPlanView(calendar: access?.document.calendar ?? .current) }
        }
    }
}
