// --------------------------------------------------------------------------------------------------
// @file       PlenactDemoAccountSection.swift
// @brief      Shared demo login, directory, and SampleData initialization controls
// @details    Exposes authentication and a synthetic shared-demo Board separately from local
//             profile and Board storage; this is not production multi-tenant synchronization
//
// --------------------------------------------------------------------------------------------------
import SwiftUI


///
/// Presents the authenticated shared-demo account and Board controls
///
/// @section    Purpose
///     Keep shared-demo identity, Board edits, and assignment actions separate from local profile
///     and Board storage
///
/// @note       Only the explicit SampleData initialization flow seeds the shared Board; normal
///             local Board changes are not uploaded by this view
///
struct PlenactDemoAccountSection: View {

    @State private var remoteSession        = PlenactSessionStore.load() /* Restored authenticated session */
    @State private var username             = "" /* Login handle draft */
    @State private var password             = "" /* Short-lived login password */
    @State private var newMemberUsername    = "" /* Invited member handle draft */
    @State private var newMemberDisplayName = "" /* Invited member display-name draft */
    @State private var newMemberPassword    = "" /* Short-lived invited-member password */

    @State private var manualAssigneeDrafts: [Int: String]            = [:] /* Per-card manual assignment text */
    @State private var directory:            [PlenactRemoteUser]      = [] /* Authenticated user directory */
    @State private var remoteSnapshot:       PlenactBoardSnapshotResponse? /* Last fetched server snapshot */
    @State private var remoteDraft:          PlenactBoardDocument? /* Editable remote-only Board copy */

    @State private var currentRevision:      Int64? /* Last fetched server revision */
    @State private var activeOperationCount = 0 /* Number of in-flight demo service operations */

    ///
    /// @fcn        PlenactDemoAccountSection.isWorking
    /// @brief      Report whether a shared-demo operation is in flight
    /// @details    Derives the busy state from the active operation count
    ///
    /// @return     (Bool) true while at least one operation is active
    ///
    private var isWorking: Bool { activeOperationCount > 0 } /* Whether a demo operation is active */
    @State private var needsConflictReload = false /* Stale-draft reload requirement */
    @State private var alertMessage        = "" /* Current alert text */
    @State private var showsAlert          = false /* Shared-demo alert presentation state */
    @State private var confirmsSeed        = false /* Initial SampleData confirmation state */

    ///
    /// @fcn        PlenactDemoAccountSection.canInitializeSampleBoard
    /// @brief      Indicate whether the editor can initialize the shared demo Board
    /// @details    Requires editor role and the unseeded revision marker
    ///
    /// @return     (Bool) true when the SampleData seed action is available
    ///
    private var canInitializeSampleBoard: Bool {                                    /* Editor permission and unseeded revision */

        remoteSession?.user.accountRole == "board_editor" && currentRevision == 0
    }

    ///
    /// @fcn        PlenactDemoAccountSection.hasUnsavedRemoteEdits
    /// @brief      Indicate whether the remote draft differs from its last fetched snapshot
    /// @details    Compares the editable shared-demo document with the fetched document
    ///
    /// @return     (Bool) true when a draft differs from the last fetched snapshot
    ///
    private var hasUnsavedRemoteEdits: Bool {                                       /* Draft differs from the fetched snapshot */
        
        remoteDraft != nil && remoteDraft != remoteSnapshot?.document
    }

    ///
    /// @fcn        PlenactDemoAccountSection.body
    /// @brief      Build the sign-in, directory, and shared-demo Board controls
    /// @details    Separates authenticated shared-demo actions from local Board and profile state
    ///
    /// @return     (some View) shared-demo account and Board section
    ///
    /// @pre        The view state is initialized from the stored session, when available
    /// @post       Shared-demo mutations occur only through explicit authenticated actions
    ///
    var body: some View {                                                           /* Account form, directory, and shared Board controls */

        Section("Shared demo") {

            if let remoteSession { /* Authenticated server identity */

                LabeledContent("Signed in", value: remoteSession.user.displayName)
                LabeledContent("Account",   value: "@\(remoteSession.user.username)")
                LabeledContent("Access",    value: remoteSession.user.accountRole == "board_editor" ? "Board editor" : "Member")

                Button("Refresh shared directory and Board") {
                    Task { await refreshRemoteState() }
                }

                .disabled(isWorking)
                .disabled(isWorking || hasUnsavedRemoteEdits)

                if let currentRevision, currentRevision > 0 {                       /* Initialized shared Board revision */

                    LabeledContent("Shared Board", value: "Revision \(currentRevision)")

                    if let remoteSnapshot {                                         /* Most recently fetched Board snapshot */
                  
                       ForEach(remoteSnapshot.document.lists) { list in
                  
                            sharedListContent(list, session: remoteSession, revision: remoteSnapshot.revision)
                        }
                    }

                    if remoteSession.user.accountRole == "board_editor", hasUnsavedRemoteEdits {

                        Button("Save shared Board changes", systemImage: "arrow.triangle.2.circlepath") {
                            Task { await saveSharedBoard() }
                        }

                        .disabled(isWorking || remoteDraft?.validationMessage != nil)

                        if let validationMessage = remoteDraft?.validationMessage { /* Draft validation result */
                     
                            Text(validationMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }

                    if needsConflictReload {

                        Button("Discard edits and refresh") {

                            Task {
                                needsConflictReload = false
                                remoteDraft         = remoteSnapshot?.document
                                await refreshRemoteState()
                            }
                        }

                        .disabled(isWorking)
                    }
                } else if currentRevision == 0 {

                    LabeledContent("Shared Board", value: "Not initialized")
                }

                if canInitializeSampleBoard {

                    Button("Initialize with SampleData", systemImage: "arrow.up.to.line") {
                        confirmsSeed = true
                    }

                    .disabled(isWorking)
                }

                if !directory.isEmpty {

                    ForEach(directory) { user in

                        LabeledContent(user.displayName, value: "@\(user.username)")
                    }
                }

                if remoteSession.user.accountRole == "board_editor" {

                    DisclosureGroup("Add demo member") {

                        TextField("Username", text: $newMemberUsername)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        TextField("Display name", text: $newMemberDisplayName)

                        SecureField("Temporary password", text: $newMemberPassword)
                            .textContentType(.newPassword)

                        Button("Create member account") {
                            Task { await createMember() }
                        }

                        .disabled(isWorking || newMemberUsername.isEmpty || newMemberDisplayName.isEmpty || newMemberPassword.count < 12 || newMemberPassword.utf8.count > 72)
                    }
                }

                Button("Sign out", role: .destructive) {

                    Task { await signOut(remoteSession) }
                }

                .disabled(isWorking || hasUnsavedRemoteEdits)

            } else {

                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)

                SecureField("Password", text: $password)
                    .textContentType(.password)

                Button {
                    Task { await signIn() }

                } label: {
                    if isWorking {

                        ProgressView()

                    } else {

                        Text("Sign in to shared demo")
                    }
                }

                .disabled(isWorking || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || password.utf8.count > 72)
            }
        }
        .task {
            if remoteSession != nil && currentRevision == nil {

                await refreshRemoteState()
            }
        }

        .confirmationDialog(
            "Initialize the shared Board?",
            isPresented:     $confirmsSeed,
            titleVisibility: .visible
        ) {
            Button("Publish SampleData", role: .destructive) {

                Task { await initializeSampleBoard() }
            }

            Button("Cancel", role: .cancel) {}

        } message: {

            Text("Only the app's synthetic weekday SampleData will be uploaded. Your local Board, profile, and attachments will not be changed.")
        }

        .alert("Shared demo", isPresented: $showsAlert) {

            Button("OK", role: .cancel) {}

        } message: {
            Text(alertMessage)
        }
    }


    ///
    /// @fcn        PlenactDemoAccountSection.signIn()
    /// @brief      Authenticate the entered shared-demo account
    /// @details    Exchanges the entered credentials for a Keychain-backed session, then refreshes
    ///             the remote directory and Board state
    ///
    /// @return     (Void) updates the local view state and Keychain session
    ///
    /// @post       The password draft is cleared after either success or failure
    ///
    @MainActor
    private func signIn() async {

        activeOperationCount += 1

        defer {

            activeOperationCount -= 1
        }

        do {

            let client    = try PlenactAPIClient() /* Configured HTTPS API client */

            remoteSession = try await client.login(username: username, password: password)
            password      = ""

            await refreshRemoteState()

        } catch {

            password = ""

            present(error)
        }
    }


    ///
    /// @fcn        PlenactDemoAccountSection.refreshRemoteState()
    /// @brief      Fetch the latest shared-demo directory and Board snapshot
    /// @details    Updates only remote view state and handles unseeded or expired-session responses
    ///
    /// @return     (Void) updates remote view state without replacing the local Board
    ///
    /// @pre        A registered remote session is available
    /// @post       Local Board persistence remains unchanged
    ///
    @MainActor
    private func refreshRemoteState() async {

        guard let remoteSession else { /* Authenticated shared-demo session */

            return
        }

        activeOperationCount += 1

        defer {

            activeOperationCount -= 1
        }

        do {

            let client      = try PlenactAPIClient()            /* Configured HTTPS API client */

            directory       = try await client.directory(token: remoteSession.accessToken)

            let snapshot    = try await client.board(token: remoteSession.accessToken) /* Latest shared Board */

            remoteSnapshot  = snapshot
            remoteDraft     = snapshot.document
            currentRevision = snapshot.revision

        } catch PlenactAPIError.boardNotSeeded {

            remoteSnapshot  = nil
            remoteDraft     = nil
            currentRevision = 0

        } catch PlenactAPIError.unauthorized {

            PlenactSessionStore.remove()

            self.remoteSession = nil
            directory          = []
            remoteSnapshot     = nil
            remoteDraft        = nil
            currentRevision    = nil

            present(PlenactAPIError.unauthorized)

        } catch {

            present(error)
        }
    }


    ///
    /// @fcn        PlenactDemoAccountSection.initializeSampleBoard()
    /// @brief      Initialize the shared demo Board using synthetic SampleData
    /// @details    Publishes the approved seed only from the editor's revision-zero state and then
    ///             refreshes remote state
    ///
    /// @return     (Void) updates the fetched shared revision or presents an error
    ///
    /// @pre        The active account is an editor and the remote Board is unseeded
    /// @post       Local profile, Board, and attachment data are not modified
    ///
    @MainActor
    private func initializeSampleBoard() async {

        guard let remoteSession, /* Authenticated editor session */
              canInitializeSampleBoard else { /* Eligible unseeded editor state */

            return
        }

        activeOperationCount += 1

        defer {

            activeOperationCount -= 1
        }

        do {

            let client   = try PlenactAPIClient() /* Configured HTTPS API client */
            let response = try await client.publishSampleData(                 /* Initial SampleData response */
                token:            remoteSession.accessToken,
                user:             remoteSession.user,
                expectedRevision: 0
            )

            currentRevision = response.revision

            await refreshRemoteState()

            present("SampleData is now the shared Board at revision \(response.revision). Local data was not changed.")

        } catch {

            await refreshRemoteState()

            present(error)
        }
    }


    ///
    /// @fcn        PlenactDemoAccountSection.signOut(_:)
    /// @brief      Revoke a shared-demo session and clear its local presentation state
    /// @details    Attempts server logout when the endpoint is configured, then clears the session
    ///             and fetched remote data
    ///
    /// @param[in]  session  Authenticated remote session to sign out
    ///
    /// @return     (Void) clears the remote session and directory state
    ///
    /// @post       Shared-demo session and view state are cleared
    ///
    @MainActor
    private func signOut(_ session: PlenactRemoteSession) async {
        
        activeOperationCount += 1

        defer {

            activeOperationCount -= 1
        }

        if let client = try? PlenactAPIClient() { /* Revoke the session when the endpoint is configured */

            await client.logout(session)

        } else {

            PlenactSessionStore.remove()
        }

        remoteSession   = nil
        directory       = []
        remoteSnapshot  = nil
        remoteDraft     = nil
        currentRevision = nil
    }


    ///
    /// @fcn        PlenactDemoAccountSection.sharedListContent(_:session:revision:)
    /// @brief      Build one expandable section of the fetched shared demo Board
    /// @details    Omits section-divider cards from the displayed count and content
    ///
    /// @param[in]  list      Board list displayed by the section
    /// @param[in]  session   Authenticated user and assignment permissions
    /// @param[in]  revision  Snapshot revision used for mutation checks
    ///
    /// @return     (some View) expandable list of shared cards
    ///
    /// @pre        list belongs to the fetched shared Board snapshot
    /// @post       The view does not mutate local Board storage
    ///
    @ViewBuilder
    private func sharedListContent(_ list: KanbanList, session: PlenactRemoteSession, revision: Int64) -> some View {

        DisclosureGroup("\(list.title) · \(list.cards.filter { !$0.isSectionDivider }.count)") {

            ForEach(list.cards.filter { !$0.isSectionDivider }) { card in
            
                sharedCardContent(card, session: session, revision: revision)
            }
        }
    }


    ///
    /// @fcn        PlenactDemoAccountSection.sharedCardContent(_:session:revision:)
    /// @brief      Build a shared-card row with role-appropriate editing and assignments
    /// @details    Editors modify the remote draft while registered users can perform permitted
    ///             assignment operations
    ///
    /// @param[in]  card      Shared Board card shown in the row
    /// @param[in]  session   Authenticated user and assignment permissions
    /// @param[in]  revision  Snapshot revision used for mutation checks
    ///
    /// @return     (some View) editor or member-facing shared-card controls
    ///
    /// @pre        card and session come from the current shared-demo snapshot
    /// @post       Title, completion, and manual-assignee edits remain in remoteDraft until save;
    ///             registered-user assignments are submitted separately through the API
    ///
    @ViewBuilder
    private func sharedCardContent(_ card: KanbanCard, session: PlenactRemoteSession, revision: Int64) -> some View {

        let isAssigned = card.members.contains { /* Whether the current account is assigned */
            $0.kind == .registeredUser && $0.userID?.lowercased() == session.user.userID.lowercased()
        }

        let isEditor = session.user.accountRole == "board_editor" /* Canonical edit permission */

        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                if isEditor, let cardBinding = cardBinding(cardID: card.id) { /* Editable remote-card binding */

                    TextField("Card title", text: cardBinding.word)
                    Toggle("Complete", isOn: cardBinding.isTitleChecked)
                        .font(.caption)
                } else {

                    Text(card.word)
                }

                let names = card.members.map(\.displayName).joined(separator: ", ") /* Visible card assignees */

                if !names.isEmpty {

                    Text(names)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isEditor {

                    TextField(
                        "Manual person",
                        text: Binding(
                            get: { manualAssigneeDrafts[card.id, default: ""] },
                            set: { manualAssigneeDrafts[card.id] = $0 }
                        )
                    )
                    HStack {
                        ForEach(card.members.filter { $0.kind == .manual }) { assignee in
                            Button {
                                removeManualAssignee(cardID: card.id, assigneeID: assignee.id)
                            } label: {
                                Label(assignee.displayName, systemImage: "xmark.circle.fill")
                                    .labelStyle(.titleAndIcon)
                            }

                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove manual assignee \(assignee.displayName)")
                        }

                        Button("Add manual", systemImage: "plus") {
                            addManualAssignee(cardID: card.id)
                        }

                        .buttonStyle(.borderless)
                        .disabled(manualAssigneeDrafts[card.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            Spacer()

            if isEditor {

                Menu {
                    ForEach(directory) { user in
                        let assigned = card.members.contains { /* Whether this directory user is assigned */
                            $0.kind == .registeredUser && $0.userID?.lowercased() == user.userID.lowercased()
                        }

                        Button(assigned ? "Remove \(user.displayName)" : "Assign \(user.displayName)") {
                            Task {
                                await changeOwnAssignment(
                                    cardID:       card.id,
                                    action:       assigned ? "unassign" : "assign",
                                    targetUserID: user.userID
                                )
                            }
                        }
                    }
                } label: {
                    Image(systemName: "person.crop.circle.badge.plus")
                }

                .accessibilityLabel("Manage card assignments")
                .disabled(isWorking || revision != currentRevision || hasUnsavedRemoteEdits)
            } else {

                Button(isAssigned ? "Remove me" : "Assign me") {
                    Task { await changeOwnAssignment(cardID: card.id, action: isAssigned ? "unassign" : "assign") }
                }

                .buttonStyle(.borderless)
                .disabled(isWorking || revision != currentRevision || hasUnsavedRemoteEdits)
            }
        }
    }


    ///
    /// @fcn        PlenactDemoAccountSection.changeOwnAssignment(cardID:action:targetUserID:)
    /// @brief      Apply an assignment mutation using the latest known shared Board revision
    /// @details    Sends the mutation to the server and refreshes the shared snapshot afterward
    ///
    /// @param[in]  cardID        Stable target card ID
    /// @param[in]  action        Assignment operation
    /// @param[in]  targetUserID  Optional editor-selected account ID
    ///
    /// @return     (Void) refreshes the shared Board after the operation
    ///
    /// @pre        A remote session and current Board revision are available
    /// @post       Local Board data remains unchanged
    ///
    @MainActor
    private func changeOwnAssignment(cardID: Int, action: String, targetUserID: String? = nil) async {

        guard let remoteSession, /* Authenticated shared-demo session */
              let currentRevision else { /* Fetched Board revision */

            return
        }

        activeOperationCount += 1

        defer {

            activeOperationCount -= 1
        }

        do {

            let client = try PlenactAPIClient() /* Configured HTTPS API client */

            _ = try await client.changeAssignment(
                token:            remoteSession.accessToken,
                expectedRevision: currentRevision,
                cardID:           cardID,
                action:           action,
                userID:           targetUserID
            )
            await refreshRemoteState()
            needsConflictReload = false
        } catch {

            await refreshRemoteState()
            present(error)
        }
    }


    ///
    /// @fcn        PlenactDemoAccountSection.cardBinding(cardID:)
    /// @brief      Create a binding into the remote draft for one stable card identity
    /// @details    Locates the card's current list and card indices and writes updates back to the
    ///             remote-only document draft
    ///
    /// @param[in]  cardID  Stable card ID to locate in the draft
    ///
    /// @return     (Binding<KanbanCard>?) editable remote-card binding, when found
    ///
    /// @pre        remoteDraft contains the shared document to edit
    /// @post       Resolving the binding does not change the draft
    ///
    private func cardBinding(cardID: Int) -> Binding<KanbanCard>? {

          guard let document = remoteDraft, /* Current remote-only draft */
              let listIndex = document.lists.firstIndex(where: { $0.cards.contains(where: { $0.id == cardID }) }), /* List containing the target card */
              let cardIndex = document.lists[listIndex].cards.firstIndex(where: { $0.id == cardID }) else { /* Card's current list index */
            return nil
        }
          let originalCard = document.lists[listIndex].cards[cardIndex] /* Fallback card value for the binding */

        return Binding(
            get: { remoteDraft?.lists[listIndex].cards[cardIndex] ?? originalCard },
            set: { updatedCard in
                guard var updatedDocument = remoteDraft else { /* Mutable copy of the remote draft */

                    return
                }
                updatedDocument.lists[listIndex].cards[cardIndex] = updatedCard
                remoteDraft = updatedDocument
            }
        )
    }


    ///
    /// @fcn        PlenactDemoAccountSection.addManualAssignee(cardID:)
    /// @brief      Add a manual person to the selected shared-demo card draft
    /// @details    Trims the entry, appends a manual assignment, and clears that card's draft text
    ///
    /// @param[in]  cardID  Stable card ID receiving the manual assignment
    ///
    /// @return     (Void) appends a manual-only assignment to the unsaved draft
    ///
    /// @pre        cardID identifies a card in the current remote draft
    /// @post       The updated assignment remains unsaved in remoteDraft
    ///
    private func addManualAssignee(cardID: Int) {

        let displayName = manualAssigneeDrafts[cardID, default: ""].trimmingCharacters(in: .whitespacesAndNewlines) /* Normalized manual name */

        guard !displayName.isEmpty,
              let binding = cardBinding(cardID: cardID) else { /* Matching remote draft card */

            return
        }

        binding.wrappedValue.members.append(.manual(displayName))
        manualAssigneeDrafts[cardID] = ""
    }


    ///
    /// @fcn        PlenactDemoAccountSection.removeManualAssignee(cardID:assigneeID:)
    /// @brief      Remove one manual assignment from the selected shared-demo card draft
    /// @details    Deletes only the matching manual member from the draft card
    ///
    /// @param[in]  cardID      Stable card ID containing the assignment
    /// @param[in]  assigneeID  Stable manual-assignment identity
    ///
    /// @return     (Void) removes only the selected manual assignment
    ///
    /// @pre        cardID identifies a card in the current remote draft
    /// @post       Other assignments and local Board data remain unchanged
    ///
    private func removeManualAssignee(cardID: Int, assigneeID: UUID) {

        guard let binding = cardBinding(cardID: cardID) else { /* Matching remote draft card */

            return
        }
        binding.wrappedValue.members.removeAll { $0.kind == .manual && $0.id == assigneeID }
    }


    ///
    /// @fcn        PlenactDemoAccountSection.saveSharedBoard()
    /// @brief      Save the editor's shared-demo Board draft against its fetched revision
    /// @details    Writes only a valid remote draft and marks revision conflicts for reload
    ///
    /// @return     (Void) refreshes after success or preserves the draft on conflict
    ///
    /// @pre        An editor session, fetched snapshot, and valid remote draft are available
    /// @post       The local Board and profile stores are unchanged
    ///
    @MainActor
    private func saveSharedBoard() async {

          guard let remoteSession, let remoteSnapshot, let remoteDraft, /* Current editor session and snapshot */
              remoteDraft.validationMessage == nil else { return } /* Only save a valid document */
        activeOperationCount += 1

        defer {

            activeOperationCount -= 1
        }

        do {

            let client = try PlenactAPIClient() /* Configured HTTPS API client */

            _ = try await client.saveBoard(
                token:            remoteSession.accessToken,
                document:         remoteDraft,
                expectedRevision: remoteSnapshot.revision
            )
            await refreshRemoteState()
            needsConflictReload = false
        } catch PlenactAPIError.revisionConflict {

            needsConflictReload = true
            present(PlenactAPIError.revisionConflict(nil))
        } catch {

            present(error)
        }
    }


    ///
    /// @fcn        PlenactDemoAccountSection.createMember()
    /// @brief      Create a shared-demo member account through the editor-only invite flow
    /// @details    Submits the entered credentials and refreshes the directory on success
    ///
    /// @return     (Void) refreshes the directory and clears the entered password
    ///
    /// @pre        The signed-in account has the shared-demo editor role
    /// @post       The temporary password draft is cleared after success or failure
    ///
    @MainActor
    private func createMember() async {

        guard let remoteSession, /* Authenticated shared-demo session */
              remoteSession.user.accountRole == "board_editor" else {

            return
        } /* Require Board-editor access */

        activeOperationCount += 1

        defer {

            activeOperationCount -= 1
        }

        do {

            let client = try PlenactAPIClient() /* Configured HTTPS API client */

            _ = try await client.createMember(
                token:       remoteSession.accessToken,
                username:    newMemberUsername,
                displayName: newMemberDisplayName,
                password:    newMemberPassword
            )
            newMemberUsername = ""
            newMemberDisplayName = ""
            newMemberPassword = ""
            directory = try await client.directory(token: remoteSession.accessToken)
            present("Member account created. Share its temporary credentials privately.")
        } catch {

            newMemberPassword = ""
            present(error)
        }
    }


    ///
    /// @fcn        PlenactDemoAccountSection.present(_:)
    /// @brief      Present a user-facing description for an API or transport error
    /// @details    Converts the error to its localized description and forwards it to alert state
    ///
    /// @param[in]  error  Error being presented
    ///
    /// @return     (Void) updates the shared-demo alert state
    ///
    /// @pre        error describes a failure suitable for display in the demo section
    /// @post       The error alert is presented
    ///
    @MainActor
    private func present(_ error: Error) {

        present(error.localizedDescription)
    }


    ///
    /// @fcn        PlenactDemoAccountSection.present(_:)
    /// @brief      Present a user-facing shared-demo message
    /// @details    Stores the supplied text and enables the shared-demo alert
    ///
    /// @param[in]  message  Alert text to display
    ///
    /// @return     (Void) updates the shared-demo alert state
    ///
    /// @post       The alert displays message
    ///
    @MainActor
    private func present(_ message: String) {

        alertMessage = message
        showsAlert = true
    }
}
