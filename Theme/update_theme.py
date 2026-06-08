import os
import re

theme_dir = r"d:\Downloads\Watashi-Manager\Theme"
files = [f for f in os.listdir(theme_dir) if f.endswith('.html')]

custom_css = """
        /* --- Premium Custom Scrollbar --- */
        ::-webkit-scrollbar { width: 8px; height: 8px; }
        ::-webkit-scrollbar-track { background: var(--bg-body); border-left: 1px solid var(--border-color); }
        ::-webkit-scrollbar-thumb { background: linear-gradient(180deg, var(--primary-purple) 0%, var(--primary-blue) 100%); border-radius: 10px; border: 2px solid var(--bg-body); }
        ::-webkit-scrollbar-thumb:hover { background: linear-gradient(180deg, var(--primary-blue) 0%, var(--primary-purple) 100%); }

        /* --- Premium Custom Cursor --- */
        body {
            cursor: url('data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="rgba(124,58,237,0.2)" stroke="%237c3aed" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M4 4l7.07 16.97 2.51-7.39 7.39-2.51L4 4z"/></svg>') 2 2, auto;
        }
        a, button, .btn, .nav-item, input[type="checkbox"], .toggle-slider, .slider, .tab-btn, .custom-table tr, select {
            cursor: url('data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="rgba(16,185,129,0.2)" stroke="%2310b981" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M4 4l7.07 16.97 2.51-7.39 7.39-2.51L4 4z"/></svg>') 2 2, pointer !important;
        }
        input[type="text"], input[type="password"], input[type="number"], textarea {
            cursor: url('data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="%233b82f6" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4v16m-4-16h8m-8 16h8"/></svg>') 12 12, text !important;
        }

        /* --- Enhanced Modals --- */
        .modal-box {
            box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.6), 0 0 0 1px rgba(124, 58, 237, 0.3) !important;
            background: linear-gradient(145deg, var(--bg-modal), var(--bg-card)) !important;
        }
"""

for f in files:
    path = os.path.join(theme_dir, f)
    with open(path, 'r', encoding='utf-8') as file:
        content = file.read()
    
    # Remove existing scrollbar rules
    content = re.sub(r'::-webkit-scrollbar\s*{[^}]*}', '', content)
    content = re.sub(r'::-webkit-scrollbar-track\s*{[^}]*}', '', content)
    content = re.sub(r'::-webkit-scrollbar-thumb\s*{[^}]*}', '', content)
    content = re.sub(r'::-webkit-scrollbar-thumb:hover\s*{[^}]*}', '', content)

    # Inject custom_css before </style>
    if '/* --- Premium Custom Scrollbar --- */' not in content:
        content = content.replace('</style>', custom_css + '\n</style>')
        
        with open(path, 'w', encoding='utf-8') as file:
            file.write(content)
        print(f"Updated {f}")
    else:
        print(f"Already updated {f}")

