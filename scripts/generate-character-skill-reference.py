#!/usr/bin/env python3
"""Rebuild the bundled reference from a pinned local Snap.Metadata checkout (no downloads)."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

COMMIT = 'b3aef3dbe0299e512654bb296930b3b6571fc87f'
ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, help='Local Snap.Metadata repository root')
    parser.add_argument('--check', action='store_true', help='Verify pinned projection; do not write')
    args = parser.parse_args()
    revision = subprocess.check_output(['git', '-C', str(args.source), 'rev-parse', 'HEAD'], text=True).strip()
    if revision != COMMIT:
        raise SystemExit(f'Expected {COMMIT}, got {revision}; review a new source version before updating')
    fixture_path = ROOT / 'tests/fixtures/character-skill-reference.json'
    fixture = json.loads(fixture_path.read_text())
    for expected in fixture['avatars']:
        relative = f"Genshin/CHS/Avatar/{expected['id']}.json"
        raw = subprocess.check_output(['git', '-C', str(args.source), 'show', f'{COMMIT}:{relative}'])
        blob = hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
        avatar = json.loads(raw)
        depot = avatar['SkillDepot']
        combat = [skill for skill in depot['Skills'] if len(skill['Proud']['Parameters']) > 1]
        combat.append(depot['EnergySkill'])
        if len(combat) != 3:
            raise SystemExit(f"Unsupported skill shape: {relative}")
        projected = {
            'id': avatar['Id'], 'sha': blob, 'name': avatar['Name'], 'skillDepotId': depot.get('Id', 0),
            'skills': [{'id': skill['Id'], 'group': skill['GroupId'], 'kind': kind,
                        'name': skill['Name'], 'icon': skill['Icon']}
                       for skill, kind in zip(combat, ('A', 'E', 'Q'))],
            'bonus': int(any(skill['GroupId'] == 3323 for skill in depot['Inherents'])),
            'talents': [{'id': talent['Id'], 'index': talent.get('ExtraLevel', {}).get('Index', 0),
                         'level': talent.get('ExtraLevel', {}).get('Level', 0)} for talent in depot['Talents']],
        }
        if projected != expected:
            raise SystemExit(f'Pinned reference differs: {relative}')
    target = ROOT / 'entry/src/main/ets/model/AvatarSkillReference.ets'
    existing = target.read_text()
    prefix = existing[:existing.index('  static readonly profiles:')]
    lines = []
    quote = lambda value: json.dumps(value, ensure_ascii=False)
    for avatar in fixture['avatars']:
        skills = ', '.join(f"new AvatarSkillReference({s['id']}, {s['group']}, '{s['kind']}', {quote(s['name'])}, '{s['icon']}')"
                           for s in avatar['skills'])
        kinds = {1: 'A', 2: 'E', 9: 'Q'}
        talents = ', '.join(f"new AvatarConstellationReference({t['id']}, '{kinds.get(t['index'], '')}', {t['level']})"
                            for t in avatar['talents'])
        lines.append(f"    new AvatarSkillProfile({avatar['id']}, {quote(avatar['name'])}, [{skills}], [{talents}], {avatar['bonus']}),")
    result = prefix + '  static readonly profiles: AvatarSkillProfile[] = [\n' + '\n'.join(lines) + '\n  ];\n}\n'
    if args.check:
        if existing != result:
            raise SystemExit('Generated ArkTS differs from the pinned fixture')
    else:
        target.write_text(result)
    print(f"PASS: {len(fixture['avatars'])} pinned avatar blobs and generated identity reference")


if __name__ == '__main__':
    main()
