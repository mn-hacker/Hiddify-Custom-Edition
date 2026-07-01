import datetime
import re

version_new = '12.1.61b'

def bump(path, old_v, new_v):
    with open(path, 'r', encoding='utf-8') as f:
        c = f.read()
    c = c.replace(old_v, new_v)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(c)

bump(r'd:\Downloads\Watashi-Manager\VERSION', '12.1.60b', version_new)
bump(r'd:\Downloads\Watashi-Manager\hiddify-panel\src\hiddifypanel\VERSION', '12.1.60b', version_new)

vpy_path = r'd:\Downloads\Watashi-Manager\hiddify-panel\src\hiddifypanel\VERSION.py'
with open(vpy_path, 'r', encoding='utf-8') as f:
    c = f.read()

c = c.replace('12.1.60b', version_new)

now = datetime.datetime.now()
c = re.sub(r'__release_date__ = ".*?"', f'__release_date__ = "{now.strftime("%Y-%m-%d")}"', c)
c = re.sub(r'__release_time__ = ".*?"', f'__release_time__ = "{now.strftime("%H:%M:%S")}"', c)

with open(vpy_path, 'w', encoding='utf-8') as f:
    f.write(c)

bump(r'd:\Downloads\Watashi-Manager\hiddify-panel\src\pyproject.toml', '12.1.60b', version_new)
