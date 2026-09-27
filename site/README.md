# kenos.rh1.tech

Marketing site plus Support and Privacy (English and Russian). Static HTML,
no build step. Document root is `site/`.

```bash
python3 -m http.server 8000 --directory site
```

## Layout

```
site/
├── index.html · support/ · privacy/ · impressum/
├── ru/…                  Russian counterparts
├── 404.html · robots.txt · sitemap.xml
└── assets/{css,fonts,img,js}
    └── img/shots/   real Kenos window captures (light + dark WebP)
```

## Deploy (rbx1)

Host: `xtreme@rbx1.re-hash.org` (SSH alias `rh1`, sudoer). Cloudflare fronts
nginx; origin vhost reference: `deploy/nginx-kenos-site.conf`.

```bash
./scripts/deploy-site.sh
```

Deploy stamps every `/assets/` URL with a content hash (`?v=…`) so Cloudflare
cannot keep serving yesterday’s CSS/JS after a redesign. The files in `site/`
stay unstamped; only the staged copy on the server gets the query string.

First time on the server (creates web root + installs the vhost):

```bash
./scripts/deploy-site.sh --bootstrap
```

App updates later: put `Kenos.dmg`, `Kenos.zip` and `appcast.json` under
`site/download/` and `site/appcast.json` (or symlink from the build artifacts)
before syncing.
