// --------------------------------------------------------------------------------------------------
// @file       SourceInventory.swift
// @brief      Audit actual Swift Codable declarations and preference-key string segments
// @details    Supported User Data Model versions: 1.0 source mapping; Version 0 reference.
//             Build-time inventory only. Uses SwiftSyntax rather than parsing model bodies by regex.
// --------------------------------------------------------------------------------------------------
import Foundation
import SwiftParser
import SwiftSyntax

/// Traverses source syntax without executing app code or reading user data.
final class Inventory: SyntaxVisitor
{
    var models: [[String: Any]] = []
    var keys: Set<String> = []

    /// @fcn Inventory.owner
    /// @brief Qualify nested source types independently of similarly named store documents
    /// @param[in] node Current declaration
    /// @return Qualified enclosing type path
    func owner(_ node: some SyntaxProtocol) -> String
    {
        var names: [String] = []
        var parent = node.parent
        while let current = parent
        {
            if let value = current.as(StructDeclSyntax.self)
            {
                names.insert(value.name.text, at: 0)
            }
            else if let value = current.as(EnumDeclSyntax.self)
            {
                names.insert(value.name.text, at: 0)
            }
            parent = current.parent
        }
        return names.joined(separator: ".")
    }

    /// @fcn Inventory.collect
    /// @brief Record direct stored members of an explicitly Codable source declaration
    /// @param[in] name Declaration name
    /// @param[in] parent Qualified enclosing type
    /// @param[in] inheritance Explicit protocol inheritance
    /// @param[in] members Direct member declarations
    /// @return Void; appends a source-inventory entry when applicable
    func collect(name: String, parent: String, inheritance: InheritanceClauseSyntax?, members: MemberBlockItemListSyntax)
    {
        let protocols = inheritance?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
        guard protocols.contains(where: { ["Codable", "Encodable", "Decodable"].contains($0) }) else
        {
            return
        }
        var fields: [[String: String]] = []
        var cases: [String] = []
        for member in members
        {
            if let declaration = member.decl.as(EnumCaseDeclSyntax.self)
            {
                cases.append(declaration.trimmedDescription)
            }
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  !variable.modifiers.contains(where: { ["static", "class"].contains($0.name.text) }) else
            {
                continue
            }
            for binding in variable.bindings
            {
                if let block = binding.accessorBlock
                {
                    switch block.accessors
                    {
                    case .getter:
                        continue
                    case .accessors(let accessors):
                        if accessors.contains(where: { !["didSet", "willSet"].contains($0.accessorSpecifier.text) })
                        {
                            continue
                        }
                    @unknown default:
                        fatalError("Unsupported Swift accessor syntax")
                    }
                }
                fields.append(["name": binding.pattern.trimmedDescription,
                               "declaration": binding.trimmedDescription])
            }
        }
        models.append(["name": parent.isEmpty ? name : parent + "." + name,
                       "fields": fields, "cases": cases])
    }

    /// @fcn Inventory.visit
    /// @brief Inspect Codable structs and continue into nested declarations
    /// @param[in] node Struct declaration
    /// @return Continue traversing children
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind
    {
        collect(name: node.name.text, parent: owner(node), inheritance: node.inheritanceClause, members: node.memberBlock.members)
        return .visitChildren
    }

    /// @fcn Inventory.visit
    /// @brief Inspect Codable enums and continue into nested declarations
    /// @param[in] node Enum declaration
    /// @return Continue traversing children
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind
    {
        collect(name: node.name.text, parent: owner(node), inheritance: node.inheritanceClause, members: node.memberBlock.members)
        return .visitChildren
    }

    /// @fcn Inventory.visit
    /// @brief Record Plenact literal key segments while excluding comments and interpolation code
    /// @param[in] node String segment
    /// @return Continue traversing children
    override func visit(_ node: StringSegmentSyntax) -> SyntaxVisitorContinueKind
    {
        let value = node.content.text
        if value.hasPrefix("Plenact.") || value.hasPrefix("plenact.creationDraft.")
        {
            keys.insert(value)
        }
        return .visitChildren
    }
}

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let paths = FileManager.default.enumerator(at: root.appendingPathComponent("Src"), includingPropertiesForKeys: nil)!
var inventory: [[String: Any]] = []
for case let file as URL in paths where file.pathExtension == "swift"
{
    let text = try String(contentsOf: file, encoding: .utf8)
    let visitor = Inventory(viewMode: .sourceAccurate)
    visitor.walk(Parser.parse(source: text))
    inventory.append(["file": String(file.path.dropFirst(root.path.count + 1)),
                      "models": visitor.models, "key_segments": visitor.keys.sorted()])
}
let output = try JSONSerialization.data(withJSONObject: inventory.sorted { ($0["file"] as! String) < ($1["file"] as! String) }, options: [.sortedKeys])
FileHandle.standardOutput.write(output)
