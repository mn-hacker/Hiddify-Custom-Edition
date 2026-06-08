import glob
import re

css_patch = """
        /* --- Accordion Sidebar CSS --- */
        .sidebar { width: 86px !important; overflow-x: hidden !important; padding-top: 20px !important; transition: width 0.4s cubic-bezier(0.25, 0.8, 0.25, 1) !important; border-right: 1px solid var(--border-color); }
        .sidebar:hover { width: 250px !important; } 
        .logo { display: flex; align-items: center; justify-content: flex-start; margin-bottom: 40px; padding-left: 20px; }
        .logo i { font-size: 24px; min-width: 24px; text-align: center; color: var(--primary-purple); }
        .logo-text { display: inline-block !important; font-size: 18px; font-weight: 600; margin-left: 12px; opacity: 0; transition: opacity 0.2s ease; white-space: nowrap; }
        .sidebar:hover .logo-text { opacity: 1; transition-delay: 0.1s; }
        
        .nav-menu { list-style: none; display: flex; flex-direction: column; gap: 8px; flex: 1; align-items: stretch; padding: 0; width: 100%; }
        .nav-item-group { display: flex; flex-direction: column; }
        .nav-item-header { display: flex; justify-content: space-between; align-items: center; padding: 12px 14px; border-radius: 8px; color: var(--text-muted); cursor: pointer; transition: all 0.3s; margin: 0 10px; }
        .nav-item-header:hover { background: var(--bg-card); color: var(--text-main); }
        .nav-item-header.active { color: var(--primary-purple); }
        .nav-header-left { display: flex; align-items: center; gap: 12px; }
        .nav-header-left i { font-size: 18px; min-width: 24px; text-align: center; }
        .nav-text { opacity: 0; transition: opacity 0.2s ease; white-space: nowrap; }
        .sidebar:hover .nav-text { opacity: 1; transition-delay: 0.1s; }
        .chevron { opacity: 0; transition: transform 0.3s, opacity 0.2s; font-size: 12px; }
        .sidebar:hover .chevron { opacity: 1; transition-delay: 0.1s; }
        .nav-item-group:hover .chevron { transform: rotate(180deg); }
        
        .nav-accordion { max-height: 0; overflow: hidden; transition: max-height 0.4s cubic-bezier(0.25, 0.8, 0.25, 1); display: flex; flex-direction: column; gap: 4px; padding: 0 10px 0 34px; }
        .nav-item-group:hover .nav-accordion, .nav-item-group.open .nav-accordion { max-height: 300px; margin-top: 4px; margin-bottom: 4px; }
        
        .nav-item { display: flex; align-items: center; gap: 12px; padding: 10px 14px; border-radius: 8px; color: var(--text-muted); text-decoration: none; font-size: 13px; font-weight: 500; transition: all 0.2s; white-space: nowrap; }
        .nav-item i { font-size: 14px; width: 20px; text-align: center; opacity: 0.6; transition: opacity 0.2s; }
        .nav-item:hover { background: var(--bg-detail); color: var(--text-main); transform: translateX(4px); }
        .nav-item:hover i { opacity: 1; color: var(--primary-purple); }
        .nav-item.active { background: linear-gradient(90deg, #6366f1 0%, #8b5cf6 100%); color: #fff; box-shadow: 0 4px 15px rgba(99, 102, 241, 0.25); }
        .nav-item.active i { opacity: 1; color: #fff; }
        
        .upgrade-card { background-color: var(--bg-body); border: 1px solid rgba(16, 185, 129, 0.2); padding: 16px; border-radius: 12px; margin: auto 10px 20px 10px; opacity: 0; transform: translateY(10px); pointer-events: none; transition: all 0.4s ease; cursor: pointer; display: block !important; white-space: normal; }
        .sidebar:hover .upgrade-card { opacity: 1; transform: translateY(0); pointer-events: auto; }
        .upgrade-card h4 { font-size: 12px; color: var(--primary-green); margin-bottom: 4px; }
        .upgrade-card p { font-size: 10px; color: var(--text-muted); }
        .upgrade-card-mini { display: none !important; }
"""

sidebar_html = """<div class="logo">
        <i class="fa-solid fa-hexagon-nodes"></i>
        <span class="logo-text">Watashi⚡️Manager</span>
    </div>
    
    <div class="nav-menu">
        <div class="nav-item-group {overview_group_class}">
            <div class="nav-item-header {overview_active}">
                <div class="nav-header-left">
                    <i class="fa-solid fa-border-all"></i>
                    <span class="nav-text">Overview</span>
                </div>
                <i class="fa-solid fa-chevron-down chevron"></i>
            </div>
            <div class="nav-accordion">
                <a href="dashboard.html" class="nav-item {dashboard_active}"><i class="fa-solid fa-gauge"></i> <span class="nav-text">Dashboard</span></a>
                <a href="monitoring.html" class="nav-item {monitoring_active}"><i class="fa-solid fa-binoculars"></i> <span class="nav-text">Monitoring</span></a>
                <a href="#" class="nav-item {usage_active}"><i class="fa-solid fa-chart-line"></i> <span class="nav-text">Usage</span></a>
            </div>
        </div>

        <div class="nav-item-group {access_group_class}">
            <div class="nav-item-header {access_active}">
                <div class="nav-header-left">
                    <i class="fa-solid fa-users"></i>
                    <span class="nav-text">Access</span>
                </div>
                <i class="fa-solid fa-chevron-down chevron"></i>
            </div>
            <div class="nav-accordion">
                <a href="users.html" class="nav-item {users_active}"><i class="fa-solid fa-user-group"></i> <span class="nav-text">Users</span></a>
                <a href="admins.html" class="nav-item {admins_active}"><i class="fa-solid fa-shield-halved"></i> <span class="nav-text">Admins</span></a>
                <a href="#" class="nav-item {account_active}"><i class="fa-regular fa-user"></i> <span class="nav-text">My Account</span></a>
            </div>
        </div>

        <div class="nav-item-group {network_group_class}">
            <div class="nav-item-header {network_active}">
                <div class="nav-header-left">
                    <i class="fa-solid fa-network-wired"></i>
                    <span class="nav-text">Network</span>
                </div>
                <i class="fa-solid fa-chevron-down chevron"></i>
            </div>
            <div class="nav-accordion">
                <a href="domains.html" class="nav-item {domains_active}"><i class="fa-solid fa-globe"></i> <span class="nav-text">Domains</span></a>
                <a href="proxies.html" class="nav-item {proxies_active}"><i class="fa-solid fa-network-wired"></i> <span class="nav-text">Proxies</span></a>
                <a href="tunnel.html" class="nav-item {tunnel_active}"><i class="fa-solid fa-route"></i> <span class="nav-text">Tunnel</span></a>
            </div>
        </div>

        <div class="nav-item-group {system_group_class}">
            <div class="nav-item-header {system_active}">
                <div class="nav-header-left">
                    <i class="fa-solid fa-gear"></i>
                    <span class="nav-text">System</span>
                </div>
                <i class="fa-solid fa-chevron-down chevron"></i>
            </div>
            <div class="nav-accordion">
                <a href="settings.html" class="nav-item {settings_active}"><i class="fa-solid fa-gear"></i> <span class="nav-text">Settings</span></a>
                <a href="actions.html" class="nav-item {actions_active}"><i class="fa-solid fa-terminal"></i> <span class="nav-text">Actions</span></a>
                <a href="backup.html" class="nav-item {backup_active}"><i class="fa-solid fa-floppy-disk"></i> <span class="nav-text">Backup</span></a>
            </div>
        </div>
    </div>
    
    <div class="upgrade-card">
        <h4>Upgrade Plan</h4>
        <p>Get more processing power.</p>
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

    # Insert CSS
    if '/* --- Accordion Sidebar CSS --- */' not in content:
        if '/* --- Flyout Sidebar CSS --- */' in content:
            content = re.sub(r'/\* --- Flyout Sidebar CSS ---\s*\*/.*?</style>', css_patch + '\n</style>', content, flags=re.DOTALL)
        else:
            content = content.replace('</style>', css_patch + '\n</style>')

    # Replace old <div class="logo"> ... </aside>
    content = re.sub(r'<div class="logo">.*?</aside>', formatted_html + '\n</aside>', content, flags=re.DOTALL)
    
    with open(filename, 'w', encoding='utf-8') as f:
        f.write(content)
        
    print(f"Patched {filename}")
