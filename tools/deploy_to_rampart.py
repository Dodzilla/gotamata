#!/usr/bin/env python3

from __future__ import annotations

import argparse
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RAMPART_ROOT = ROOT.parent / "rampart"
PLUGIN_SOURCE = ROOT / "godot-plugin" / "addons" / "gotamata_agent_bridge"
SKILL_SOURCE = ROOT / "agent-skill" / "godot-editor-agent-bridge"
SKILL_DEST = Path.home() / ".codex" / "skills" / "godot-editor-agent-bridge"
PLUGIN_ENTRY = 'res://addons/gotamata_agent_bridge/plugin.cfg'
AGENTS_MARKER_BEGIN = "<!-- BEGIN GOTAMATA BRIDGE SKILL -->"
AGENTS_MARKER_END = "<!-- END GOTAMATA BRIDGE SKILL -->"


def ensure_symlink(target: Path, link_path: Path) -> None:
    if link_path.is_symlink():
        current = link_path.resolve()
        if current == target.resolve():
            return
        link_path.unlink()
    elif link_path.exists():
        raise SystemExit(f"Refusing to replace non-symlink path: {link_path}")

    link_path.parent.mkdir(parents=True, exist_ok=True)
    link_path.symlink_to(target, target_is_directory=target.is_dir())


def parse_packed_string_array(line: str) -> list[str]:
    items: list[str] = []
    start = line.find("(")
    end = line.rfind(")")
    if start == -1 or end == -1 or end <= start:
        return items
    payload = line[start + 1 : end]
    for raw in payload.split(","):
        value = raw.strip().strip('"')
        if value:
            items.append(value)
    return items


def render_packed_string_array(items: list[str]) -> str:
    rendered = ", ".join(f'"{item}"' for item in items)
    return f"enabled=PackedStringArray({rendered})"


def ensure_plugin_enabled(project_path: Path) -> None:
    text = project_path.read_text()
    lines = text.splitlines()

    section_start = None
    section_end = len(lines)
    for index, line in enumerate(lines):
        if line.strip() == "[editor_plugins]":
            section_start = index
            for next_index in range(index + 1, len(lines)):
                if lines[next_index].startswith("[") and lines[next_index].endswith("]"):
                    section_end = next_index
                    break
            break

    if section_start is None:
        if lines and lines[-1] != "":
            lines.append("")
        lines.extend(
            [
                "[editor_plugins]",
                render_packed_string_array([PLUGIN_ENTRY]),
            ]
        )
        project_path.write_text("\n".join(lines) + "\n")
        return

    enabled_index = None
    enabled_items: list[str] = []
    for index in range(section_start + 1, section_end):
        if lines[index].startswith("enabled=PackedStringArray("):
            enabled_index = index
            enabled_items = parse_packed_string_array(lines[index])
            break

    if PLUGIN_ENTRY not in enabled_items:
        enabled_items.append(PLUGIN_ENTRY)

    rendered = render_packed_string_array(enabled_items)
    if enabled_index is None:
        lines.insert(section_start + 1, rendered)
    else:
        lines[enabled_index] = rendered

    project_path.write_text("\n".join(lines) + "\n")


def ensure_agents_note(agents_path: Path) -> None:
    note = (
        f"{AGENTS_MARKER_BEGIN}\n"
        "## Installed Skills\n\n"
        "- `godot-editor-agent-bridge`: Use when an agent needs to control the local Godot editor and the GoTamata asset pipeline bridge over localhost JSON/TCP. "
        f"Skill file: `{SKILL_DEST / 'SKILL.md'}`\n"
        f"{AGENTS_MARKER_END}"
    )
    if not agents_path.exists():
        agents_path.write_text(note + "\n")
        return

    text = agents_path.read_text()
    if AGENTS_MARKER_BEGIN in text and AGENTS_MARKER_END in text:
        start = text.index(AGENTS_MARKER_BEGIN)
        end = text.index(AGENTS_MARKER_END) + len(AGENTS_MARKER_END)
        updated = text[:start] + note + text[end:]
    else:
        suffix = "" if text.endswith("\n") else "\n"
        updated = text + suffix + "\n" + note + "\n"
    agents_path.write_text(updated)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, default=DEFAULT_RAMPART_ROOT)
    args = parser.parse_args()

    project_root = args.project_root.resolve()
    project_file = project_root / "project.godot"
    agents_file = project_root / "AGENTS.md"
    addon_link = project_root / "addons" / "gotamata_agent_bridge"

    if not project_file.exists():
        raise SystemExit(f"Not a Godot project root: {project_root}")

    ensure_symlink(PLUGIN_SOURCE, addon_link)
    SKILL_DEST.parent.mkdir(parents=True, exist_ok=True)
    ensure_symlink(SKILL_SOURCE, SKILL_DEST)
    ensure_plugin_enabled(project_file)
    ensure_agents_note(agents_file)

    print(f"linked plugin: {addon_link} -> {PLUGIN_SOURCE}")
    print(f"linked skill: {SKILL_DEST} -> {SKILL_SOURCE}")
    print(f"enabled editor plugin in: {project_file}")
    print(f"updated skill note in: {agents_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
