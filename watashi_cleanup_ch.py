#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""watashi v12.2.130ch - پاک‌سازی فایل‌های بازنشسته

این را در ریشه پروژه (کنار install.sh) بگذار و اجرا کن:

    python3 watashi_cleanup_ch.py            # فقط گزارش می‌دهد، چیزی پاک نمی‌کند
    python3 watashi_cleanup_ch.py --apply    # واقعاً پاک می‌کند

چیزی که پاک می‌شود: صفحه آمار زنده پروکسی، سرویس hiddify-cli و قالب‌های
قدیمی فلسک‌ادمین که تم جدید جایشان را گرفته. هیچ فایل زنده‌ای در فهرست نیست.
"""
import os
import shutil
import sys

PANEL = 'hiddify-panel/src/hiddifypanel'

RETIRED = [
    # the live proxy dashboard and the service that served it
    PANEL + '/panel/admin/ProxyStatsAdmin.py',
    PANEL + '/panel/admin/templates/proxy_stats.html',
    'other/hiddify-cli',
    # the old flask-admin chrome the new theme replaced
    PANEL + '/templates/a.html',
    PANEL + '/templates/fake.html',
    PANEL + '/templates/static.html',
    PANEL + '/templates/lte-master.html',
    PANEL + '/templates/master.html',
    PANEL + '/templates/admin-layout.html',
    PANEL + '/templates/flaskadmin-layout.html',
    PANEL + '/templates/donation.html',
    PANEL + '/templates/macros.html',
    PANEL + '/templates/admin.ht.old',
    PANEL + '/templates/admin-layout.html.b51',
    PANEL + '/panel/commercial/templates/configc.html',
    PANEL + '/panel/commercial/templates/parent_dash.html',
    # the user panel that watashi_user.html replaced
    PANEL + '/panel/user/templates/new.html',
    PANEL + '/panel/user/templates/redirect_to_new_format.html',
    PANEL + '/panel/user/templates/home',
]

# if these are missing we are not in the project root, so nothing is touched
MARKERS = ['install.sh', 'common/utils.sh', PANEL + '/panel/common.py']


def main():
    apply = '--apply' in sys.argv
    root = os.path.abspath(os.path.dirname(__file__) or '.')
    os.chdir(root)

    missing = [m for m in MARKERS if not os.path.exists(m)]
    if missing:
        print('این پوشه ریشه پروژه نیست، چون %s پیدا نشد.' % ', '.join(missing))
        print('فایل را کنار install.sh بگذار و دوباره اجرا کن.')
        return 1

    found, absent, freed = [], [], 0
    for rel in RETIRED:
        if not os.path.exists(rel):
            absent.append(rel)
            continue
        if os.path.isdir(rel):
            size = sum(os.path.getsize(os.path.join(dp, f))
                       for dp, _, fn in os.walk(rel) for f in fn)
        else:
            size = os.path.getsize(rel)
        found.append((rel, size))
        freed += size

    print('ریشه پروژه: %s' % root)
    print('پیدا شد: %d مورد   قبلاً نبود: %d مورد   حجم: %.1f کیلوبایت\n'
          % (len(found), len(absent), freed / 1024.0))
    for rel, size in found:
        kind = 'پوشه' if os.path.isdir(rel) else 'فایل'
        print('  %-5s %-62s %7.1f KB' % (kind, rel, size / 1024.0))

    if not apply:
        print('\nچیزی پاک نشد. برای پاک کردن واقعی:  python3 %s --apply'
              % os.path.basename(__file__))
        return 0

    gone = 0
    for rel, _ in found:
        try:
            if os.path.isdir(rel):
                shutil.rmtree(rel)
            else:
                os.remove(rel)
            gone += 1
        except OSError as err:
            print('  نشد پاک شود: %s (%s)' % (rel, err))
    print('\n%d مورد پاک شد.' % gone)
    return 0


if __name__ == '__main__':
    sys.exit(main())
