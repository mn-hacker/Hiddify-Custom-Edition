import glob
import re

css_patch = """
        /* --- Accordion Sidebar CSS v17 (Fix Logo Text Color in Light Mode) --- */
        .sidebar { width: 86px !important; overflow-x: hidden !important; padding: 20px 0 !important; transition: width 0.4s cubic-bezier(0.4, 0, 0.2, 1) !important; border-right: 1px solid var(--border-color); display: flex; flex-direction: column; }
        .sidebar:hover { width: 250px !important; } 
        
        /* Logo Perfect Alignment (Anchored to match panel icons) */
        .logo { display: flex; align-items: center; justify-content: flex-start; margin-bottom: 40px; height: 50px; flex-shrink: 0; padding-left: 27px; transition: all 0.4s cubic-bezier(0.4, 0, 0.2, 1); cursor: pointer; }
        .sidebar:hover .logo { padding-left: 28px; }
        
        /* Alive Animated Icon (Reactor Core) */
        .alive-icon { position: relative; width: 32px; height: 32px; display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
        .alive-icon .core { width: 10px; height: 10px; background: var(--primary-purple); border-radius: 50%; box-shadow: 0 0 10px var(--primary-purple), 0 0 20px var(--primary-purple); animation: corePulse 1.5s infinite alternate; }
        .alive-icon .ring { position: absolute; width: 22px; height: 22px; border: 2px solid transparent; border-top-color: var(--primary-green); border-bottom-color: var(--primary-green); border-radius: 50%; animation: ringSpin 3s linear infinite; }
        .alive-icon .ring2 { width: 30px; height: 30px; border-top-color: transparent; border-bottom-color: transparent; border-left-color: var(--primary-purple); border-right-color: var(--primary-purple); animation: ringSpinReverse 4s linear infinite; }
        
        @keyframes corePulse { 0% { transform: scale(0.8); box-shadow: 0 0 5px var(--primary-purple); } 100% { transform: scale(1.3); box-shadow: 0 0 15px var(--primary-purple), 0 0 30px var(--primary-purple); } }
        @keyframes ringSpin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
        @keyframes ringSpinReverse { 0% { transform: rotate(360deg); } 100% { transform: rotate(0deg); } }
        
        /* Logo Text - Uses var(--text-main) for Light/Dark mode support */
        .logo-text { max-width: 0; opacity: 0; overflow: hidden; white-space: nowrap; margin-left: 0; transition: max-width 0.4s cubic-bezier(0.4, 0, 0.2, 1), opacity 0.2s, margin-left 0.4s cubic-bezier(0.4, 0, 0.2, 1); font-size: 16px; font-weight: 700; color: var(--text-main); }
        .sidebar:hover .logo-text { max-width: 170px; opacity: 1; margin-left: 6px; transition: max-width 0.4s cubic-bezier(0.4, 0, 0.2, 1), opacity 0.3s 0.1s, margin-left 0.4s cubic-bezier(0.4, 0, 0.2, 1); }
        .logo-text .highlight { color: var(--primary-purple); }
        
        .nav-menu { list-style: none; display: flex; flex-direction: column; gap: 8px; flex: 1; align-items: stretch; padding: 0; width: 100%; overflow-y: auto; overflow-x: hidden; margin-bottom: 30px; }
        .nav-menu::-webkit-scrollbar { width: 0; }
        
        .nav-item-group { display: flex; flex-direction: column; }
        
        .nav-item-header { display: flex; align-items: center; justify-content: flex-start; padding: 12px 15px; border-radius: 8px; color: var(--text-muted); cursor: pointer; transition: all 0.3s ease; margin: 0 16px; position: relative; z-index: 1; }
        .sidebar:hover .nav-item-header { padding: 12px 16px; }
        .nav-item-header:hover { background: var(--bg-card); color: var(--text-main); }
        
        .nav-item-header::before { content: ''; position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); width: 0; height: 0; border-radius: 50%; background: linear-gradient(90deg, #6366f1 0%, #8b5cf6 100%); opacity: 0; transition: all 0.4s cubic-bezier(0.4, 0, 0.2, 1); z-index: -1; }
        .sidebar:not(:hover) .nav-item-header.active::before { width: 44px; height: 44px; opacity: 1; box-shadow: 0 4px 15px rgba(99, 102, 241, 0.25); }
        .sidebar:not(:hover) .nav-item-header.active i { color: #fff; transition: color 0.3s; }
        .sidebar:hover .nav-item-header.active { color: var(--primary-purple); }
        
        .nav-header-left { display: flex; align-items: center; }
        .nav-header-left i { font-size: 18px; width: 24px; text-align: center; flex-shrink: 0; }
        
        .nav-text { max-width: 0; opacity: 0; overflow: hidden; white-space: nowrap; margin-left: 0; transition: max-width 0.4s cubic-bezier(0.4, 0, 0.2, 1), opacity 0.2s, margin-left 0.4s cubic-bezier(0.4, 0, 0.2, 1); display: inline-block; vertical-align: middle; font-size: 14px; }
        .sidebar:hover .nav-text { max-width: 150px; opacity: 1; margin-left: 16px; transition: max-width 0.4s cubic-bezier(0.4, 0, 0.2, 1), opacity 0.3s 0.1s, margin-left 0.4s cubic-bezier(0.4, 0, 0.2, 1); }
        
        .chevron { position: absolute; right: 16px; opacity: 0; font-size: 12px; transition: opacity 0.2s, transform 0.4s cubic-bezier(0.4, 0, 0.2, 1); pointer-events: none; }
        .sidebar:hover .chevron { opacity: 1; transition: opacity 0.3s 0.1s, transform 0.4s cubic-bezier(0.4, 0, 0.2, 1); }
        .nav-item-group.open .chevron { transform: rotate(180deg); }
        
        .nav-accordion { max-height: 0; opacity: 0; overflow: hidden; transition: max-height 0.4s cubic-bezier(0.4, 0, 0.2, 1), margin 0.4s cubic-bezier(0.4, 0, 0.2, 1), opacity 0.3s; display: flex; flex-direction: column; gap: 4px; margin-top: 0; }
        .sidebar:hover .nav-item-group.open .nav-accordion { max-height: 160px; opacity: 1; margin-top: 4px; margin-bottom: 8px; }
        
        .nav-item { display: flex; align-items: center; justify-content: flex-start; padding: 10px 15px; border-radius: 8px; color: var(--text-muted); text-decoration: none; font-size: 13px; font-weight: 500; transition: all 0.3s ease; margin: 0 16px; }
        .sidebar:hover .nav-item { padding: 10px 16px 10px 40px; }
        
        .nav-item i { font-size: 14px; width: 24px; text-align: center; opacity: 0.6; transition: opacity 0.2s; flex-shrink: 0; }
        .nav-item:hover { background: var(--bg-detail); color: var(--text-main); }
        .sidebar:hover .nav-item:hover { transform: translateX(4px); }
        .nav-item:hover i { opacity: 1; color: var(--primary-purple); }
        .nav-item.active { background: linear-gradient(90deg, #6366f1 0%, #8b5cf6 100%); color: #fff; box-shadow: 0 4px 15px rgba(99, 102, 241, 0.25); }
        .nav-item.active i { opacity: 1; color: #fff; }
        
        .upgrade-card { 
            background-color: var(--bg-body) !important; 
            border: 1px solid rgba(16, 185, 129, 0.2) !important; 
            border-radius: 12px !important; 
            margin: auto 16px 20px 16px !important; 
            display: flex !important; 
            align-items: center !important; 
            justify-content: flex-start !important; 
            padding: 12px 14px !important; 
            cursor: pointer !important; 
            transition: all 0.4s cubic-bezier(0.4, 0, 0.2, 1) !important; 
            overflow: hidden !important; 
            position: relative !important; 
            flex-shrink: 0 !important; 
            text-decoration: none !important; 
            opacity: 1 !important;
            pointer-events: auto !important;
            transform: none !important;
        }
        .upgrade-card:hover { 
            background-color: var(--bg-detail) !important; 
            border-color: rgba(16, 185, 129, 0.5) !important; 
            transform: translateY(-4px) !important; 
            box-shadow: 0 6px 20px rgba(16, 185, 129, 0.15) !important; 
        }
        
        .sidebar:not(:hover) .upgrade-card {
            background-color: transparent !important;
            border-color: transparent !important;
            box-shadow: none !important;
        }
        .sidebar:not(:hover) .upgrade-card:hover {
            transform: scale(1.1) !important; 
            background-color: transparent !important;
            border-color: transparent !important;
            box-shadow: none !important; 
        }
        
        .upgrade-icon { font-size: 16px; color: var(--primary-green); width: 24px; text-align: center; flex-shrink: 0; transition: font-size 0.4s; }
        .sidebar:hover .upgrade-icon { font-size: 18px; }
        
        .upgrade-content { max-width: 0; opacity: 0; overflow: hidden; white-space: nowrap; margin-left: 0; line-height: 1.4; transition: max-width 0.4s cubic-bezier(0.4, 0, 0.2, 1), opacity 0.2s, margin-left 0.4s cubic-bezier(0.4, 0, 0.2, 1); }
        .sidebar:hover .upgrade-content { max-width: 150px; opacity: 1; margin-left: 12px; transition: max-width 0.4s cubic-bezier(0.4, 0, 0.2, 1), opacity 0.3s 0.1s, margin-left 0.4s cubic-bezier(0.4, 0, 0.2, 1); }
        .upgrade-content h4 { font-size: 12px; color: var(--primary-green); margin: 0 0 2px 0; font-weight: 600; white-space: nowrap; }
        .upgrade-content p { font-size: 10px; color: var(--text-muted); margin: 0; }
"""

onclick_logic = "document.querySelectorAll('.nav-item-group').forEach(el => {{ if(el !== this.parentElement) el.classList.remove('open') }}); this.parentElement.classList.toggle('open');"

sidebar_html = f"""<div class="logo">
        <div class="alive-icon">
            <div class="core"></div>
            <div class="ring ring1"></div>
            <div class="ring ring2"></div>
        </div>
        <span class="logo-text">Watashi <span class="highlight">Manager</span></span>
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
                <a href="account.html" class="nav-item {{account_active}}"><i class="fa-regular fa-user"></i> <span class="nav-text">My Account</span></a>
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
    </div>
    
    <a href="#" class="upgrade-card">
        <i class="fa-solid fa-bolt upgrade-icon"></i>
        <div class="upgrade-content">
            <h4>Upgrade Plan</h4>
            <p>Get more power</p>
        </div>
    </a>"""

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

    if '/* --- Accordion Sidebar CSS v16' in content:
        content = re.sub(r'/\* --- Accordion Sidebar CSS v16 .*?\*/.*?</style>', css_patch + '\n</style>', content, flags=re.DOTALL)
    elif '/* --- Accordion Sidebar CSS v15' in content:
        content = re.sub(r'/\* --- Accordion Sidebar CSS v15 .*?\*/.*?</style>', css_patch + '\n</style>', content, flags=re.DOTALL)
    elif '/* --- Accordion Sidebar CSS v14' in content:
        content = re.sub(r'/\* --- Accordion Sidebar CSS v14 .*?\*/.*?</style>', css_patch + '\n</style>', content, flags=re.DOTALL)
    elif '/* --- Accordion Sidebar CSS v13' in content:
        content = re.sub(r'/\* --- Accordion Sidebar CSS v13 .*?\*/.*?</style>', css_patch + '\n</style>', content, flags=re.DOTALL)
    elif '/* --- Accordion Sidebar CSS v12' in content:
        content = re.sub(r'/\* --- Accordion Sidebar CSS v12 .*?\*/.*?</style>', css_patch + '\n</style>', content, flags=re.DOTALL)
    elif '/* --- Accordion Sidebar CSS v11' in content:
        content = re.sub(r'/\* --- Accordion Sidebar CSS v11 .*?\*/.*?</style>', css_patch + '\n</style>', content, flags=re.DOTALL)
    elif '/* --- Accordion Sidebar CSS v10' in content:
        content = re.sub(r'/\* --- Accordion Sidebar CSS v10 .*?\*/.*?</style>', css_patch + '\n</style>', content, flags=re.DOTALL)
    elif '/* --- Accordion Sidebar CSS v9' in content:
        content = re.sub(r'/\* --- Accordion Sidebar CSS v9 .*?\*/.*?</style>', css_patch + '\n</style>', content, flags=re.DOTALL)
    elif '/* --- Accordion Sidebar CSS v8' in content:
        content = re.sub(r'/\* --- Accordion Sidebar CSS v8 .*?\*/.*?</style>', css_patch + '\n</style>', content, flags=re.DOTALL)
    elif '/* --- Accordion Sidebar CSS v7' in content:
        content = re.sub(r'/\* --- Accordion Sidebar CSS v7 .*?\*/.*?</style>', css_patch + '\n</style>', content, flags=re.DOTALL)
    elif '/* --- Accordion Sidebar CSS v6' in content:
        content = re.sub(r'/\* --- Accordion Sidebar CSS v6 .*?\*/.*?</style>', css_patch + '\n</style>', content, flags=re.DOTALL)
    elif '/* --- Accordion Sidebar CSS v5' in content:
        content = re.sub(r'/\* --- Accordion Sidebar CSS v5 .*?\*/.*?</style>', css_patch + '\n</style>', content, flags=re.DOTALL)
    elif '/* --- Accordion Sidebar CSS v4' in content:
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
        
    print(f"Patched {filename} with v17 CSS")
