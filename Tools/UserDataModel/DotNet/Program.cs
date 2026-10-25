// --------------------------------------------------------------------------------------------------
// @file       Program.cs
// @brief      Prototype C# content-envelope and JSON fixture round trips
// @details    Supported User Data Model versions: 1.0, final specification.
//             Local tooling only; schemas and semantic validation are separate prerequisites.
//             Does not migrate legacy data, synchronize, or establish account authorization.
// --------------------------------------------------------------------------------------------------
using System.Text.Json;
using System.Text.Json.Serialization;

/// <summary>Preserves the entire validated payload behind an explicitly named content envelope.</summary>
internal sealed class PortableContentDocument
{
    [JsonPropertyName("user_data_model_version")]
    public required string ModelVersion { get; init; }
    [JsonPropertyName("payload_schema_version")]
    public required int SchemaVersion { get; init; }
    [JsonPropertyName("record_type")]
    public required string RecordType { get; init; }
    [JsonPropertyName("id")]
    public required string Id { get; init; }
    [JsonPropertyName("workspace_id")]
    public required string WorkspaceId { get; init; }
    [JsonPropertyName("payload")]
    public required JsonElement Payload { get; init; }
}

/// <summary>Runs shared valid fixtures through standalone .NET codecs.</summary>
internal static class Program
{
    /// <summary>Emit codec output for independent schema, semantic, and value comparison.</summary>
    /// <param name="args">Fixture folder and caller-supplied temporary output folder.</param>
    /// <returns>Zero on success; one on an invalid input or codec failure.</returns>
    private static int Main(string[] args)
    {
        try
        {
            if (args.Length != 2)
            {
                throw new ArgumentException("Expected fixture and temporary output folders.");
            }
            using JsonDocument manifest = JsonDocument.Parse(File.ReadAllText(Path.Combine(args[0], "manifest.json")));
            Directory.CreateDirectory(args[1]);
            var options = new JsonSerializerOptions
            {
                WriteIndented = true,
                UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow
            };
            var contentSchemas = new HashSet<string>
            {
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
            };
            int count = 0;
            foreach (JsonElement fixture in manifest.RootElement.GetProperty("cases").EnumerateArray())
            {
                if (!fixture.GetProperty("valid").GetBoolean())
                {
                    continue;
                }
                string file = fixture.GetProperty("file").GetString()!;
                if (Path.GetFileName(file) != file)
                {
                    throw new ArgumentException("Invalid fixture filename.");
                }
                string input = File.ReadAllText(Path.Combine(args[0], file));
                string output;
                if (contentSchemas.Contains(fixture.GetProperty("schema").GetString()!))
                {
                    PortableContentDocument content = JsonSerializer.Deserialize<PortableContentDocument>(input, options)
                        ?? throw new JsonException("Missing content document.");
                    output = JsonSerializer.Serialize(content, options);
                }
                else
                {
                    using JsonDocument content = JsonDocument.Parse(input);
                    output = JsonSerializer.Serialize(content.RootElement, options);
                }
                File.WriteAllText(Path.Combine(args[1], file), output);
                count++;
            }
            Console.WriteLine($"C# emitted {count} valid fixture round trips.");
            return 0;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine($"C# codec probe failed: {error.GetType().Name}");
            return 1;
        }
    }
}
