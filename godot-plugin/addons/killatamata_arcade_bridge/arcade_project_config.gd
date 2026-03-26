@tool
extends RefCounted
class_name ArcadeProjectConfig

const CONFIG_PATH := "res://killatamata.arcade.json"
const DEFAULT_STAGING_BASE_DIR := "res://.gotamata/arcade_builds"
const DEFAULT_ENTRY_PATH := "index.html"
const DEFAULT_PRESET_NAME := "KillaTamata Arcade Web"

func get_config_path() -> String:
	return CONFIG_PATH

func config_exists() -> bool:
	return FileAccess.file_exists(CONFIG_PATH)

func load_config() -> Variant:
	if not config_exists():
		return null
	var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return normalize_config(parsed)

func load_raw_config() -> Dictionary:
	if not config_exists():
		return {}
	var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func upsert_config(patch: Dictionary) -> Dictionary:
	var existing: Dictionary = load_raw_config()
	var merged: Dictionary = _deep_merge(existing, patch)
	var normalized: Dictionary = normalize_config(merged)
	_write_json(CONFIG_PATH, normalized)
	return normalized

func default_config() -> Dictionary:
	var project_name: String = str(ProjectSettings.get_setting("application/config/name", "Godot Project")).strip_edges()
	if project_name.is_empty():
		project_name = "Godot Project"
	return normalize_config({
		"title": project_name,
		"version": str(ProjectSettings.get_setting("application/config/version", "0.1.0")),
	})

func normalize_config(candidate: Dictionary) -> Dictionary:
	var normalized: Dictionary = {}
	var default_value: Dictionary = default_config_internal()
	normalized = _deep_merge(default_value, candidate)

	normalized["gameSlug"] = normalize_slug(str(normalized.get("gameSlug", normalized.get("title", ""))))
	normalized["title"] = str(normalized.get("title", "")).strip_edges()
	normalized["shortDescription"] = str(normalized.get("shortDescription", "")).strip_edges()
	normalized["description"] = str(normalized.get("description", "")).strip_edges()
	normalized["version"] = str(normalized.get("version", "0.1.0")).strip_edges()
	normalized["coverImageSource"] = str(normalized.get("coverImageSource", "")).strip_edges()
	normalized["entryPath"] = DEFAULT_ENTRY_PATH
	normalized["exportPresetName"] = str(normalized.get("exportPresetName", DEFAULT_PRESET_NAME)).strip_edges()
	if normalized["exportPresetName"].is_empty():
		normalized["exportPresetName"] = DEFAULT_PRESET_NAME
	normalized["stagingBaseDir"] = str(normalized.get("stagingBaseDir", DEFAULT_STAGING_BASE_DIR)).strip_edges()
	if normalized["stagingBaseDir"].is_empty():
		normalized["stagingBaseDir"] = DEFAULT_STAGING_BASE_DIR
	normalized["launchPriceUsdMicros"] = max(0, int(normalized.get("launchPriceUsdMicros", 0)))
	normalized["supportsThreads"] = bool(normalized.get("supportsThreads", false))

	var tags: Array = []
	for item in normalized.get("tags", []):
		var value: String = str(item).strip_edges()
		if not value.is_empty() and not tags.has(value):
			tags.append(value)
	normalized["tags"] = tags

	var display: Dictionary = default_value["display"].duplicate(true)
	display = _deep_merge(display, normalized.get("display", {}))
	display["width"] = max(1, int(display.get("width", 1280)))
	display["height"] = max(1, int(display.get("height", 720)))
	display["mode"] = _normalize_display_mode(str(display.get("mode", "contain")))
	display["backgroundColor"] = _normalize_color_hex(str(display.get("backgroundColor", "#000000")))
	normalized["display"] = display

	var controls: Dictionary = default_value["controls"].duplicate(true)
	controls = _deep_merge(controls, normalized.get("controls", {}))
	controls["primaryAction"] = str(controls.get("primaryAction", "")).strip_edges()
	controls["secondaryAction"] = str(controls.get("secondaryAction", "")).strip_edges()
	var keyboard_labels: Array = []
	for item in controls.get("keyboard", []):
		var label: String = str(item).strip_edges()
		if not label.is_empty():
			keyboard_labels.append(label)
	controls["keyboard"] = keyboard_labels
	controls["gamepad"] = bool(controls.get("gamepad", false))
	controls["touch"] = bool(controls.get("touch", false))
	normalized["controls"] = controls

	return normalized

func generate_manifest(config: Dictionary) -> Dictionary:
	var normalized: Dictionary = normalize_config(config)
	return {
		"gameSlug": normalized.get("gameSlug", ""),
		"title": normalized.get("title", ""),
		"version": normalized.get("version", ""),
		"engineVersion": get_engine_version_string(),
		"entryPath": normalized.get("entryPath", DEFAULT_ENTRY_PATH),
		"shortDescription": normalized.get("shortDescription", ""),
		"description": normalized.get("description", ""),
		"display": normalized.get("display", {}).duplicate(true),
		"controls": normalized.get("controls", {}).duplicate(true),
		"tags": normalized.get("tags", []).duplicate(),
		"coverImage": _cover_image_manifest_value(str(normalized.get("coverImageSource", ""))),
		"launchPriceUsdMicros": int(normalized.get("launchPriceUsdMicros", 0)),
		"supportsThreads": bool(normalized.get("supportsThreads", false)),
	}

func get_engine_version_string() -> String:
	var version_info: Dictionary = Engine.get_version_info()
	var major: int = int(version_info.get("major", 0))
	var minor: int = int(version_info.get("minor", 0))
	var patch: int = int(version_info.get("patch", 0))
	var status: String = str(version_info.get("status", "")).strip_edges()
	var version: String = "%d.%d.%d" % [major, minor, patch]
	if not status.is_empty():
		version += "-%s" % status
	return version

func normalize_slug(value: String) -> String:
	var slug: String = value.to_lower().strip_edges()
	var output: String = ""
	var previous_dash: bool = false
	for i in range(slug.length()):
		var char: String = slug.substr(i, 1)
		var code: int = char.unicode_at(0)
		var keep_char: bool = (code >= 97 and code <= 122) or (code >= 48 and code <= 57)
		if keep_char:
			output += char
			previous_dash = false
		else:
			if not previous_dash:
				output += "-"
			previous_dash = true
	output = output.strip_edges()
	while output.begins_with("-"):
		output = output.substr(1)
	while output.ends_with("-"):
		output = output.left(output.length() - 1)
	while output.find("--") != -1:
		output = output.replace("--", "-")
	return output

func resolve_staging_dir(config: Dictionary) -> String:
	var normalized: Dictionary = normalize_config(config)
	return "%s/%s/%s" % [
		_trim_suffix(str(normalized.get("stagingBaseDir", DEFAULT_STAGING_BASE_DIR)), "/"),
		str(normalized.get("gameSlug", "")),
		str(normalized.get("version", "")),
	]

func resolve_staging_dir_absolute(config: Dictionary) -> String:
	return ProjectSettings.globalize_path(resolve_staging_dir(config))

func resolve_zip_path(config: Dictionary) -> String:
	var normalized: Dictionary = normalize_config(config)
	return "%s/%s-%s.zip" % [
		resolve_staging_dir(normalized),
		str(normalized.get("gameSlug", "")),
		str(normalized.get("version", "")),
	]

func resolve_zip_path_absolute(config: Dictionary) -> String:
	return ProjectSettings.globalize_path(resolve_zip_path(config))

func resolve_cover_image_absolute(config: Dictionary) -> String:
	var normalized: Dictionary = normalize_config(config)
	var source: String = str(normalized.get("coverImageSource", "")).strip_edges()
	if source.is_empty():
		return ""
	return ProjectSettings.globalize_path(source)

func ensure_parent_dir(path: String) -> void:
	var target_dir: String = ProjectSettings.globalize_path(path).get_base_dir()
	if target_dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(target_dir)

func write_json(path: String, payload: Dictionary) -> void:
	_write_json(path, payload)

func default_config_internal() -> Dictionary:
	var project_name: String = str(ProjectSettings.get_setting("application/config/name", "Godot Project")).strip_edges()
	if project_name.is_empty():
		project_name = "Godot Project"
	return {
		"schemaVersion": 1,
		"gameSlug": normalize_slug(project_name),
		"title": project_name,
		"shortDescription": "",
		"description": "",
		"version": str(ProjectSettings.get_setting("application/config/version", "0.1.0")),
		"coverImageSource": "",
		"tags": [],
		"display": {
			"width": 1280,
			"height": 720,
			"mode": "contain",
			"backgroundColor": "#000000",
		},
		"controls": {
			"primaryAction": "",
			"secondaryAction": "",
			"keyboard": [],
			"gamepad": false,
			"touch": false,
		},
		"launchPriceUsdMicros": 0,
		"supportsThreads": false,
		"entryPath": DEFAULT_ENTRY_PATH,
		"exportPresetName": DEFAULT_PRESET_NAME,
		"stagingBaseDir": DEFAULT_STAGING_BASE_DIR,
	}

func _write_json(path: String, payload: Dictionary) -> void:
	ensure_parent_dir(path)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open %s for writing." % path)
		return
	file.store_string(JSON.stringify(payload, "  "))

func _deep_merge(base: Dictionary, patch: Dictionary) -> Dictionary:
	var merged: Dictionary = base.duplicate(true)
	for key in patch.keys():
		if typeof(merged.get(key)) == TYPE_DICTIONARY and typeof(patch.get(key)) == TYPE_DICTIONARY:
			merged[key] = _deep_merge(merged.get(key, {}), patch.get(key, {}))
		else:
			merged[key] = patch[key]
	return merged

func _normalize_display_mode(value: String) -> String:
	var mode: String = value.strip_edges().to_lower()
	if mode in ["contain", "cover", "stretch"]:
		return mode
	return "contain"

func _normalize_color_hex(value: String) -> String:
	var color_value: String = value.strip_edges()
	if color_value.is_empty():
		return "#000000"
	if not color_value.begins_with("#"):
		color_value = "#" + color_value
	if color_value.length() == 7 or color_value.length() == 9:
		return color_value.to_upper()
	return "#000000"

func _cover_image_manifest_value(source: String) -> String:
	if source.is_empty():
		return ""
	return source.get_file()

func _trim_suffix(value: String, suffix: String) -> String:
	if suffix.is_empty() or not value.ends_with(suffix):
		return value
	return value.left(value.length() - suffix.length())
