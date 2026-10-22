#!/usr/bin/env python3
"""Deterministically sample public-domain Natural Earth land on a unit sphere.
Uses only Python's standard library; no network access or user data.
"""
import hashlib, json, math, struct, zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
archive=ROOT/'Configuration/Geography/ne_50m_land.zip'
lock=json.loads((ROOT/'Configuration/Geography/source.json').read_text())
assert hashlib.sha256(archive.read_bytes()).hexdigest()==lock['sha256']
with zipfile.ZipFile(archive) as z: data=z.read('ne_50m_land.shp')
assert struct.unpack_from('>i',data)[0]==9994
rows=[[] for _ in range(720)]
position=100
while position<len(data):
    size=struct.unpack_from('>i',data,position+4)[0]*2
    record=data[position+8:position+8+size];position+=8+size
    if struct.unpack_from('<i',record)[0]==0:continue
    assert struct.unpack_from('<i',record)[0]==5
    parts,count=struct.unpack_from('<ii',record,36)
    offsets=list(struct.unpack_from('<'+'i'*parts,record,44))+[count]
    coords=[struct.unpack_from('<dd',record,44+parts*4+i*16) for i in range(count)]
    for begin,end in zip(offsets,offsets[1:]):
        ring=coords[begin:end]
        for (x1,y1),(x2,y2) in zip(ring,ring[1:]+ring[:1]):
            if y1==y2:continue
            lo=max(0,math.ceil((min(y1,y2)+90)*4-.5))
            hi=min(720,math.ceil((max(y1,y2)+90)*4-.5))
            for row in range(lo,hi):
                lat=(row+.5)/4-90
                rows[row].append(x1+(lat-y1)*(x2-x1)/(y2-y1))
for row in rows:row.sort()
def land(lon,lat):
    import bisect
    row=rows[min(719,max(0,int((lat+90)*4)))]
    return bisect.bisect_right(row,lon)%2==1
# Known interior points catch coordinate inversion and land/ocean reversal.
for lon,lat in [(20,5),(100,35),(-100,40),(135,-25),(-60,-10)]:assert land(lon,lat)
for lon,lat in [(-140,0),(-30,0),(75,-35)]:assert not land(lon,lat)
points=[]
for i in range(78000):
    y=1-2*(i+.5)/78000
    lat=math.degrees(math.asin(y)); lon=(i*137.50776405003785)%360-180
    if land(lon,lat):
        r=math.sqrt(1-y*y);a=math.radians(lon)
        points.append((r*math.sin(a),y,r*math.cos(a),1.0))
assert 18000<len(points)<29000
output=ROOT/'Horizon/Features/Horizon/Resources/earth-land.bin'
output.write_bytes(b''.join(struct.pack('<4f',*p) for p in points))
print(f'PASS: {len(points)} land particles; unit sphere, geographic control points and source SHA verified')
print('output sha256:',hashlib.sha256(output.read_bytes()).hexdigest())
