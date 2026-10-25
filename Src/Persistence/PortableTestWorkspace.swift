// --------------------------------------------------------------------------------------------------
// @file       PortableTestWorkspace.swift
// @brief      Isolated Simulator installation, durable selection and undo of portable test snapshots
// @details    Supported User Data Model versions: 1.0 base and working 1.1; test-store format 1.
//             Never installs legacy preferences, changes the main workspace or authenticates an owner.
// --------------------------------------------------------------------------------------------------
import Foundation


/// Retains independently verified portable snapshots in a separate local test workspace.
/// @section Purpose
///     Prove package installation and readback with atomic activation and retained undo generations.
@MainActor
struct PortableTestWorkspace
{

    let root: URL


    /// @fcn PortableTestWorkspace.live
    /// @brief Resolve the dedicated test store independently of native workspace storage
    /// @return Store rooted in application support
    /// @throws Application support resolution errors
    static func live() throws -> PortableTestWorkspace
    {

        let support = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        return PortableTestWorkspace(root: support.appendingPathComponent("PlenactPortableTest", isDirectory: true))
    }


    /// @fcn PortableTestWorkspace.state
    /// @brief Load only a supported, closed activation record
    /// @return Current generation, undo generation and explicit undo availability
    /// @throws Corrupt, unsupported or unsafe state errors
    private func state() throws -> [String: Any]
    {

        let path = root.appendingPathComponent("state.json")
        if !FileManager.default.fileExists(atPath: path.path)
        {
            return ["format_version": 1, "active": NSNull(), "undo": NSNull(), "can_undo": false]
        }
        guard let value = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any],
              Set(value.keys) == ["format_version", "active", "undo", "can_undo"],
              value["format_version"] as? Int == 1, value["can_undo"] is Bool else
        {
            throw PortablePackageReview.Failure.invalid
        }
        for field in ["active", "undo"]
        {
            guard value[field] is NSNull || (value[field] as? String).flatMap(UUID.init(uuidString:)) != nil else
            {
                throw PortablePackageReview.Failure.invalid
            }
        }
        return value
    }


    /// @fcn PortableTestWorkspace.read
    /// @brief Verify a retained generation from disk before exposing or activating it
    /// @param[in] id Previously allocated generation UUID
    /// @return Frozen package with checked original files and core references
    /// @throws Hash, package or filesystem failures
    private func read(_ id: String) throws -> ReviewedPortablePackage
    {

        guard UUID(uuidString: id) != nil else
        {
            throw PortablePackageReview.Failure.invalid
        }
        let folder = root.appendingPathComponent(id, isDirectory: true)
        let bytes = try Data(contentsOf: folder.appendingPathComponent("snapshot.bin"))
        guard bytes.count <= LegacyWorkspaceExport.maximumBytes,
              let receipt = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("receipt.json"))) as? [String: Any],
              Set(receipt.keys) == ["format_version", "sha256"], receipt["format_version"] as? Int == 1,
              receipt["sha256"] as? String == MigrationBackupReader.digest(bytes),
              let files = FileWrapper(serializedRepresentation: bytes) else
        {
            throw PortablePackageReview.Failure.integrity
        }
        return try PortablePackageReview.review(files: files)
    }


    /// @fcn PortableTestWorkspace.active
    /// @brief Reopen the active portable package independently of its original file provider
    /// @return Verified installed test package, or nil for an empty test workspace
    /// @throws Invalid activation or retained-file errors
    func active() throws -> ReviewedPortablePackage?
    {

        guard let id = try state()["active"] as? String else
        {
            return nil
        }
        return try read(id)
    }


    /// @fcn PortableTestWorkspace.canUndo
    /// @brief Read retained undo availability without mutating state
    /// @return Whether a prior test state can be restored
    /// @throws Invalid state errors
    func canUndo() throws -> Bool
    {

        try state()["can_undo"] as? Bool == true
    }


    /// @fcn PortableTestWorkspace.install
    /// @brief Write and verify a new isolated generation before atomically activating it
    /// @param[in] reviewed Frozen user-reviewed package
    /// @param[in] beforeCommit Optional synthetic-test failure injection before activation
    /// @return Installed readback counts
    /// @throws Unsupported environment, review, disk or injected failures; existing active state is retained
    func install(_ reviewed: ReviewedPortablePackage, beforeCommit: (() throws -> Void)? = nil) throws -> ReviewedPortablePackage
    {

        #if targetEnvironment(simulator)
        guard reviewed.snapshot.count <= LegacyWorkspaceExport.maximumBytes,
              let source = FileWrapper(serializedRepresentation: reviewed.snapshot) else
        {
            throw PortablePackageReview.Failure.invalid
        }
        _ = try PortablePackageReview.review(files: source)
        let previous = try state()
        if let active = previous["active"] as? String
        {
            _ = try read(active)
        }
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let id = UUID().uuidString.lowercased()
        let folder = root.appendingPathComponent(id, isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var committed = false
        defer
        {
            if !committed
            {
                try? manager.removeItem(at: folder)
            }
        }
        try reviewed.snapshot.write(to: folder.appendingPathComponent("snapshot.bin"), options: [.atomic, .completeFileProtection])
        let receipt: [String: Any] = ["format_version": 1, "sha256": MigrationBackupReader.digest(reviewed.snapshot)]
        try JSONSerialization.data(withJSONObject: receipt, options: .sortedKeys)
            .write(to: folder.appendingPathComponent("receipt.json"), options: .atomic)
        let installed = try read(id)
        guard try Data(contentsOf: folder.appendingPathComponent("snapshot.bin")) == reviewed.snapshot else
        {
            throw PortablePackageReview.Failure.integrity
        }
        try beforeCommit?()
        let next: [String: Any] = ["format_version": 1, "active": id, "undo": previous["active"] ?? NSNull(), "can_undo": true]
        try JSONSerialization.data(withJSONObject: next, options: .sortedKeys).write(to: root.appendingPathComponent("state.json"), options: .atomic)
        committed = true
        return installed
        #else
        throw PortablePackageReview.Failure.invalid
        #endif
    }


    /// @fcn PortableTestWorkspace.undo
    /// @brief Restore the previous isolated test selection after verifying its retained snapshot
    /// @return Restored package, or nil when undo returns the test workspace to empty
    /// @throws Unsupported environment, missing undo state or corrupted retained package
    func undo() throws -> ReviewedPortablePackage?
    {

        #if targetEnvironment(simulator)
        let current = try state()
        guard current["can_undo"] as? Bool == true else
        {
            throw PortablePackageReview.Failure.invalid
        }
        let previous = try (current["undo"] as? String).map { try read($0) }
        let next: [String: Any] = ["format_version": 1, "active": current["undo"] ?? NSNull(),
            "undo": current["active"] ?? NSNull(), "can_undo": true]
        try JSONSerialization.data(withJSONObject: next, options: .sortedKeys).write(to: root.appendingPathComponent("state.json"), options: .atomic)
        return previous
        #else
        throw PortablePackageReview.Failure.invalid
        #endif
    }
}
