import re

# Update backup.html
with open('backup.html', 'r', encoding='utf-8') as f:
    backup_content = f.read()

backup_content = backup_content.replace('<title>Watashi⚡️Manager - Panel Settings</title>', '<title>Watashi⚡️Manager - Backup Manager</title>')
backup_content = backup_content.replace('class="nav-item active">', 'class="nav-item">')
backup_content = backup_content.replace('href="backup.html" class="nav-item"', 'href="backup.html" class="nav-item active"')
backup_content = backup_content.replace('<div class="header-title">Panel Settings</div>', '<div class="header-title">Backup & Restore</div>')

# Replace layout
layout_match = re.search(r'<div class="settings-layout">.*?</div>\s*</div>\s*</main>', backup_content, re.DOTALL)

new_layout = """<div class="settings-layout">
            <div class="settings-content" style="width:100%; max-width: 800px; margin: 0 auto;">
                
                <div class="settings-card animated-item delay-1">
                    <div class="card-header">
                        <i class="fa-solid fa-cloud-arrow-down"></i>
                        <h3>System Backup</h3>
                    </div>
                    <div class="card-body">
                        <div class="setting-item" style="flex-direction: column; align-items: center; text-align: center; padding: 40px;">
                            <i class="fa-solid fa-server" style="font-size: 64px; color: var(--primary-blue); margin-bottom: 20px;"></i>
                            <h4 style="margin-bottom: 10px; font-size: 18px;">Download Server Configuration</h4>
                            <p style="color: var(--text-muted); margin-bottom: 30px; max-width: 400px; font-size: 14px;">Generate and download a full backup of your panel configuration, users, and proxy settings. Keep this file safe.</p>
                            <button class="btn btn-primary" style="font-size: 16px; padding: 12px 30px;"><i class="fa-solid fa-download"></i> Generate & Download Backup</button>
                        </div>
                    </div>
                </div>

                <div class="settings-card animated-item delay-2">
                    <div class="card-header">
                        <i class="fa-solid fa-cloud-arrow-up"></i>
                        <h3>Restore System</h3>
                    </div>
                    <div class="card-body">
                        <div class="setting-item" style="flex-direction: column; align-items: center; text-align: center; padding: 40px; border: 2px dashed var(--border-color); margin: 20px; border-radius: 12px; background: rgba(255,255,255,0.02);">
                            <i class="fa-solid fa-file-import" style="font-size: 48px; color: var(--primary-purple); margin-bottom: 20px;"></i>
                            <h4 style="margin-bottom: 10px;">Upload Backup File</h4>
                            <p style="color: var(--text-muted); margin-bottom: 20px; font-size: 13px;">Drag and drop your .json backup file here, or click to browse.</p>
                            <input type="file" id="backupFile" style="display: none;">
                            <button class="btn btn-outline" onclick="document.getElementById('backupFile').click()"><i class="fa-solid fa-folder-open"></i> Select File</button>
                            <div style="margin-top: 30px; width: 100%;">
                                <button class="btn btn-danger" style="width: 100%; justify-content: center;"><i class="fa-solid fa-rotate-left"></i> Restore Configuration</button>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </main>"""

if layout_match:
    backup_content = backup_content[:layout_match.start()] + new_layout + backup_content[layout_match.end():]

with open('backup.html', 'w', encoding='utf-8') as f:
    f.write(backup_content)

# Update tunnel.html
with open('tunnel.html', 'r', encoding='utf-8') as f:
    tunnel_content = f.read()

tunnel_content = tunnel_content.replace('<title>Watashi⚡️Manager - Panel Settings</title>', '<title>Watashi⚡️Manager - Server Tunnels</title>')
tunnel_content = tunnel_content.replace('class="nav-item active">', 'class="nav-item">')
tunnel_content = tunnel_content.replace('href="tunnel.html" class="nav-item"', 'href="tunnel.html" class="nav-item active"')
tunnel_content = tunnel_content.replace('<div class="header-title">Panel Settings</div>', '<div class="header-title">Tunnel Management</div>')

new_tunnel_layout = """<div class="settings-layout">
            <div class="settings-content" style="width:100%;">
                
                <div class="settings-card animated-item delay-1">
                    <div class="card-header" style="justify-content: space-between;">
                        <div style="display: flex; align-items: center; gap: 12px;">
                            <i class="fa-solid fa-route"></i>
                            <h3>Active Tunnels</h3>
                        </div>
                        <button class="btn btn-green"><i class="fa-solid fa-plus"></i> Add Tunnel</button>
                    </div>
                    <div class="card-body">
                        <div style="padding: 20px;">
                            <div style="background: var(--bg-body); border: 1px solid var(--border-color); border-radius: 12px; padding: 20px; display: flex; justify-content: space-between; align-items: center;">
                                <div style="display: flex; align-items: center; gap: 20px;">
                                    <div style="width: 50px; height: 50px; border-radius: 12px; background: rgba(59, 130, 246, 0.1); color: var(--primary-blue); display: flex; align-items: center; justify-content: center; font-size: 24px;">
                                        <i class="fa-solid fa-server"></i>
                                    </div>
                                    <div>
                                        <h4 style="margin-bottom: 5px;">Iran Relay Node 1</h4>
                                        <div style="display: flex; gap: 15px; font-size: 12px; color: var(--text-muted);">
                                            <span><i class="fa-solid fa-globe"></i> IP: 185.12.x.x</span>
                                            <span><i class="fa-solid fa-diagram-project"></i> Mode: GRE</span>
                                            <span><i class="fa-solid fa-signal" style="color: var(--primary-green);"></i> Status: Connected</span>
                                        </div>
                                    </div>
                                </div>
                                <div style="display: flex; gap: 10px;">
                                    <button class="btn btn-outline"><i class="fa-solid fa-pen"></i> Edit</button>
                                    <button class="btn btn-danger"><i class="fa-solid fa-trash"></i></button>
                                </div>
                            </div>
                        </div>
                        
                        <div style="padding: 0 20px 20px 20px;">
                            <div style="background: var(--bg-body); border: 1px dashed var(--border-color); border-radius: 12px; padding: 20px; text-align: center; color: var(--text-muted); cursor: pointer; transition: all 0.3s;" onmouseover="this.style.borderColor='var(--primary-purple)'; this.style.color='var(--primary-purple)'" onmouseout="this.style.borderColor='var(--border-color)'; this.style.color='var(--text-muted)'">
                                <i class="fa-solid fa-plus-circle" style="font-size: 24px; margin-bottom: 10px;"></i>
                                <p>Click here to configure a new tunnel (Wireguard, GRE, IPIP, etc.)</p>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </main>"""

if layout_match:
    tunnel_content = tunnel_content[:layout_match.start()] + new_tunnel_layout + tunnel_content[layout_match.end():]

with open('tunnel.html', 'w', encoding='utf-8') as f:
    f.write(tunnel_content)
