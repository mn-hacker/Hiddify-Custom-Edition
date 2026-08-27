<div align="center">

<img src="assets/watashi-banner.svg?v=3" alt="Watashi Manager" width="880">

[![Release](https://img.shields.io/github/v/release/mn-hacker/Hiddify-Custom-Edition?style=for-the-badge&color=7c3aed&label=RELEASE)](https://github.com/mn-hacker/Hiddify-Custom-Edition/releases)
[![Last commit](https://img.shields.io/github/last-commit/mn-hacker/Hiddify-Custom-Edition?style=for-the-badge&color=f59e0b&label=LAST%20COMMIT)](https://github.com/mn-hacker/Hiddify-Custom-Edition/commits)
[![Stars](https://img.shields.io/github/stars/mn-hacker/Hiddify-Custom-Edition?style=for-the-badge&color=22d3ee)](https://github.com/mn-hacker/Hiddify-Custom-Edition/stargazers)
[![License](https://img.shields.io/badge/LICENSE-GPL--3.0-10b981?style=for-the-badge)](LICENSE)

[![Xray](https://img.shields.io/badge/Xray--core-26.2.2-3b82f6?style=for-the-badge)](https://github.com/XTLS/Xray-core)
[![sing-box](https://img.shields.io/badge/sing--box-1.12.19-8b5cf6?style=for-the-badge)](https://github.com/SagerNet/sing-box)
[![Telegram](https://img.shields.io/badge/TELEGRAM-Watashi__Manager-229ED9?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/Watashi_Manager)

**English** · [فارسی](README_fa.md)

</div>

---

## Watashi Manager

**Watashi Manager** is a self-hosted platform for running a proxy service as a product, not as a script collection. One command turns a bare server into a full stack: multi-protocol cores, TLS and domain routing, per-user quotas, tunnels, monitoring, Telegram automation, and a subscription page your customers actually enjoy opening.

What separates Watashi from the usual panel is that **everything a human touches has been rebuilt** — the admin console, the customer page, the motion, the typography, the bilingual behaviour — on top of an engine that is designed to bring itself back up when a server has a bad day.

<table>
<tr><td width="210"><b>Watashi Theme</b></td><td>One design system across every page: living mark, shared custom cursor, overlay scrollbar, floating toasts, glass cards, full Persian/English parity with correct RTL and LTR on every single line.</td></tr>
<tr><td><b>Living Core</b></td><td>The brand mark is animated by design — a rotating hex cage, a breathing core and a three-channel <code>W</code> that glitches on a five second beat. Pure vector, under 3 KB, also used as the browser favicon.</td></tr>
<tr><td><b>Watashi Link</b></td><td>The customer-facing subscription page: four config families, QR that can be copied <i>as an image</i>, per-platform setup guides, usage ring, expiry in plain words, instant language and theme switch.</td></tr>
<tr><td><b>Self-Heal Guard</b></td><td>A watchdog that notices a service which quietly died and brings it back before anybody opens a ticket.</td></tr>
<tr><td><b>Restart Orchestrator</b></td><td>Restarts follow dependency order and wait for Redis and MariaDB to be genuinely healthy, so one stuck unit can no longer take the whole stack down with a 503.</td></tr>
<tr><td><b>Signal</b></td><td>Telegram automation that speaks for you: expiry warnings, 80% quota warnings, quota-finished notices — translated, not machine-dumped.</td></tr>
<tr><td><b>Sentinel</b></td><td>Advanced monitoring, per-user activity log, optional access log, device and concurrency limits, server-wide ad blocking.</td></tr>
<tr><td><b>Tunnel Studio</b></td><td>Tunnel management with Rathole v2 as a first-class citizen, ECH inside the TLS tricks, changeable Hysteria port, fixed XHTTP and WireGuard configs.</td></tr>
</table>

> [!TIP]
> Every capability above is already shipping. The section below is what landed in the current generation, and the roadmap further down is what is being built next.

---
## What landed in this generation

<details open>
<summary><b>Watashi Theme — one design language for the whole product</b></summary>

- A **shared cursor and overlay scrollbar** engine used by every page, admin and customer alike. The scrollbar is a real DOM element, so dragging it never loses the pointer and the native system cursor is never revealed.
- **Floating toasts** replace browser dialogs. No `alert`, no `confirm`, no native tooltip anywhere in the product.
- **Glass cards with fixed geometry** — a long value or a long name can no longer stretch a card and break the grid.
- **True bilingual layout**: Persian and English are both first-class. Direction-aware CSS logical properties everywhere, Latin numerals in every language, protocol names kept in Latin, and instant language switching without losing the page you were on.
- **Dark and light skins** remembered per visitor.

</details>

<details open>
<summary><b>Living Core — the mark that proves the panel is alive</b></summary>

- Rotating outer cage, counter-rotating inner cage, breathing core, and a `W` split into cyan / magenta / white channels that tear apart for a few frames every five seconds.
- Rendered as **pure vector animation** — no image files, no JavaScript, under 3 KB — and reused as the browser favicon, so even the tab is branded.
- Present in the admin sidebar, on the top bar of the customer page and in its footer, at three different sizes with per-size detail.
- Honours `prefers-reduced-motion`: the mark stays complete and readable, it simply stops moving.

</details>

<details open>
<summary><b>Watashi Link — the page your customers open</b></summary>

- Four config families as separate cards: **Clash / Meta**, **Sing-Box**, **V2Ray / Xray**, **WireGuard** — each with copy, QR and download in one reach.
- The QR can be **copied as an image**, not only scanned.
- **Per-platform setup guides** for Android, iOS, Windows, macOS and Linux, each pointing at the right client for that platform.
- Account panel with a **usage ring**, remaining volume, days left written in human words, reset rhythm, last-connection details, country and network.
- Admin-controlled content: which cards appear, which apps are offered, the branding line, the support and bot links — with the sections collapsing gracefully when nothing is configured.

</details>

<details>
<summary><b>Operations console — rebuilt admin pages</b></summary>

- **Restart page** with a live service table that reports what each unit is actually doing, instead of a spinner and a guess.
- **Action log** rendered as readable output — no raw CSS, no raw JSON, no leaking ANSI markup.
- **Usage counter** and **Reality probe** as first-class cards with real status, real icons and translated results.
- Copy buttons that genuinely copy, with a translated confirmation toast.

</details>

<details>
<summary><b>Reliability engine</b></summary>

- **Self-Heal Guard** brings a silently dead service back on its own.
- **Restart Orchestrator** waits for Redis and MariaDB to become truly healthy before touching panel units, and follows dependency order after that.
- System log rotation and clearing repaired, so a full disk no longer becomes an outage.

> [!WARNING]
> Self-healing covers accidental service death. It is not a substitute for fixing a broken config or a failing server.

</details>

<details>
<summary><b>Cores, protocols and network</b></summary>

- **Xray-core `26.2.2`** and **sing-box `1.12.19`**, both far ahead of the versions common panels still ship.
- Telegram proxy Go library rebuilt and its crash fixed.
- **Rathole v2** tunnels, **ECH** under the TLS tricks, changeable **Hysteria** port.
- WARP installation and the wrong-server-IP display fixed, XHTTP and WireGuard config bugs fixed, SpeedTest on the customer page fixed.

</details>

---

## Roadmap

The next milestones, in the order they are being built.

**`Watashi identity`** — the service layer becomes ours
- [ ] Rename every unit from the inherited `hiddify-*` names to **`watashi-*`**, with aliases kept so existing installs keep working.
- [ ] Panel, installer, updater, status and menu scripts all speaking the same name.

**`Link Studio`** — the customer page becomes yours
- [ ] An admin page to design the customer page without touching code: brand line, which config cards appear, which apps are offered per platform, support and bot links, section toggles, default skin and language.
- [ ] **Multiple selectable templates** for the customer page, so a reseller can pick a look per brand.
- [ ] Per-plan and per-user presentation, so a premium plan can look premium.

**`Console`** — the rest of the admin pages in Watashi Theme
- [ ] Backup, Domains, Proxies, Settings and Tunnel pages redesigned to match.
- [ ] A theme guard so a panel update can never drop the product back to the inherited look.

**`Pulse`** — the panel reacts to its own health
- [ ] The living mark bound to real service health: calm when everything is green, warm when a unit is struggling, red when something is down.
- [ ] Health history and incident timeline on the dashboard.

**`Reach`**
- [ ] Russian and Chinese translations at the same quality bar as Persian and English.
- [ ] Still-image and app-icon variants of the mark for stores and social cards.
- [ ] Continuous core updates as Xray, sing-box and HAProxy move.

---
## Install

| Channel | Command |
| :-- | :-- |
| **Stable** | <code>bash <(curl -Ls https://raw.githubusercontent.com/mn-hacker/Hiddify-Custom-Edition/main/common/download.sh)</code> |
| **Beta** | <code>bash <(curl -Ls https://raw.githubusercontent.com/mn-hacker/Hiddify-Custom-Edition/main/common/download.sh) beta</code> |
| **Update** | <code>cd /opt/hiddify-manager && bash update.sh</code> |
| **Uninstall** | <code>cd /opt/hiddify-manager && bash uninstall.sh</code> |

**Requirements**

- Ubuntu 22.04 or newer, or Debian 12 — on `x86_64` or `ARM64`.
- `root` access and at least 1 GB of RAM.
- A domain pointing at the server IP.
- Ports `80` and `443` free.
- Python `3.12`+ only if you plan to develop against the panel.

**First run**

The installer prints your admin link when it finishes. If you ever lose it, open the management menu:

```bash
cd /opt/hiddify-manager && bash menu.sh
```

---

## Project layout

```text
Hiddify-Custom-Edition/
├─ hiddify-panel/     ← the web panel and the Watashi Theme
├─ xray/              ← Xray-core service and configs
├─ singbox/           ← sing-box service and configs
├─ haproxy/           ← traffic and TLS front door
├─ nginx/             ← web service and domains
├─ hiddify-cli/       ← command line client
├─ common/            ← shared install and runtime scripts
├─ operations/        ← backup and scheduled work
├─ Theme/             ← design sources of the Watashi Theme
├─ install.sh update.sh restart.sh status.sh menu.sh uninstall.sh
└─ VERSION
```

---

## Support

| | |
| :-- | :-- |
| Telegram channel | [Watashi Manager](https://t.me/Watashi_Manager) |
| Maintainer | [シングル (MNHACKER)](https://t.me/MNHACKER) |
| Bug reports | [GitHub Issues](https://github.com/mn-hacker/Hiddify-Custom-Edition/issues) |

## Credits and license

Watashi Manager grows on open source and says so plainly: it builds on the [Hiddify Manager](https://github.com/hiddify/Hiddify-Manager) engine, and ships [Xray-core](https://github.com/XTLS/Xray-core), [sing-box](https://github.com/SagerNet/sing-box) and HAProxy. The Watashi Theme, the Living Core mark, the customer page, the reliability engine and the operations console are original work in this repository.

Released under the **GNU GPL v3** — see [LICENSE](LICENSE).

> [!IMPORTANT]
> This software exists for privacy and free access to information. Complying with the laws that apply to you is your own responsibility.

<div align="center">

<img src="assets/watashi-mark.svg?v=3" alt="Watashi" width="32" height="32">

**Watashi Manager** — Made by シングル

</div>
