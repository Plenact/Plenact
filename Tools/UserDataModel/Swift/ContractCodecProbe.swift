// --------------------------------------------------------------------------------------------------
// @file       ContractCodecProbe.swift
// @brief      Exercise portable JSON and content-envelope Codable round trips
// @details    Supported User Data Model versions: 1.0, final specification.
//             Local prototype only; input validation belongs to the shared schema/semantic runner.
//             Not an application migration adapter, sync engine, or authorization boundary.
// --------------------------------------------------------------------------------------------------
import Foundation

/// Retains complete JSON payloads without dropping nested or future fields.
/// @section Purpose
///     Separate a codec round trip from legacy Kanban model reconstruction.
indirect enum PortableJSONValue: Codable
{
    case object([String: PortableJSONValue])
    case array([PortableJSONValue])
    case string(String)
    case number(Decimal)
    case boolean(Bool)
    case null

    /// @fcn PortableJSONValue.init
    /// @brief Decode a JSON value while preserving nulls and nested containers
    /// @param[in] decoder Source JSON decoder
    /// @return Initialized portable value
    init(from decoder: Decoder) throws
    {
        let value = try decoder.singleValueContainer()
        if value.decodeNil()
        {
            self = .null
        }
        else if let boolean = try? value.decode(Bool.self)
        {
            self = .boolean(boolean)
        }
        else if let text = try? value.decode(String.self)
        {
            self = .string(text)
        }
        else if let object = try? value.decode([String: PortableJSONValue].self)
        {
            self = .object(object)
        }
        else if let array = try? value.decode([PortableJSONValue].self)
        {
            self = .array(array)
        }
        else
        {
            self = .number(try value.decode(Decimal.self))
        }
    }

    /// @fcn PortableJSONValue.encode
    /// @brief Encode retained JSON without reducing nested content to known fields
    /// @param[in] encoder Destination JSON encoder
    /// @return Void; throws on unsupported numeric representation
    func encode(to encoder: Encoder) throws
    {
        var value = encoder.singleValueContainer()
        switch self
        {
        case .null:
            try value.encodeNil()
        case .boolean(let boolean):
            try value.encode(boolean)
        case .string(let text):
            try value.encode(text)
        case .number(let number):
            try value.encode(number)
        case .object(let object):
            try value.encode(object)
        case .array(let array):
            try value.encode(array)
        }
    }
}

/// Decodes the content envelope while retaining its entire schema-validated payload.
/// @section Purpose
///     Exercise shared wire names independently of platform-specific app models.
struct PortableContentDocument: Codable
{
    let modelVersion:   String
    let schemaVersion:  Int
    let recordType:     String
    let id:             String
    let workspaceID:    String
    let payload:        [String: PortableJSONValue]

    enum CodingKeys: String, CodingKey
    {
        case modelVersion = "user_data_model_version"
        case schemaVersion = "payload_schema_version"
        case recordType = "record_type"
        case id
        case workspaceID = "workspace_id"
        case payload
    }
}

/// Describes a shared fixture expectation without defining runtime sync behavior.
struct FixtureCase: Decodable
{
    let file:   String
    let schema: String
    let valid:  Bool
}

/// Retains the shared fixture list consumed by prototype codecs.
struct FixtureManifest: Decodable
{
    let cases: [FixtureCase]
}

/// @fcn roundTripFixtures
/// @brief Write valid shared fixtures through Swift codecs for independent comparison
/// @param[in] fixtures Input folder containing manifest.json
/// @param[in] output Caller-supplied temporary output folder
/// @return Number of emitted fixture files
func roundTripFixtures(fixtures: URL, output: URL) throws -> Int
{
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    let manifest = try decoder.decode(
        FixtureManifest.self,
        from: Data(contentsOf: fixtures.appendingPathComponent("manifest.json")))
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let contentSchemas = Set([
        "card.schema.json",
        "list.schema.json",
        "collection.schema.json",
        "calendar-week.schema.json",
        "calendar-index.schema.json",
        "daily-plan.schema.json",
        "weekly-review.schema.json",
        "periodic-review.schema.json",
        "planning-template.schema.json",
        "template-library.schema.json",
        "review-rhythm.schema.json",
        "asset.schema.json",
        "account.schema.json",
        "user-profile.schema.json",
        "label-category.schema.json",
        "label.schema.json",
        "studio-settings.schema.json",
        "studio-artwork.schema.json",
        "today-shortcuts.schema.json",
        "workspace-display-preferences.schema.json",
                "workspace.schema.json",
                "user-preferences.schema.json",
                "content-selection.schema.json",
                "unavailable-reference.schema.json"
    ])
    var count = 0
    for fixture in manifest.cases where fixture.valid
    {
        guard URL(fileURLWithPath: fixture.file).lastPathComponent == fixture.file else
        {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let input = try Data(contentsOf: fixtures.appendingPathComponent(fixture.file))
        let result: Data
        if contentSchemas.contains(fixture.schema)
        {
            result = try encoder.encode(decoder.decode(PortableContentDocument.self, from: input))
        }
        else
        {
            result = try encoder.encode(decoder.decode(PortableJSONValue.self, from: input))
        }
        try result.write(to: output.appendingPathComponent(fixture.file), options: .atomic)
        count += 1
    }
    return count
}

// Execute only as a standalone tooling probe, outside the Plenact app target.
do
{
    guard CommandLine.arguments.count == 3 else
    {
        throw CocoaError(.fileReadInvalidFileName)
    }
    let count = try roundTripFixtures(
        fixtures: URL(fileURLWithPath: CommandLine.arguments[1]),
        output: URL(fileURLWithPath: CommandLine.arguments[2]))
    print("Swift emitted \(count) valid fixture round trips.")
}
catch
{
    fputs("Swift codec probe failed: \(error)\n", stderr)
    exit(1)
}
