// -------------------------------------------------------------------------------------------------
// @file       PlenactDemoAccountSection.swift
// @brief      Shared demo login, directory, and SampleData initialization controls
// @details    Keeps server account/session state separate from the local profile and Board
// -------------------------------------------------------------------------------------------------
import SwiftUI


///
/// Presents the authenticated shared-demo account and Board controls
///
/// @section    Purpose
///     Keep remote identity, Board edits, and assignment actions separate from local profile and Board storage
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
    @State private var isWorking           = false /* Network operation state */
    @State private var needsConflictReload = false /* Stale-draft reload requirement */
    @State private var alertMessage        = "" /* Current alert text */
    @State private var showsAlert          = false /* Shared-demo alert presentation state */
    @State private var confirmsSeed        = false /* Initial SampleData confirmation state */

    /// Indicates whether the editor can initialize the unseeded shared Board
    private var canInitializeSampleBoard: Bool {                                    /* Editor permission and unseeded revision */

        remoteSession?.user.accountRole == "board_editor" && currentRevision == 0
    }

    /// Indicates whether the remote draft differs from its last fetched snapshot
    private var hasUnsavedRemoteEdits: Bool {                                       /* Draft differs from the fetched snapshot */
        
        remoteDraft != nil && remoteDraft != remoteSnapshot?.document
    }

    /// Builds the account form, remote directory, and shared Board controls
    var body: some View {                                                           /* Account form, directory, and shared Board controls */

        Section("Shared demo") {

            if let remoteSession { /* Authenticated server identity */
                LabeledContent("Signed in", value: remoteSession.user.displayName)
                LabeledContent("Account",   value: "@\(remoteSession.user.username)")
                LabeledContent("Access",    value: remoteSession.user.accountRole == "board_editor" ? "Board editor" : "Member")

                Button("Refresh shared directory and Board") {
                    Task { await refreshRemoteState() }
                }
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
            isPresented: $confirmsSeed,
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

    /// Authenticate the entered account and refresh its shared demo data
    ///
    /// @return     (Void) updates the local view state and Keychain session
    ///
    @MainActor
    private func signIn() async {

        isWorking = true

        defer { isWorking = false }

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

    /// Fetch the latest directory and shared Board snapshot
    ///
    /// @return     (Void) updates remote view state without replacing the local Board
    ///
    @MainActor
    private func refreshRemoteState() async {

        guard let remoteSession else { return }                 /* Require an authenticated session */

        isWorking = true

        defer { isWorking = false }

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

    /// Initialize the shared Board using the explicit synthetic SampleData seed
    ///
    /// @return     (Void) updates the fetched shared revision or presents an error
    ///
    @MainActor
    private func initializeSampleBoard() async {

        guard let remoteSession, canInitializeSampleBoard else { return } /* Require the editor seed state */

        isWorking = true

        defer { isWorking = false }

        do {
            let client   = try PlenactAPIClient() /* Configured HTTPS API client */
            let response = try await client.publishSampleData( /* Initial SampleData response */
                token: remoteSession.accessToken,
                user: remoteSession.user,
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

    /// Revoke a remote session and clear its local Keychain-backed presentation state
    ///
    /// @param[in]  session Authenticated remote session to sign out
    ///
    /// @return     (Void) clears the remote session and directory state
    ///
    @MainActor
    private func signOut(_ session: PlenactRemoteSession) async {
        
        isWorking = true

        defer { isWorking = false }

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

    /// Build one expandable section of the fetched shared Board
    ///
    /// @param[in]  list     Board list displayed by the section
    /// @param[in]  session  Authenticated user and assignment permissions
    /// @param[in]  revision Snapshot revision used for mutation checks
    ///
    /// @return     (some View) expandable list of shared cards
    ///
    @ViewBuilder
    private func sharedListContent(_ list: KanbanList, session: PlenactRemoteSession, revision: Int64) -> some View {

        DisclosureGroup("\(list.title) · \(list.cards.filter { !$0.isSectionDivider }.count)") {

            ForEach(list.cards.filter { !$0.isSectionDivider }) { card in
            
                sharedCardContent(card, session: session, revision: revision)
            }
        }
    }

    /// Build a shared-card row with role-appropriate editing and assignments
    ///
    /// @param[in]  card     Shared Board card shown in the row
    /// @param[in]  session  Authenticated user and assignment permissions
    /// @param[in]  revision Snapshot revision used for mutation checks
    ///
    /// @return     (some View) editor or member-facing shared-card controls
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
                                    cardID: card.id,
                                    action: assigned ? "unassign" : "assign",
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

    /// Apply an assignment mutation using the latest known Board revision
    ///
    /// @param[in]  cardID       Stable target card ID
    /// @param[in]  action       Assignment operation
    /// @param[in]  targetUserID Optional editor-selected account ID
    ///
    /// @return     (Void) refreshes the shared Board after the operation
    ///
    @MainActor
    private func changeOwnAssignment(cardID: Int, action: String, targetUserID: String? = nil) async {
        guard let remoteSession, let currentRevision else { return } /* Require current session and revision */
        isWorking = true
        defer { isWorking = false }

        do {
            let client = try PlenactAPIClient() /* Configured HTTPS API client */
            _ = try await client.changeAssignment(
                token: remoteSession.accessToken,
                expectedRevision: currentRevision,
                cardID: cardID,
                action: action,
                userID: targetUserID
            )
            await refreshRemoteState()
            needsConflictReload = false
        } catch {
            await refreshRemoteState()
            present(error)
        }
    }

    /// Create a binding into the remote draft for one stable card identity
    ///
    /// @param[in]  cardID Stable card ID to locate in the draft
    ///
    /// @return     (Binding<KanbanCard>?) editable remote-card binding, when found
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
                guard var updatedDocument = remoteDraft else { return } /* Mutable copy of the remote draft */
                updatedDocument.lists[listIndex].cards[cardIndex] = updatedCard
                remoteDraft = updatedDocument
            }
        )
    }

    /// Add a manual person to the selected remote card draft
    ///
    /// @param[in]  cardID Stable card ID receiving the manual assignment
    ///
    /// @return     (Void) appends a manual-only assignment to the unsaved draft
    ///
    private func addManualAssignee(cardID: Int) {
        let displayName = manualAssigneeDrafts[cardID, default: ""].trimmingCharacters(in: .whitespacesAndNewlines) /* Normalized manual name */
        guard !displayName.isEmpty, let binding = cardBinding(cardID: cardID) else { return } /* Require text and matching card */
        binding.wrappedValue.members.append(.manual(displayName))
        manualAssigneeDrafts[cardID] = ""
    }

    /// Remove one manual assignment from the selected remote card draft
    ///
    /// @param[in]  cardID      Stable card ID containing the assignment
    /// @param[in]  assigneeID  Stable manual-assignment identity
    ///
    /// @return     (Void) removes only the selected manual assignment
    ///
    private func removeManualAssignee(cardID: Int, assigneeID: UUID) {
        guard let binding = cardBinding(cardID: cardID) else { return } /* Require a matching remote card */
        binding.wrappedValue.members.removeAll { $0.kind == .manual && $0.id == assigneeID }
    }

    /// Save Jim's full remote Board draft against its fetched revision
    ///
    /// @return     (Void) refreshes after success or preserves the draft on conflict
    ///
    @MainActor
    private func saveSharedBoard() async {
          guard let remoteSession, let remoteSnapshot, let remoteDraft, /* Current editor session and snapshot */
              remoteDraft.validationMessage == nil else { return } /* Only save a valid document */
        isWorking = true
        defer { isWorking = false }

        do {
            let client = try PlenactAPIClient() /* Configured HTTPS API client */
            _ = try await client.saveBoard(
                token: remoteSession.accessToken,
                document: remoteDraft,
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

    /// Create a member account through the editor-only invite flow
    ///
    /// @return     (Void) refreshes the directory and clears the entered password
    ///
    @MainActor
    private func createMember() async {
        guard let remoteSession, remoteSession.user.accountRole == "board_editor" else { return } /* Require Board-editor access */
        isWorking = true
        defer { isWorking = false }

        do {
            let client = try PlenactAPIClient() /* Configured HTTPS API client */
            _ = try await client.createMember(
                token: remoteSession.accessToken,
                username: newMemberUsername,
                displayName: newMemberDisplayName,
                password: newMemberPassword
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

    /// Present a user-facing description for an API or transport error
    ///
    /// @param[in]  error Error being presented
    ///
    /// @return     (Void) updates the shared-demo alert state
    ///
    @MainActor
    private func present(_ error: Error) {
        present(error.localizedDescription)
    }

    /// Present a user-facing shared-demo message
    ///
    /// @param[in]  message Alert text to display
    ///
    /// @return     (Void) updates the shared-demo alert state
    ///
    @MainActor
    private func present(_ message: String) {
        alertMessage = message
        showsAlert = true
    }
}
