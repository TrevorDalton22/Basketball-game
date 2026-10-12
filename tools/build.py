#!/usr/bin/env python3
"""Build helpers for the Street Hoops Roblox project (no Rojo required).

Reads src/ using Rojo's file-naming conventions and can produce:
  sourcemap.json            - for luau-lsp type checking
  build/StreetHoops.rbxlx   - an optional place file you can open in Studio
  a paste manifest          - the exact Studio path + script type of every file

Conventions (same as Rojo, so a later move to Rojo needs no renames):
  Name.server.luau  -> Script
  Name.client.luau  -> LocalScript
  Name.luau         -> ModuleScript
  Dir/init.client.luau -> LocalScript named Dir; other files in Dir are its children
  plain directory   -> Folder

Usage:
  python3 tools/build.py sourcemap
  python3 tools/build.py place
  python3 tools/build.py manifest
"""

import json
import sys
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"

# src/<top-level dir> -> (service, optional child container under that service)
SERVICES = {
    "ReplicatedStorage": ("ReplicatedStorage", None),
    "ServerScriptService": ("ServerScriptService", None),
    "StarterPlayerScripts": ("StarterPlayer", "StarterPlayerScripts"),
}


def classify(path: Path):
    name = path.name
    for suffix, cls in ((".server.luau", "Script"), (".client.luau", "LocalScript"), (".luau", "ModuleScript")):
        if name.endswith(suffix):
            return name[: -len(suffix)], cls
    return None, None


def build_node(path: Path):
    """Return a node dict {name, className, file?, children} for a src path."""
    if path.is_dir():
        init = None
        for candidate in ("init.server.luau", "init.client.luau", "init.luau"):
            if (path / candidate).exists():
                init = path / candidate
        children = []
        for child in sorted(path.iterdir(), key=lambda p: p.name.lower()):
            if init is not None and child == init:
                continue
            node = build_node(child)
            if node:
                children.append(node)
        if init is not None:
            _, cls = classify(init)
            return {"name": path.name, "className": cls, "file": init, "children": children}
        return {"name": path.name, "className": "Folder", "file": None, "children": children}
    name, cls = classify(path)
    if not cls:
        return None
    return {"name": name, "className": cls, "file": path, "children": []}


def tree():
    services = {}
    for top, (service, container) in SERVICES.items():
        top_path = SRC / top
        if not top_path.exists():
            continue
        children = [n for n in (build_node(p) for p in sorted(top_path.iterdir())) if n]
        svc = services.setdefault(service, {"name": service, "className": service, "file": None, "children": []})
        if container:
            svc["children"].append({"name": container, "className": container, "file": None, "children": children})
        else:
            svc["children"].extend(children)
    return list(services.values())


def to_sourcemap(node):
    out = {"name": node["name"], "className": node["className"]}
    if node.get("file"):
        out["filePaths"] = [str(node["file"].relative_to(ROOT))]
    if node["children"]:
        out["children"] = [to_sourcemap(c) for c in node["children"]]
    return out


def cmd_sourcemap():
    data = {"name": "StreetHoops", "className": "DataModel", "children": [to_sourcemap(s) for s in tree()]}
    (ROOT / "sourcemap.json").write_text(json.dumps(data, indent=1))
    print("wrote sourcemap.json")


def walk(node, prefix, out):
    path = f"{prefix} > {node['name']}" if prefix else node["name"]
    if node.get("file") or node["className"] == "Folder":
        out.append((path, node["className"], node.get("file")))
    for child in node["children"]:
        walk(child, path, out)


def cmd_manifest():
    rows = []
    for service in tree():
        walk(service, "", rows)
    for path, cls, file in rows:
        rel = file.relative_to(ROOT) if file else ""
        print(f"{cls:12} {path:70} {rel}")


_ref = 0


def next_ref():
    global _ref
    _ref += 1
    return f"RBX{_ref:08X}"


def item_xml(node, depth):
    pad = "  " * depth
    lines = [f'{pad}<Item class="{node["className"]}" referent="{next_ref()}">', f"{pad}  <Properties>"]
    lines.append(f'{pad}    <string name="Name">{escape(node["name"])}</string>')
    if node.get("file"):
        source = node["file"].read_text(encoding="utf-8")
        # CDATA cannot contain "]]>"; split it if it ever appears
        source = source.replace("]]>", "]]]]><![CDATA[>")
        lines.append(f'{pad}    <ProtectedString name="Source"><![CDATA[{source}]]></ProtectedString>')
    lines.append(f"{pad}  </Properties>")
    for child in node["children"]:
        lines.append(item_xml(child, depth + 1))
    lines.append(f"{pad}</Item>")
    return "\n".join(lines)


def cmd_place():
    services = tree()
    names = {s["name"] for s in services}
    # A Workspace with a camera keeps Studio happy; the server builds the map at runtime.
    parts = ['<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" version="4">']
    parts.append('  <Item class="Workspace" referent="%s">\n    <Properties>\n      <string name="Name">Workspace</string>\n    </Properties>\n  </Item>' % next_ref())
    for extra in ("Lighting", "Players", "StarterGui"):
        if extra not in names:
            parts.append(f'  <Item class="{extra}" referent="{next_ref()}">\n    <Properties>\n      <string name="Name">{extra}</string>\n    </Properties>\n  </Item>')
    for service in services:
        parts.append(item_xml(service, 1))
    parts.append("</roblox>")
    out = ROOT / "build" / "StreetHoops.rbxlx"
    out.parent.mkdir(exist_ok=True)
    out.write_text("\n".join(parts) + "\n", encoding="utf-8")
    print(f"wrote {out.relative_to(ROOT)}")


if __name__ == "__main__":
    commands = {"sourcemap": cmd_sourcemap, "manifest": cmd_manifest, "place": cmd_place}
    if len(sys.argv) != 2 or sys.argv[1] not in commands:
        print(__doc__)
        sys.exit(1)
    commands[sys.argv[1]]()
