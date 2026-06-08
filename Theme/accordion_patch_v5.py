import glob
import re

css_patch = """
        /* --- Accordion Sidebar CSS v5 (Bulletproof Centering) --- */
        .sidebar { width: 86px !important; overflow-x: hidden !important; padding-top: 20px !important; transition: width 0.4s cubic-bezier(0.25, 0.8, 0.25, 1) !important; border-right: 1px solid var(--border-color); }
        .sidebar:hover { width: 250px !important; } 
        
        .logo { display: flex; align-items: center; justify-content: center; margin-bottom: 40px; height: 50px; }
        .sidebar:hover .logo { justify-content: flex-start; padding-left: 24px; }
        .logo i { font-size: 24px; color: var(--primary-purple); text-align: center; }
        .logo-text { display: none; }
        .sidebar:hover .logo-text { display: inline-block; font-size: 18px; font-weight: 600; margin-left: 12px; opacity: 0; animation: textFadeIn 0.3s 0.1s forwards; white-space: nowrap; }
        
        .nav-menu { list-style: none; display: flex; flex-direction: column; gap: 8px; flex: 1; align-items: stretch; padding: 0; width: 100%; overflow-y: auto; overflow-x: hidden; }
        .nav-menu::-webkit-scrollbar { width: 0; }
        
        .nav-item-group { display: flex; flex-direction: column; }
        
        .nav-item-header { display: flex; align-items: center; justify-content: center; padding: 12px 0; border-radius: 8px; color: var(--text-muted); cursor: pointer; transition: all 0.2s; margin: 0 16px; position: relative; }
        .sidebar:hover .nav-item-header { justify-content: flex-start; padding: 12px 16px; }
        .nav-item-header:hover { background: var(--bg-card); color: var(--text-main); }
        .nav-item-header.active { color: var(--primary-purple); }
        
        .nav-header-left { display: flex; align-items: center; gap: 16px; }
        .nav-header-left i { font-size: 18px; width: 24px; text-align: center; }
        
        .nav-text { display: none; white-space: nowrap; }
        .sidebar:hover .nav-text { display: inline-block; opacity: 0; animation: textFadeIn 0.3s 0.1s forwards; }
        
        @keyframes textFadeIn { to { opacity: 1; } }
        
        .chevron { display: none; }
        .sidebar:hover .chevron { display: block; position: absolute; right: 16px; opacity: 0; animation: textFadeIn 0.3s 0.1s forwards; transition: transform 0.3s; font-size: 12px; }
        .nav-item-group.open .chevron { transform: rotate(180deg); }
        
        .nav-accordion { max-height: 0; overflow: hidden; transition: max-height 0.3s ease-in-out, margin 0.3s ease-in-out, opacity 0.3s ease-in-out; display: flex; flex-direction: column; gap: 4px; opacity: 0; margin-top: 0; }
        .nav-item-group.open .nav-accordion { max-height: 350px; opacity: 1; margin-top: 4px; margin-bottom: 8px; }
        
        .nav-item { display: flex; align-items: center; justify-content: center; padding: 10px 0; border-radius: 8px; color: var(--text-muted); text-decoration: none; font-size: 13px; font-weight: 500; transition: all 0.2s; margin: 0 16px; }
        .sidebar:hover .nav-item { justify-content: flex-start; padding: 10px 16px 10px 40px; gap: 16px; }
        
        .nav-item i { font-size: 14px; width: 24px; text-align: center; opacity: 0.6; transition: opacity 0.2s; }
        .nav-item:hover { background: var(--bg-detail); color: var(--text-main); }
        .sidebar:hover .nav-item:hover { transform: translateX(4px); }
        .nav-item:hover i { opacity: 1; color: var(--primary-purple); }
        .nav-item.active { background: linear-gradient(90deg, #6366f1 0%, #8b5cf6 100%); color: #fff; box-shadow: 0 4px 15px rgba(99, 102, 241, 0.25); }
        .nav-item.active i { opacity: 1; color: #fff; }
        
        .upgrade-card { display: none !important; }
"""

onclick_logic = "document.querySelectorAll('.nav-item-group').forEach(el => {{ if(el !== this.parentElement) el.classList.remove('open') }}); this.parentElement.classList.toggle('open');"

sidebar_html = f"""<div class="logo">
        <i class="fa-solid fa-hexagon-nodes"></i>
        <span class="logo-text">Watashi⚡️Manager</span>
    </div>
    
    <div class="nav-menu">
        <div class="nav-item-group {{overview_group_class}}">
            <div class="nav-item-header {{overview_active}}" onclick="{onclick_logic}">
                <div class="nav-header-left">
                    <i class="fa-solid fa-border-all"></i>
                    <span class="nav-text">Overview</span>
                </div>
                <i class="fa-solid fa-chevron-down chevron"></i>
            </div>
            <div class="nav-accordion">
                <a href="dashboard.html" class="nav-item {{dashboard_active}}"><i class="fa-solid fa-gauge"></i> <span class="nav-text">Dashboard</span></a>
                <a href="monitoring.html" class="nav-item {{monitoring_active}}"><i class="fa-solid fa-binoculars"></i> <span class="nav-text">Monitoring</span></a>
                <a href="#" class="nav-item {{usage_active}}"><i class="fa-solid fa-chart-line"></i> <span class="nav-text">Usage</span></a>
            </div>
        </div>

        <div class="nav-item-group {{access_group_class}}">
            <div class="nav-item-header {{access_active}}" onclick="{onclick_logic}">
                <div class="nav-header-left">
                    <i class="fa-solid fa-users"></i>
                    <span class="nav-text">Access</span>
                </div>
                <i class="fa-solid fa-chevron-down chevron"></i>
            </div>
            <div class="nav-accordion">
                <a href="users.html" class="nav-item {{users_active}}"><i class="fa-solid fa-user-group"></i> <span class="nav-text">Users</span></a>
                <a href="admins.html" class="nav-item {{admins_active}}"><i class="fa-solid fa-shield-halved"></i> <span class="nav-text">Admins</span></a>
                <a href="#" class="nav-item {{account_active}}"><i class="fa-regular fa-user"></i> <span class="nav-text">My Account</span></a>
            </div>
        </div>

        <div class="nav-item-group {{network_group_class}}">
            <div class="nav-item-header {{network_active}}" onclick="{onclick_logic}">
                <div class="nav-header-left">
                    <i class="fa-solid fa-network-wired"></i>
                    <span class="nav-text">Network</span>
                </div>
                <i class="fa-solid fa-chevron-down chevron"></i>
            </div>
            <div class="nav-accordion">
                <a href="domains.html" class="nav-item {{domains_active}}"><i class="fa-solid fa-globe"></i> <span class="nav-text">Domains</span></a>
                <a href="proxies.html" class="nav-item {{proxies_active}}"><i class="fa-solid fa-network-wired"></i> <span class="nav-text">Proxies</span></a>
                <a href="tunnel.html" class="nav-item {{tunnel_active}}"><i class="fa-solid fa-route"></i> <span class="nav-text">Tunnel</span></a>
            </div>
        </div>

        <div class="nav-item-group {{system_group_class}}">
            <div class="nav-item-header {{system_active}}" onclick="{onclick_logic}">
                <div class="nav-header-left">
                    <i class="fa-solid fa-gear"></i>
                    <span class="nav-text">System</span>
                </div>
                <i class="fa-solid fa-chevron-down chevron"></i>
            </div>
            <div class="nav-accordion">
                <a href="settings.html" class="nav-item {{settings_active}}"><i class="fa-solid fa-gear"></i> <span class="nav-text">Settings</span></a>
                <a href="actions.html" class="nav-item {{actions_active}}"><i class="fa-solid fa-terminal"></i> <span class="nav-text">Actions</span></a>
                <a href="backup.html" class="nav-item {{backup_active}}"><i class="fa-solid fa-floppy-disk"></i> <span class="nav-text">Backup</span></a>
            </div>
        </div>
    </div>"""

files = glob.glob('*.html')
if 'user-panel.html' in files:
    files.remove('user-panel.html')

for filename in files:
    with open(filename, 'r', encoding='utf-8') as f:
        content = f.read()

    page_name = filename.replace('.html', '')
    if page_name == 'account': page_name = 'account'

    overview_pages = ['dashboard', 'monitoring', 'usage']
    access_pages = ['users', 'admins', 'account']
    network_pages = ['domains', 'proxies', 'tunnel']
    system_pages = ['settings', 'actions', 'backup']

    formatted_html = sidebar_html.format(
        overview_group_class='open' if page_name in overview_pages else '',
        access_group_class='open' if page_name in access_pages else '',
        network_group_class='open' if page_name in network_pages else '',
        system_group_class='open' if page_name in system_pages else '',
        
        overview_active='active' if page_name in overview_pages else '',
        access_active='active' if page_name in access_pages else '',
        network_active='active' if page_name in network_pages else '',
        system_active='active' if page_name in system_pages else '',
        
        dashboard_active='active' if page_name=='dashboard' else '',
        monitoring_active='active' if page_name=='monitoring' else '',
        usage_active='active' if page_name=='usage' else '',
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

    if '/* --- Accordion Sidebar CSS v4' in content:
        content = re.sub(r'/\* --- Accordion Sidebar CSS v4 .*?\*/.*?</style>', css_patch + '\n</style>', content, flags=re.DOTALL)
    elif '/* --- Accordion Sidebar CSS v3' in content:
        content = re.sub(r'/\* --- Accordion Sidebar CSS v3 .*?\*/.*?</style>', css_patch + '\n</style>', content, flags=re.DOTALL)
    elif '/* --- Accordion Sidebar CSS v2' in content:
        content = re.sub(r'/\* --- Accordion Sidebar CSS v2 .*?\*/.*?</style>', css_patch + '\n</style>', content, flags=re.DOTALL)
    elif '/* --- Accordion Sidebar CSS' in content:
        content = re.sub(r'/\* --- Accordion Sidebar CSS .*?\*/.*?</style>', css_patch + '\n</style>', content, flags=re.DOTALL)

    content = re.sub(r'<div class="logo">.*?</aside>', formatted_html + '\n</aside>', content, flags=re.DOTALL)
    
    with open(filename, 'w', encoding='utf-8') as f:
        f.write(content)
        
    print(f"Patched {filename} with v5 CSS")
