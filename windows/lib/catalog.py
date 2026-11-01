import datetime
import json
import re
import urllib.parse
import urllib.request

BASE = "https://www.catalog.update.microsoft.com/"
UA = {"User-Agent": "Mozilla/5.0"}


def search(query):
    req = urllib.request.Request(BASE + "Search.aspx?q=" + urllib.parse.quote(query), headers=UA)
    html = urllib.request.urlopen(req, timeout=60).read().decode("utf-8", "replace")
    out = []
    for m in re.finditer(r'<tr id="([0-9a-f-]+)_R\d+"[^>]*>(.*?)</tr>', html, re.S):
        cells = [re.sub(r"<[^>]+>|\s+", " ", c).strip() for c in re.findall(r"<td[^>]*>(.*?)</td>", m.group(2), re.S)]
        if len(cells) < 7:
            continue
        date = datetime.datetime.strptime(cells[4], "%m/%d/%Y").date()
        kb = re.search(r"\((KB\d+)\)", cells[1])
        build = re.search(r"\((\d+\.\d+)\)\s*$", cells[1])
        out.append({"id": m.group(1), "title": cells[1], "product": cells[2], "classification": cells[3], "date": date,
                    "kb": kb.group(1) if kb else None, "build": build.group(1) if build else None})
    return out


def pick(query, title_re, classification="Security Updates"):
    rows = [r for r in search(query) if re.search(title_re, r["title"]) and r["classification"] == classification]
    if not rows:
        return None
    rows.sort(key=lambda r: (r["date"], r["title"]), reverse=True)
    return rows[0]


def download_urls(update_id):
    body = urllib.parse.urlencode({"updateIDs": json.dumps([{"size": 0, "languages": "", "uidInfo": update_id, "updateID": update_id}])}).encode()
    req = urllib.request.Request(BASE + "DownloadDialog.aspx", data=body, headers=UA)
    html = urllib.request.urlopen(req, timeout=60).read().decode("utf-8", "replace")
    return re.findall(r"downloadInformation\[\d+\]\.files\[\d+\]\.url = '([^']+)'", html)
