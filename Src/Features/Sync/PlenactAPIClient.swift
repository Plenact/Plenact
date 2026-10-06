// --------------------------------------------------------------------------------------------------
// @file       PlenactAPIClient.swift
// @brief      HTTPS client and Keychain session boundary for the Plenact shared demo API
// @details    Provides the authenticated client for the app's synthetic shared-demo service, not
//             production multi-tenant synchronization; ordinary local Board data is not uploaded
//
// --------------------------------------------------------------------------------------------------
import Foundation
import Security


///
/// Represents a registered account in the shared demo directory
///
/// @section    Purpose
///     Keep stable server identity and approved display fields together for assignment and access checks
///
struct PlenactRemoteUser: Codable, Equatable, Identifiable {

    let userID:      String         /* Stable user identifier         */
    let username:    String         /* User's login name              */
    let displayName: String         /* User's display name            */
    var accountRole: String?        /* User's role in the account     */

    ///
    /// @fcn        PlenactRemoteUser.id
    /// @brief      Expose the remote user ID as the identifiable value
    /// @details    Reuses the stable account identifier for SwiftUI lists
    ///
    /// @return     (String) server-assigned user identifier
    ///
    var id: String { userID } /* Stable identity for SwiftUI lists */

    ///
    /// Maps approved remote-user fields to the directory JSON names
    ///
    /// @section    Purpose
    ///     Keep the user identity response coding contract explicit
    ///
    enum CodingKeys: String, CodingKey {
        case userID      = "user_id"
        case username
        case displayName = "display_name"
        case accountRole = "account_role"
    }
}


///
/// Stores the authenticated account and its Keychain-managed bearer credential
///
/// @section    Purpose
///     Keep remote session identity separate from the local Plenact profile
///
struct PlenactRemoteSession: Codable, Equatable {

    let accessToken:  String                /* Access token for the session    */
    let expiresAtUTC: String                /* Expiration timestamp in UTC     */
    let user:         PlenactRemoteUser     /* Associated remote user          */

    ///
    /// Maps remote-session fields to the authentication JSON names
    ///
    /// @section    Purpose
    ///     Keep the bearer session response coding contract explicit
    ///
    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case expiresAtUTC = "expires_at_utc"
        case user
    }
}


///
/// Carries the approved fields returned by the shared user directory
///
/// @section    Purpose
///     Decode the active account collection without exposing private account fields
///
struct PlenactUserDirectoryResponse: Decodable {
    let users: [PlenactRemoteUser] /* Active users visible in the directory */
}


///
/// Carries the safe account fields returned after member provisioning
///
/// @section    Purpose
///     Decode the new member identity without returning its password hash
///
private struct PlenactCreatedUserResponse: Decodable {
    let user: PlenactRemoteUser /* Newly provisioned account identity */
}


///
/// Encodes credentials for a shared demo login request
///
/// @section    Purpose
///     Send account credentials only to the configured HTTPS authentication endpoint
///
private struct PlenactLoginRequest: Encodable {

    let action = "login" /* Authentication operation */
    let username: String /* Account handle submitted for login */
    let password: String /* Account secret sent over HTTPS */
}


///
/// Encodes the operation used to revoke the current bearer session
///
/// @section    Purpose
///     Keep logout request shape aligned with the authentication endpoint
///
private struct PlenactLogoutRequest: Encodable {
    let action = "logout" /* Session-revocation operation */
}


///
/// Encodes the Board-editor-only member creation request
///
/// @section    Purpose
///     Map Swift account fields to the invited-member JSON contract
///
private struct PlenactCreateMemberRequest: Encodable {

    let username:    String /* New member's login handle */
    let displayName: String /* New member's directory name */
    let password:    String /* Temporary member password */

    ///
    /// Maps member provisioning fields to the API request names
    ///
    /// @section    Purpose
    ///     Keep the invited-member request coding contract explicit
    ///
    enum CodingKeys: String, CodingKey {
        case username
        case displayName = "display_name"
        case password
    }
}


///
/// Encodes a complete Board snapshot with its optimistic revision
///
/// @section    Purpose
///     Separate the one-time SampleData seed marker from regular Board writes
///
struct PlenactBoardWriteRequest: Encodable {

    let expectedRevision: Int64                /* Revision read before editing */
    let document:         PlenactBoardDocument /* Complete snapshot payload */
    let seedKind:         String?              /* Explicit first-seed marker */

    ///
    /// Maps Board write fields to the snapshot API request names
    ///
    /// @section    Purpose
    ///     Preserve the API's expected revision, document, and seed field names
    ///
    enum CodingKeys: String, CodingKey {
        case expectedRevision = "expected_revision"
        case document
        case seedKind = "seed_kind"
    }
}


///
/// Encodes a registered-user assignment operation
///
/// @section    Purpose
///     Send an expected revision and card identity for a restricted assignment mutation
///
private struct PlenactAssignmentRequest: Encodable {

    let expectedRevision: Int64    /* Revision read before mutation */
    let cardID:           Int      /* Stable target card identity */
    let action:           String   /* Assign or unassign operation */
    let userID:           String?  /* Editor-selected target; omitted for members */

    ///
    /// Maps registered assignment mutation fields to the API request names
    ///
    /// @section    Purpose
    ///     Keep the assignment endpoint's expected revision and target fields explicit
    ///
    enum CodingKeys: String, CodingKey {
        case expectedRevision = "expected_revision"
        case cardID = "card_id"
        case action
        case userID = "user_id"
    }
}


///
/// Decodes the stable error code and optional revision returned by the API
///
/// @section    Purpose
///     Map conflict and authorization responses to app-level errors
///
private struct PlenactAPIErrorResponse: Decodable {

    let error:           String  /* Stable server error code */
    let currentRevision: Int64? /* Current revision included with conflicts */

    ///
    /// Maps stable API error fields to their JSON response names
    ///
    /// @section    Purpose
    ///     Decode the error code and optional current revision from service responses
    ///
    enum CodingKeys: String, CodingKey {
        case error
        case currentRevision = "current_revision"
    }
}


///
/// Describes recoverable failures from the shared demo API client
///
/// @section    Purpose
///     Provide concise user-facing errors for configuration, authentication, and revision conflicts
///
enum PlenactAPIError: LocalizedError {
    case endpointNotConfigured
    case invalidEndpoint
    case invalidResponse
    case payloadTooLarge
    case unauthorized
    case boardNotSeeded
    case revisionConflict(Int64?)
    case server(String)

    ///
    /// @fcn        PlenactAPIError.errorDescription
    /// @brief      Return a safe message for presentation without exposing response internals
    /// @details    Maps known API error cases to concise shared-demo UI text
    ///
    /// @return     (String?) user-facing description for the error
    ///
    var errorDescription: String? { /* Safe user-facing error text */

        switch self {

            case .endpointNotConfigured:
                return "The shared demo API endpoint is not configured in this build."
            case .invalidEndpoint:
                return "The shared demo API must use a valid HTTPS URL."
            case .invalidResponse:
                return "The shared demo API returned an invalid response."
            case .payloadTooLarge:
                return "The shared demo payload exceeds the 1 MiB size limit."
            case .unauthorized:
                return "Sign in again to continue."
            case .boardNotSeeded:
                return "The shared demo Board has not been initialized yet."
            case .revisionConflict(let revision): /* Current server revision, when available */

                if let revision {

                    /* Revision value used in the conflict message */ return "The shared Board changed. Its current revision is \(revision). Refresh before retrying."
                }

                return "The shared Board changed. Refresh before retrying."
            case .server(let code): /* Stable API error code */
                return "The shared demo request could not be completed (\(code))."
        }
    }
}


///
/// Persists the remote bearer session in the iOS Keychain
///
/// @section    Purpose
///     Isolate session storage from the local profile and UserDefaults
///
enum PlenactSessionStore {

    private static let account = "shared-demo-session" /* Keychain account key */
    private static let service = Bundle.main.bundleIdentifier.map { "\($0).remote-session" } ?? "Plenact.remote-session" /* App-specific Keychain service */

    ///
    /// @fcn        PlenactSessionStore.load()
    /// @brief      Load the previously authenticated remote session from Keychain
    /// @details    Reads the app-specific generic-password item and decodes its session payload
    ///
    /// @return     (PlenactRemoteSession?) stored session, or nil when none is available
    ///
    /// @post       The Keychain item remains unchanged
    ///
    static func load() -> PlenactRemoteSession? {

        let query: [String: Any] = [ /* Keychain session lookup attributes */

            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData  as String: true,
            kSecMatchLimit  as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef? /* Keychain lookup result */

        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { /* Encoded session value */
            return nil
        }

        return try? JSONDecoder().decode(PlenactRemoteSession.self, from: data)
    }

    ///
    /// @fcn        PlenactSessionStore.save(_:)
    /// @brief      Save the remote bearer session with device-only accessibility
    /// @details    Encodes the session and updates or adds its app-specific Keychain item
    ///
    /// @param[in]  session  Authenticated remote identity and access token
    ///
    /// @return     (Bool) true when Keychain accepted the session value
    ///
    /// @pre        session contains the authenticated remote identity and token to persist
    /// @post       The Keychain item contains the encoded session when true is returned
    ///
    @discardableResult
    static func save(_ session: PlenactRemoteSession) -> Bool {

        guard let data = try? JSONEncoder().encode(session) else {

            return false
        } /* Encoded session payload */

        let query: [String: Any] = [ /* Keychain item identity */
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [ /* Data and device-only accessibility */

            kSecValueData      as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary) /* Existing item update result */

        if updateStatus == errSecItemNotFound {

            var insert = query /* New Keychain item attributes */

            attributes.forEach { insert[$0.key] = $0.value }

            return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }

        return updateStatus == errSecSuccess
    }

    ///
    /// @fcn        PlenactSessionStore.remove()
    /// @brief      Remove the stored remote session from Keychain
    /// @details    Deletes only the app-specific session item
    ///
    /// @return     (Void) requests removal of the stored remote session
    ///
    /// @post       No local profile or Board data is changed
    ///
    static func remove() {

        let query: [String: Any] = [ /* Keychain item identity */

            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}


///
/// Sends authenticated HTTPS requests to the Plenact shared demo API
///
/// @section    Purpose
///     Keep transport, session handling, and revisioned Board operations outside SwiftUI views
///
struct PlenactAPIClient {

    static let maximumJSONBodyBytes = 1_048_576 /* Maximum UTF-8 JSON HTTP body size */

    ///
    /// @fcn        PlenactAPIClient.isJSONBodyWithinLimit(_:)
    /// @brief      Check whether JSON bytes fit within the client size limit
    /// @details    Compares the data length with maximumJSONBodyBytes
    ///
    /// @param[in]  body  Encoded or received JSON body
    ///
    /// @return     (Bool) true when body does not exceed the configured byte limit
    ///
    static func isJSONBodyWithinLimit(_ body: Data) -> Bool {

        body.count <= maximumJSONBodyBytes
    }

    private let baseURL: URL       /* Validated HTTPS API base URL */
    private let session: URLSession /* Transport used for API requests */

    ///
    /// @fcn        PlenactAPIClient.init(baseURL:session:)
    /// @brief      Create a client using the configured HTTPS endpoint or an injected URL
    /// @details    Validates and normalizes the endpoint before storing the URLSession transport
    ///
    /// @param[in]  baseURL Optional API base URL override
    /// @param[in]  session URL session used to send requests
    ///
    /// @return     (PlenactAPIClient) configured transport client
    ///
    /// @throws     PlenactAPIError when the endpoint is missing or is not HTTPS
    ///
    /// @post       The client stores a validated HTTPS base URL and the provided transport
    ///
    init(baseURL: URL? = nil, session: URLSession = .shared) throws {

        let configuredURL: URL? /* Endpoint supplied by the caller or app build settings */

        if let baseURL { /* Injected endpoint override */

            configuredURL = baseURL /* Use the explicit endpoint */

        } else if let value = Bundle.main.object(forInfoDictionaryKey: "PLENACT_API_BASE_URL") as? String, /* Configured base URL text */

                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

            configuredURL = URL(string: value) /* Parse the configured endpoint */

        } else {

            configuredURL = nil /* No endpoint configured for this build */
        }

        guard let configuredURL else {

            throw PlenactAPIError.endpointNotConfigured
        } /* Required API endpoint */

        guard configuredURL.scheme?.lowercased() == "https",
              configuredURL.host != nil,
              configuredURL.user == nil,
              configuredURL.password == nil else {

            throw PlenactAPIError.invalidEndpoint
        }

        var components = URLComponents(url: configuredURL, resolvingAgainstBaseURL: false) /* Mutable URL normalization components */

        if components?.path.hasSuffix("/") == false {

            components?.path.append("/")
        }

        guard let normalizedURL = components?.url else {

            throw PlenactAPIError.invalidEndpoint
        } /* Normalized endpoint URL */

        self.baseURL = normalizedURL /* Store validated endpoint */
        self.session = session       /* Store request transport */
    }

    ///
    /// @fcn        PlenactAPIClient.login(username:password:)
    /// @brief      Authenticate a shared-demo user and store the returned bearer session
    /// @details    Sends credentials to the configured authentication endpoint and persists the
    ///             returned session in Keychain
    ///
    /// @param[in]  username  Normalized demo account handle
    /// @param[in]  password  Account password submitted over HTTPS
    ///
    /// @return     (PlenactRemoteSession) authenticated identity and session
    ///
    /// @throws     PlenactAPIError for request, authentication, or Keychain failures
    ///
    /// @pre        The configured endpoint is the trusted HTTPS shared-demo service
    /// @post       The returned session is saved in Keychain, or a save failure is reported
    ///
    func login(username: String, password: String) async throws -> PlenactRemoteSession {

        let response: PlenactRemoteSession = try await send( /* Authenticated session response */
            path: "auth.php",
            method: "POST",
            body: PlenactLoginRequest(username: username, password: password)
        )
        guard PlenactSessionStore.save(response) else {

            await logout(response)
            throw PlenactAPIError.server("keychain_unavailable")
        }

        return response
    }

    ///
    /// @fcn        PlenactAPIClient.logout(_:)
    /// @brief      Revoke a remote session and remove its Keychain value
    /// @details    Attempts the logout request and removes the stored session even if revocation
    ///             fails
    ///
    /// @param[in]  remoteSession  Authenticated session to revoke
    ///
    /// @return     (Void) attempts remote revocation and clears the stored session
    ///
    /// @post       The session is removed from Keychain
    ///
    func logout(_ remoteSession: PlenactRemoteSession) async {

        _ = try? await send(
            path: "auth.php",
            method: "POST",
            token: remoteSession.accessToken,
            body: PlenactLogoutRequest()
        ) as EmptyResponse

        PlenactSessionStore.remove()
    }

    ///
    /// @fcn        PlenactAPIClient.directory(token:)
    /// @brief      Fetch the active registered-user directory
    /// @details    Returns the approved remote user fields visible to the authenticated account
    ///
    /// @param[in]  token  Bearer token for the current account
    ///
    /// @return     ([PlenactRemoteUser]) safe active-user directory entries
    ///
    /// @throws     PlenactAPIError when the directory request fails
    ///
    /// @pre        token is a valid bearer credential for the shared-demo service
    /// @post       No local profile or Board data is changed
    ///
    func directory(token: String) async throws -> [PlenactRemoteUser] {

        let response: PlenactUserDirectoryResponse = try await send( /* Safe directory response */
            path: "users.php",
            method: "GET",
            token: token
        )
        return response.users
    }

    ///
    /// @fcn        PlenactAPIClient.createMember(token:username:displayName:password:)
    /// @brief      Create an invited member account as the Board editor
    /// @details    Sends account fields to the authenticated user endpoint and returns its safe
    ///             directory identity
    ///
    /// @param[in]  token        Board-editor bearer token
    /// @param[in]  username     New member's login handle
    /// @param[in]  displayName  New member's directory name
    /// @param[in]  password     New member's temporary password
    ///
    /// @return     (PlenactRemoteUser) provisioned member identity
    ///
    /// @throws     PlenactAPIError when the editor request is rejected
    ///
    /// @pre        token belongs to a shared-demo Board editor and account fields meet service
    ///             rules
    /// @post       A member account is created only when the service accepts the request
    ///
    func createMember(token: String, username: String, displayName: String, password: String) async throws -> PlenactRemoteUser {

        let response: PlenactCreatedUserResponse = try await send( /* Safe new-member response */
            path: "users.php",
            method: "POST",
            token: token,
            body: PlenactCreateMemberRequest(
                username: username,
                displayName: displayName,
                password: password
            )
        )

        return response.user
    }

    ///
    /// @fcn        PlenactAPIClient.board(token:)
    /// @brief      Fetch the current shared-demo Board snapshot
    /// @details    Retrieves the document and server-maintained revision provenance
    ///
    /// @param[in]  token  Bearer token for a registered demo user
    ///
    /// @return     (PlenactBoardSnapshotResponse) current immutable Board revision
    ///
    /// @throws     PlenactAPIError when the Board is unavailable or request fails
    ///
    /// @pre        token authenticates an account on the shared-demo service
    /// @post       Local Board persistence remains unchanged
    ///
    func board(token: String) async throws -> PlenactBoardSnapshotResponse {

        try await send(path: "board.php", method: "GET", token: token)
    }

    ///
    /// @fcn        PlenactAPIClient.saveBoard(token:document:expectedRevision:)
    /// @brief      Save a shared-demo Board snapshot using optimistic revision checking
    /// @details    Validates the document and requires a positive expected revision before writing
    ///
    /// @param[in]  token             Board-editor bearer token
    /// @param[in]  document          Validated Board payload to persist
    /// @param[in]  expectedRevision  Last revision read by the editor
    ///
    /// @return     (PlenactBoardWriteResponse) newly appended snapshot revision
    ///
    /// @throws     PlenactAPIError when validation or the revision check fails
    ///
    /// @pre        The caller explicitly edits the shared-demo Board and supplies its fetched
    ///             revision
    /// @post       A successful request appends the accepted remote snapshot
    ///
    func saveBoard(token: String, document: PlenactBoardDocument, expectedRevision: Int64) async throws -> PlenactBoardWriteResponse {

        guard expectedRevision > 0, document.validationMessage == nil else {

            throw PlenactAPIError.server("invalid_board_write")
        }

        return try await writeBoard(
            token: token,
            document: document,
            expectedRevision: expectedRevision,
            seedKind: nil
        )
    }

    ///
    /// @fcn        PlenactAPIClient.sampleDataDocument(for:)
    /// @brief      Build the approved initial seed without reading or mutating local Board storage
    /// @details    Copies synthetic weekday SampleData and maps its known manual Jim assignment to
    ///             the supplied registered demo user
    ///
    /// @param[in]  user  Registered account receiving the known starter assignment
    ///
    /// @return     (PlenactBoardDocument) synthetic SampleData with its explicit Jim mapping
    ///
    /// @pre        user identifies the registered account receiving the seeded assignment
    /// @post       Local SampleData and Board storage are unchanged
    ///
    static func sampleDataDocument(for user: PlenactRemoteUser) -> PlenactBoardDocument {

        var sampleLists = SampleData.lists /* Copy synthetic data before mapping its known assignee */

        for listIndex in sampleLists.indices { /* Visit each seeded weekday list */

            for cardIndex in sampleLists[listIndex].cards.indices { /* Visit each seeded card */

                let card = sampleLists[listIndex].cards[cardIndex] /* Original seed card */

                // Covers and bundled illustrations belong to the local example, not the demo schema.
                sampleLists[listIndex].cards[cardIndex].coverAttachmentID = nil
                sampleLists[listIndex].cards[cardIndex].attachments = nil

                sampleLists[listIndex].cards[cardIndex].members = card.members.map { assignee /* Existing seed assignment */ in

                    guard assignee.kind == .manual, assignee.displayName == "Justin Reina" else {

                        return assignee
                    }

                    return CardAssignee(
                        id: assignee.id,
                        kind: .registeredUser,
                        userID: user.userID,
                        displayName: user.displayName
                    )
                }
            }
        }

        return PlenactBoardDocument(lists: sampleLists, labelLibrary: .starter)
    }

    ///
    /// @fcn        PlenactAPIClient.publishSampleData(token:user:expectedRevision:)
    /// @brief      Initialize revision one from the synthetic weekday SampleData only
    /// @details    Requires an unseeded shared Board and marks the request as the approved initial
    ///             SampleData seed
    ///
    /// @param[in]  token             Board-editor bearer token
    /// @param[in]  user              Authenticated editor receiving the starter assignment
    /// @param[in]  expectedRevision  Required initial revision value of zero
    ///
    /// @return     (PlenactBoardWriteResponse) seeded shared Board revision
    ///
    /// @throws     PlenactAPIError when seed preconditions or the request fail
    ///
    /// @pre        expectedRevision is zero and the target is the shared demo Board
    /// @post       The synthetic seed is published only if the service accepts revision zero
    ///
    func publishSampleData(token: String, user: PlenactRemoteUser, expectedRevision: Int64) async throws -> PlenactBoardWriteResponse {

        guard expectedRevision == 0 else {

            throw PlenactAPIError.server("sample_seed_requires_revision_zero")
        }

        let document = Self.sampleDataDocument(for: user) /* Explicit SampleData seed document */

        guard document.validationMessage == nil else {

            throw PlenactAPIError.server("invalid_sample_data")
        }

        return try await writeBoard(
            token: token,
            document: document,
            expectedRevision: expectedRevision,
            seedKind: "sample_data_v1"
        )
    }

    ///
    /// @fcn        PlenactAPIClient.changeAssignment(token:expectedRevision:cardID:action:userID:)
    /// @brief      Add or remove an assignment through the server-enforced role boundary
    /// @details    Sends the expected revision and target identity to the assignment endpoint
    ///
    /// @param[in]  token             Current registered-user bearer token
    /// @param[in]  expectedRevision  Last shared Board revision read
    /// @param[in]  cardID            Stable target card ID
    /// @param[in]  action            Assignment operation, either assign or unassign
    /// @param[in]  userID            Optional editor-selected account ID; members are scoped to
    ///             self
    ///
    /// @return     (PlenactAssignmentResponse) resulting revision and mutation status
    ///
    /// @throws     PlenactAPIError when authorization or revision checks fail
    ///
    /// @pre        action is an assignment operation supported by the API
    /// @post       The server applies at most the authorized assignment mutation
    ///
    func changeAssignment(token: String, expectedRevision: Int64, cardID: Int, action: String, userID: String? = nil) async throws -> PlenactAssignmentResponse {

        try await send(
            path: "assignments.php",
            method: "POST",
            token: token,
            body: PlenactAssignmentRequest(
                expectedRevision: expectedRevision,
                cardID: cardID,
                action: action,
                userID: userID
            )
        )
    }

    ///
    /// @fcn        PlenactAPIClient.writeBoard(token:document:expectedRevision:seedKind:)
    /// @brief      Encode and send a Board snapshot with an optional initial-seed marker
    /// @details    Uses the shared Board endpoint and its optimistic revision request format
    ///
    /// @param[in]  token             Authenticated bearer credential
    /// @param[in]  document          Complete Board document
    /// @param[in]  expectedRevision  Last revision read by the caller
    /// @param[in]  seedKind          Approved initial seed identifier, when applicable
    ///
    /// @return     (PlenactBoardWriteResponse) write result
    ///
    /// @throws     PlenactAPIError when encoding or the server request fails
    ///
    /// @pre        Caller has selected an explicit shared-demo Board write operation
    /// @post       The server result is returned without changing local Board persistence
    ///
    private func writeBoard(token: String, document: PlenactBoardDocument, expectedRevision: Int64, seedKind: String?) async throws -> PlenactBoardWriteResponse {

        try await send(
            path: "board.php",
            method: "PUT",
            token: token,
            body: PlenactBoardWriteRequest(
                expectedRevision: expectedRevision,
                document: document,
                seedKind: seedKind
            )
        )
    }

    ///
    /// @fcn        PlenactAPIClient.send(path:method:token:body:)
    /// @brief      Encode and send a JSON request body
    /// @details    Enforces the outgoing JSON size limit before forwarding encoded bytes
    ///
    /// @param[in]  path    API endpoint path
    /// @param[in]  method  HTTP method
    /// @param[in]  token   Optional bearer credential
    /// @param[in]  body    Encodable request payload
    ///
    /// @return     (Response) decoded API response
    ///
    /// @throws     PlenactAPIError for an oversized body or API/response failure; JSON encoding and
    ///             transport errors are propagated
    ///
    /// @pre        body can be encoded by JSONEncoder
    /// @post       Request processing is delegated with the encoded body
    ///
    private func send<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        token: String? = nil,
        body: Body
    ) async throws -> Response {

        let encodedBody = try JSONEncoder().encode(body) /* Encoded request payload */

        guard Self.isJSONBodyWithinLimit(encodedBody) else {

            throw PlenactAPIError.payloadTooLarge
        }

        return try await send(path: path, method: method, token: token, bodyData: encodedBody)
    }

    ///
    /// @fcn        PlenactAPIClient.send(path:method:token:)
    /// @brief      Send a request without a body and decode its response
    /// @details    Forwards the endpoint and optional bearer credential with no request payload
    ///
    /// @param[in]  path    API endpoint path
    /// @param[in]  method  HTTP method
    /// @param[in]  token   Optional bearer credential
    ///
    /// @return     (Response) decoded API response
    ///
    /// @throws     PlenactAPIError for API or response failures; transport errors are propagated
    ///
    /// @post       No request body is attached
    ///
    private func send<Response: Decodable>(
        path: String,
        method: String,
        token: String? = nil
    ) async throws -> Response {

        try await send(path: path, method: method, token: token, bodyData: nil)
    }

    ///
    /// @fcn        PlenactAPIClient.send(path:method:token:bodyData:)
    /// @brief      Execute a request with already encoded body data
    /// @details    Tracks the request as a shared-database operation and clears activity on either
    ///             success or failure
    ///
    /// @param[in]  path      API endpoint path
    /// @param[in]  method    HTTP method
    /// @param[in]  token     Optional bearer credential
    /// @param[in]  bodyData  Encoded request body, when present
    ///
    /// @return     (Response) decoded API response
    ///
    /// @throws     PlenactAPIError for oversized data, API status, or response decoding failures;
    ///             transport errors are propagated
    ///
    /// @post       The activity entry is ended before returning or rethrowing
    ///
    private func send<Response: Decodable>(
        path: String,
        method: String,
        token: String?,
        bodyData: Data?
    ) async throws -> Response {
        let operation = await DatabaseActivity.shared.begin("Synchronizing shared database...")

        do {

            let response: Response = try await executeRequest(
                path: path, method: method, token: token, bodyData: bodyData
            )
            await DatabaseActivity.shared.end(operation)

            return response
        } catch {
            await DatabaseActivity.shared.end(operation)
            throw error
        }
    }

    ///
    /// @fcn        PlenactAPIClient.executeRequest(path:method:token:bodyData:)
    /// @brief      Build, execute, validate, and decode one HTTP request
    /// @details    Applies JSON headers and optional bearer authorization, enforces response size,
    ///             maps known status errors, and decodes successful response data
    ///
    /// @param[in]  path      API endpoint path relative to the configured base URL
    /// @param[in]  method    HTTP method for the request
    /// @param[in]  token     Optional bearer credential
    /// @param[in]  bodyData  Optional encoded JSON request data
    ///
    /// @return     (Response) decoded successful API response
    ///
    /// @throws     PlenactAPIError for invalid response, oversized payload, API status, or decoding
    ///             failures; transport errors are propagated
    ///
    private func executeRequest<Response: Decodable>(
        path: String,
        method: String,
        token: String?,
        bodyData: Data?
    ) async throws -> Response {

        var request = URLRequest(url: baseURL.appendingPathComponent(path)) /* Mutable outgoing request */

        request.httpMethod      = method
        request.timeoutInterval = 20

        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let bodyData { /* Optional encoded request payload */

            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
        }

        if let token { /* Optional bearer credential */

            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request) /* Response bytes and transport metadata */

        guard let httpResponse = response as? HTTPURLResponse else { /* Require an HTTP response */

            throw PlenactAPIError.invalidResponse
        }

        guard Self.isJSONBodyWithinLimit(data) else {

            throw PlenactAPIError.payloadTooLarge
        } /* Bound downloaded JSON */

        guard (200..<300).contains(httpResponse.statusCode) else {

            let serverError = try? JSONDecoder().decode(PlenactAPIErrorResponse.self, from: data) /* Optional API error payload */

            switch serverError?.error {

                case "unauthorized":      throw PlenactAPIError.unauthorized
                case "board_not_seeded":  throw PlenactAPIError.boardNotSeeded
                case "revision_conflict": throw PlenactAPIError.revisionConflict(serverError?.currentRevision)
                case "request_too_large": throw PlenactAPIError.payloadTooLarge
                default:                  throw PlenactAPIError.server(serverError?.error ?? "http_\(httpResponse.statusCode)")
            }
        }

        do {

            return try JSONDecoder().decode(Response.self, from: data)

        } catch {
            throw PlenactAPIError.invalidResponse
        }
    }

    ///
    /// Represents an empty successful API response body shape
    ///
    /// @section    Purpose
    ///     Allow endpoints with no response fields to use the common Decodable request path
    ///
    private struct EmptyResponse: Decodable {}
}


///
/// Carries the new revision returned after a canonical Board write
///
/// @section    Purpose
///     Pair the server revision number with the accepted Board document
///
struct PlenactBoardWriteResponse: Decodable {
    let revision: Int64                /* Newly accepted snapshot revision */
    let document: PlenactBoardDocument /* Stored document returned by the API */
}


///
/// Carries the result of an idempotent assignment operation
///
/// @section    Purpose
///     Report the current Board revision and whether assignment state changed
///
struct PlenactAssignmentResponse: Decodable {
    let revision: Int64 /* Current Board revision */
    let changed:  Bool  /* Whether assignment state changed */
}
