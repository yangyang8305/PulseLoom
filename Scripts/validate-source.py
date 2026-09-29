#!/usr/bin/env python3
"""Structural/source checks, not an Apple SDK build or a device acceptance test."""
import argparse
import hashlib
import json
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]

# Literal Swift calls supported by this checker. Computed keys still need manual
# review; named tables must not be silently treated as Localizable.strings.
def localized_references(text):
    expression = re.compile(
        r'\b(T|NSLocalizedString)\(\s*"([A-Za-z0-9_.-]+)"'
        r'(?:\s*,\s*tableName\s*:\s*(?:"([^"\n]*)"|(nil)))?')
    for match in expression.finditer(text):
        function, key, table, _ = match.groups()
        if key.endswith('.'):
            continue  # Existing dynamic prefix checks remain outside static scope.
        suffix = text[match.end():]
        if function == 'NSLocalizedString' and re.match(r'\s*,\s*tableName\s*:', suffix):
            raise ValueError('Nonliteral localization table for ' + key)
        yield (table or 'Localizable') if function == 'NSLocalizedString' else 'Localizable', key


def read_strings(path):
    text = path.read_text()
    matches = re.findall(r'("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*");', text)
    parsed = {json.loads(k): json.loads(v) for k, v in matches}
    if len(parsed) != len(matches):
        raise ValueError('Duplicate localization key in ' + str(path))
    return parsed


def localization_failures(text, resources):
    failures = []
    for table, key in sorted(set(localized_references(text))):
        if not re.fullmatch(r'[A-Za-z0-9_.-]+', table):
            failures.append('Invalid literal table ' + table)
            continue
        for language in ['en', 'zh-Hans', 'ja']:
            path = resources / (language + '.lproj') / (table + '.strings')
            try:
                values = read_strings(path)
                if key not in values or not values[key]:
                    failures.append(f'{language}/{table}.strings missing key {key}')
            except (OSError, ValueError) as error:
                failures.append(f'{language}/{table}.strings: {error}')
    return failures

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--no-swift-parse', action='store_true')
    args = parser.parse_args()
    passed, failures = [], []
    def check(name, condition):
        (passed if condition else failures).append(name)
    native = sorted(p for base in ['App','WatchApp','Widgets','UITests','ServiceTests'] for p in (ROOT/base).rglob('*.swift'))
    core = sorted((ROOT/'Packages/PulseLoomCore/Sources').rglob('*.swift'))
    tests = sorted((ROOT/'Packages/PulseLoomCore/Tests').rglob('*.swift'))
    approval = json.loads((ROOT/'Reference/APPROVAL.json').read_text())
    check('Approved v0.6 reference preserved', hashlib.sha256((ROOT/'Reference/v0.6/index.html').read_bytes()).hexdigest() == approval['sha256'])
    manifest = json.loads((ROOT/'Config/project-manifest.json').read_text())
    check('All native Swift files are in generated project manifest', set(manifest['sourceFiles']) == {str(p.relative_to(ROOT)) for p in native})
    check('Four product/UI targets plus native service test target', len(manifest['targets']) == 5)
    pbx = (ROOT/'PulseLoom.xcodeproj/project.pbxproj').read_text()
    check('Native source references exist in project', all(str(p.relative_to(ROOT)) in pbx for p in native))
    for p in list((ROOT/'Config').glob('*.plist')) + list((ROOT/'Config').glob('*.entitlements')) + [ROOT/b/'Resources/PrivacyInfo.xcprivacy' for b in ['App','WatchApp','Widgets']]:
        try: plistlib.loads(p.read_bytes()); check('plist '+str(p.relative_to(ROOT)),True)
        except Exception as e: check('plist '+str(p.relative_to(ROOT))+': '+str(e),False)
    for p in (ROOT/'PulseLoom.xcodeproj').rglob('*.xcscheme'):
        ET.parse(p)
        check('scheme '+p.name, True)
    for base in ['App','WatchApp','Widgets','Packages/PulseLoomCore/Sources','Config']:
        for p in (ROOT/base).rglob('*.json'):
            try: json.loads(p.read_bytes()); check('json '+str(p.relative_to(ROOT)),True)
            except Exception as e: check('json '+str(p.relative_to(ROOT))+': '+str(e),False)
    entries = {}
    for line in (ROOT/'Scripts/localizations.tsv').read_text().splitlines():
        if not line.strip(): continue
        values = line.split('|')
        check('unique locale key '+values[0],len(values)==4 and values[0] not in entries)
        if len(values)==4: entries[values[0]]=values[1:]
    for language,i in [('en',0),('zh-Hans',1),('ja',2)]:
        for target in ['App','WatchApp','Widgets']:
            text = (ROOT/target/'Resources'/f'{language}.lproj/Localizable.strings').read_text()
            matches = re.findall(r'("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*");',text)
            parsed = {json.loads(k):json.loads(v) for k,v in matches}
            check(f'All translations {target}/{language}', parsed=={k:v[i] for k,v in entries.items()})
    for key,values in entries.items():
        fmt = [sorted(re.findall(r'%(?:[0-9]+\$)?(?:\.[0-9]+)?(?:ld|lu|lld|llu|d|u|f|@|s)',s)) for s in values]
        check('format placeholders '+key,fmt[0]==fmt[1]==fmt[2])
    for p in native:
        target = p.relative_to(ROOT).parts[0]
        if target in ['UITests', 'ServiceTests']:
            target = 'App'  # Hosted tests use the application bundle.
        try:
            missing = localization_failures(p.read_text(), ROOT/target/'Resources')
            check('literal localization tables '+str(p.relative_to(ROOT)), not missing)
            failures.extend(str(p.relative_to(ROOT))+': '+message for message in missing)
        except ValueError as error:
            check('literal localization tables '+str(p.relative_to(ROOT))+': '+str(error), False)
    # This compiler error can survive frontend parsing: one property wrapper on multiple bindings.
    for p in native:
        for line in p.read_text().splitlines():
            if re.search(r'@(?:State|StateObject|Published|AppStorage)\b.*\bvar\s',line):
                remainder=line.split('=',1)[-1]
                check('property wrapper single binding '+str(p.relative_to(ROOT))+':'+line.strip(),not re.search(r',\s*\w+\s*=',remainder))
        check('no production prototype unlock '+p.name, p.is_relative_to(ROOT/'ServiceTests') or not re.search(r'\b(?:isPro|pro)\s*=\s*true\b',p.read_text()))
        check('no pasted private token '+p.name,not re.search(r'github_pat_[A-Za-z0-9_]{30,}|ghp_[A-Za-z0-9]{30,}|-----BEGIN (?:RSA |EC )?PRIVATE KEY-----',p.read_text()))
    check('Four primary tabs in RootView', (ROOT/'App/Application/PulseLoomApp.swift').read_text().count('.tabItem')==4)
    parseCount=0
    if not args.no_swift_parse and shutil.which('swiftc'):
        for p in native+core+tests:
            result=subprocess.run(['swiftc','-frontend','-parse',str(p)],capture_output=True,text=True)
            check('Swift syntax '+str(p.relative_to(ROOT)),result.returncode==0)
            if result.returncode: print(result.stderr,file=sys.stderr)
            parseCount+=1
    result={'checks_passed':len(passed),'checks_failed':len(failures),'native_swift_files':len(native),'core_swift_files':len(core),'localization_keys':len(entries),'swift_syntax_files':parseCount,'apple_sdk_build':'NOT RUN by this checker','failures':failures}
    print(json.dumps(result,ensure_ascii=False,indent=2))
    if failures: return 1
    return 0
if __name__=='__main__':sys.exit(main())
