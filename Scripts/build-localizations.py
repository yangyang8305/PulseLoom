#!/usr/bin/env python3
"""Deterministic, local-only localization generation; does not change external resources."""
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]
entries={}
for row in (ROOT/'Scripts/localizations.tsv').read_text().splitlines():
    if not row.strip():continue
    pieces=row.split('|')
    if len(pieces)!=4:raise ValueError(f'Expected four fields: {row}')
    key,*translations=pieces
    if key in entries:raise ValueError('Duplicate localization: '+key)
    entries[key]=translations
for i,lang in enumerate(['en','zh-Hans','ja']):
    text='/* Generated from Scripts/localizations.tsv. */\n'+''.join(f'{json.dumps(k)} = {json.dumps(v[i],ensure_ascii=False)};\n' for k,v in sorted(entries.items()))
    for folder in ['App/Resources','WatchApp/Resources','Widgets/Resources']:
        path=ROOT/folder/(lang+'.lproj');path.mkdir(parents=True,exist_ok=True);(path/'Localizable.strings').write_text(text)
    descriptions=['Choose music to follow its rhythm with haptics. Your music authorization is optional.','选择音乐并跟随节奏生成触感，音乐授权为可选。','音楽に合わせて触覚を使うために曲を選びます。音楽へのアクセスは任意です。']
    path=ROOT/'App/Resources'/(lang+'.lproj')/'InfoPlist.strings'
    path.write_text('"NSAppleMusicUsageDescription" = '+json.dumps(descriptions[i],ensure_ascii=False)+';\n')
print(f'{len(entries)} localization entries × 3 languages generated.')
