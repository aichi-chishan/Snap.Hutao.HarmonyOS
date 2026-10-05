#!/usr/bin/env python3
"""Validate/rebuild the bundled affix reference from a pinned local Git blob, without networking."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

COMMIT = 'b3aef3dbe0299e512654bb296930b3b6571fc87f'
BLOB = 'c4e65e91229f84014003703837faddb668a4c3be'
ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, help='Local Snap.Metadata checkout')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    raw = subprocess.check_output(['git', '-C', str(args.source), 'show', f'{COMMIT}:Genshin/CHS/ReliquarySubAffix.json'])
    actual = hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
    if actual != BLOB:
        raise SystemExit(f'Unexpected source blob {actual}')
    rows = json.loads(raw)
    if len(rows) != 350 or len({row['Id'] for row in rows}) != 350:
        raise SystemExit('Unexpected affix identity set')
    target = ROOT / 'entry/src/main/ets/model/ReliquaryAffixReference.ets'
    existing = target.read_text()
    prefix = existing[:existing.index('  static readonly rows:')]
    lines = [f"    [{row['Id']}, {row['Type']}, {json.dumps(row['Value'])}]," for row in rows]
    result = prefix + '  static readonly rows: number[][] = [\n' + '\n'.join(lines) + '\n  ];\n}\n'
    if args.check:
        # JS and JSON allow integer spellings for integral float metadata values.
        import re
        generated_rows = json.loads('[' + ','.join(re.findall(r'^    (\[.*\]),$', existing, re.MULTILINE)) + ']')
        if generated_rows != [[row['Id'], row['Type'], row['Value']] for row in rows]:
            raise SystemExit('Bundled rows differ from the pinned source')
    else:
        target.write_text(result)
    print('PASS: 350 pinned affix identities and raw values')


if __name__ == '__main__':
    main()
