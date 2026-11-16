#!/usr/bin/env python3
"""Update bundled game data from a verified local Snap.Metadata export."""

import argparse
from copy import deepcopy
from datetime import datetime
import json
from pathlib import Path
import re
from uuid import uuid4


TARGET = Path(__file__).resolve().parents[1] / "entry/src/main/resources/rawfile/metadata"
# Install referenced data before the records that use it.
FILES = (
    "material_meta.json", "AvatarCurve.json", "WeaponCurve.json", "AvatarPromote.json",
    "WeaponPromote.json", "NameCard.json", "avatar_associations.json", "avatar_meta.json",
    "weapon_meta.json", "GachaEvent.json",
)
CHALLENGE_TABLES = (
    "AchievementGoal.json", "Achievement.json", "TowerLevel.json", "TowerFloor.json",
    "TowerSchedule.json", "RoleCombatSchedule.json", "HardChallengeSchedule.json",
)
MONSTER_RESISTANCES = ("Fire", "Water", "Grass", "Elec", "Wind", "Ice", "Rock", "Physical")


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def project_avatar(row):
    fetter = row.get("FetterInfo") or {}
    base = row["BaseValue"]
    depot = row["SkillDepot"]
    card = row.get("NameCard") or {}
    recipe = fetter.get("CookBonus") or {}
    month, day = fetter.get("BirthMonth"), fetter.get("BirthDay")

    def skill_text(skill):
        return {"n": skill["Name"], "d": skill.get("Description") or "", "i": skill["Icon"]}

    active = depot.get("Skills") or []
    upgradeable = [skill for skill in active if len(skill["Proud"]["Parameters"]) > 1]
    kinds = {skill["Id"]: kind for skill, kind in zip(upgradeable, ("A", "E"))} if len(upgradeable) == 2 else {}
    skills = [dict(skill_text(skill), k=kinds.get(skill["Id"], "X")) for skill in active]
    if depot.get("EnergySkill"):
        skills.append(dict(skill_text(depot["EnergySkill"]), k="Q"))
    skills.extend(dict(skill_text(skill), k="P") for skill in depot.get("Inherents") or [])

    return {
        "id": row["Id"], "name": row["Name"], "icon": row["Icon"], "sideIcon": row["SideIcon"],
        "quality": row["Quality"], "weapon": row["Weapon"], "sort": row["Sort"],
        "begin": (row.get("BeginTime") or "").split("T", 1)[0], "title": fetter.get("Title") or "",
        "detail": fetter.get("Detail") or row.get("Description") or "", "native": fetter.get("Native") or "",
        "birth": f"{month}/{day}" if month and day else "", "constellation": fetter.get("ConstellationBefore") or "",
        "vision": fetter.get("VisionBefore") or "",
        "cv": [fetter.get(key) or "" for key in ("CvChinese", "CvJapanese", "CvEnglish", "CvKorean")],
        "skills": skills, "talents": [skill_text(skill) for skill in depot.get("Talents") or []],
        "cultivationItems": row["CultivationItems"],
        "cook": {"origin": recipe["OriginItemId"], "item": recipe["ItemId"]} if recipe else None,
        "fetters": [{"t": value["Title"], "c": value["Context"]} for value in fetter.get("Fetters") or []],
        "stories": [{"t": value["Title"], "c": value["Context"]} for value in fetter.get("FetterStories") or []],
        "hpBase": base["HpBase"], "attackBase": base["AttackBase"], "defenseBase": base["DefenseBase"],
        "promoteId": row["PromoteId"],
        "growCurves": [{"t": curve["Type"], "v": curve["Value"]} for curve in row["GrowCurves"]],
        "nameCardIcon": card.get("Icon") or "", "nameCardPic": f"{card['PicturePrefix']}_P" if card.get("PicturePrefix") else "",
        "body": row["Body"], "costumes": [
            {"id": value["Id"], "name": value["Name"], "description": value.get("Description") or "",
             "isDefault": value.get("IsDefault", False), "frontIcon": value.get("FrontIcon") or ""}
            for value in row.get("Costumes") or []
        ],
    }


def project_weapon(row):
    affix = row.get("Affix") or {}
    descriptions = sorted(affix.get("Descriptions") or [], key=lambda value: value["Level"])
    return {
        "id": row["Id"], "name": row["Name"], "icon": row["Icon"], "awakenIcon": row.get("AwakenIcon") or "",
        "weaponType": row["WeaponType"], "rankLevel": row["RankLevel"], "sort": row["Sort"],
        "description": row.get("Description") or "", "affixName": affix.get("Name") or "",
        "affixDesc": [value["Description"] for value in descriptions], "cultivationItems": row["CultivationItems"],
        "promoteId": row["PromoteId"], "growCurves": [
            {"i": curve["InitValue"], "t": curve["Type"], "v": curve["Value"]} for curve in row["GrowCurves"]
        ],
    }


def project_monster(row):
    base = row.get("BaseValue") or {}
    return {
        "id": row["Id"], "describeId": row["DescribeId"], "name": row["Name"], "title": row["Title"],
        "icon": row["Icon"], "type": row["Type"], "arkhe": row["Arkhe"],
        "description": row.get("Description") or "", "affixes": row.get("Affixes") or [],
        "drops": row.get("Drops") or [], "hpBase": base.get("HpBase", 0),
        "attackBase": base.get("AttackBase", 0), "defenseBase": base.get("DefenseBase", 0),
        # Preserve the storage order used by existing bundled and remote snapshots.
        "subHurts": [base[f"{element}SubHurt"] for element in MONSTER_RESISTANCES] if base else [],
        "growCurves": [{"t": curve["Type"], "v": curve["Value"]} for curve in row.get("GrowCurves") or []],
    }


def normalize_traveler(rows):
    # Windows AvatarIds and upstream ProfilePicture UnlockParameter use 05 Boy, 07 Girl.
    boy = next(row for row in rows if row["id"] == 10000005)
    girl = next((row for row in rows if row["id"] == 10000007), None)
    if girl is None:
        girl = dict(deepcopy(boy), id=10000007)
        rows.insert(rows.index(boy) + 1, girl)
    for row, icon in ((boy, "PlayerBoy"), (girl, "PlayerGirl")):
        row["icon"] = f"UI_AvatarIcon_{icon}"
        row["sideIcon"] = f"UI_AvatarIcon_Side_{icon}"


def insert_by_sort(rows, new_rows):
    for row in sorted(new_rows, key=lambda value: value["sort"], reverse=True):
        position = next((index for index, old in enumerate(rows)
                         if old["id"] not in (10000005, 10000007) and old["sort"] < row["sort"]), len(rows))
        rows.insert(position, row)


def add_materials(materials, source, avatars, weapons):
    required = set()

    def tiers(highest, count):
        required.update(range(highest - count + 1, highest + 1))

    for avatar in avatars:
        gem, boss, specialty, drop, book, weekly = avatar["cultivationItems"]
        required.update((boss, specialty, weekly))
        tiers(gem, 4)
        tiers(drop, 3)
        tiers(book, 3)
        if avatar["cook"]:
            required.update(avatar["cook"].values())
    for weapon in weapons:
        domain, drop_a, drop_b = weapon["cultivationItems"]
        tier_count = 2 if weapon["rankLevel"] <= 2 else 3
        tiers(domain, tier_count + 1)
        tiers(drop_a, tier_count)
        tiers(drop_b, tier_count)

    add_material_rows(materials, {row["Id"]: row for row in source}, required)


def add_material_rows(materials, by_id, required):
    for identity in sorted(required):
        key = str(identity)
        if key not in materials:
            row = by_id[identity]
            materials[key] = {"n": row["Name"], "i": row["Icon"], "r": row["RankLevel"]}


def add_progression(base, chs, kind, items):
    if not items:
        return
    promote_ids = {item["promoteId"] for item in items}
    filename = f"{kind}Promote.json"
    existing = {(row["Id"], row["Level"]) for row in base[filename]}
    for row in read_json(chs / filename):
        key = row["Id"], row["Level"]
        if row["Id"] in promote_ids and key not in existing:
            base[filename].append(row)
            existing.add(key)
    if not promote_ids <= {identity for identity, _ in existing}:
        raise ValueError(f"Missing source {kind} promote IDs")

    curve_types = {curve["v"] for item in items for curve in item["growCurves"]}
    filename = f"{kind}Curve.json"
    incoming = {row["Level"]: row["Curves"] for row in read_json(chs / filename)}
    for row in base[filename]:
        present = {curve["Type"] for curve in row["Curves"]}
        needed = curve_types - present
        if needed:
            additions = [curve for curve in incoming[row["Level"]] if curve["Type"] in needed]
            if {curve["Type"] for curve in additions} != needed:
                raise ValueError(f"Missing source {kind} curve types at level {row['Level']}")
            row["Curves"].extend(additions)


def event_time_key(row):
    return (row["Type"], datetime.fromisoformat(row["From"]), datetime.fromisoformat(row["To"]), row["Order"])


def event_pool_key(row):
    return row["Version"], row["Order"], row["Type"], row["Name"]


def add_events(events, incoming, avatars, weapons):
    times = {event_time_key(row) for row in events}
    pools = {event_pool_key(row) for row in events}
    avatar_ids = {row["id"] for row in avatars}
    weapon_ids = {row["id"] for row in weapons}
    for row in incoming:
        time, pool = event_time_key(row), event_pool_key(row)
        if time in times or pool in pools:
            continue
        allowed = weapon_ids if row["Type"] == 302 else avatar_ids | weapon_ids
        missing = set(row["UpOrangeList"] + row["UpPurpleList"]) - allowed
        if missing:
            raise ValueError(f"Gacha pool {pool} refers to missing items {sorted(missing)}")
        events.append(row)
        times.add(time)
        pools.add(pool)


def update(base, chs):
    avatar_rows = base["avatar_meta.json"]
    weapon_rows = base["weapon_meta.json"]
    old_avatars = {row["id"] for row in avatar_rows}
    old_weapons = {row["id"] for row in weapon_rows}
    upstream_avatars = {}
    for path in sorted((chs / "Avatar").glob("*.json")):
        row = read_json(path)
        identity = row["Id"]
        if str(identity) != path.stem or identity in upstream_avatars:
            raise ValueError(f"Invalid avatar identity in {path}")
        if identity not in old_avatars:
            upstream_avatars[identity] = row

    avatars = [project_avatar(row) for row in upstream_avatars.values()]
    weapons = [project_weapon(row) for row in read_json(chs / "Weapon.json") if row["Id"] not in old_weapons]
    add_materials(base["material_meta.json"], read_json(chs / "Material.json"), avatars, weapons)
    add_progression(base, chs, "Avatar", avatars)
    add_progression(base, chs, "Weapon", weapons)
    known_cards = {card["Icon"] for card in base["NameCard.json"]}
    for avatar in avatars:
        identity = avatar["id"]
        row = upstream_avatars[identity]
        association = (row.get("FetterInfo") or {}).get("Association")
        if association is not None:
            base["avatar_associations.json"][str(identity)] = association
        card = row.get("NameCard") or {}
        if avatar["nameCardIcon"] and avatar["nameCardPic"] and avatar["nameCardIcon"] not in known_cards:
            base["NameCard.json"].append({"Name": card["Name"], "Description": card["Description"],
                                          "Icon": avatar["nameCardIcon"], "Picture": avatar["nameCardPic"]})
            known_cards.add(avatar["nameCardIcon"])

    normalize_traveler(avatar_rows)
    insert_by_sort(avatar_rows, avatars)
    insert_by_sort(weapon_rows, weapons)
    add_events(base["GachaEvent.json"], read_json(chs / "GachaEvent.json"), avatar_rows, weapon_rows)
    return avatars, weapons


def merge_by_id(existing, upstream, key, filename):
    upstream_ids = {row[key] for row in upstream}
    if len(upstream_ids) != len(upstream) or len({row[key] for row in existing}) != len(existing):
        raise ValueError(f"{filename}: duplicate {key}")
    return upstream + [row for row in existing if row[key] not in upstream_ids]


def update_challenges(base, chs):
    name = "monster_meta.json"
    monsters = [project_monster(row) for row in read_json(chs / "Monster.json")]
    base[name] = sorted(merge_by_id(base[name], monsters, "describeId", name), key=lambda row: row["describeId"])
    drop_ids = {identity for monster in monsters for identity in monster["drops"]}
    materials = {row["Id"]: row for row in read_json(chs / "Material.json")}
    add_material_rows(base["material_meta.json"], materials, drop_ids & materials.keys())
    base["monster_drop_meta.json"] = project_monster_drops(monsters, materials, read_json(chs / "DisplayItem.json"))

    for filename in CHALLENGE_TABLES:
        base[filename] = merge_by_id(base[filename], read_json(chs / filename), "Id", filename)
    return drop_ids - materials.keys()


def project_monster_drops(monsters, materials, display_items):
    drop_ids = {identity for monster in monsters for identity in monster["drops"]} - materials.keys()
    rows = []
    for item in display_items:
        if item["Id"] not in drop_ids:
            continue
        icon = item["Icon"]
        relic = re.fullmatch(r"UI_RelicIcon_(\d+)_\d+", icon)
        rows.append({"Id": item["Id"], "Name": item["Name"], "Icon": icon,
                     "RankLevel": item["RankLevel"], "SetId": int(relic[1]) if relic else 0})
    return sorted(rows, key=lambda row: row["Id"])


def encode(name, value):
    original = (TARGET / name).read_bytes()
    indent = 2 if b"\n" in original else None
    separators = (",", ":") if name == "material_meta.json" else None
    text = json.dumps(value, ensure_ascii=False, indent=indent, separators=separators, allow_nan=False)
    if original.endswith(b"\n"):
        text += "\n"
    if b"\r\n" in original:
        text = text.replace("\n", "\r\n")
    return text.encode("utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="Verified Snap.Metadata Genshin directory")
    parser.add_argument("--revision", required=True, help="Full Git revision of the verified export")
    parser.add_argument("--include-challenges", action="store_true", help="Also sync monsters, challenges and achievements")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--apply", action="store_true", help="Write bundled metadata after staging")
    mode.add_argument("--check", action="store_true", help="Report pending changes and exit nonzero if any")
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", args.revision):
        parser.error("--revision must be a full Git commit hash")
    chs = args.source.resolve() / "CHS"
    if not any((chs / "Avatar").glob("*.json")):
        parser.error("--source must contain CHS/Avatar metadata")

    files = FILES + (("monster_meta.json", "monster_drop_meta.json") + CHALLENGE_TABLES if args.include_challenges else ())
    original = {name: read_json(TARGET / name) for name in files}
    updated = deepcopy(original)
    avatars, weapons = update(updated, chs)
    non_material_drops = update_challenges(updated, chs) if args.include_challenges else set()
    changes = [name for name in files if original[name] != updated[name]]
    print(f"Snap.Metadata {args.revision}")
    for kind, rows in (("avatar", avatars), ("weapon", weapons)):
        for row in rows:
            print(f"+ {kind} {row['id']} {row['name']}")
    for name in changes:
        print(f"{name}: {len(original[name])} -> {len(updated[name])}")
    if non_material_drops:
        print("Monster drop IDs outside Material.json: " + ", ".join(map(str, sorted(non_material_drops))))
    if args.check:
        if changes:
            raise SystemExit("Bundled compact metadata needs updating")
        print("Bundled compact metadata is current for this source")
        return
    # Temporary directories on Windows may be private to the generating user. Stage
    # each asset beside its destination so DevEco can read it with the project's ACL.
    staged = {}
    try:
        for name in changes:
            path = TARGET / f".{name}.{uuid4().hex}.tmp"
            staged[name] = path
            path.write_bytes(encode(name, updated[name]))
        for name, path in staged.items():
            path.replace(TARGET / name)
    finally:
        for path in staged.values():
            path.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
