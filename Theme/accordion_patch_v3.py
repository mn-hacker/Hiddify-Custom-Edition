import glob
import re

css_patch = """
        /* --- Accordion Sidebar CSS v3 (Perfect Centering & Smooth) --- */
        .sidebar { width: 86px !important; overflow-x: hidden !important; padding-top: 20px !important; transition: width 0.4s cubic-bezier(0.25, 0.8, 0.25, 1) !important; border-right: 1px solid var(--border-color); }
        .sidebar:hover { width: 250px !important; } 
        
        .logo { display: flex; align-items: center; padding: 0 16px; margin-bottom: 40px; overflow: hidden; }
        .logo i { font-size: 24px; min-width: 24px; text-align: center; color: var(--primary-purple); margin-left: 15px; transition: margin 0.3s; }
        .sidebar:hover .logo i { margin-left: 0; }
        .logo-text { display: inline-block !important; font-size: 18px; font-weight: 600; margin-left: 12px; opacity: 0; transition: opacity 0.2s ease; white-space: nowrap; }
        .sidebar:hover .logo-text { opacity: 1; transition-delay: 0.1s; }
        
        .nav-menu { list-style: none; display: flex; flex-direction: column; gap: 8px; flex: 1; align-items: stretch; padding: 0; width: 100%; overflow-y: auto; overflow-x: hidden; }
        .nav-menu::-webkit-scrollbar { width: 0; }
        
        .nav-item-group { display: flex; flex-direction: column; }
        
        .nav-item-header { display: flex; align-items: center; padding: 12px 15px; border-radius: 8px; color: var(--text-muted); cursor: pointer; transition: all 0.2s; margin: 0 16px; position: relative; }
        .nav-item-header:hover { background: var(--bg-card); color: var(--text-main); }
        .nav-item-header.active { color: var(--primary-purple); }
        
        .nav-header-left { display: flex; align-items: center; gap: 16px; }
        .nav-header-left i { font-size: 18px; min-width: 24px; text-align: center; }
        
        .nav-text { opacity: 0; transition: opacity 0.2s ease; white-space: nowrap; }
        .sidebar:hover .nav-text { opacity: 1; transition-delay: 0.1s; }
        
        .chevron { position: absolute; right: 16px; opacity: 0; transition: transform 0.3s, opacity 0.2s; font-size: 12px; }
        .sidebar:hover .chevron { opacity: 1; transition-delay: 0.1s; }
        .nav-item-group.open .chevron { transform: rotate(180deg); }
        
        .nav-accordion { max-height: 0; overflow: hidden; transition: max-height 0.3s ease-in-out, margin 0.3s ease-in-out, opacity 0.3s ease-in-out; display: flex; flex-direction: column; gap: 4px; opacity: 0; margin-top: 0; }
        .nav-item-group.open .nav-accordion { max-height: 350px; opacity: 1; margin-top: 4px; margin-bottom: 8px; }
        
        .nav-item { display: flex; align-items: center; gap: 16px; padding: 10px 15px; border-radius: 8px; color: var(--text-muted); text-decoration: none; font-size: 13px; font-weight: 500; transition: all 0.2s; white-space: nowrap; margin: 0 16px; }
        .sidebar:hover .nav-accordion .nav-item { padding-left: 24px; } 
        
        .nav-item i { font-size: 14px; min-width: 24px; text-align: center; opacity: 0.6; transition: opacity 0.2s; }
        .nav-item:hover { background: var(--bg-detail); color: var(--text-main); transform: translateX(4px); }
        .nav-item:hover i { opacity: 1; color: var(--primary-purple); }
        .nav-item.active { background: linear-gradient(90deg, #6366f1 0%, #8b5cf6 100%); color: #fff; box-shadow: 0 4px 15px rgba(99, 102, 241, 0.25); }
        .nav-item.active i { opacity: 1; color: #fff; }
        
        .upgrade-card { background-color: var(--bg-body); border: 1px solid rgba(16, 185, 129, 0.2); padding: 16px; border-radius: 12px; margin: auto 16px 20px 16px; opacity: 0; transform: translateY(10px); pointer-events: none; transition: all 0.4s ease; cursor: pointer; display: block !important; white-space: normal; }
        .sidebar:hover .upgrade-card { opacity: 1; transform: translateY(0); pointer-events: auto; }
        .upgrade-card h4 { font-size: 12px; color: var(--primary-green); margin-bottom: 4px; }
        .upgrade-card p { font-size: 10px; color: var(--text-muted); }
        .upgrade-card-mini { display: none !important; }
"""

files = glob.glob('*.html')
if 'user-panel.html' in files:
    files.remove('user-panel.html')

for filename in files:
    with open(filename, 'r', encoding='utf-8') as f:
        content = f.read()

    # We just need to replace the Accordion Sidebar CSS v2 with v3
    if '/* --- Accordion Sidebar CSS v2 (Click) --- */' in content:
        content = re.sub(r'/\* --- Accordion Sidebar CSS v2 \(Click\) ---\s*\*/.*?</style>', css_patch + '\n</style>', content, flags=re.DOTALL)
    elif '/* --- Accordion Sidebar CSS --- */' in content:
        content = re.sub(r'/\* --- Accordion Sidebar CSS ---\s*\*/.*?</style>', css_patch + '\n</style>', content, flags=re.DOTALL)

    with open(filename, 'w', encoding='utf-8') as f:
        f.write(content)
        
    print(f"Patched {filename} with v3 CSS")
