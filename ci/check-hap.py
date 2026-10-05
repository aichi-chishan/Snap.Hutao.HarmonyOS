"""Fail closed on absent, corrupt or incorrectly targeted unsigned HAP output."""
from pathlib import Path
import hashlib,json,sys,zipfile
hap=Path(sys.argv[1])
if not hap.is_file() or hap.stat().st_size == 0:
    raise SystemExit('Expected nonempty unsigned HAP is missing')
with zipfile.ZipFile(hap) as archive:
    bad=archive.testzip()
    if bad:raise SystemExit('HAP CRC failure: '+bad)
    manifest=json.loads(archive.read('module.json'))
app=manifest['app'];module=manifest['module']
if (app.get('minAPIVersion'),app.get('targetAPIVersion'),app.get('apiReleaseType')) != (60101024,260000026,'Release'):
    raise SystemExit('Unexpected packaged API compatibility')
if set(module.get('deviceTypes',[])) != {'phone','tablet','2in1'}:
    raise SystemExit('Unexpected packaged device types')
with hap.open('rb') as stream:sha=hashlib.file_digest(stream,'sha256').hexdigest()
print(json.dumps({'bytes':hap.stat().st_size,'sha256':sha,'app':app,'module':module},indent=2))
