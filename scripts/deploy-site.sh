#!/bin/bash
# Sync site/ to kenos.rh1.tech on rbx1 (SSH host: rh1).
#
#   ./scripts/deploy-site.sh              # rsync + verify through Cloudflare
#   ./scripts/deploy-site.sh --bootstrap  # also create web root + install vhost
#
# nginx lets Cloudflare keep /assets/ for a day. There is no CF purge token for
# rh1.tech, so every /assets/ URL is stamped with a content hash at deploy time
# (repo stays clean). Change a file → URL changes → CF fetches fresh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${KENOS_DEPLOY_HOST:-rh1}"
REMOTE_ROOT=/var/www/kenos-site
VHOST_SRC="$ROOT/deploy/nginx-kenos-site.conf"
VHOST_DST=/etc/nginx/vhosts/kenos.rh1.tech.conf
SITE="$ROOT/site"

BOOTSTRAP=0
for arg in "$@"; do
  case "$arg" in
    --bootstrap) BOOTSTRAP=1 ;;
    -h|--help)
      sed -n '2,10p' "$0"
      exit 0
      ;;
  esac
done

if [ ! -d "$SITE" ]; then
  echo "missing $SITE" >&2
  exit 1
fi

if [ "$BOOTSTRAP" = 1 ]; then
  echo "bootstrap on ${HOST}…"
  ssh "$HOST" "sudo mkdir -p '${REMOTE_ROOT}/download' && sudo chown -R \"\$(whoami):\" '${REMOTE_ROOT}'"
  scp "$VHOST_SRC" "${HOST}:/tmp/kenos.rh1.tech.conf"
  ssh "$HOST" "sudo mv /tmp/kenos.rh1.tech.conf '${VHOST_DST}' && sudo nginx -t && sudo systemctl reload nginx"
  echo "vhost installed: ${VHOST_DST}"
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "${SITE}/." "$STAGE/"

# Stamp /assets/ links; leave the repo untouched.
python3 - "$STAGE" <<'PY'
import hashlib
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
digests: dict[pathlib.Path, str] = {}
broken: list[str] = []
REF = re.compile(r'((?:href|src)=")(/[^"#?]*)((?:\?[^"#]*)?)((?:#[^"]*)?)(")')
SRCSET = re.compile(r'(srcset=")([^"]+)(")')
SRCSET_ITEM = re.compile(r'(/assets/[^,\s]+)(\s+\d+[wx])?')


def digest(path: pathlib.Path) -> str:
    if path not in digests:
        digests[path] = hashlib.sha256(path.read_bytes()).hexdigest()[:10]
    return digests[path]


def stamp_path(target: str):
    path = root / target.lstrip("/")
    if target.endswith("/"):
        path = path / "index.html"
    if not path.exists():
        broken.append(target)
        return None
    if not target.startswith("/assets/"):
        return target
    return f"{target}?v={digest(path)}"


for page in sorted(root.rglob("*.html")):
    text = page.read_text()

    def stamp_ref(match: re.Match[str]) -> str:
        head, target, _query, fragment, tail = match.groups()
        stamped = stamp_path(target)
        if stamped is None:
            broken.append(f"{page.relative_to(root)} -> {target}")
            return match.group(0)
        return f"{head}{stamped}{fragment}{tail}"

    def stamp_srcset(match: re.Match[str]) -> str:
        head, value, tail = match.groups()

        def one(m: re.Match[str]) -> str:
            target, dens = m.group(1), m.group(2) or ""
            stamped = stamp_path(target)
            if stamped is None:
                broken.append(f"{page.relative_to(root)} srcset -> {target}")
                return m.group(0)
            return f"{stamped}{dens}"

        return f"{head}{SRCSET_ITEM.sub(one, value)}{tail}"

    stamped = REF.sub(stamp_ref, text)
    stamped = SRCSET.sub(stamp_srcset, stamped)
    if stamped != text:
        page.write_text(stamped)

if broken:
    print("broken links:", *sorted(set(broken)), sep="\n  ")
    sys.exit(1)
print(f"links ok, {len(digests)} assets stamped")
PY

chmod -R a+rX "$STAGE"

echo "rsync → ${HOST}:${REMOTE_ROOT}"
rsync -a --delete \
  --exclude 'README.md' \
  --exclude '.DS_Store' \
  "${STAGE}/" "${HOST}:${REMOTE_ROOT}/"

echo "verify through Cloudflare…"
fail=0
home=""
for _ in $(seq 1 8); do
  home="$(curl -fsS -m 12 https://kenos.rh1.tech/ || true)"
  case "$home" in
    *"<title>"*) break ;;
  esac
  sleep 2
done
case "$home" in
  *"<title>"*) echo "OK    /" ;;
  *) echo "FAIL  /"; fail=1 ;;
esac

css_href="$(printf '%s' "$home" | sed -n 's/.*href="\(\/assets\/css\/site\.css[^"]*\)".*/\1/p' | head -1)"
if [ -z "$css_href" ]; then
  echo "FAIL  could not find site.css link in /"
  fail=1
else
  hdr="$(curl -sI -m 12 "https://kenos.rh1.tech${css_href}")"
  status="$(printf '%s' "$hdr" | awk 'NR==1 {print $2}')"
  cf="$(printf '%s' "$hdr" | awk -F': ' 'tolower($1)=="cf-cache-status" {print $2}' | tr -d '\r')"
  if [ "$status" = "200" ]; then
    echo "OK    ${css_href} (cf-cache-status: ${cf:-?})"
  else
    echo "FAIL  ${css_href} → HTTP ${status}"
    fail=1
  fi
fi

for path in /support/ /privacy/ /ru/ /ru/support/ /ru/privacy/ /impressum/; do
  ok=""
  for _ in $(seq 1 8); do
    if curl -fsS -m 12 "https://kenos.rh1.tech${path}" | grep -q '<title>'; then
      ok=1
      break
    fi
    sleep 2
  done
  if [ -n "$ok" ]; then
    echo "OK    ${path}"
  else
    echo "FAIL  ${path}"
    fail=1
  fi
done
code=$(curl -s -o /dev/null -w '%{http_code}' -m 12 https://kenos.rh1.tech/__missing__)
if [ "$code" = "404" ]; then
  echo "OK    404 handler"
else
  echo "FAIL  404 handler returned ${code}"
  fail=1
fi
exit "$fail"
