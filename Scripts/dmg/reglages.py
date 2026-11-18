# Réglages de dmgbuild : fenêtre d'installation de Cardinal (fond, taille, place des icônes).
# Variables reçues avec -D : app (chemin de Cardinal.app), fond (fond.tiff).
import os.path

app = defines['app']
files = [app]
symlinks = {'Applications': '/Applications'}
format = 'UDZO'
filesystem = 'HFS+'
icon = os.path.join(app, 'Contents', 'Resources', 'AppIcon.icns')
background = defines['fond']
window_rect = ((200, 120), (660, 400))
default_view = 'icon-view'
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 104
text_size = 13
arrange_by = None
icon_locations = {
    'Cardinal.app': (180, 200),
    'Applications': (480, 200),
}
hide_extensions = ['Cardinal.app']
