#!/usr/bin/env python3
"""Project game language packs, profile pictures and Archon Quest chapters from Snap.Metadata."""

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "snap-hutao-data/.local/upstream/Snap.Metadata/Genshin"
METADATA = ROOT / "entry/src/main/resources/rawfile/metadata"
WINDOWS_STRINGS = ROOT / (
    "Snap.Hutao.Remastered-latest/src/Snap.Hutao.Remastered/"
    "Snap.Hutao.Remastered/Resource/Localization"
)
# Snap.Hutao.Remastered Service/LocaleNames.cs
LOCALES = {
    "zh-Hans": "CHS", "zh-Hant": "CHT", "de": "DE", "en": "EN", "es": "ES",
    "fr": "FR", "id": "ID", "it": "IT", "ja": "JP", "ko": "KR", "pt": "PT",
    "ru": "RU", "th": "TH", "tr": "TR", "vi": "VI",
}
SPECIAL_NAMES = {
    "nickname": "MetadataSpecialNameNickname",
    "realName": "MetadataSpecialNameRealNameId1",
    "timeZone": "MetadataSpecialNameServerTimeZone",
    "heShe": "MetadataSpecialNamePlayerAvatarSexProInfoPronounHeShe",
    "firstPerson": "MetadataSpecialNameMetaAvatarSexProInfoPronounBoyGirlFirst",
    "princePrincess": "MetadataSpecialNameMetaAvatarSexProInfoPronounBoyGirlD",
}
# HoYoWiki Traveler (Anemo) profile. The official title and affiliation are empty.
# https://wiki.hoyolab.com/pc/genshin/entry/19?lang=en-us
TRAVELER_DETAILS = {
    "EN": (
        "A traveler from another world who had their only kin taken away, "
        "forcing them to embark on a journey to find The Seven."
    ),
}
MAX_LOCALE_BYTES = 16 * 1024 * 1024


def read_json(path):
    with path.open(encoding="utf-8-sig") as stream:
        return json.load(stream)


def read_rows(directory, filename):
    rows = read_json(directory / filename)
    if not isinstance(rows, list):
        raise ValueError(f"{directory / filename}: expected an array")
    return rows


def read_avatars(directory):
    paths = sorted((directory / "Avatar").glob("*.json"))
    if not paths:
        raise ValueError(f"{directory / 'Avatar'}: no metadata found")
    rows = {}
    for path in paths:
        avatar = read_json(path)
        identity = avatar["Id"]
        if str(identity) != path.stem or identity in rows:
            raise ValueError(f"{path}: invalid avatar ID {identity}")
        rows[identity] = avatar
    return rows


def windows_strings(directory, locale):
    # Windows adds Traveler outside the metadata repository and formats birth dates in its UI.
    filename = "SH.resx" if locale == "zh-Hans" else f"SH.{locale}.resx"
    resources = ET.parse(directory / filename).getroot()
    return {entry.attrib["name"]: entry.findtext("value") for entry in resources.findall("data")}


def ordered_texts(avatar_id, localized, canonical, field):
    rows = localized.get(field) or []
    source = canonical.get(field) or []
    if len(rows) != len(source):
        raise ValueError(f"Avatar {avatar_id}: {field} count differs from CHS")
    # Fetter text has no ID. Preserve its position, title, and context where a title repeats.
    title_counts = Counter(row["Title"] for row in source)
    entries = []
    for index, (row, origin) in enumerate(zip(rows, source)):
        title = origin["Title"]
        entry = {"id": index, "sourceTitle": title, "t": row["Title"], "c": row["Context"]}
        if title_counts[title] > 1:
            entry["sourceContext"] = origin["Context"]
        entries.append(entry)
    return entries


def skill_texts(rows):
    return [
        {"id": row["Id"], "i": row["Icon"], "n": row["Name"], "d": row.get("Description", "")}
        for row in rows
    ]


def avatar_text(avatar, source, birthday_format):
    identity = avatar["Id"]
    info = avatar.get("FetterInfo") or {}
    source_info = source.get("FetterInfo") or {}
    depot = avatar.get("SkillDepot") or {}
    skills = list(depot.get("Skills") or [])
    if depot.get("EnergySkill"):
        skills.append(depot["EnergySkill"])
    skills.extend(depot.get("Inherents") or [])
    month, day = info.get("BirthMonth"), info.get("BirthDay")
    return {
        "id": identity,
        "name": avatar["Name"],
        "title": info.get("Title", ""),
        "detail": info.get("Detail") or avatar.get("Description", ""),
        "native": info.get("Native", ""),
        "birth": birthday_format.format(month, day) if month and day else "",
        "constellation": info.get("ConstellationBefore", ""),
        "vision": info.get("VisionBefore", ""),
        "cv": [info.get(key, "") for key in ("CvChinese", "CvJapanese", "CvEnglish", "CvKorean")],
        "skills": skill_texts(skills),
        "talents": skill_texts(depot.get("Talents") or []),
        "fetters": ordered_texts(identity, info, source_info, "Fetters"),
        "stories": ordered_texts(identity, info, source_info, "FetterStories"),
        "costumes": [
            {"id": row["Id"], "name": row["Name"], "description": row.get("Description", "")}
            for row in (avatar.get("Costumes") or [])
        ],
    }


def weapon_text(row):
    affix = row.get("Affix") or {}
    return {
        "id": row["Id"], "name": row["Name"], "description": row.get("Description", ""),
        "affixName": affix.get("Name", ""),
        "affixDesc": [item["Description"] for item in (affix.get("Descriptions") or [])],
    }


def monster_text(row):
    return {
        "id": row["Id"], "describeId": row["DescribeId"], "name": row["Name"],
        "title": row.get("Title", ""), "description": row.get("Description", ""),
        "affixes": row.get("Affixes") or [],
    }


def material_text(row, described_materials):
    result = {"id": row["Id"], "n": row["Name"]}
    if row["Id"] in described_materials:
        result["description"] = row.get("Description", "")
    return result


def select_rows(directory, filename, fields):
    return [{key: row[key] for key in fields if key in row} for row in read_rows(directory, filename)]


def read_archon_chapters(directory):
    # QuestType.AQ is 0. The Windows progress denominator includes untitled chapters.
    chapters = {}
    for row in read_rows(directory, "Chapter.json"):
        if row["QuestType"] != 0:
            continue
        identity = row["Id"]
        if type(identity) is not int or identity < 1 or identity in chapters:
            raise ValueError(f"{directory / 'Chapter.json'}: invalid chapter ID {identity}")
        if not isinstance(row["Number"], str) or not isinstance(row["Title"], str):
            raise ValueError(f"{directory / 'Chapter.json'}: invalid chapter text for {identity}")
        chapters[identity] = {key: row[key] for key in ("Id", "QuestType", "Number", "Title")}
    return chapters


def collect_text(directory, canonical_avatars, resources, described_materials, canonical_chapters):
    localized_avatars = read_avatars(directory)
    avatar_rows = [
        avatar_text(avatar, canonical_avatars[identity], resources["ModelMetadataFetterInfoBirthday"])
        for identity, avatar in localized_avatars.items()
    ]
    for identity in (10000005, 10000007):
        traveler = {"id": identity, "name": resources["ModelMetadataAvatarPlayerName"]}
        if directory.name in TRAVELER_DETAILS:
            traveler["detail"] = TRAVELER_DETAILS[directory.name]
            traveler["title"] = ""
            traveler["native"] = ""
        avatar_rows.append(traveler)
    avatar_rows.sort(key=lambda row: row["id"])
    namecards = select_rows(directory, "NameCard.json", ("Id", "Icon", "Name", "Description"))
    card_icons = {row["Icon"] for row in namecards}
    # New character cards can precede the standalone NameCard table in the same source revision.
    for avatar in localized_avatars.values():
        card = avatar.get("NameCard") or {}
        if card.get("Icon") and card["Icon"] not in card_icons:
            namecards.append({key: card[key] for key in ("Icon", "Name", "Description")})
            card_icons.add(card["Icon"])
    chapters = read_archon_chapters(directory)
    return {
        "avatar_meta.json": avatar_rows,
        "weapon_meta.json": [weapon_text(row) for row in read_rows(directory, "Weapon.json")],
        "monster_meta.json": [monster_text(row) for row in read_rows(directory, "Monster.json")],
        "material_meta.json": [material_text(row, described_materials) for row in read_rows(directory, "Material.json")],
        "Achievement.json": select_rows(directory, "Achievement.json", ("Id", "Title", "Description")),
        "AchievementGoal.json": select_rows(directory, "AchievementGoal.json", ("Id", "Name")),
        "NameCard.json": namecards,
        "ProfilePicture.json": select_rows(directory, "ProfilePicture.json", ("Id", "Name")),
        "GachaEvent.json": select_rows(directory, "GachaEvent.json", ("Type", "From", "To", "Order", "Name")),
        "TowerFloor.json": select_rows(directory, "TowerFloor.json", ("Id", "Descriptions")),
        "TowerSchedule.json": select_rows(directory, "TowerSchedule.json", ("Id", "BuffName", "Descriptions")),
        "HardChallengeSchedule.json": select_rows(directory, "HardChallengeSchedule.json", ("Id", "Name")),
        "BeyondItem.json": select_rows(directory, "BeyondItem.json", ("Id", "Name", "Description")),
        "Reliquary.json": select_rows(directory, "Reliquary.json", ("Ids", "Name", "Description")),
        "ReliquarySet.json": select_rows(directory, "ReliquarySet.json", ("SetId", "Name", "Descriptions")),
        "Furniture.json": select_rows(directory, "Furniture.json", ("Id", "Name")),
        "Chapter.json": [
            {key: chapters[identity][key] for key in ("Id", "Number", "Title")}
            for identity in canonical_chapters if identity in chapters
        ],
    }


def json_text(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def encode_locale(locale, source_locale, revision, special_names, files):
    # Use one row per line so generated diffs remain readable.
    header = {
        "schema": 1, "locale": locale, "sourceLocale": source_locale, "upstreamRevision": revision,
        "specialNames": special_names,
    }
    tables = []
    for name, rows in files.items():
        body = ",\n".join(json_text(row) for row in rows)
        tables.append(f"    {json_text(name)}: [\n{body}\n    ]")
    content = json_text(header)[:-1] + ',\n  "files": {\n' + ",\n".join(tables) + "\n  }\n}\n"
    return content.encode("utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=SOURCE, help="Snap.Metadata Genshin directory")
    parser.add_argument("--output", type=Path, default=METADATA,
                        help="output directory for locale_*.json, ProfilePicture.json and Chapter.json")
    parser.add_argument("--base-metadata", type=Path, default=METADATA,
                        help="compact metadata directory used to select material descriptions")
    parser.add_argument("--windows-strings", type=Path, default=WINDOWS_STRINGS, help="upstream SH.*.resx directory")
    parser.add_argument("--upstream-revision", help="Snap.Metadata revision if source is an exported tree")
    parser.add_argument("--check", action="store_true", help="compare generated bytes without writing files")
    args = parser.parse_args()

    revision = args.upstream_revision or subprocess.check_output(
        ["git", "-C", str(args.source), "rev-parse", "HEAD"], text=True
    ).strip()
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        parser.error("--upstream-revision must be a full commit hash")

    canonical_source = args.source / "CHS"
    canonical_avatars = read_avatars(canonical_source)
    canonical_chapters = read_archon_chapters(canonical_source)
    if not canonical_chapters:
        parser.error("CHS/Chapter.json has no Archon Quest chapters")
    chapter_data = ("[\n" + ",\n".join(f"  {json_text(row)}" for row in canonical_chapters.values()) + "\n]\n").encode("utf-8")
    # Retain the upstream file, using its Git blob's LF line endings on all hosts.
    profile_data = (canonical_source / "ProfilePicture.json").read_bytes().replace(b"\r\n", b"\n")
    described_materials = {int(key) for key in read_json(args.base_metadata / "material_meta.json")}
    results = {}
    for locale, source_locale in LOCALES.items():
        resources = windows_strings(args.windows_strings, locale)
        files = collect_text(args.source / source_locale, canonical_avatars, resources, described_materials, canonical_chapters)
        special_names = {key: resources[token] for key, token in SPECIAL_NAMES.items()}
        data = encode_locale(locale, source_locale, revision, special_names, files)
        if len(data) > MAX_LOCALE_BYTES:
            parser.error(f"{locale}: locale file exceeds {MAX_LOCALE_BYTES} bytes")
        results[args.output / f"locale_{locale}.json"] = data

    outputs = {**results, args.output / "ProfilePicture.json": profile_data, args.output / "Chapter.json": chapter_data}
    if args.check:
        mismatches = [path.name for path, data in outputs.items() if not path.is_file() or path.read_bytes() != data]
        if mismatches:
            parser.error("generated metadata differs: " + ", ".join(mismatches))
    else:
        args.output.mkdir(parents=True, exist_ok=True)
        for path, data in outputs.items():
            path.write_bytes(data)
    print(f"Snap.Metadata {revision}: {len(results)} locales, "
          f"{sum(map(len, results.values())):,} bytes total, {max(map(len, results.values())):,} bytes largest")
    print(f"ProfilePicture.json: {len(profile_data):,} bytes")
    print(f"Chapter.json: {len(canonical_chapters)} Archon Quest chapters, {len(chapter_data):,} bytes")


if __name__ == "__main__":
    main()
