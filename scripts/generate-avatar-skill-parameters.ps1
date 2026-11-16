#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $Source = (Join-Path $PSScriptRoot '../.local/metadata-fb3e269/Genshin'),
    [switch] $Check
)

$ErrorActionPreference = 'Stop'
$output = Join-Path $PSScriptRoot '../entry/src/main/resources/rawfile/metadata'

# Use the same .NET Single formatting as Windows, including locale-specific separators.
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.RegularExpressions;

public static class AvatarSkillParameterGenerator
{
    private static readonly Dictionary<string, string> Locales = new Dictionary<string, string>
    {
        { "zh-Hans", "CHS" }, { "zh-Hant", "CHT" }, { "en", "EN" }, { "de", "DE" },
        { "es", "ES" }, { "fr", "FR" }, { "id", "ID" }, { "it", "IT" },
        { "ja", "JP" }, { "ko", "KR" }, { "pt", "PT" }, { "ru", "RU" },
        { "th", "TH" }, { "tr", "TR" }, { "vi", "VI" }
    };
    private static readonly Regex Parameter = new Regex(@"\{param([1-9][0-9]*?):(.+?)\}");
    private static readonly Regex Layout = new Regex(@"\{LAYOUT_MOBILE#(.+?)\}\{LAYOUT_PC#(.+?)\}\{LAYOUT_PS#(.+?)\}");
    private static readonly JsonSerializerOptions JsonOptions = new JsonSerializerOptions
    {
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    public static void Run(string source, string output, bool check)
    {
        string[] canonicalIds = null;
        foreach (KeyValuePair<string, string> language in Locales)
        {
            string folder = Path.Combine(source, language.Value, "Avatar");
            string[] files = Directory.GetFiles(folder, "*.json").OrderBy(Path.GetFileName, StringComparer.Ordinal).ToArray();
            string[] ids = files.Select(Path.GetFileNameWithoutExtension).ToArray();
            if (files.Length == 0) throw new InvalidDataException("No avatar files in " + folder);
            if (canonicalIds == null) canonicalIds = ids;
            if (!ids.SequenceEqual(canonicalIds)) throw new InvalidDataException("Avatar identities differ from CHS in " + folder);

            CultureInfo culture = CultureInfo.GetCultureInfo(language.Key);
            var avatars = new Dictionary<string, object[]>();
            foreach (string file in files)
            {
                using (JsonDocument document = JsonDocument.Parse(File.ReadAllText(file)))
                {
                    JsonElement avatar = document.RootElement;
                    string id = Path.GetFileNameWithoutExtension(file);
                    if (avatar.GetProperty("Id").GetInt32().ToString(CultureInfo.InvariantCulture) != id)
                        throw new InvalidDataException("Unexpected avatar ID in " + file);
                    avatars.Add(id, Skills(avatar.GetProperty("SkillDepot"))
                        .Select(entry => ConvertSkill(entry.Skill, entry.Kind, culture)).ToArray());
                }
            }

            string destination = Path.Combine(output, "avatar_skill_" + language.Key + ".json");
            string text = JsonSerializer.Serialize(new { schema = 1, locale = language.Key, avatars }, JsonOptions) + "\n";
            if (check)
            {
                if (!File.Exists(destination) || File.ReadAllText(destination) != text)
                    throw new InvalidDataException("Outdated skill parameters: " + destination);
            }
            else
            {
                File.WriteAllText(destination, text);
            }
            Console.WriteLine("{0} {1} avatars {2} bytes", language.Key, avatars.Count, System.Text.Encoding.UTF8.GetByteCount(text));
        }
    }

    // SkillDepot.CompositeSkills order, including alternate sprint and non-levelled talents.
    private static IEnumerable<(JsonElement Skill, int Kind)> Skills(JsonElement depot)
    {
        foreach (JsonElement skill in depot.GetProperty("Skills").EnumerateArray()) yield return (skill, 0);
        yield return (depot.GetProperty("EnergySkill"), 1);
        if (depot.TryGetProperty("SpecialSkills", out JsonElement specials) && specials.ValueKind == JsonValueKind.Array)
            foreach (JsonElement skill in specials.EnumerateArray()) yield return (skill, 2);
        foreach (JsonElement skill in depot.GetProperty("Inherents").EnumerateArray()) yield return (skill, 3);
    }

    private static object ConvertSkill(JsonElement skill, int kind, CultureInfo culture)
    {
        JsonElement proud = skill.GetProperty("Proud");
        string[] descriptions = proud.GetProperty("Descriptions").EnumerateArray().Select(value => value.GetString()).ToArray();
        JsonElement[] entries = descriptions.Length == 0 ? Array.Empty<JsonElement>()
            : proud.GetProperty("Parameters").EnumerateArray().OrderBy(entry => entry.GetProperty("Level").GetInt32()).ToArray();
        if (descriptions.Length > 0 && entries.Length == 0)
            throw new InvalidDataException("Skill has descriptions without parameter levels: " + skill.GetProperty("Id"));
        int[] levels = entries.Select(entry => entry.GetProperty("Level").GetInt32()).ToArray();
        float[][] parameters = entries.Select(entry => entry.GetProperty("Parameters").EnumerateArray()
            .Select(value => value.GetSingle()).ToArray()).ToArray();

        // DescriptionsParametersDescriptor marks SpecialDescriptionList minus DescriptionList.
        HashSet<int> special = Indexes(proud, "SpecialDescriptionList");
        special.ExceptWith(Indexes(proud, "DescriptionList"));
        var rows = new List<object>();
        for (int index = 0; index < descriptions.Length; index++)
        {
            string description = descriptions[index];
            int split = description.IndexOf('|');
            if (split <= 0) throw new InvalidDataException("Invalid parameter description: " + description);
            string label = Expand(description.Substring(0, split));
            string template = Expand(description.Substring(split + 1));
            string[] values = parameters.Select(level => Parameter.Replace(template, match =>
                Format(level[int.Parse(match.Groups[1].Value, CultureInfo.InvariantCulture) - 1], match.Groups[2].Value, culture))).ToArray();
            if (values.All(value => value == values[0])) values = new[] { values[0] };
            rows.Add(new { label, values, isSpecial = special.Contains(index + 1) });
        }

        return new
        {
            id = skill.GetProperty("Id").GetInt32(),
            groupId = skill.GetProperty("GroupId").GetInt32(),
            kind,
            name = Text(skill, "Name"),
            icon = Text(skill, "Icon"),
            description = Text(skill, "Description"),
            specialDescription = Text(skill, "SpecialDescription"),
            levels,
            // WikiAvatarPage requests index 9; DescParamComboBox otherwise selects the last level.
            defaultLevel = levels.Length == 0 ? 0 : levels[Math.Min(9, levels.Length - 1)],
            parameterSeries = rows
        };
    }

    private static HashSet<int> Indexes(JsonElement source, string key) =>
        source.TryGetProperty(key, out JsonElement items) && items.ValueKind == JsonValueKind.Array
            ? new HashSet<int>(items.EnumerateArray().Select(value => value.GetInt32())) : new HashSet<int>();

    private static string Text(JsonElement source, string key) =>
        source.TryGetProperty(key, out JsonElement value) ? value.GetString() ?? "" : "";

    private static string Expand(string text) =>
        Layout.Replace((text.StartsWith("#") ? text.Substring(1) : text)
            .Replace("{NON_BREAK_SPACE}", "\u00A0").Replace("{SPACE}", " "), "$2");

    // Mirrors Windows ParameterFormat. The literal units and multi-parameter expressions stay in their template.
    private static string Format(float value, string format, CultureInfo culture)
    {
        if (format.Length == 3) return value.ToString("P" + format[1], culture);
        if (format.Length == 2) return value.ToString(format, culture);
        if (format == "P") return value.ToString("P0", culture);
        if (format == "I") return Convert.ToInt32(value).ToString(culture);
        return value.ToString(culture);
    }
}
'@

[AvatarSkillParameterGenerator]::Run((Resolve-Path -LiteralPath $Source).Path, $output, $Check.IsPresent)
