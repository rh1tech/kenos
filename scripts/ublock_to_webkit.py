#!/usr/bin/env python3
"""
Convert uBlock Origin / EasyList network + cosmetic filters into a Safari /
WKContentRuleList JSON file.

WebKit cannot run uBlock's engine. This keeps the lists uBlock ships by
default and translates what content blockers can express (block URL, hide
element, exceptions). Scriptlets, redirects, and HTML filtering are skipped.

Usage:
  ./scripts/ublock_to_webkit.py [out.json]

Downloads from uBlock's CDN (same sources as gorhill/uBlock assets.json).
"""
from __future__ import annotations

import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "Sources/Kenos/Resources/Shield/ublock.json"

# Default lists enabled in stock uBlock (see assets/assets.json). Unbreak last
# so its @@ exceptions can ignore earlier blocks.
LISTS = [
    ("easylist", "https://ublockorigin.github.io/uAssetsCDN/thirdparties/easylist.txt"),
    ("easyprivacy", "https://ublockorigin.github.io/uAssetsCDN/thirdparties/easyprivacy.txt"),
    ("ublock-filters", "https://ublockorigin.github.io/uAssetsCDN/filters/filters.min.txt"),
    ("ublock-badware", "https://ublockorigin.github.io/uAssetsCDN/filters/badware.min.txt"),
    ("ublock-privacy", "https://ublockorigin.github.io/uAssetsCDN/filters/privacy.min.txt"),
    ("ublock-quick-fixes", "https://ublockorigin.github.io/uAssetsCDN/filters/quick-fixes.min.txt"),
    ("ublock-unbreak", "https://ublockorigin.github.io/uAssetsCDN/filters/unbreak.min.txt"),
]

# Hard Safari / WKWebView ceiling is 50_000; leave headroom.
MAX_RULES = 45_000

RESOURCE = {
    "script": "script",
    "image": "image",
    "stylesheet": "style-sheet",
    "object": "media",
    "xmlhttprequest": "raw",
    "xhr": "raw",
    "ping": "raw",
    "media": "media",
    "font": "font",
    "subdocument": "document",
    "other": "other",
    "websocket": "websocket",
    "ping": "raw",
    "fetch": "fetch",
}


def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "KenosBrowser/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8", "replace")


def escape_regex(s: str) -> str:
    return re.escape(s)


def domain_filter(host: str) -> str:
    # WebKit content blockers reject regex disjunctions (`|`). Do not use
    # `([:/?]|$)` — a host prefix match is enough for resource URLs.
    host = host.lstrip("*.").lower().rstrip(".")
    return rf"^https?://([^/]+\.)?{escape_regex(host)}"


def wildcard_regex(s: str, end_anchor: bool = False) -> str:
    out = []
    for ch in s:
        if ch == "*":
            out.append(".*")
        else:
            out.append(escape_regex(ch))
    body = "".join(out)
    if end_anchor:
        body += "$"
    # WebKit: no alternation.
    if "|" in body:
        return ""
    return body


def path_filter(pattern: str) -> str | None:
    """Turn an Adblock URL pattern into a Safari url-filter, or None if unsupported."""
    p = pattern.strip()
    if not p or p.startswith("@@"):
        return None
    # Drop options
    if "$" in p:
        p = p.split("$", 1)[0]
    # Adblock `|` at end = end-of-URL anchor (not a regex pipe).
    end_anchor = p.endswith("|") and not p.endswith("||")
    if end_anchor:
        p = p[:-1]
    # Skip regex filters /.* /
    if p.startswith("/") and p.endswith("/") and len(p) > 2:
        return None
    # Hostname anchor ||
    if p.startswith("||"):
        rest = p[2:]
        # ||domain^ or ||domain/path
        m = re.match(r"^([a-z0-9.-]+)(\^|/)(.*)$", rest, re.I)
        if not m:
            # ||domain alone
            if re.match(r"^[a-z0-9.-]+$", rest, re.I):
                return domain_filter(rest)
            return None
        host, sep, path = m.group(1), m.group(2), m.group(3)
        if sep == "^" and not path:
            return domain_filter(host)
        # path may contain *
        path = path.rstrip("^")
        path_re = wildcard_regex(path, end_anchor=end_anchor)
        if path_re is None or path_re == "":
            # empty path after strip — domain only
            return domain_filter(host)
        return rf"^https?://([^/]+\.)?{escape_regex(host)}/.*{path_re}"
    # Leading |http
    if p.startswith("|http"):
        body = p[1:]
        if body.endswith("|"):
            body = body[:-1]
            end_anchor = True
        uf = "^" + wildcard_regex(body, end_anchor=end_anchor)
        return uf or None
    # Bare path contains
    if p.startswith("/") or "*" in p or "." in p:
        uf = wildcard_regex(p, end_anchor=end_anchor)
        return uf or None
    return None


def parse_options(opt: str) -> dict:
    out: dict = {
        "third": None,
        "resources": [],
        "domains": [],
        "unless": [],
        "important": False,
    }
    if not opt:
        return out
    for part in opt.split(","):
        part = part.strip().lower()
        if not part:
            continue
        if part in ("third-party", "3p"):
            out["third"] = True
        elif part in ("~third-party", "first-party", "1p"):
            out["third"] = False
        elif part in RESOURCE:
            out["resources"].append(RESOURCE[part])
        elif part.startswith("domain="):
            for d in part[7:].split("|"):
                d = d.strip()
                if not d:
                    continue
                if d.startswith("~"):
                    out["unless"].append(d[1:].lstrip("*."))
                else:
                    out["domains"].append(d.lstrip("*."))
        elif part == "important":
            out["important"] = True
        # skip document/elemhide/popup/mp4/redirect etc.
    return out


def trigger_from(url_filter: str, opts: dict) -> dict | None:
    if not url_filter or "|" in url_filter:
        return None
    t: dict = {"url-filter": url_filter}
    if opts["third"] is True:
        t["load-type"] = ["third-party"]
    elif opts["third"] is False:
        t["load-type"] = ["first-party"]
    if opts["resources"]:
        # unique preserve order; drop types WebKit may reject
        seen = []
        for r in opts["resources"]:
            if r in ("websocket",):  # map away — not universally accepted
                r = "other"
            if r not in seen:
                seen.append(r)
        t["resource-type"] = seen
    # WebKit allows only one of if-domain / unless-domain.
    if opts["domains"] and not opts["unless"]:
        t["if-domain"] = [f"*{d}" if not d.startswith("*") else d for d in opts["domains"][:50]]
    elif opts["unless"] and not opts["domains"]:
        t["unless-domain"] = [f"*{d}" if not d.startswith("*") else d for d in opts["unless"][:50]]
    elif opts["domains"] and opts["unless"]:
        # Prefer allowlisted exclusions over inclusions when both appear.
        t["unless-domain"] = [f"*{d}" if not d.startswith("*") else d for d in opts["unless"][:50]]
    return t


def convert_line(line: str) -> list[dict]:
    line = line.strip()
    if not line or line.startswith("!") or line.startswith("[") or line.startswith("# "):
        return []
    # Cosmetic exceptions / element hiding exceptions — never network rules.
    if "#@#" in line or "#?#" in line or "#$#" in line:
        return []
    # Skip HTML filters, scriptlets, procedural
    if "+js(" in line or ":has(" in line or ":xpath(" in line or "##^" in line:
        return []
    if line.startswith("@@"):
        # Exception → ignore-previous-rules
        body = line[2:]
        opts = parse_options("")
        if "$" in body:
            body, opt = body.split("$", 1)
            opts = parse_options(opt)
        uf = path_filter(body)
        if not uf:
            return []
        trig = trigger_from(uf, opts)
        if not trig:
            return []
        return [{"trigger": trig, "action": {"type": "ignore-previous-rules"}}]

    # Cosmetic: domain##selector or ##selector
    if "##" in line and not line.startswith("@@"):
        if "#@#" in line:  # cosmetic exception — skip (limited support)
            return []
        left, sel = line.split("##", 1)
        sel = sel.strip()
        if not sel or sel.startswith("+js") or ":style(" in sel:
            return []
        # Safari selector length / complexity limits — skip very long / unsupported
        if len(sel) > 512:
            return []
        for bad in (":not(", ":has(", ":is(", ":where(", ":nth-", "::", "+js"):
            if bad in sel:
                return []
        trigger: dict = {"url-filter": ".*"}
        if left:
            domains = [d.lstrip("~*.") for d in left.split(",") if d and not d.startswith("~")]
            if domains:
                trigger["if-domain"] = [f"*{d}" for d in domains[:40]]
            else:
                return []
        return [{"trigger": trigger, "action": {"type": "css-display-none", "selector": sel}}]

    # Network
    opts = parse_options("")
    body = line
    if "$" in line:
        body, opt = line.split("$", 1)
        opts = parse_options(opt)
        # Skip types we can't map well
        bad = {"popup", "csp", "inline-script", "inline-font", "webrtc", "ping"}
        if any(p.strip().lower() in bad for p in opt.split(",")):
            # still allow if also has script/image etc — keep simple: skip pure popup
            parts = {p.strip().lower() for p in opt.split(",")}
            if parts & bad and not (parts & set(RESOURCE)):
                return []
    uf = path_filter(body)
    if not uf:
        return []
    trig = trigger_from(uf, opts)
    if not trig:
        return []
    return [{"trigger": trig, "action": {"type": "block"}}]


def host_rules_from_files() -> list[dict]:
    """High-priority domain blocks from bundled host lists (covers d3ward etc.)."""
    rules: list[dict] = []
    seen: set[str] = set()
    for name in ("d3host.txt", "hosts.txt"):
        path = ROOT / "Sources/Kenos/Resources/Shield" / name
        if not path.exists():
            continue
        for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            # hosts file forms: "0.0.0.0 domain" / "127.0.0.1 domain" / bare domain
            parts = line.split()
            host = parts[-1] if parts[0] in ("0.0.0.0", "127.0.0.1", "::1") else parts[0]
            host = host.lstrip("*.").lower().rstrip(".")
            if not host or host in seen or "/" in host or " " in host:
                continue
            if not re.match(r"^[a-z0-9.-]+\.[a-z]{2,}$", host):
                continue
            seen.add(host)
            uf = domain_filter(host)
            if "|" in uf:
                continue
            rules.append({"trigger": {"url-filter": uf}, "action": {"type": "block"}})
    return rules


def main() -> int:
    blocks: list[dict] = []
    cosmetics: list[dict] = []
    exceptions: list[dict] = []
    stats = {name: 0 for name, _ in LISTS}

    priority = host_rules_from_files()
    stats["hosts"] = len(priority)
    print(f"hosts {len(priority)} priority domain blocks", flush=True)

    for name, url in LISTS:
        print(f"fetch {name}…", flush=True)
        try:
            text = fetch(url)
        except Exception as e:
            print(f"  FAIL {e}", flush=True)
            continue
        n = 0
        for line in text.splitlines():
            for rule in convert_line(line):
                action = rule["action"]["type"]
                if action == "block":
                    blocks.append(rule)
                elif action == "css-display-none":
                    cosmetics.append(rule)
                else:
                    exceptions.append(rule)
                n += 1
        stats[name] = n
        print(f"  {n} rules", flush=True)

    def dedupe(rules: list[dict]) -> list[dict]:
        seen = set()
        out = []
        for r in rules:
            key = json.dumps(r, sort_keys=True)
            if key in seen:
                continue
            seen.add(key)
            out.append(r)
        return out

    # Hosts first — then prefer domain-anchored network blocks over long path snippets.
    priority = dedupe(priority)
    blocks = dedupe(blocks)
    cosmetics = dedupe(cosmetics)
    exceptions = dedupe(exceptions)

    def is_domain_block(r: dict) -> bool:
        uf = r.get("trigger", {}).get("url-filter", "")
        return uf.startswith("^https?://") and "resource-type" not in r.get("trigger", {})

    domain_blocks = [r for r in blocks if is_domain_block(r)]
    other_blocks = [r for r in blocks if not is_domain_block(r)]

    budget = MAX_RULES
    take: list[dict] = []
    for group in (priority, domain_blocks, other_blocks):
        room = budget - len(take)
        if room <= 0:
            break
        take.extend(group[:room])
    # Dedupe again after merge (hosts may overlap EasyList).
    take = dedupe(take)
    room = budget - len(take)
    take_cosmo = cosmetics[: min(len(cosmetics), max(0, int(room * 0.7)))]
    room -= len(take_cosmo)
    take_ex = exceptions[:room]

    rules = take + take_cosmo + take_ex
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(rules, separators=(",", ":")), encoding="utf-8")
    meta = {
        "source": "gorhill/uBlock default lists + hosts",
        "lists": stats,
        "hosts": len(priority),
        "blocks": len(take),
        "cosmetics": len(take_cosmo),
        "exceptions": len(take_ex),
        "total": len(rules),
    }
    OUT.with_suffix(".meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    print(json.dumps(meta, indent=2))
    print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
