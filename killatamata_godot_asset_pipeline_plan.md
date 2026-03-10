# KillaTamata Godot Asset Pipeline Plan

## Overview

This document captures a recommended architecture for a **Godot-native, modular asset creation pipeline** powered by KillaTamata generative AI and a custom Godot plugin.

The target audience is primarily **solo developers and very small teams** who already work inside the Godot editor. Because of that, the main workflow should live inside **Godot**, not in a browser.

A browser can still be useful later for lightweight remote review, job dashboards, or external stakeholders, but it should not be the default UX for the core pipeline.

---

## Core Product Direction

### Main recommendation

Build the system as a **Godot-native workflow engine** with:

- a **main editor tab** for asset workflow execution
- a **guided step-based UI** for day-to-day use
- an optional **graph editor** for defining workflow templates
- a **manifest-driven asset model** for versioning, lineage, and publish history

The workflow should not be modeled as one long linear status enum.

Instead, it should use three separate concepts:

1. **Workflow Template**  
   A reusable graph definition for one asset type.

2. **Workflow Run**  
   One execution of that template for one asset idea.

3. **Asset Revision**  
   The stable, versioned release that is actually published into project assets.

This separation allows nuanced iteration and branching without polluting the final asset history.

---

## Why Godot Should Be the Primary UI

For a solo dev or tiny team, keeping everything in Godot is the cleanest approach because the user can:

- create prompts
- submit generation jobs
- review concept images
- compare 3D model candidates
- inspect imported assets in the real renderer
- validate scale, materials, collisions, pivots, and scene fit
- approve and publish assets

all without leaving the editor.

### Browser usage should be optional

A browser UI is only worth adding when you need:

- remote review away from your dev machine
- non-Godot stakeholders
- backend admin/ops dashboards
- link-based comments or asynchronous collaboration

For v1, the recommended strategy is:

**Godot-first, browser-later if needed.**

---

## Workflow Model

## The wrong model

Do **not** use a single state chain like:

`Draft -> Ready for Review -> Approved -> Published -> Superseded`

That is too coarse for real asset generation, especially when assets may include:

- multiple concept rounds
- branching prompt variants
- several image generations
- image selection gates
- one or more image-to-3D passes
- repeated 3D review loops
- later rigging, animation, modularization, or texture subflows

## The better model

Use a **workflow graph** made from reusable step types.

Each step:

- consumes typed artifacts
- produces typed artifacts
- may create one or many attempts
- may require review/approval
- may branch backward or forward

### Recommended execution states for a step attempt

- `idle`
- `queued`
- `running`
- `needs_review`
- `approved`
- `rejected`
- `failed`
- `skipped`

### Recommended release states for asset revisions

- `draft_release`
- `published`
- `superseded`
- `deprecated` (optional)

### Review decisions should be explicit events

Instead of turning everything into a status, use decisions like:

- `approve_one`
- `approve_many`
- `promote_to_reference`
- `request_changes`
- `branch_new_attempt`
- `send_back_to_prompt`
- `send_back_to_previous_stage`
- `archive_candidate`

That is what allows a nuanced workflow without becoming fragile.

---

## Artifacts Should Be First-Class

The main thing moving through the pipeline is not a status; it is an **artifact**.

Examples:

- `ConceptDoc`
- `PromptSpec`
- `ConceptImage`
- `SelectedReferenceImage`
- `MeshDraft`
- `MaterialVariant`
- `ValidationReport`
- `ImportedScene`
- `AssetRevisionManifest`

This lets the workflow express real production logic such as:

- generate 8 concept images
- shortlist 3
- promote 1 to `SelectedReferenceImage`
- generate 2 different mesh attempts from the same selected image
- approve only one mesh candidate
- publish only the validated final import package

---

## Reusable Step Types

Create a library of step types instead of hardcoding one wizard.

### 1. Input steps
Human-authored or edited input.

Examples:

- concept text
- image prompt
- negative prompt
- style constraints
- asset budgets
- naming metadata
- publish notes

### 2. Job steps
Async processing tasks.

Examples:

- text-to-image
- image-to-image
- image-to-3D
- texture generation
- mesh cleanup
- rigging
- animation generation
- thumbnail rendering

### 3. Review steps
Human decision gates.

Examples:

- concept image gallery review
- mesh review
- material review
- animation review
- final publish approval

### 4. Transform steps
Deterministic processing.

Examples:

- rename outputs
- convert file formats
- generate collision
- generate LODs
- assign materials
- bake thumbnails
- package asset bundle

### 5. Validation steps
Rule enforcement.

Examples:

- texture budget checks
- poly count checks
- pivot/origin validation
- socket validation
- naming/path validation
- import warnings
- scene smoke test

### 6. Import steps
Godot-specific integration.

Examples:

- move approved source files into canonical project folders
- trigger reimport
- apply import recipe
- create inherited scene
- create material resources

### 7. Publish steps
Versioning and release.

Examples:

- freeze revision
- write manifest
- mark revision as published
- supersede prior published version
- register LFS assets

### 8. Subgraph steps
Reusable nested workflows.

Examples:

- concept generation subgraph
- 3D model generation subgraph
- rigging subgraph
- animation subgraph
- modular kit validation subgraph

Subgraphs are the main mechanism that will let the pipeline scale from simple 2D images to animated or modular 3D assets.

---

## Example: 3D Model Workflow Template

A 3D asset workflow could look like this:

```text
ConceptText
  -> ImagePrompt
  -> TextToImageJob
  -> ConceptImageReview

ConceptImageReview.approve_one
  -> TrellisImageTo3DJob
  -> MeshReview

ConceptImageReview.request_changes
  -> ImagePrompt

ConceptImageReview.more_variants
  -> TextToImageJob

MeshReview.approve
  -> ImportAndValidate
  -> PublishRevision

MeshReview.regenerate_from_same_reference
  -> TrellisImageTo3DJob

MeshReview.back_to_concept
  -> ConceptImageReview
```

### Interpreting the flow

1. User writes concept text.
2. User refines or generates an image prompt.
3. System runs text-to-image.
4. User reviews concept images.
5. One chosen image is promoted to the selected reference artifact.
6. System runs image-to-3D.
7. User reviews the 3D model result.
8. If accepted, the model moves through import, validation, and publish.
9. If rejected, the user can either regenerate from the same reference or go back and change the concept/image stage.

This is a loopable graph, not a one-way wizard.

---

## Simpler and More Complex Asset Types

The same system can support other assets by reusing the same primitives.

### 2D Image Asset

```text
Brief -> Prompt -> GenerateImages -> Review -> OptionalPolish -> Publish
```

### 3D Model Asset

```text
Concept subgraph -> Image review -> Image-to-3D -> Mesh review -> Import -> Publish
```

### Animated Character Asset

```text
3D model subgraph
  -> Material review
  -> Rigging subgraph
  -> Animation subgraph
  -> Animation review
  -> Publish bundle
```

### Modular Environment Piece

```text
Concept -> Generate base piece -> Review
  -> Socket validation
  -> Snap/grid validation
  -> Variant generation
  -> Publish set
```

The core idea is that **complexity comes from composition**, not from special-casing every asset type.

---

## Godot UI Recommendation

Use two major views in the plugin.

## 1. Guided Run View (primary day-to-day UI)

This is what normal users should spend almost all their time in.

### Layout

- **Top:** stage rail or breadcrumb trail showing the current path through the workflow
- **Left:** asset library, active workflow runs, revision history
- **Center:** large preview area (image compare, 3D turntable, side-by-side candidate compare)
- **Right:** step inspector with controls and metadata
- **Bottom:** jobs, logs, validation results, attempt history

### Main actions

- Generate
- Regenerate
- Approve
- Reject
- Promote to Reference
- Compare with Previous Attempt
- Validate
- Publish
- Create Revision
- Override Locally

## 2. Template Builder View (advanced/internal)

This is for defining and editing workflow templates.

Use a graph editor UI with node types, connections, and grouped subgraphs.

### Purpose

- create asset-type templates
- add reusable review gates
- define branching logic
- define required artifact types
- define which nodes create publishable revisions

### Important UX rule

Do **not** force ordinary users to work directly in graph view.

Use:

- **graph view** for template authors
- **guided run view** for asset creators/reviewers

---

## Recommended Data Model

The pipeline needs a clean data model so that state is not trapped inside UI widgets.

### `WorkflowTemplate`
A reusable graph definition.

Suggested fields:

- `template_id`
- `name`
- `asset_type`
- `nodes`
- `edges`
- `required_artifact_types`
- `publish_node_ids`
- `version`

### `WorkflowRun`
One live execution of a template.

Suggested fields:

- `run_id`
- `template_id`
- `asset_slug`
- `created_at`
- `active_node_ids`
- `attempts`
- `artifacts`
- `selected_artifact_ids`
- `current_review_requests`

### `StepAttempt`
One attempt of one step.

Suggested fields:

- `attempt_id`
- `step_id`
- `state`
- `inputs`
- `outputs`
- `job_metadata`
- `created_at`
- `updated_at`
- `review_notes`

### `Artifact`
A typed piece of data produced or consumed by the pipeline.

Suggested fields:

- `artifact_id`
- `artifact_type`
- `display_name`
- `source_attempt_id`
- `storage_uri`
- `preview_uri`
- `metadata`
- `parent_artifact_ids`
- `is_selected`
- `is_publish_candidate`

### `AssetRevision`
The versioned released asset record.

Suggested fields:

- `asset_id`
- `revision`
- `release_state`
- `canonical_artifact_ids`
- `import_recipe_id`
- `published_at`
- `supersedes_revision`
- `notes`

### `ImportRecipe`
Godot-specific instructions for importing and shaping the final asset.

Suggested fields:

- naming rules
- destination path
- scale corrections
- pivot rules
- collision generation settings
- material binding rules
- scene packaging settings

---

## Storage Strategy

## Goal

Keep **intermediate and exploratory pipeline data out of Git**, while keeping **published, project-relevant final assets versioned and reproducible**.

This is the right idea.

## Recommended storage policy

### In Git
Store lightweight and important source-of-truth metadata:

- workflow templates
- manifests
- prompts
- review notes
- import recipes
- validation reports
- published asset metadata
- `.import` files

### In Git LFS
Store only **approved final heavyweight assets** that are meant to live in the project and ship with it:

- final `.glb` / `.gltf` source files
- final textures
- final approved mesh sources
- final bundle archives if needed

### Outside Git
Store noisy, iterative, temporary, or rejected outputs outside Git:

- concept image batches
- rejected image candidates
- intermediate mesh attempts
- temporary exports
- thumbnails
- turntables
- validation snapshots
- work-in-progress variant files

---

## Better plan than using Google Drive as the canonical store

Google Drive is acceptable for a simple solo-dev v1, but it is not the ideal long-term canonical store.

### Preferred plan

Use a **local gitignored workspace** plus a **sync layer**.

#### Local workspace
Inside the Godot project, use a folder like:

```text
res://_ai_work/
```

This folder should be:

- gitignored
- treated as scratch/candidate workspace
- managed by your plugin or a companion external process

This gives users fast local access while keeping the repo clean.

#### External sync layer
The better long-term plan is:

- local scratch workspace for active generation
- external object storage or asset cache for persistence and recovery
- optional background sync for portability between machines

### Storage ranking recommendation

#### Best long-term canonical option
- S3-compatible or similar object storage
- or a custom lightweight asset server

#### Good short-term pragmatic option
- local gitignored workspace + sync tool

#### Acceptable early-stage option
- Google Drive or a synced cloud folder

### Why this is better than Drive-only

A local-first scratch workspace avoids several problems:

- faster read/write during iterative generation
- fewer file-locking/sync surprises
- cleaner separation between temporary candidates and published assets
- easier future migration away from a consumer sync tool

### Final storage recommendation

For KillaTamata, use:

1. **Gitignored local work folder** for active intermediate data
2. **Optional external sync/cache** for those intermediates
3. **Git LFS only for final published assets**

That gives you clean repos, fast iteration, and a path to scale later.

---

## Suggested Folder Structure

```text
res://
  addons/
    killatamata_plugin/
  assets/
    generated/
      <asset_slug>/
        v1.0.0/
          source/
          imported/
          manifest/
  workflows/
    templates/
    runs/
  _ai_work/
    concept_images/
    mesh_candidates/
    previews/
    temp_exports/
```

### Notes

- `res://_ai_work/` should be gitignored
- `assets/generated/...` contains canonical published content
- `workflows/templates/` contains reusable graph definitions
- `workflows/runs/` can contain manifest/state data if you want runs persisted in the project
- if run history becomes too noisy, it can also be partially externalized while keeping only important summary manifests in Git

---

## Publish Rule

### Important rule

**Only publish nodes create real asset revisions.**

That means:

- selecting a concept image is not a release
- approving a mesh candidate is not yet a release
- importing a candidate is not automatically a release
- only the final publish action creates `AssetRevision vX.Y.Z`

This keeps version history clean and understandable.

---

## Editing a Published Asset

A published asset should not be edited in place.

Instead, use one of two paths.

## 1. Project-local override
Use this when a change should only apply to the current game project.

Examples:

- change one material in one project
- add a project-specific collider
- create a variant inherited scene
- scene-specific socket placement

This should not create a new canonical asset revision.

## 2. Canonical revision
Use this when the asset itself should evolve.

Examples:

- better geometry
- improved textures
- new import recipe
- fixed pivots or scale
- improved prompt/reference lineage

### Canonical edit workflow

1. Open the published asset.
2. Click **Create Revision**.
3. Clone the published manifest into a new working revision.
4. Re-enter the workflow at the appropriate step.
5. Regenerate or refine upstream artifacts.
6. Revalidate.
7. Publish a new revision.
8. Mark the previous published revision as superseded.

### Important distinction

Users should always choose between:

- **Override in this project**
- **Revise asset globally**

That split prevents a lot of future confusion.

---

## Review UX Recommendations

Review nodes are where the workflow becomes understandable.

### Concept image review
Should support:

- gallery view
- compare mode
- shortlist
- reject all
- promote one to reference
- regenerate from same prompt
- refine prompt and regenerate

### 3D review
Should support:

- turntable preview
- wireframe toggle
- materials-on/materials-off
- compare against previous attempt
- pivot/origin display
- collision display
- poly/material budget summary
- approve mesh
- send back to concept
- regenerate from same reference

### Final import/publish review
Should support:

- imported scene preview
- file paths and destination confirmation
- validation summary
- version number entry or suggestion
- publish notes
- publish action

---

## Validation Strategy

Validation should be a reusable set of rule nodes.

Recommended checks:

- file naming
- folder destination rules
- triangle count budget
- material count budget
- texture resolution budget
- pivot/origin placement
- scale sanity check
- collision/sockets present when required
- missing texture references
- import warnings
- optional scene smoke test

Validation should block publish until required checks pass or are explicitly overridden.

---

## Implementation Plan

### Phase 1 - Foundations

- define `WorkflowTemplate`, `WorkflowRun`, `StepAttempt`, `Artifact`, and `AssetRevision`
- define artifact typing and edge rules
- build manifest serialization
- define storage abstraction (`local`, `external`, `published`)

### Phase 2 - Guided Godot UI

- build the primary Godot editor tab
- asset library on the left
- preview center panel
- step inspector on the right
- jobs/logs/validation on the bottom
- implement review actions and artifact selection

### Phase 3 - Basic Workflow Templates

Ship first templates for:

- image asset
- 3D model asset

### Phase 4 - Publish / Import Integration

- canonical destination paths
- import recipe execution
- publish manifest writing
- Git LFS integration for published assets only
- supersede previous revisions

### Phase 5 - Advanced Workflow Authoring

- graph template editor
- reusable subgraphs
- custom step definitions
- richer validation libraries

### Phase 6 - Future Extensions

- animated characters
- rigging workflow
- modular kits
- texture/material subgraphs
- remote browser dashboard if needed

---

## Final Recommended Product Direction

Build KillaTamata as:

- a **Godot-native asset workflow system**
- powered by **modular graph templates**
- centered on **typed artifacts and review gates**
- using a **gitignored local work area** for intermediate data
- optionally synced externally
- with **Git LFS only for final published assets**
- and **publish nodes as the sole creators of canonical asset revisions**

This gives you:

- clean repos
- much better support for complex generation loops
- a workflow that scales from simple images to complex 3D/animated assets
- a UX that feels natural for solo devs and tiny Godot-focused teams

