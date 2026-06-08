import glob
import re

css_patch = """
        /* --- Flyout Sidebar CSS --- */
        .sidebar { width: 86px !important; overflow: visible !important; padding-top: 30px; transition: none !important; }
        .sidebar:hover { width: 86px !important; } 
        .logo { display: flex; justify-content: center; margin-bottom: 40px; padding: 0; }
        .logo i { font-size: 28px; }
        .logo-text { display: none !important; }
        .nav-menu { list-style: none; display: flex; flex-direction: column; gap: 16px; flex: 1; align-items: center; padding: 0; width: 100%; }
        .nav-item-group { position: relative; width: 100%; display: flex; justify-content: center; }
        .nav-item-header { width: 50px; height: 50px; display: flex; align-items: center; justify-content: center; border-radius: 14px; color: var(--text-muted); cursor: pointer; transition: all 0.3s; }
        .nav-item-header.active { background: linear-gradient(135deg, rgba(99, 102, 241, 0.15) 0%, rgba(139, 92, 246, 0.15) 100%); color: var(--primary-purple); box-shadow: inset 0 0 0 1px rgba(124, 58, 237, 0.3); }
        .nav-item-header:hover, .nav-item-group:hover .nav-item-header { background: var(--bg-card); color: var(--text-main); box-shadow: 0 4px 12px rgba(0,0,0,0.2); }
        .nav-item-header i { font-size: 22px; }
        .nav-flyout { position: absolute; top: -10px; left: 70px; width: 220px; background: rgba(21, 26, 42, 0.85); backdrop-filter: blur(16px); -webkit-backdrop-filter: blur(16px); border: 1px solid var(--border-color); border-radius: 14px; padding: 16px; box-shadow: 0 15px 35px rgba(0,0,0,0.5), inset 0 0 0 1px rgba(255,255,255,0.05); opacity: 0; visibility: hidden; transform: translateX(-15px); transition: all 0.3s cubic-bezier(0.34, 1.56, 0.64, 1); z-index: 10000; pointer-events: none; }
        [data-theme="light"] .nav-flyout { background: rgba(255, 255, 255, 0.85); box-shadow: 0 15px 35px rgba(0,0,0,0.1); }
        .nav-item-group:hover .nav-flyout { opacity: 1; visibility: visible; transform: translateX(0); pointer-events: auto; }
        .flyout-title { font-size: 11px; font-weight: 700; color: var(--text-muted); text-transform: uppercase; letter-spacing: 1px; margin-bottom: 12px; padding-bottom: 10px; border-bottom: 1px solid var(--border-color); }
        .flyout-item { display: flex; align-items: center; gap: 12px; padding: 10px 14px; border-radius: 8px; color: var(--text-main); text-decoration: none; font-size: 13px; font-weight: 500; transition: all 0.2s; margin-bottom: 4px; }
        .flyout-item i { font-size: 16px; width: 20px; text-align: center; opacity: 0.6; transition: opacity 0.2s; }
        .flyout-item:hover { background: var(--bg-detail); transform: translateX(4px); }
        .flyout-item:hover i { opacity: 1; color: var(--primary-purple); }
        .flyout-item.active { background: linear-gradient(90deg, #6366f1 0%, #8b5cf6 100%); color: #fff; box-shadow: 0 4px 15px rgba(99, 102, 241, 0.25); }
        .flyout-item.active i { opacity: 1; color: #fff; }
        .upgrade-card { display: none !important; } /* Hide old upgrade card */
        .upgrade-card-mini { margin-top: auto; width: 50px; height: 50px; display: flex; align-items: center; justify-content: center; border-radius: 14px; background: rgba(16, 185, 129, 0.1); color: var(--primary-green); cursor: pointer; position: relative; transition: all 0.3s; margin-bottom: 20px; }
        .upgrade-card-mini:hover { background: rgba(16, 185, 129, 0.2); }
        .upgrade-flyout { top: auto; bottom: 0; left: 70px; }
        .upgrade-card-mini:hover .upgrade-flyout { opacity: 1; visibility: visible; transform: translateX(0); pointer-events: auto; }
        .upgrade-flyout h4 { font-size: 14px; color: var(--primary-green); margin-bottom: 4px; }
        .upgrade-flyout p { font-size: 12px; color: var(--text-muted); margin: 0; }
"""

sidebar_html = """<div class="nav-menu">
        <div class="nav-item-group">
            <div class="nav-item-header {overview_active}">
                <i class="fa-solid fa-border-all"></i>
            </div>
            <div class="nav-flyout">
                <div class="flyout-title">Overview</div>
                <a href="dashboard.html" class="flyout-item {dashboard_active}"><i class="fa-solid fa-gauge"></i> Dashboard</a>
                <a href="monitoring.html" class="flyout-item {monitoring_active}"><i class="fa-solid fa-binoculars"></i> Monitoring</a>
                <a href="#" class="flyout-item {usage_active}"><i class="fa-solid fa-chart-line"></i> Usage</a>
            </div>
        </div>

        <div class="nav-item-group">
            <div class="nav-item-header {access_active}">
                <i class="fa-solid fa-users"></i>
            </div>
            <div class="nav-flyout">
                <div class="flyout-title">Access & Users</div>
                <a href="users.html" class="flyout-item {users_active}"><i class="fa-solid fa-user-group"></i> Users</a>
                <a href="admins.html" class="flyout-item {admins_active}"><i class="fa-solid fa-shield-halved"></i> Admins</a>
                <a href="#" class="flyout-item {account_active}"><i class="fa-regular fa-user"></i> My Account</a>
            </div>
        </div>

        <div class="nav-item-group">
            <div class="nav-item-header {network_active}">
                <i class="fa-solid fa-network-wired"></i>
            </div>
            <div class="nav-flyout">
                <div class="flyout-title">Network & Config</div>
                <a href="domains.html" class="flyout-item {domains_active}"><i class="fa-solid fa-globe"></i> Domains</a>
                <a href="proxies.html" class="flyout-item {proxies_active}"><i class="fa-solid fa-network-wired"></i> Proxies</a>
                <a href="tunnel.html" class="flyout-item {tunnel_active}"><i class="fa-solid fa-route"></i> Tunnel</a>
            </div>
        </div>

        <div class="nav-item-group">
            <div class="nav-item-header {system_active}">
                <i class="fa-solid fa-gear"></i>
            </div>
            <div class="nav-flyout">
                <div class="flyout-title">System</div>
                <a href="settings.html" class="flyout-item {settings_active}"><i class="fa-solid fa-gear"></i> Settings</a>
                <a href="actions.html" class="flyout-item {actions_active}"><i class="fa-solid fa-terminal"></i> Actions</a>
                <a href="backup.html" class="flyout-item {backup_active}"><i class="fa-solid fa-floppy-disk"></i> Backup</a>
            </div>
        </div>
    </div>
    
    <div class="upgrade-card-mini">
        <i class="fa-solid fa-bolt"></i>
        <div class="nav-flyout upgrade-flyout">
            <h4>Upgrade Plan</h4>
            <p>Get more processing power.</p>
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

    # Determine which header should be active
    overview_pages = ['dashboard', 'monitoring', 'usage']
    access_pages = ['users', 'admins', 'account']
    network_pages = ['domains', 'proxies', 'tunnel']
    system_pages = ['settings', 'actions', 'backup']

    formatted_html = sidebar_html.format(
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

    if '/* --- Flyout Sidebar CSS --- */' not in content:
        content = content.replace('</style>', css_patch + '\n</style>')

    # Replace old <ul class="nav-menu"> and <div class="upgrade-card">
    content = re.sub(r'<ul class="nav-menu">.*?</aside>', formatted_html + '\n</aside>', content, flags=re.DOTALL)
    
    with open(filename, 'w', encoding='utf-8') as f:
        f.write(content)
        
    print(f"Patched {filename}")
