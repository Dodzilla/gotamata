# KillaTamata Arcade Publisher

This repository contains two pieces that work together:

- a Codex skill: `killatamata-arcade-publisher`
- a Godot plugin: `killatamata_arcade_bridge`

The skill helps an agent inspect, validate, build, and submit a Godot game for KillaTamata Arcade.
The plugin exposes a narrow localhost bridge from the Godot editor so the skill can safely interact with the project.

## Repo Layout

- `agent-skill/killatamata-arcade-publisher`: Codex skill package
- `godot-plugin/addons/killatamata_arcade_bridge`: Godot addon
- `killatamata_arcade_agent_plugin_spec.md`: architecture and product spec

## Prerequisites

Install these before setting anything up:

- Codex desktop or another Codex environment that supports local skills
- Godot `4.6`
- `python3`

Optional but commonly needed for submission:

- KillaTamata creator API auth in one of these environment variable forms:
  - `KILLATAMATA_API_TOKEN`
  - `KILLATAMATA_COOKIE`
  - `KILLATAMATA_AUTH_HEADER` plus `KILLATAMATA_AUTH_VALUE`

## Install The Skill

The skill must be installed into your local Codex skills directory so Codex can discover it.

### 1. Create the target skills directory

On macOS and Linux:

```bash
mkdir -p ~/.codex/skills
```

If your Codex setup uses a custom `CODEX_HOME`, use:

```bash
mkdir -p "${CODEX_HOME:-$HOME/.codex}/skills"
```

### 2. Copy or symlink the skill into Codex

From the root of this repo, choose one of these options.

Copy the skill:

```bash
cp -R agent-skill/killatamata-arcade-publisher "${CODEX_HOME:-$HOME/.codex}/skills/"
```

Or symlink it for local development so changes in this repo are picked up immediately:

```bash
ln -s "$(pwd)/agent-skill/killatamata-arcade-publisher" "${CODEX_HOME:-$HOME/.codex}/skills/killatamata-arcade-publisher"
```

If the symlink target already exists, remove or rename the old one first.

### 3. Restart Codex

Restart Codex after installing the skill so it rescans the skills directory.

### 4. Verify the skill files are present

You should now have:

```text
${CODEX_HOME:-$HOME/.codex}/skills/killatamata-arcade-publisher/SKILL.md
${CODEX_HOME:-$HOME/.codex}/skills/killatamata-arcade-publisher/scripts/send_bridge_command.py
${CODEX_HOME:-$HOME/.codex}/skills/killatamata-arcade-publisher/scripts/submission_client.py
```

### 5. Verify the skill can reach the bridge

Once the Godot plugin is installed and enabled, test the connection with:

```bash
cd "${CODEX_HOME:-$HOME/.codex}/skills/killatamata-arcade-publisher"
python3 scripts/send_bridge_command.py ping
```

Expected result: a JSON response with `"ok": true` and a `pong` message.

## Install The Godot Plugin

The plugin must be copied into the Godot project's `addons` folder and then enabled in the editor.

### 1. Create the destination folder in your Godot project

From your Godot project root:

```bash
mkdir -p addons
```

### 2. Copy the addon into the project

From this repo root, copy the plugin folder into the target Godot project:

```bash
cp -R godot-plugin/addons/killatamata_arcade_bridge /path/to/your-godot-project/addons/
```

After copying, this file should exist inside the Godot project:

```text
/path/to/your-godot-project/addons/killatamata_arcade_bridge/plugin.cfg
```

If you want the Godot project to track live edits from this repo during development, you can symlink instead:

```bash
ln -s "$(pwd)/godot-plugin/addons/killatamata_arcade_bridge" /path/to/your-godot-project/addons/killatamata_arcade_bridge
```

### 3. Open the project in Godot 4.6

Launch Godot and open the target project.

### 4. Enable the plugin

In the Godot editor:

1. Open `Project > Project Settings`.
2. Open the `Plugins` tab.
3. Find `KillaTamata Arcade Bridge`.
4. Set it to `Active`.

The plugin metadata comes from:

- `godot-plugin/addons/killatamata_arcade_bridge/plugin.cfg`

### 5. Confirm the bridge is running

With the plugin enabled and the project open in Godot, test the localhost bridge from a terminal:

```bash
cd "${CODEX_HOME:-$HOME/.codex}/skills/killatamata-arcade-publisher"
python3 scripts/send_bridge_command.py ping
```

If the plugin is active, the default bridge endpoint is:

- host: `127.0.0.1`
- port: `47891`

## Install Both Together

If you want the shortest path to a working setup:

1. Clone this repo.
2. Install the skill into `${CODEX_HOME:-$HOME/.codex}/skills/killatamata-arcade-publisher`.
3. Copy `godot-plugin/addons/killatamata_arcade_bridge` into your Godot project's `addons/` folder.
4. Open the Godot project and enable `KillaTamata Arcade Bridge`.
5. Run `python3 scripts/send_bridge_command.py ping` from the installed skill directory.

## First Use

After both pieces are installed:

1. Open the target Godot project with the plugin enabled.
2. In Codex, invoke the `killatamata-arcade-publisher` skill for that project.
3. Start with inspection commands such as:

```bash
cd "${CODEX_HOME:-$HOME/.codex}/skills/killatamata-arcade-publisher"
python3 scripts/send_bridge_command.py project_state
python3 scripts/send_bridge_command.py get_arcade_project_config
python3 scripts/send_bridge_command.py validate_arcade_project
```

4. Use the submission client only after validation passes and a build ZIP exists.

Example auth check:

```bash
cd "${CODEX_HOME:-$HOME/.codex}/skills/killatamata-arcade-publisher"
python3 scripts/submission_client.py auth-state --base-url https://creator.example.com
```

## Troubleshooting

### Codex does not see the skill

- Confirm the installed path ends at `.../skills/killatamata-arcade-publisher/SKILL.md`.
- Restart Codex after installing or updating the skill.
- If you used a symlink, confirm it points to this repo's `agent-skill/killatamata-arcade-publisher` directory.

### `ping` cannot connect

- Make sure the Godot project is open.
- Make sure the plugin is enabled in `Project Settings > Plugins`.
- Confirm nothing else is using port `47891`.
- Confirm you are running the helper script from the installed skill directory or using the correct script path.

### Submission client reports missing auth

Set one of the supported auth configurations before using `submission_client.py`:

```bash
export KILLATAMATA_API_TOKEN="..."
```

or

```bash
export KILLATAMATA_COOKIE="..."
```

or

```bash
export KILLATAMATA_AUTH_HEADER="Authorization"
export KILLATAMATA_AUTH_VALUE="Bearer ..."
```

## Additional Docs

- Skill instructions: `agent-skill/killatamata-arcade-publisher/SKILL.md`
- Plugin bridge details: `godot-plugin/addons/killatamata_arcade_bridge/README.md`
- System spec: `killatamata_arcade_agent_plugin_spec.md`
