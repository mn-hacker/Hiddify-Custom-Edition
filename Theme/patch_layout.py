import re

layout_path = r"d:\Downloads\Watashi-Manager\hiddify-panel\src\hiddifypanel\templates\admin-layout.html"

with open(layout_path, "r", encoding="utf-8") as f:
    content = f.read()

# The entire nav_bar block:
# {% block nav_bar %}
# ...
# {% endblock %}

nav_bar_match = re.search(r'{%\s*block\s*nav_bar\s*%}(.*?){%\s*endblock\s*%}', content, re.DOTALL)

new_nav_bar = """{% block nav_bar %}
<!-- Watashi Manager Modern Sidebar & Header -->
<aside class="sidebar" id="sidebar">
    <div class="logo">
        <i class="fa-solid fa-hexagon-nodes"></i>
        <span class="logo-text">{{_("master.page-title")|safe}}</span>
    </div>
    <ul class="nav-menu">
        {{ render_nav_item('admin.Dashboard:index', icon('solid','border-all','nav-icon')+(_("Parent Panel") if hutils.node.is_parent() else _('admin.menu.home')) )}}
        
        {% if hutils.node.is_child() %}
          {{ render_nav_item(hconfig(ConfigEnum.parent_panel)+"admin/user/", icon('solid','users','nav-icon')+_('admin.menu.user'), _badge=_('in parent panel') ) }}
        {% else %}
          {{ render_nav_item('flask.user.index_view', icon('solid','users','nav-icon')+_('admin.menu.user') )}}
        {% endif %}
        
        {{ render_nav_item('admin.MonitoringAdmin:index', icon('solid','binoculars','nav-icon')+_('Monitoring') )}}
        
        {% if hutils.node.is_child() %}
          {{ render_nav_item(hconfig(ConfigEnum.parent_panel)+"admin/adminuser/", icon('solid','shield-halved','nav-icon')+_('Admins'), _badge=_('in parent panel') ) }}
        {% else %}
          {{ render_nav_item('flask.adminuser.index_view', icon('solid','shield-halved','nav-icon')+_('Admins') ) }}
        {% endif %}
        
        {{ render_nav_item('flask.domain.index_view', icon('solid','globe','nav-icon')+_('admin.menu.domain') ) }}
        {{ render_nav_item('admin.ProxyAdmin:index', icon('solid','network-wired','nav-icon')+_('admin.menu.proxy') ) }}
        
        {% if g.account.mode=='super_admin' %}
          {{ render_nav_item('admin.SettingAdmin:index', icon('solid','gear','nav-icon')+_('admin.menu.config') ) }}
          {{ render_nav_item('admin.Backup:index', icon('solid','floppy-disk','nav-icon')+ _('Backup') ) }}
          {{ render_nav_item('admin.TunnelAdmin:index', icon('solid','route','nav-icon')+ _('Tunnel') ) }}
          {{ render_nav_item('admin.Actions:status', icon('solid','terminal','nav-icon')+ _('admin.actions.title') ) }}
        {% endif %}
    </ul>
    
    <div class="upgrade-card" style="margin-top: auto; opacity: 1; transform: translateY(0);">
        <h4 style="margin: 0; font-size: 14px; color: var(--primary-green);">{{version}}</h4>
        <p style="margin: 0; font-size: 12px; color: var(--text-muted);">Watashi⚡️Manager</p>
    </div>
</aside>

<header class="header main-header">
    <div class="header-left">
        <div class="header-title">{{title if title else "Admin"}}</div>
    </div>
    <div class="header-right" style="display: flex; align-items: center; gap: 16px;">
        {% if g.darkmode %}
        <a class="nav-link btn btn-outline" href="?darkmode=false"><i class="fa-solid fa-sun"></i></a>
        {% else %}
        <a class="nav-link btn btn-outline" href="?darkmode=true"><i class="fa-solid fa-moon"></i></a>
        {% endif %}
        
        <div class="user-profile" style="display: flex; align-items: center; gap: 12px; font-weight: 500;">
            {{g.account.name if g.account.name else 'Admin'}}
            <img src="https://s33.picofile.com/file/8485367300/ME.jpg" alt="Profile" class="avatar-img" style="width:36px;height:36px;border-radius:50%;object-fit:cover;border:2px solid var(--primary-purple);">
        </div>
    </div>
</header>
{% endblock %}"""

if nav_bar_match:
    content = content[:nav_bar_match.start()] + new_nav_bar + content[nav_bar_match.end():]
    with open(layout_path, "w", encoding="utf-8") as f:
        f.write(content)
    print("Patched admin-layout.html successfully.")
else:
    print("Could not find nav_bar block in admin-layout.html")
