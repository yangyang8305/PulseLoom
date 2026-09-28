"""Rebuild the self-contained HTML. Python 3, no external dependencies."""
from pathlib import Path
import argparse
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser()
p.add_argument('--output',type=Path,default=root/'index.html')
a=p.parse_args()
html=(root/'source/shell.html').read_text(encoding='utf-8')
js=(root/'source/app.js').read_text(encoding='utf-8').replace('/*HAPTIC_UI*/',(root/'source/haptic-ui.js').read_text(encoding='utf-8')).replace('/*SIMPLE_UI*/',(root/'source/simple-ui.js').read_text(encoding='utf-8'))
html=html.replace('/*CSS*/',(root/'source/style.css').read_text(encoding='utf-8')+'\n'+(root/'source/simple.css').read_text(encoding='utf-8')).replace('/*JS*/',js)
a.output.parent.mkdir(parents=True,exist_ok=True)
a.output.write_text(html,encoding='utf-8')
print(f'Built {a.output.name}: {len(html.encode())} bytes')
