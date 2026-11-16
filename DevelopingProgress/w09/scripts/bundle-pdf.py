"""Mechanical local conversion of upstream ESM bundles for ArkWeb's resource URL loader.
No PDF parser changes: keep canonical .mjs files, remove the final export statement,
wrap scope, expose the same exported names. No network or npm needed.
"""
from pathlib import Path
import re,json,hashlib
root=Path(__file__).resolve().parents[1]
p=root/'entry/src/main/resources/rawfile/pdfjs';files=[]
for name,global_name in [('pdf.worker.min.mjs','pdfjsWorker'),('pdf.min.mjs','pdfjsLib')]:
    source=(p/name).read_text(encoding='utf8')
    m=re.search(r'export\{([^{}]+)\};?\s*$',source)
    if not m:raise RuntimeError('Unexpected upstream export format')
    exports=[]
    for part in m[1].split(','):
        pair=part.strip().split(' as ');value=pair[0];key=pair[-1];exports.append(f'{key}:{value}')
    body=source[:m.start()].replace('import.meta.url','globalThis.location.href')
    bundled='(function(){\n'+body+'\nglobalThis.'+global_name+'={'+','.join(exports)+'};\n})();\n'
    out=p/name.replace('.mjs','.js');out.write_text(bundled,encoding='utf8');files.append({'file':out.name,'sha256':hashlib.sha256(out.read_bytes()).hexdigest()})
(root/'PDF_BUNDLE.json').write_text(json.dumps({'upstreamVersion':'6.5.438','conversion':'scripts/bundle-pdf.py','files':files},indent=2),encoding='utf8')
print('Created local classic-scope wrappers; upstream ESM preserved.')
