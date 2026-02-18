
import os

po_file_path = os.path.join(os.getcwd(), 'hiddify-panel', 'src', 'hiddifypanel', 'translations', 'fa', 'LC_MESSAGES', 'messages.po')

new_translations = {
    "amnezia_enable": "فعال سازی پروتکل AmneziaWG",
    "amnezia_port": "پورت AmneziaWG",
    "amnezia_s1": "S1 (Amnezia)",
    "amnezia_s2": "S2 (Amnezia)",
    "amnezia_h1": "H1 (Amnezia)",
    "amnezia_h2": "H2 (Amnezia)",
    "amnezia_h3": "H3 (Amnezia)",
    "amnezia_h4": "H4 (Amnezia)",
    "amnezia_jc": "Jc (Amnezia)",
    "amnezia_jmin": "Jmin (Amnezia)",
    "amnezia_jmax": "Jmax (Amnezia)"
}

with open(po_file_path, 'a', encoding='utf-8') as f:
    f.write('\n\n')
    for msgid, msgstr in new_translations.items():
        f.write(f'msgid "{msgid}"\n')
        f.write(f'msgstr "{msgstr}"\n\n')

print("Amnezia translations appended successfully.")
