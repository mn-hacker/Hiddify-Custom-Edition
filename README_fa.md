<div align="center">

<img src="assets/watashi-banner.svg" alt="Watashi Manager" width="880">

[![Release](https://img.shields.io/github/v/release/mn-hacker/Hiddify-Custom-Edition?style=for-the-badge&color=7c3aed&label=RELEASE)](https://github.com/mn-hacker/Hiddify-Custom-Edition/releases)
[![Last commit](https://img.shields.io/github/last-commit/mn-hacker/Hiddify-Custom-Edition?style=for-the-badge&color=f59e0b&label=LAST%20COMMIT)](https://github.com/mn-hacker/Hiddify-Custom-Edition/commits)
[![Stars](https://img.shields.io/github/stars/mn-hacker/Hiddify-Custom-Edition?style=for-the-badge&color=22d3ee)](https://github.com/mn-hacker/Hiddify-Custom-Edition/stargazers)
[![License](https://img.shields.io/badge/LICENSE-GPL--3.0-10b981?style=for-the-badge)](LICENSE)

[![Xray](https://img.shields.io/badge/Xray--core-26.2.2-3b82f6?style=for-the-badge)](https://github.com/XTLS/Xray-core)
[![sing-box](https://img.shields.io/badge/sing--box-1.12.19-8b5cf6?style=for-the-badge)](https://github.com/SagerNet/sing-box)
[![Telegram](https://img.shields.io/badge/TELEGRAM-Watashi__Manager-229ED9?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/Watashi_Manager)

[English](README.md) · **فارسی**

</div>

---

<div dir="rtl" align="right">

## معرفی

**واتاشی منیجر** یک نسخهٔ پیشرفته و غیررسمی از [Hiddify Manager](https://github.com/hiddify/Hiddify-Manager) است؛ پنلی که یک سرور را به یک سرویس پراکسی چندپروتکلی کامل با مدیریت کاربر، حجم، دامنه، تانل و پایش تبدیل می‌کند.

این نسخه موتور اصلی را دست نمی‌زند، اما همه‌چیز پیرامون آن را از نو ساخته است: **هسته‌های تازه‌تر**، **خودترمیمی سرویس‌ها**، **اعلان‌های هوشمند تلگرام**، پایش دقیق‌تر، و یک رابط کاربری کاملاً بازطراحی‌شده به نام **تم واتاشی** برای هم پنل مدیریت و هم صفحهٔ اشتراکی که مشتری می‌بیند.

</div>

> [!NOTE]
> نسخهٔ غیررسمی، نگهداری‌شده توسط [シングル (MNHACKER)](https://t.me/MNHACKER). این پروژه هیچ وابستگی یا تأییدیه‌ای از تیم رسمی Hiddify ندارد.

---

<div dir="rtl" align="right">

## چه چیزی این نسخه را جدا می‌کند

| | |
| :-- | :-- |
| **هسته‌های تازه** | Xray-core نسخهٔ `26.2.2` و sing-box نسخهٔ `1.12.19`، به‌علاوهٔ کتابخانهٔ Go پراکسی تلگرام که از نو ساخته شد. |
| **زنده می‌ماند** | نگهبان خودترمیمی، سرویسی را که از کار افتاده باشد خودش برمی‌گرداند. |
| **رابط بازسازی‌شده** | تم واتاشی در پنل مدیریت و صفحهٔ کاربر — فارسی و انگلیسی، تیره و روشن، با یک زبان طراحی مشترک. |
| **کنترل بیشتر** | مسدودسازی تبلیغات، محدودیت دستگاه هر کاربر، لاگ دسترسی، لاگ فعالیت کاربر و مدیریت پیشرفتهٔ تانل. |
| **با تو حرف می‌زند** | اعلان خودکار تلگرام برای انقضا، مصرف 80 درصد حجم و پایان حجم. |

</div>

---

<div dir="rtl" align="right">

## تم واتاشی

</div>

<table>
<tr>
<td width="150" align="center"><img src="assets/watashi-icon.svg" alt="Watashi living icon" width="96" height="96"></td>
<td dir="rtl" align="right">

همهٔ صفحه‌ها **آیکون زنده** را با خود دارند؛ مارکی به نام glitch core که از یک قفس شش‌ضلعی گردان، یک هستهٔ نفس‌کشنده و حرف `W` سه‌رنگی ساخته شده که هر چند ثانیه یک لحظه می‌شکند. تماماً SVG و CSS است: بدون عکس، بدون جاوااسکریپت، کمتر از 3 کیلوبایت، و همین مارک فاوآیکون مرورگر هم هست. اگر کاربر در سیستمش `prefers-reduced-motion` را روشن کرده باشد، آیکون بی‌حرکت اما کامل و خوانا می‌ماند.

</td>
</tr>
</table>

<div dir="rtl" align="right">

**در سراسر پنل**

- یک نظام بصری مشترک: نشانگر موس اختصاصی، اسکرول‌بار شفاف، کارت‌های شیشه‌ای و اعلان‌های شناور به جای پنجره‌های پیش‌فرض مرورگر.
- رابط کامل **فارسی / انگلیسی** با تغییر لحظه‌ای زبان، رعایت درست RTL و LTR در هر خط، و اعداد لاتین در همه‌جا.
- پوستهٔ **تیره و روشن** که برای هر بازدیدکننده به خاطر سپرده می‌شود.
- بازسازی صفحات عملیاتی: ری‌استارت سرویس‌ها با جدول وضعیت زنده، لاگ عملیات به شکل خوانا، شمارندهٔ مصرف، آزمون Reality و پایش.

**صفحه‌ای که کاربر تو می‌بیند**

- برای هر خانوادهٔ کانفیگ یک کارت جداگانه — **Clash / Meta**، **Sing-Box**، **V2Ray / Xray** و **WireGuard** — هر کدام با کپی، کیوآر و دانلود در دسترس یک حرکت.
- کیوآر را می‌توان **به شکل تصویر کپی کرد**، نه فقط اسکن.
- راهنمای راه‌اندازی جداگانه برای Android، iOS، Windows، macOS و Linux با برنامهٔ مناسب هر کدام.
- حلقهٔ مصرف، حجم باقی‌مانده، روزهای مانده، ریتم ریست و اطلاعات آخرین اتصال — همه به زبان خود کاربر.

</div>

---

<div dir="rtl" align="right">

## فهرست کامل قابلیت‌ها

</div>

<details>
<summary><b>هسته و کارایی</b></summary>

<div dir="rtl" align="right">

- ارتقای Xray-core از `25.6.8` به `26.2.2`.
- ارتقای sing-box از `1.8.8` به `1.12.19`.
- رفع مشکل تست سرعت در صفحهٔ کاربر.
- بازسازی کتابخانهٔ Go پراکسی تلگرام و رفع کراش آن.

</div>

</details>

<details>
<summary><b>پایداری و خودترمیمی</b></summary>

<div dir="rtl" align="right">

- سرویسی که ناخواسته متوقف شود، شناسایی و خودکار دوباره راه‌اندازی می‌شود.
- روند ری‌استارت اول منتظر سلامت Redis و MariaDB می‌ماند و بعد سرویس‌های پنل را دست می‌زند؛ پس یک وابستگی گیرکرده دیگر نمی‌تواند همهٔ مجموعه را زمین بزند.
- چرخش و پاک‌سازی لاگ‌های سیستم دوباره درست کار می‌کند.
- نمایش وضعیت واقعی هر سرویس در صفحهٔ ری‌استارت، به جای پیام‌های مبهم.

</div>

> [!WARNING]
> خودترمیمی فقط توقف‌های اتفاقی سرویس را پوشش می‌دهد و جایگزین درست کردن یک کانفیگ خراب یا سرور معیوب نیست.

</details>

<details>
<summary><b>اعلان‌های تلگرام</b></summary>

<div dir="rtl" align="right">

- اعلان **انقضای اشتراک**.
- اعلان **مصرف 80 درصد حجم**.
- اعلان **پایان حجم اشتراک**.
- متن اعلان‌ها هم فارسی و هم انگلیسی ترجمه شده است.

</div>

</details>

<details>
<summary><b>امنیت و کنترل</b></summary>

<div dir="rtl" align="right">

- **مسدودسازی تبلیغات** در سطح سرور.
- **محدودیت دستگاه یا کاربر همزمان** برای هر اشتراک.
- **پایش پیشرفته** منابع و ترافیک.
- **لاگ فعالیت هر کاربر**.
- **لاگ دسترسی** برای مقاصد بازدیدشده.

</div>

> [!CAUTION]
> لاگ دسترسی، مقاصدی را که کاربرانت باز می‌کنند ثبت می‌کند و روی کارایی هم هزینه دارد. فقط وقتی واقعاً لازم است روشنش کن و حریم خصوصی افراد را نگه دار.

</details>

<details>
<summary><b>شبکه، تانل و دامنه</b></summary>

<div dir="rtl" align="right">

- صفحهٔ اختصاصی **مدیریت تانل** با نصب و مدیریت پیش‌فرض **Rathole v2**.
- پشتیبانی از **ECH** در بخش ترفندهای TLS.
- امکان تغییر **پورت Hysteria**.
- رفع مشکل نصب WARP و نمایش نادرست IP سرور وقتی WARP فعال است.
- رفع باگ کانفیگ‌های **XHTTP** و **WireGuard**.

</div>

</details>

<details>
<summary><b>رفع ایرادهای رابط کاربری</b></summary>

<div dir="rtl" align="right">

- دکمه‌های کپی در همهٔ صفحات درست کار می‌کنند و پیام تأیید ترجمه‌شده می‌دهند.
- لاگ عملیات دیگر CSS خام یا JSON خام نشان نمی‌دهد.
- چیدمان RTL و LTR در همهٔ کارت‌ها، جدول‌ها و سربرگ‌ها درست شد.
- کارت‌ها با طول داده کشیده نمی‌شوند و قالب صفحه ثابت می‌ماند.
- نشانگر موس و اسکرول‌بار در پنل و صفحهٔ کاربر یکسان شدند.

</div>

</details>

---

<div dir="rtl" align="right">

## نصب

</div>

| کانال | دستور |
| :-- | :-- |
| **نسخهٔ پایدار** | <code>bash <(curl -Ls https://raw.githubusercontent.com/mn-hacker/Hiddify-Custom-Edition/main/common/download.sh)</code> |
| **نسخهٔ بتا** | <code>bash <(curl -Ls https://raw.githubusercontent.com/mn-hacker/Hiddify-Custom-Edition/main/common/download.sh) beta</code> |
| **بروزرسانی** | <code>cd /opt/hiddify-manager && bash update.sh</code> |
| **حذف کامل** | <code>cd /opt/hiddify-manager && bash uninstall.sh</code> |

<div dir="rtl" align="right">

**پیش‌نیازها**

- Ubuntu 22.04 یا بالاتر، یا Debian 12 — روی معماری x86_64 یا ARM64.
- دسترسی `root` و حداقل 1 گیگابایت حافژه.
- یک دامنه که به IP سرور اشاره کند.
- پورت‌های `80` و `443` آزاد باشند.
- برای توسعه: Python نسخهٔ `3.12` یا بالاتر.

**اولین اجرا**

در پایان نصب، لینک پنل مدیر در خروجی نمایش داده می‌شود. اگر بعداً آن را گم کردی، کافی است منوی مدیریت را باز کنی:

</div>

```bash
cd /opt/hiddify-manager && bash menu.sh
```

---

<div dir="rtl" align="right">

## ساختار پروژه

</div>

```text
Hiddify-Custom-Edition/
├─ hiddify-panel/     ← پنل وب (Flask) + تم واتاشی
├─ xray/              ← کانفیگ و سرویس Xray-core
├─ singbox/           ← کانفیگ و سرویس sing-box
├─ haproxy/           ← توزیع ترافیک و TLS
├─ nginx/             ← سرویس وب و دامنه‌ها
├─ hiddify-cli/       ← کلاینت خط فرمان
├─ common/            ← اسکریپت‌های مشترک و نصب
├─ operations/        ← پشتیبان‌گیری و عملیات دوره‌ای
├─ Theme/             ← طرح‌ها و قالب‌های تم
├─ install.sh update.sh restart.sh status.sh menu.sh uninstall.sh
└─ VERSION
```

---

<div dir="rtl" align="right">

## مسیر پیش‌رو

- [ ] تغییر نام سرویس‌ها از `hiddify-*` به `watashi-*` با حفظ سازگاری.
- [ ] صفحهٔ مدیریت برای شخصی‌سازی صفحهٔ کاربر و قالب‌های متعدد.
- [ ] بازطراحی مانده: پشتیبان‌گیری، دامنه‌ها، پراکسی‌ها، تنطیمات و تانل.
- [ ] بروزرسانی مداوم xray، sing-box و haproxy.
- [ ] ترجمهٔ روسی و چینی.

</div>

---

<div dir="rtl" align="right">

## پشتیبانی و ارتباط

| | |
| :-- | :-- |
| کانال تلگرام | [Watashi Manager](https://t.me/Watashi_Manager) |
| سازنده | [シングル (MNHACKER)](https://t.me/MNHACKER) |
| گزارش ایراد | [GitHub Issues](https://github.com/mn-hacker/Hiddify-Custom-Edition/issues) |

## قدردانی

این پروژه روی دوش کار دیگران ایستاده است:
[Hiddify Manager](https://github.com/hiddify/Hiddify-Manager)،
[Xray-core](https://github.com/XTLS/Xray-core)،
[sing-box](https://github.com/SagerNet/sing-box)
و HAProxy.

## پروانه

منتشرشده با پروانهٔ **GNU GPL v3** — فایل [LICENSE](LICENSE).

</div>

> [!IMPORTANT]
> این ابزار برای حفاظت از حریم خصوصی و دسترسی آزاد به اطلاعات ساخته شده است. مسئولیت رعایت قوانین محل خود بر عهدهٔ کاربر است.

<div align="center">

<img src="assets/watashi-icon.svg" alt="Watashi" width="28" height="28">

**Watashi Manager** — Made by シングル

</div>
