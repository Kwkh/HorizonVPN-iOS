#!/usr/bin/env python3
"""Verify bundled public Geo assets; --fetch restores only hash-pinned official bytes."""
import argparse, hashlib, json, urllib.request
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--fetch',action='store_true');args=p.parse_args()
lock=json.loads((root/'Configuration/GeoData.lock.json').read_text())
out=root/'Horizon/Resources/GeoData';out.mkdir(parents=True,exist_ok=True)
for asset in lock['assets']:
 path=out/asset['file']
 if args.fetch and (not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest()!=asset['sha256']):
  url='https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/'+lock['version']+'/'+asset['file']
  with urllib.request.urlopen(url,timeout=30) as response:data=response.read(asset['bytes']+1)
  assert len(data)==asset['bytes'] and hashlib.sha256(data).hexdigest()==asset['sha256'], 'Pinned Geo digest mismatch'
  path.write_bytes(data)
 data=path.read_bytes();assert len(data)==asset['bytes'] and hashlib.sha256(data).hexdigest()==asset['sha256']
 print(asset['file'],len(data),'verified')
manifest=out/'BundledGeo.json'
if args.fetch:
 manifest.write_text(json.dumps(lock,indent=2)+'\n')
 for filename,target in [('LICENSE','GeoData-LICENSE.txt'),('README.md','GeoData-UPSTREAM.md')]:
  url='https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/'+lock['licenseRevision']+'/'+filename
  with urllib.request.urlopen(url,timeout=30) as response:data=response.read(1024*1024)
  (out/target).write_bytes(data)
assert json.loads(manifest.read_text())==lock
assert (out/'GeoData-LICENSE.txt').exists() and (out/'GeoData-UPSTREAM.md').exists()
