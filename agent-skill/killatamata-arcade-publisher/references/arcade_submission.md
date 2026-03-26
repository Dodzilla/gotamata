# KillaTamata Arcade Submission Requirements

This reference is the agent-side summary of the current arcade submission rules captured in `killatamata_arcade_agent_plugin_spec.md`.

## Submission Artifact

- Submit a ZIP of the exported Godot Web build folder.
- The ZIP's embedded `arcade.release.json` is the release metadata source of truth.
- The ZIP must contain:
  - `index.html`
  - at least one Godot-generated `.js`
  - at least one Godot-generated `.wasm`
  - at least one `.pck`
  - `arcade.release.json`
- The manifest `entryPath` must point to an HTML file that exists in the ZIP.
- The manifest `coverImage` path must exist in the ZIP unless a separate `coverImage` upload is provided to replace it at upload time.

## Limits

- Bundle ZIP size limit: `64 MB`
- Cover image size limit: `8 MB`
- Maximum extracted file count: `256`

## Unsupported In V1

- Godot 4 C# web exports
- Threaded web exports

## Required Manifest Fields

- `gameSlug`
- `title`
- `version`
- `engineVersion`
- `entryPath`
- `shortDescription`
- `description`
- `display.width`
- `display.height`
- `display.mode`
- `display.backgroundColor`
- `controls.primaryAction`
- `controls.secondaryAction`
- `controls.keyboard[]`
- `controls.gamepad`
- `controls.touch`
- `tags[]`
- `coverImage`
- `launchPriceUsdMicros`
- `supportsThreads`

## Safe Defaults

- `entryPath`: `index.html`
- `supportsThreads`: `false`
- web export preset name: `KillaTamata Arcade Web`
- staging base dir: `res://.gotamata/arcade_builds`

## Creator API Sequence

### New game + new release

1. `POST /api/v1/arcade/games`
2. `POST /api/v1/arcade/releases/upload`
   - `manifestJson` must exactly match `arcade.release.json` inside the ZIP
3. `PATCH /api/v1/arcade/releases/submit`

### Existing game + new release

1. `GET /api/v1/arcade/games/mine`
2. Resolve `gameId`
3. `POST /api/v1/arcade/releases/upload`
   - default game resolution can use `gameSlug` from the embedded manifest
4. `PATCH /api/v1/arcade/releases/submit`

## Validation Semantics

- Blocking issue: prevents a valid KillaTamata submission artifact from being built or accepted.
- Warning: worth review, but does not necessarily block a build.
- Missing cover image config is a blocking issue for the plugin build path because the plugin is expected to stage the manifest cover asset into the bundle.
