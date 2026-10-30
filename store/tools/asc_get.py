#!/usr/bin/env python3
"""Read-only GET against ASC API. Usage: asc_get.py /v1/path?query"""
import json, sys, urllib.request, importlib.util, os
spec = importlib.util.spec_from_file_location("asc", os.path.expanduser("~/.tomo/workspace/tmp/lf/asc.py"))
asc = importlib.util.module_from_spec(spec); spec.loader.exec_module(asc)
path = sys.argv[1]
req = urllib.request.Request("https://api.appstoreconnect.apple.com" + path, headers={"Authorization": f"Bearer {asc.token()}"})
try:
    with urllib.request.urlopen(req, timeout=30) as r: print(json.dumps(json.load(r), indent=1, ensure_ascii=False))
except urllib.error.HTTPError as e: print("HTTP", e.code, e.read().decode()[:800])
