import os


application = defines["app"]  # noqa: F821
background = defines["background"]  # noqa: F821
volume_icon = defines["volume_icon"]  # noqa: F821

if not os.path.isdir(application):
    raise RuntimeError(f"Application bundle does not exist: {application}")
if not os.path.isfile(background):
    raise RuntimeError(f"DMG background does not exist: {background}")
if not os.path.isfile(volume_icon):
    raise RuntimeError(f"DMG volume icon does not exist: {volume_icon}")

format = "UDZO"
filesystem = "HFS+"
files = [(application, "WindowRanger.app")]
symlinks = {"Applications": "/Applications"}
icon = volume_icon
background = background

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
window_rect = ((100, 100), (720, 450))
default_view = "icon-view"
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False

arrange_by = None
grid_offset = (0, 0)
grid_spacing = 90
scroll_position = (0, 0)
label_pos = "bottom"
text_size = 14
icon_size = 128
icon_locations = {
    "WindowRanger.app": (175, 225),
    "Applications": (545, 225),
}
