from pathlib import Path
import hashlib,json,os,stat,sys,zipfile,zlib
root=Path(sys.argv[1]).resolve()
parts={'clt-part-00':'2cb88715aa489620da78bd664660af97fc3b645320e998ae4fedd33e8b2c736d','clt-part-01':'5f44978744f1c3d8ef82175963fb0087a7e831ac48f5b7cbe36668b8b3e41838'}
sizes={'clt-part-00':1992294400,'clt-part-01':355587885}
for name,expected in parts.items():
    if (root/'downloads'/name).stat().st_size!=sizes[name]:raise RuntimeError('Unexpected size '+name)
    with (root/'downloads'/name).open('rb') as f: actual=hashlib.file_digest(f,'sha256').hexdigest()
    if actual!=expected:raise RuntimeError('SHA-256 mismatch '+name)
    print(name+' SHA-256 verified '+actual,flush=True)
(root/'evidence').mkdir(exist_ok=False)
zip_path=root/'downloads/clt.zip';combined=hashlib.sha256()
with zip_path.open('xb') as output:
    for name in parts:
        with (root/'downloads'/name).open('rb') as f:
            while chunk:=f.read(4*1024*1024):combined.update(chunk);output.write(chunk)
combined_sha=combined.hexdigest()
with zip_path.open('rb') as f:stored_sha=hashlib.file_digest(f,'sha256').hexdigest()
if stored_sha!=combined_sha:raise RuntimeError('Stored ZIP differs from verified ordered source parts')
receipt={'parts':parts,'combined_sha256':combined_sha,'combined_hash_source':'derived from pinned verified parts in order 00 then 01; stored ZIP independently rehashed','zip_bytes':zip_path.stat().st_size}
(root/'evidence/archive-hashes.json').write_text(json.dumps(receipt,indent=2)+'\n')
print('Combined derived and stored SHA-256 '+combined_sha,flush=True)
if combined_sha != '58da7359019e9360a8bb82da0cd1d3b3b26fedc338379f257849f2162e3ac1fc':
    raise RuntimeError('Combined ZIP differs from the previously verified release')
with zipfile.ZipFile(zip_path) as zf:
    names=set()
    for info in zf.infolist():
        p=Path(info.filename);mode=info.external_attr>>16
        if p.is_absolute() or '..' in p.parts or info.filename in names:raise RuntimeError('Unsafe/duplicate ZIP path '+info.filename)
        names.add(info.filename)
        if info.is_dir():continue
        if stat.S_ISLNK(mode):
            text=zf.read(info).decode('utf-8');target=root/'clt'/p
            if Path(text).is_absolute() or not (target.parent/text).resolve().is_relative_to((root/'clt').resolve()):raise RuntimeError('Unsafe ZIP link '+info.filename)
        elif stat.S_IFMT(mode) not in (0,stat.S_IFREG):raise RuntimeError('Unexpected ZIP file type '+info.filename)
    print('Safe archive entry preflight passed; testing ZIP CRC before extraction',flush=True)
    bad=zf.testzip()
    if bad:raise RuntimeError('Archive CRC failure '+bad)
    print('All ZIP CRC passed before extraction',flush=True)
dest=root/'clt';dest.mkdir(exist_ok=False);links=[];files=0;total=0
with zipfile.ZipFile(zip_path) as zf:
    for info in zf.infolist():
        p=Path(info.filename)
        if p.is_absolute() or '..' in p.parts:raise RuntimeError('Unsafe ZIP path '+info.filename)
        target=dest/p;mode=info.external_attr>>16
        if info.is_dir():target.mkdir(parents=True,exist_ok=True);continue
        target.parent.mkdir(parents=True,exist_ok=True)
        if stat.S_ISLNK(mode):
            text=zf.read(info).decode('utf-8')
            if Path(text).is_absolute() or not (target.parent/text).resolve().is_relative_to(dest.resolve()):raise RuntimeError('Unsafe ZIP link '+info.filename)
            links.append((target,text));continue
        if stat.S_IFMT(mode) not in (0,stat.S_IFREG):raise RuntimeError('Unexpected ZIP file type '+info.filename)
        with zf.open(info) as f,target.open('xb') as output:
            while chunk:=f.read(1024*1024):output.write(chunk)
        if mode:target.chmod(stat.S_IMODE(mode))
        files+=1;total+=info.file_size
        if files%10000==0:print(f'Extracted {files} regular files',flush=True)
    for target,text in links:target.symlink_to(text)
    verified=0
    for info in zf.infolist():
        if info.is_dir():continue
        target=dest/info.filename
        if target.is_symlink():
            crc=zlib.crc32(os.readlink(target).encode())&0xffffffff
            if not target.resolve().is_relative_to(dest.resolve()):raise RuntimeError('Resolved link outside root '+str(target))
            if not target.exists():raise RuntimeError('Broken ZIP link '+str(target))
        else:
            crc=0
            with target.open('rb') as f:
                while chunk:=f.read(1024*1024):crc=zlib.crc32(chunk,crc)
            crc &= 0xffffffff
        if crc!=info.CRC:raise RuntimeError('CRC mismatch '+info.filename)
        verified+=1
summary={**receipt,'regular_files':files,'symlinks':len(links),'crc_verified_entries':verified,'uncompressed_regular_bytes':total,'toolchain_executed':False}
(root/'evidence/extraction-verification.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2),flush=True)
