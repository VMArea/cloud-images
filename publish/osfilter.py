#!/usr/bin/env python3
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def allowed_os():
    with open(os.path.join(HERE, "allowed-os.txt")) as f:
        return {l.strip() for l in f if l.strip() and not l.startswith("#")}


def manifests(outdir):
    out = []
    for fn in sorted(os.listdir(outdir)):
        if not re.search(r"-\d{8}\.json$", fn):
            continue
        p = os.path.join(outdir, fn)
        with open(p) as f:
            m = json.load(f)
        if "file" not in m or "name" not in m:
            continue
        m["_path"] = p
        m["_date"] = re.search(r"-(\d{8})\.json$", fn).group(1)
        out.append(m)
    return out


if __name__ == "__main__":
    outdir = sys.argv[1]
    allow = allowed_os()
    for m in manifests(outdir):
        if m["name"] in allow and os.path.exists(os.path.join(outdir, m["file"])):
            print(m["_path"])
        else:
            print(f"skip {m['file']}: {m['name']} is not redistributable", file=sys.stderr)
