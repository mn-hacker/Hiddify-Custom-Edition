# Watashi Manager — repo prune list (v12.2.54, 2026-08-27)

هر مسیر با گرپ روی درخت مرجع بررسی شده است. ستون «ارجاع» یعنی چند فایل زنده
(بدون `.git`, `__pycache__`, `.venv`, `Other panel`, `theme_backup`, `docs`,
`HISTORY.md`, `uv.lock`, `poetry.lock`) نام آن مسیر را دارند.

روش پیشنهادی: اسکریپت `cleanup-repo.sh` را اجرا کن. خودش قبل از حذف هر مسیر
دنبال ارجاع می‌گردد و اگر چیزی پیدا کرد فایل را **نگه می‌دارد** و می‌گوید چه
فایلی به آن اشاره کرده. دستی حذف نکن.

```bash
cd <repo>
bash cleanup-repo.sh a      # فقط گروه A
bash cleanup-repo.sh b      # گروه B (حجم اصلی)
bash cleanup-repo.sh a b    # هر دو
bash cleanup-repo.sh list   # فقط نمایش، بدون حذف
```

---

## گروه A — مرده و تأییدشده (بی‌خطر)

| مسیر | ارجاع | حجم | دلیل |
|---|---|---|---|
| `arm.tar.gz` | 0 | 27253014 | هیچ اسکریپتی بازش نمی‌کند |
| `other/warp_old_beta/` | 0 | ~40 K | نسخهٔ بتای قدیمی warp؛ مسیر زنده `other/warp/` است |
| `uv.toml` | 0 | کوچک | نصب از `pyproject.toml` می‌آید |
| `hiddify-panel/src/project.inlang/` | 0 | — | ابزار ترجمهٔ inlang استفاده نمی‌شود |
| `hiddify-panel/src/ABOUT_THIS_TEMPLATE.md` | 0 | — | بازماندهٔ قالب cookiecutter |
| `hiddify-panel/src/apply.sh` | 0 | 2297 | فقط `Containerfile` را صدا می‌زند که وجود ندارد |
| `hiddify-panel/src/hiddifypanel/panel/auth_back.py` | 0 | — | هیچ‌کس import نمی‌کند و `flask_httpauth` را می‌خواهد که اعلام‌نشده است |
| `hiddify-panel/src/hiddifypanel/panel/node/a.py` | 0 | 343 | دموی grpc |
| `hiddify-panel/src/hiddifypanel/panel/node/test_grpc.py` | 0 | 1277 | از قبل شکسته: `hiddifypanel.hasync.node.test_pb2` وجود ندارد |
| `hiddify-panel/src/hiddifypanel/panel/node/test.proto` | 0* | 199 | تنها ارجاعش دو فایل بالا بود |
| `hiddify-panel/src/hiddifypanel/panel/node/test_pb2.pyi` | 0 | 578 | فقط type stub |
| `.github/FUNDING.yml` | 0 | — | لینک حمایت مالی پروژهٔ اصلی؛ با برند واتاشی تناقض دارد |
| `.github/workflows/delete_issue.yml` | 0 | — | اتوماسیون ایشوهای مخزن بالادستی |
| `.github/dependabot.yml` | 0 | — | روی این fork اجرا نمی‌شود |
| `README_cn.md` | 0 | — | فقط `fa`/`en` پشتیبانی می‌شود (قانون 10) |
| `README_ru.md` | 0 | — | همان |

**نگه‌داشتنی‌های همان پوشه (حذف نکن!):**
`panel/node/__init__.py`, `panel/node/hello.py`, `panel/node/test_pb2.py`,
`panel/node/test_pb2_grpc.py` — این چهار فایل زنده‌اند، چون
`base.py:50` روی هر اپ وب `hiddifypanel.panel.node:init_app` را ثبت می‌کند.

### A2 — بکاپ‌های راندها که اشتباهی کامیت شده‌اند (24 فایل)

این‌ها فایل‌های `.bNN` من هستند؛ روی سرور به کار می‌آیند، در گیت‌هاب نه.

```
common/commander.py.b51
common/package_manager.sh.b50
common/run.sh.j2.b46
common/utils.sh.b46
hiddify-panel/hiddify-panel-background-tasks.service.b46
hiddify-panel/hiddify-panel.service.b46
hiddify-panel/src/hiddifypanel/hutils/proxy/shared.py.b52
hiddify-panel/src/hiddifypanel/panel/admin/SettingAdmin.py.b53
hiddify-panel/src/hiddifypanel/panel/admin/__init__.py.b51
hiddify-panel/src/hiddifypanel/panel/cli.py.b52
hiddify-panel/src/hiddifypanel/panel/common_bp/login.py.b52
hiddify-panel/src/hiddifypanel/panel/common_bp/templates/login.html.b52
hiddify-panel/src/hiddifypanel/panel/init_db.py.b46
hiddify-panel/src/hiddifypanel/panel/init_db.py.b53
hiddify-panel/src/hiddifypanel/panel/run_commander.py.b51
hiddify-panel/src/hiddifypanel/templates/admin-layout.html.b51
other/telegram/disable.sh.b53
other/telegram/install.sh.j2.b53
other/telegram/run.sh.j2.b53
other/telegram/tgo/install.sh.b53
singbox/add_version.sh.b50
singbox/install.sh.b50
xray/add_version.sh.b50
xray/install.sh.b50
```

پیشنهاد: یک خط `*.b[0-9][0-9]` به `.gitignore` اضافه کن تا دوباره تکرار نشود.

### A3 — پوشهٔ `tools/` (40 فایل)

اسکریپت‌های patch/check راندهای 47 تا 53 و لاگ‌هایشان. هیچ‌کدام در اجرا نقشی
ندارند. **اول** `tools/cleanup53.sh` و `tools/cleanup54.sh` را روی سرور اجرا کن،
بعد کل پوشه را از مخزن بردار (اگر سابقه‌شان را می‌خواهی، `checks*.log` را جدا
نگه دار، ولی بیرون از گیت).

### A4 — فایل‌های راند v12.2.54

اگر بستهٔ v12.2.54 را اعمال کرده‌ای، `tools/cleanup54.sh` این چهار مورد را خودش
برمی‌دارد و لازم نیست در این لیست باشند:
`hiddify-panel/src/hiddifypanel/panel/admin/Terminal.py` (1762) ·
`hiddify-panel/uwsgi.ini` (1165) · `hiddify-panel/src/1pyproject.toml` (1093) ·
`hiddify-panel/src/poetry.lock` (343406).

---

## گروه B — حجم اصلی (~51 مگابایت)

| مسیر | تعداد فایل | حجم | ارجاع |
|---|---|---|---|
| `Other panel/` | 1860 | 28 M | فقط یک خط در `.gitignore` |
| `theme_backup/` | 714 | 23 M | فقط یک خط در `.gitignore` |

این دو پوشه کپی کامل از یک پنل دیگر و یک بکاپ قالبند. هیچ کد زنده‌ای به
آن‌ها اشاره نمی‌کند. بعد از حذف، دو خط مربوطه در `.gitignore` را هم بردار.
اگر می‌خواهی دورریخته نشوند، قبل از حذف یک زیپ لوکال بگیر — ولی در مخزن جایی
ندارند.

مهم: حجم گیت‌هاب فقط با حذف فایل از آخرین کامیت کم نمی‌شود؛ تاریخچه سر جایش
می‌ماند. حجم clone برای همیشه کم می‌شود ولی پاک‌سازی کامل تاریخچه
(`git filter-repo`) یک عملیات جداگانه و خطرناک است — فعلاً توصیه نمی‌کنم.

---

## گروه C — تصمیم خودت (کار می‌کنند ولی مصرف ندارند)

| گروه | مسیرها | توضیح |
|---|---|---|
| داکر | `Dockerfile`, `docker-compose.yml`, `docker-init.sh`, `docker.env`, `.dockerignore`, `other/docker/`, `common/docker-installer.sh`, `.github/workflows/docker.yaml` | مسیر نصب داکری سال‌هاست نگهداری نشده؛ اگر قرار نیست پنل داکری بدهی، همه برود |
| دیپلوی اوراکل | `btn-deploy/` (19 فایل) | ترافرم دکمهٔ «Deploy to Oracle»؛ صفر ارجاع در کد |
| ابزار ریلیز بالادستی | `.gitchangelog.rc`, `release`, `.github/release_message.sh`, `.github/workflows/main.yml` | فقط اگر ریلیز دستی می‌زنی؛ `release.yml` را نگه دار |
| اسپک IDE | `.kiro/specs/amneziawg-protocol-fix/` (3 فایل) | یادداشت مربوط به ابزار IDE؛ روی سرور بی‌استفاده |
| ابزار دیباگ | `diag_cli.py`, `diag_singbox.py`, `append_amnezia_translations.py` | حذف نکن، ببر درون `scratch/` تا ریشهٔ مخزن تمیز شود |
| poetry باقیمانده | `hiddify-panel/src/Makefile`, `hiddify-panel/src/mkdocs.yml` | Makefile دنبال `[tool.poetry]` می‌گردد که دیگر وجود ندارد |
| دو لایسنس | `LICENSE` و `LICENSE.md` | اول `diff LICENSE LICENSE.md`؛ اگر یکی بودند، `LICENSE.md` را نگه دار (`pyproject.toml` به همین اشاره دارد) |
| قالب ایشو | `.github/ISSUE_TEMPLATE/*` (3 فایل) | متنشان مال پروژهٔ قدیم است؛ یا حذف یا بازنویسی با برند واتاشی |

---

## گروه D — حذف نکن (زنده‌اند، گول‌زننده)

| مسیر | ارجاع | چرا ماند |
|---|---|---|
| `lib/hiddify-core.so` (73 M) + `hiddify-cli` (1.5 M) | 14 | `other/hiddify-cli/`، `diag_cli.py` و README از آن استفاده می‌کنند. راه درست حذف نیست؛ راند جدا می‌خواهد تا مانند بقیهٔ هسته‌ها هنگام نصب با `packages.lock` دانلود شود (تنها راه کم کردن ~75 مگ بعدی) |
| `other/deprecated/` | 8 | `remove_deprecated.sh` از درون `install.sh` صدا می‌شود |
| `other/rathole/` | 11 | در `commander.py` و `install.sh` زنده است |
| `other/speedtest/`، `other/ssfaketls/` | 26 و 24 | در مسیرهای haproxy و نصب زنده‌اند |
| `operations/lxd/` | 8 | در README و نصب مستند است |
| `Theme/`، `assets/`، `docs/`، `scratch/` | 3 / 2 / — / 2 | برند، مستندات و ابزار خودت (`generate_tree.py` همین نقشه را ساخت) |
| `nginx/uwsgi_params` | 1 | تنها ارجاعش درون بلوک کامنت‌شدهٔ `proxy_to_panel.conf.j2` است؛ اول باید آن کامنت حذف شود، بعد این فایل — راند بعدی |
| `HISTORY.md` ها | — | تاریخچه؛ بی‌ازار، نگه دار |

### یک مورد که در نقشه نبود ولی مهم است

در نقشهٔ درختی تو هیچ `\.venv` دیده نمی‌شود، ولی در نسخهٔ مرجع یک پوشهٔ کامل
`.venv` ویندوزی درون `hiddify-panel/` کامیت شده بود. حتماً چک کن:

```bash
git ls-files | grep -c '\.venv/'
# اگر عدد بزرگی داد:
git rm -r -q --cached hiddify-panel/.venv
echo '.venv/' >> .gitignore
```

این می‌تواند از هر دو پوشهٔ گروه B بزرگتر باشد.

---

## جمع بندی

- گروه A: ~27.3 مگابایت + 24 بکاپ + پوشهٔ `tools/`
- گروه B: ~51 مگابایت
- جمع A+B ≈ **78 مگابایت** و حدود **2600 فایل** کمتر در مخزن
- گروه C: حدود 40 فایل کوچک، فقط تمیزی و برند

بعد از هر گروه:

```bash
bash install.sh --check-only 2>/dev/null || true
grep -rn --exclude-dir=.git -F 'arm.tar.gz' . | head
git status --short | head -20
```
