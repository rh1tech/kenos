# Kenos

A small, fast WebKit browser for macOS 26+, with nothing in the way.

Tabs, an address field, back / forward / reload — and the page. Liquid Glass on the chrome. Reading mode, hide-anything, a built-in ad blocker, floating video, passwords in the macOS keychain, Chrome extensions on WebKit, and quiet updates.

**Requires macOS 26 or later.**

Site: [kenos.rh1.tech](https://kenos.rh1.tech) · Source: [github.com/rh1tech/kenos](https://github.com/rh1tech/kenos) · Support: [support@rh1.tech](mailto:support@rh1.tech)

Website sources: `site/`. Deploy: `./scripts/deploy-site.sh`.

## Build

```bash
swift build
./build.sh                 # → build/Kenos.app (Developer ID when available)
./build.sh release dmg     # + DMG / ZIP / appcast
./build.sh release ship    # + notarise & staple (publisher: Elizaveta Fragner / WL6TS5H5B4)
```

Signing and notarisation use the publisher’s App Store Connect API key and
Developer ID certificate (same layout as the other rh1.tech Mac apps). Do not
commit keys or provision profiles.

Open `build/Kenos.app`, or run the SwiftPM binary from `.build/debug/Kenos`.

## Ad blocking

Uses [uBlock Origin](https://github.com/gorhill/uBlock)’s default lists (EasyList, EasyPrivacy, uBlock filters, …), converted to WebKit content rules (WebKit cannot run uBlock’s engine itself).

- Bundled baseline: `Sources/Kenos/Resources/Shield/ublock.json`
- Updated copies: `~/Library/Application Support/Kenos/Shield/`
- Settings › Privacy → **Update now**, or automatic daily/weekly refresh

Regenerate the shipped baseline:

```bash
python3 scripts/ublock_to_webkit.py
```

| What | Where |
|---|---|
| History, bookmarks, session, hidden elements, prefs | `~/Library/Application Support/Kenos/` |
| Passwords | macOS keychain, labeled `Kenos` |
| Cookies / site data | WebKit’s store for the app |
| Extensions | `~/Library/Application Support/Kenos/Extensions/` |

## Features

- **⌘⇧R** reading mode · **⌘⇧H** hide elements · **⌘⇧P** float video
- **⌘Y** history · **⇧⌘J** downloads · **⇧⌘B** bookmark · **⌘,** settings
- Tabs across the top, along the bottom, or down the left (Settings › Tabs)
- Light / dark / system appearance
- Chrome extensions via WebKit’s `WKWebExtension` (macOS 15.4+ APIs), with shims for APIs WebKit lacks
- Quiet daily update check (Developer ID builds); App Store distribution is a later channel

## Testing

With a probe run (isolated from your real data):

```bash
KENOS_PROBE=1 .build/debug/Kenos &
# enable scripting is automatic in probe world once consented via bench:
./bench --test consent grant
./bench --test open https://example.com
./bench --test wait <id>
./bench --test text <id>
./bench --test close all
```

## License

Copyright © 2026 Mikhail Matveev. Published by Elizaveta Fragner.

MIT — see [LICENSE](LICENSE).
