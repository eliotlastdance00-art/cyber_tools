#!/usr/bin/env python3
"""Build the VoiceReader release ZIP to upload to Gumroad.
Run from anywhere:  python tools/make_release_zip.py
Output: voicereader-pro-<date>.zip in the current working directory.
"""
import shutil
from datetime import date
from pathlib import Path

src = Path(__file__).resolve().parent.parent  # voicereader/
out_name = f'voicereader-pro-{date.today().isoformat()}'
out_path = Path.cwd() / out_name
zip_path = shutil.make_archive(str(out_path), 'zip', src)
print('Created:', zip_path)
print('Upload this file to Gumroad as the product. Customers unzip it and run:')
print('    cd voicereader && python3 -m http.server 8080')
print('then open http://localhost:8080  (or use the hosted app).')
