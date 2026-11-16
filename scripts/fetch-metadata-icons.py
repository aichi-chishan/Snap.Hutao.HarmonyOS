#!/usr/bin/env python3
"""Fetch missing icons for the pinned Snap.Metadata fb3e269 data."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import re
from tempfile import NamedTemporaryFile
from time import sleep
from urllib.error import HTTPError
from urllib.request import HTTPRedirectHandler, Request, build_opener


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / ".local/metadata-fb3e269/Genshin/CHS"
ICONS = ROOT / "entry/src/main/resources/rawfile/icons"
CDN = "https://api.snaphutaorp.org/static/raw/"
REDIRECT = "https://static.snaphutaorp.org/static/raw/"
AVATAR_IDS = (10000136, 10000137, 10000140, 10000143)
WEAPON_IDS = (11437, 11438, 11522, 14437, 14524, 14525, 15437)
MAX_PNG_BYTES = 2 * 1024 * 1024
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
PNG_END = b"\x00\x00\x00\x00IEND\xaeB`\x82"


class IconRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        source_url = request.full_url
        if not source_url.startswith(CDN) or new_url != REDIRECT + source_url[len(CDN):]:
            raise HTTPError(source_url, code, "unexpected icon redirect", headers, response)
        return super().redirect_request(request, response, code, message, headers, new_url)


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def add(jobs, category, name):
    if name:
        if not re.fullmatch(r"[A-Za-z0-9_-]{1,251}", name):
            raise ValueError(f"invalid icon name: {name!r}")
        jobs.add((category, name))


def collect_icons(source, primary_only, include_challenges=False):
    avatars = [read_json(source / "Avatar" / f"{identity}.json") for identity in AVATAR_IDS]
    if tuple(row["Id"] for row in avatars) != AVATAR_IDS:
        raise ValueError("avatar metadata IDs do not match the requested IDs")
    weapon_rows = {row["Id"]: row for row in read_json(source / "Weapon.json")}
    weapons = [weapon_rows[identity] for identity in WEAPON_IDS]
    jobs = set()
    for avatar in avatars:
        add(jobs, "AvatarIcon", avatar["Icon"])
    for weapon in weapons:
        add(jobs, "EquipIcon", weapon["Icon"])
    if primary_only:
        return jobs

    add(jobs, "AvatarIcon", "UI_AvatarIcon_Side_PlayerBoy")
    for avatar in avatars:
        add(jobs, "AvatarIcon", avatar["SideIcon"])
        depot = avatar["SkillDepot"]
        for skill in (*depot["Skills"], depot["EnergySkill"], *depot["Inherents"]):
            icon = skill["Icon"]
            add(jobs, "Talent" if icon.startswith("UI_Talent_") else "Skill", icon)
        for talent in depot["Talents"]:
            add(jobs, "Talent", talent["Icon"])
        card = avatar["NameCard"]
        add(jobs, "NameCardIcon", card["Icon"])
        add(jobs, "NameCardPic", card["PicturePrefix"] + "_P")
    for weapon in weapons:
        add(jobs, "EquipIcon", weapon["AwakenIcon"])

    materials = {row["Id"]: row for row in read_json(source / "Material.json")}
    # CultivationItems stores the highest ID for each upgradeable tier family.
    for entities, lower_tiers in ((avatars, (3, 0, 0, 2, 2, 0)), (weapons, (3, 2, 2))):
        for entity in entities:
            for identity, tiers in zip(entity["CultivationItems"], lower_tiers, strict=True):
                for material_id in range(identity - tiers, identity + 1):
                    add(jobs, "ItemIcon", materials[material_id]["Icon"])

    if include_challenges:
        for category, filename in (("MonsterIcon", "Monster.json"), ("AchievementIcon", "AchievementGoal.json")):
            for row in read_json(source / filename):
                add(jobs, category, row["Icon"])
        for path in sorted((source / "Avatar").glob("*.json")):
            recipe = (read_json(path).get("FetterInfo") or {}).get("CookBonus")
            if recipe:
                for key in ("ItemId", "OriginItemId"):
                    add(jobs, "ItemIcon", materials[recipe[key]]["Icon"])
    return jobs


def download(relative):
    request = Request(CDN + relative, headers={"Accept": "image/png", "User-Agent": "SnapHutaoHarmonyOS"})
    opener = build_opener(IconRedirect())
    for attempt in range(3):
        try:
            with opener.open(request, timeout=15) as response:
                return response.read(MAX_PNG_BYTES + 1)
        except HTTPError as error:
            if attempt == 2 or error.code not in (429, 500, 502, 503, 504):
                raise
            error.close()
            sleep(0.5 * (attempt + 1))


def fetch(job):
    category, name = job
    relative = f"{category}/{name}.png"
    destination = ICONS / relative
    if destination.exists():
        return f"PRESENT {relative}", True
    try:
        png = download(relative)
        if not 57 <= len(png) <= MAX_PNG_BYTES or not png.startswith(PNG_SIGNATURE) or not png.endswith(PNG_END):
            raise ValueError("invalid PNG signature, size or end marker")
        with NamedTemporaryFile(dir=destination.parent, prefix=f".{name}.", suffix=".tmp", delete=False) as file:
            temporary = Path(file.name)
            try:
                file.write(png)
                file.close()
                # Publish atomically without replacing a destination that appeared during the download.
                os.link(temporary, destination)
            except FileExistsError:
                return f"PRESENT {relative}", True
            finally:
                file.close()
                temporary.unlink()
        return f"ADDED {relative} ({len(png)} bytes)", True
    except (OSError, ValueError) as error:
        return f"FAILED {relative} ({error})", False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=SOURCE, help="path to the pinned Genshin/CHS directory")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--primary-only", action="store_true", help="fetch only character portraits and weapon base icons")
    mode.add_argument("--include-challenges", action="store_true",
                      help="also fetch missing monster, achievement goal and character recipe icons")
    args = parser.parse_args()
    jobs = sorted(collect_icons(args.source, args.primary_only, args.include_challenges))
    failures = 0
    with ThreadPoolExecutor(max_workers=4) as pool:
        for line, succeeded in pool.map(fetch, jobs):
            print(line, flush=True)
            if not succeeded:
                failures += 1
    return int(failures > 0)


if __name__ == "__main__":
    raise SystemExit(main())
