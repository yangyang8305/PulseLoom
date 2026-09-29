#!/usr/bin/env python3
"""Export actual XCResult attachments and build a local, ordered screenshot index.
Accessibility findings are diagnostic data, never translated into a clean audit.
"""
import glob, html, json, os, pathlib, subprocess, sys
root = pathlib.Path(__file__).resolve().parents[1]
pattern = sys.argv[1] if len(sys.argv)>1 else 'Artifacts/UITests-*.xcresult'
out = root / (sys.argv[2] if len(sys.argv)>2 else 'Artifacts/UserFlows')
out.mkdir(parents=True, exist_ok=True)
bundles = sorted(glob.glob(str(root / pattern)))
if not bundles: raise SystemExit('No XCResult bundle: user flows were not verified')
records=[]; errors=[]
for i, bundle in enumerate(bundles):
    folder=out/f'result-{i}'; folder.mkdir(exist_ok=True)
    for command, name in [('summary','summary.json'),('tests','tests.json')]:
        r=subprocess.run(['xcrun','xcresulttool','get','test-results',command,'--path',bundle],capture_output=True,text=True)
        (folder/name).write_text(r.stdout or r.stderr)
        if r.returncode: errors.append(f'{command}: {r.stderr}')
    r=subprocess.run(['xcrun','xcresulttool','export','attachments','--path',bundle,'--output-path',str(folder/'attachments')],capture_output=True,text=True)
    (folder/'export.log').write_text(r.stdout+r.stderr)
    if r.returncode: errors.append(r.stderr)
    manifest=folder/'attachments/manifest.json'
    if manifest.exists():
        def walk(value, test=''):
            if isinstance(value,list):
                for v in value: walk(v,test)
            elif isinstance(value,dict):
                test=value.get('testName', value.get('testIdentifier',test))
                exported=value.get('exportedFileName')
                if exported:
                    f=folder/'attachments'/exported
                    label=value.get('suggestedHumanReadableName',value.get('name',exported))
                    records.append({'test':test,'name':label,'path':str(f.relative_to(out))})
                for k,v in value.items():
                    if isinstance(v,(dict,list)): walk(v,test)
        walk(json.loads(manifest.read_text()))
    else: errors.append('Attachment manifest missing: '+str(manifest))
records.sort(key=lambda x:(x['test'],x['name']))
audits=[]
for item in records:
    path=out/item['path']
    if 'ACCESSIBILITY-' in item['name'] and path.exists():
        try: audits.append(json.loads(path.read_text()))
        except (ValueError,UnicodeError): errors.append('Unreadable accessibility attachment: '+str(path))
report={'commit':os.environ.get('GITHUB_SHA'),'run':os.environ.get('GITHUB_RUN_ID'),
        'attachments':records,'accessibility_reports':audits,
        'accessibility_status':'issues_detected' if any(a.get('issue_count',0) for a in audits) else 'no_issues_reported' if audits else 'not_executed',
        'export_errors':errors,'physical_haptics':'not_verified','translation_human_review':'not_performed'}
(out/'index.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
lines=['# Simulator 用户流程截图索引','',f"提交：`{report['commit']}`",'',
       '截图来自实际 XCTest 附件；测试结果见各 result 的 summary.json/tests.json。无障碍审查是问题采集，issues_detected 不表示通过。真机触觉与人工翻译未验收。','']
parts=['<!doctype html><meta charset="utf-8"><title>PulseLoom 用户流程证据</title><style>body{font:16px system-ui;max-width:1100px;margin:32px auto;padding:16px}img{max-width:360px;height:auto}figure{display:inline-block;vertical-align:top;margin:16px}pre{white-space:pre-wrap}a{overflow-wrap:anywhere}</style>', '<h1>PulseLoom 模拟器用户流程</h1>', '<pre>'+html.escape(json.dumps({k:v for k,v in report.items() if k not in ('attachments','accessibility_reports')},ensure_ascii=False,indent=2))+'</pre>']
for item in records:
    if 'FLOW-' not in item['name'] and 'ACCESSIBILITY-' not in item['name']: continue
    label=item['test']+' / '+item['name']; p=item['path']
    lines.append(f'- [{label}]({p})')
    parts.append('<figure><figcaption>'+html.escape(label)+'</figcaption><a href="'+html.escape(p,quote=True)+'">')
    if pathlib.Path(p).suffix.lower() in ('.png','.jpg','.jpeg','.heic'): parts.append('<img loading="lazy" src="'+html.escape(p,quote=True)+'">')
    else: parts.append('查看原始审查记录')
    parts.append('</a></figure>')
(out/'INDEX.md').write_text('\n'.join(lines)+'\n')
(out/'index.html').write_text('\n'.join(parts))
print(json.dumps({'attachments':len(records),'audits':len(audits),'errors':errors},ensure_ascii=False))
if errors: raise SystemExit(1)
