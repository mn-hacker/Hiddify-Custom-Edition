import glob
import re
import os

files = glob.glob('*.html')
if 'user-panel.html' in files:
    files.remove('user-panel.html')

css_to_add = """
        .nav-category { font-size: 11px; font-weight: 700; color: var(--text-muted); text-transform: uppercase; letter-spacing: 1px; margin: 16px 0 8px 16px; opacity: 0; transition: opacity 0.2s ease; }
        .sidebar:hover .nav-category { opacity: 0.7; transition-delay: 0.1s; }
"""

sidebar_template = """<ul class="nav-menu">
            <li class="nav-category">Overview</li>
            <a href="dashboard.html" class="nav-item {dashboard_active}">
                <i class="fa-solid fa-border-all"></i> <span class="nav-text">Dashboard</span>
            </a>
            <a href="monitoring.html" class="nav-item {monitoring_active}">
                <i class="fa-solid fa-binoculars"></i> <span class="nav-text">Monitoring</span>
            </a>
            
            <li class="nav-category">Access & Users</li>
            <a href="users.html" class="nav-item {users_active}">
                <i class="fa-solid fa-users"></i> <span class="nav-text">Users</span>
            </a>
            <a href="admins.html" class="nav-item {admins_active}">
                <i class="fa-solid fa-shield-halved"></i> <span class="nav-text">Admins</span>
            </a>
            <a href="#" class="nav-item {account_active}">
                <i class="fa-regular fa-user"></i> <span class="nav-text">My Account</span>
            </a>

            <li class="nav-category">Network & Config</li>
            <a href="domains.html" class="nav-item {domains_active}">
                <i class="fa-solid fa-globe"></i> <span class="nav-text">Domains</span>
            </a>
            <a href="proxies.html" class="nav-item {proxies_active}">
                <i class="fa-solid fa-network-wired"></i> <span class="nav-text">Proxies</span>
            </a>
            <a href="tunnel.html" class="nav-item {tunnel_active}">
                <i class="fa-solid fa-route"></i> <span class="nav-text">Tunnel</span>
            </a>

            <li class="nav-category">System</li>
            <a href="settings.html" class="nav-item {settings_active}">
                <i class="fa-solid fa-gear"></i> <span class="nav-text">Settings</span>
            </a>
            <a href="actions.html" class="nav-item {actions_active}">
                <i class="fa-solid fa-terminal"></i> <span class="nav-text">Actions</span>
            </a>
            <a href="backup.html" class="nav-item {backup_active}">
                <i class="fa-solid fa-floppy-disk"></i> <span class="nav-text">Backup</span>
            </a>
        </ul>"""

for filename in files:
    with open(filename, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 1. Update CSS
    if '.nav-category' not in content:
        # Find </style> and insert before
        content = content.replace('</style>', css_to_add + '</style>')
    
    # 2. Update nav-menu
    page_name = filename.replace('.html', '')
    if page_name == 'account': page_name = 'account' # special
    
    formatted_sidebar = sidebar_template.format(
        dashboard_active='active' if page_name=='dashboard' else '',
        monitoring_active='active' if page_name=='monitoring' else '',
        users_active='active' if page_name=='users' else '',
        admins_active='active' if page_name=='admins' else '',
        account_active='active' if page_name=='account' else '',
        domains_active='active' if page_name=='domains' else '',
        proxies_active='active' if page_name=='proxies' else '',
        tunnel_active='active' if page_name=='tunnel' else '',
        settings_active='active' if page_name=='settings' else '',
        actions_active='active' if page_name=='actions' else '',
        backup_active='active' if page_name=='backup' else ''
    )
    
    # replace the entire <ul class="nav-menu">...</ul> block
    content = re.sub(r'<ul class="nav-menu">.*?</ul>', formatted_sidebar, content, flags=re.DOTALL)
    
    with open(filename, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print(f"Updated {filename}")
