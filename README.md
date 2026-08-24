<div align="center">

<img src="assets/watashi-banner.svg" alt="Watashi Manager" width="880">

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

## Overview

**Watashi Manager** is an advanced, community-maintained edition of [Hiddify Manager](https://github.com/hiddify/Hiddify-Manager) — a self-hosted panel that turns a single server into a multi-protocol proxy service with users, quotas, domains, tunnels and monitoring.

This edition keeps the upstream engine intact and rebuilds everything around it: **newer cores**, **self-healing services**, **smarter Telegram notifications**, deeper monitoring, and a completely redesigned interface — the **Watashi Theme** — for both the admin panel and the subscription page your customers see.

> [!NOTE]
> Unofficial edition, maintained by [シングル (MNHACKER)](https://t.me/MNHACKER). It is not affiliated with, or endorsed by, the official Hiddify team.

---

## Why this edition

| | |
| :-- | :-- |
| **Newer cores** | Xray-core `26.2.2` and sing-box `1.12.19`, plus a rebuilt Telegram-proxy Go library. |
| **Stays alive** | A self-healing watchdog brings services back up when one of them drops out. |
| **Rebuilt interface** | The Watashi Theme across admin and user pages — Persian and English, dark and light, one shared design language. |
| **More control** | Ad blocking, per-user device limits, access logs, user activity logs, advanced tunnel management. |
| **Talks to you** | Automatic Telegram alerts for expiry, 80% usage and exhausted quota. |

---

## The Watashi Theme

<table>
<tr>
<td width="150" align="center"><img src="assets/watashi-icon.svg" alt="Watashi living icon" width="96" height="96"></td>
<td>

Every page carries the **living icon** — a glitch-core mark built from a rotating hex cage, a breathing core and a chromatic `W` that fractures for a moment every few seconds. Pure SVG and CSS: no images, no JavaScript, under 3 KB, and it doubles as the favicon. It honours `prefers-reduced-motion`, so it holds still for anyone who asks for less animation.

</td>
</tr>
</table>

**Across the panel**

- A shared visual system: custom cursor, overlay scrollbars, glass cards and non-blocking toast notifications instead of browser dialogs.
- Full **Persian / English** interface with instant switching, correct RTL and LTR handling on every line, and English numerals everywhere.
- **Dark and light** skins, remembered per visitor.
- Rebuilt operational pages: service restart with a live status table, action logs in readable form, usage counters, Reality probing and monitoring.

**The subscription page your users see**

- One card per configuration family — **Clash / Meta**, **Sing-Box**, **V2Ray / Xray** and **WireGuard** — each with copy, QR and download in one reach.
- QR codes can be **copied as an image**, not just scanned.
- Per-platform setup guides for Android, iOS, Windows, macOS and Linux, with the right client apps for each one.
- A usage ring, remaining volume, days left, reset rhythm and last-connection details — all in the visitor's own language.

---

## Features in detail

<details>
<summary><b>Cores and performance</b></summary>

- Xray-core updated to `26.2.2`.
- sing-box updated to `1.12.19`.
- Speed test on the user page fixed.
- Telegram proxy Go library rebuilt and fixed.

</details>

<details>
<summary><b>Reliability and self-healing</b></summary>

- Services that stop unexpectedly are detected and started again automatically.
- Restart flow waits for Redis and MariaDB to become healthy before touching the panel services, so a stuck dependency can no longer take the whole stack down.
- System logs rotate and clear correctly again.

> [!WARNING]
> Self-healing covers accidental service stops. It is not a substitute for fixing a broken configuration or a failing server.

</details>

<details>
<summary><b>Telegram notifications</b></summary>

- Subscription **expiry** alerts.
- **80% of quota** consumed alerts.
- **Quota exhausted** alerts.

</details>

<details>
<summary><b>Security and control</b></summary>

- **Ad blocker** at the server level.
- **Device / user limit** per subscription.
- **Advanced monitoring** dashboard.
- **Per-user activity log**.
- **Access log** for visited destinations.

> [!CAUTION]
> The access log exposes the sites your users visit and costs performance. Enable it only when you genuinely need it, and respect the privacy of the people on your server.

</details>

<details>
<summary><b>Networking and tunnels</b></summary>

- Dedicated **tunnel management** page, with **Rathole v2** installed and managed out of the box.
- **ECH** (Encrypted Client Hello) support under the TLS tricks section.
- Configurable **Hysteria port**.
- WARP installation and server-IP reporting fixed.
- XHTTP and WireGuard configuration bugs fixed.

</details>

---

## Install

| Channel | Command |
| :-- | :-- |
| **Stable** | <code>bash <(curl -Ls https://raw.githubusercontent.com/mn-hacker/Hiddify-Custom-Edition/main/common/download.sh)</code> |
| **Beta** | <code>bash <(curl -Ls https://raw.githubusercontent.com/mn-hacker/Hiddify-Custom-Edition/main/common/download.sh) beta</code> |
| **Update** | <code>cd /opt/hiddify-manager && bash update.sh</code> |

**Requirements**

- Ubuntu 22.04 / 24.04 or Debian 12, on `x86_64` or `arm64`.
- Root access, 1 GB RAM or more, ports `80` and `443` free.
- A domain whose `A` record already points at the server IP.
- Python `3.12+` (only if you plan to work on the panel source).

**After the install finishes**

```bash
cd /opt/hiddify-manager
bash menu.sh      # admin links, service status, common operations
bash status.sh    # health of every service
bash restart.sh   # ordered restart of the whole stack
```

---

## Repository layout

```text
hiddify-panel/src/   the Flask panel: admin pages, user subscription page, Watashi Theme
common/              install, update and shared shell helpers
xray/  singbox/      proxy core configuration
haproxy/  nginx/     edge routing and TLS termination
hiddify-cli/         command line client bundle
Theme/               design sources for the Watashi Theme
docs/                additional documentation
install.sh  update.sh  restart.sh  status.sh  menu.sh  uninstall.sh
```

---

## Roadmap

- [ ] Rename the service units from `hiddify-*` to `watashi-*`, keeping aliases for compatibility.
- [ ] Admin page for customising the user subscription page, with selectable templates.
- [ ] Finish the redesign of the backup, domains, proxies, settings and tunnel pages.
- [ ] Keep Xray, sing-box and HAProxy on their latest stable releases.
- [ ] Russian and Chinese translations.

---

## Credits

Built on [Hiddify Manager](https://github.com/hiddify/Hiddify-Manager), which does the heavy lifting, and on the work of [Xray-core](https://github.com/XTLS/Xray-core), [sing-box](https://github.com/SagerNet/sing-box) and HAProxy.

| Author | Channel | Issues |
| :-: | :-: | :-: |
| [シングル (MNHACKER)](https://t.me/MNHACKER) | [Watashi Manager](https://t.me/Watashi_Manager) | [Report a bug](https://github.com/mn-hacker/Hiddify-Custom-Edition/issues) |

Released under the **GPL-3.0** license — see [LICENSE](LICENSE).

> [!IMPORTANT]
> This project exists to give people private, uncensored access to the open internet. Use it lawfully and responsibly.

<div align="center">

<img src="assets/watashi-icon.svg" alt="" width="28" height="28">

<sub>Made with care by シングル</sub>

</div>
