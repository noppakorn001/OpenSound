#!/usr/bin/env python3
"""Regenerate the optional Finder layout template; no host paths or aliases.

Build-only dependencies: ds_store==1.3.1 and mac_alias==2.2.2. Install them
into build/dmg-tools, never into the application or the published source.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "build/dmg-tools"))
from ds_store import DSStore

target = ROOT / "Resources/Installer/FinderLayout.dsstore"
target.parent.mkdir(parents=True, exist_ok=True)
with DSStore.open(str(target), "w+") as store:
    store["."]["vSrn"] = ("long", 1)
    store["."]["bwsp"] = {
        "WindowBounds": "{{200, 200}, {640, 400}}",
        "ShowToolbar": False,
        "ShowStatusBar": False,
        "ShowPathbar": False,
        "ShowSidebar": False,
        "SidebarWidth": 0,
        "ContainerShowSidebar": False,
        "PreviewPaneVisibility": False,
        "ShowTabView": False,
    }
    store["."]["icvp"] = {
        "viewOptionsVersion": 1,
        "backgroundType": 0,
        "iconSize": 128.0,
        "textSize": 14.0,
        "gridSpacing": 100.0,
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "scrollPositionX": 0.0,
        "scrollPositionY": 0.0,
        "backgroundColorRed": 1.0,
        "backgroundColorGreen": 1.0,
        "backgroundColorBlue": 1.0,
        "arrangeBy": "none",
        "showIconPreview": True,
        "showItemInfo": False,
        "labelOnBottom": True,
    }
    store["."]["icvl"] = ("type", b"icnv")
    store["OpenSound.app"]["Iloc"] = (170, 170)
    store["Applications"]["Iloc"] = (470, 170)
print("Generated Finder layout with fixed window settings and two icon positions.")
