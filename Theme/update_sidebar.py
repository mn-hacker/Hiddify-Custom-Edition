import os

theme_dir = r"d:\Downloads\Watashi-Manager\Theme"
files = [f for f in os.listdir(theme_dir) if f.endswith('.html')]

sidebar_addition = """
            <a href="backup.html" class="nav-item"><i class="fa-solid fa-floppy-disk"></i> <span class="nav-text">Backup</span></a>
            <a href="tunnel.html" class="nav-item"><i class="fa-solid fa-route"></i> <span class="nav-text">Tunnel</span></a>
"""

for f in files:
    path = os.path.join(theme_dir, f)
    with open(path, 'r', encoding='utf-8') as file:
        content = file.read()
    
    if 'href="backup.html"' not in content:
        # Find the line with monitoring.html or actions.html and insert before or after
        # It's better to insert after settings or proxies
        content = content.replace('<a href="monitoring.html"', sidebar_addition + '            <a href="monitoring.html"')
        
        with open(path, 'w', encoding='utf-8') as file:
            file.write(content)
        print(f"Updated sidebar in {f}")
    else:
        print(f"Already updated {f}")
