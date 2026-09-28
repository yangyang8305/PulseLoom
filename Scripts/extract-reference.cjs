const fs=require('fs'),vm=require('vm'),path=require('path');
const root=path.resolve(__dirname,'..'),s=fs.readFileSync(root+'/Reference/v0.6/source/app.js','utf8');
const a=s.slice(s.indexOf('const baseSeg='),s.indexOf('const SCREENS='));
const b=s.slice(s.indexOf('const THEMES='),s.indexOf('const systemAppearance='));
const out=vm.runInNewContext(a+b+';JSON.stringify({presets:PRESETS,themes:THEMES,dark:DARK_PALETTES})');
fs.writeFileSync(root+'/Reference/catalog-extracted.json',out);
