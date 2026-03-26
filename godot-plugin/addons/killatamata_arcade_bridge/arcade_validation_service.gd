@tool
extends RefCounted
class_name ArcadeValidationService

signal message_logged(text: String)

var _config_store: ArcadeProjectConfig

func _init(config_store: ArcadeProjectConfig = null) -> void:
	_config_store = config_store if config_store != null else ArcadeProjectConfig.new()

func list_export_presets() -> Array:
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load(ProjectSettings.globalize_path("res://export_presets.cfg"))
	if err != OK:
		return []

	var summaries: Array = []
	for section in config.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue
		var options_section: String = "%s.options" % section
		summaries.append({
			"section": section,
			"index": int(section.get_slice(".", 1)),
			"name": str(config.get_value(section, "name", "")),
			"platform": str(config.get_value(section, "platform", "")),
			"exportPath": str(config.get_value(section, "export_path", "")),
			"runnable": bool(config.get_value(section, "runnable", true)),
			"enabled": not bool(config.get_value(section, "disabled", false)),
			"threadSupport": bool(config.get_value(options_section, "variant/thread_support", false)),
		})

	summaries.sort_custom(Callable(self, "_sort_preset_summary"))
	return summaries

func validate_arcade_web_export_preset(config: Dictionary = {}, emit_logs: bool = false) -> Dictionary:
	var normalized: Dictionary = _config_store.normalize_config(config if not config.is_empty() else _effective_config())
	var preset_name: String = str(normalized.get("exportPresetName", ArcadeProjectConfig.DEFAULT_PRESET_NAME))
	var preset: Dictionary = _find_preset_summary_by_name(preset_name)
	var blocking_issues: Array = []
	var warnings: Array = []

	if emit_logs:
		emit_signal("message_logged", "Validating arcade export preset %s." % preset_name)

	if preset.is_empty():
		blocking_issues.append(_issue(
			"missing_export_preset",
			"Arcade web export preset %s does not exist." % preset_name
		))
		return {
			"ok": false,
			"blockingIssues": blocking_issues,
			"warnings": warnings,
			"presetSummary": {},
		}

	if str(preset.get("platform", "")) != "Web":
		blocking_issues.append(_issue(
			"wrong_export_platform",
			"Arcade export preset must target Web."
		))
	if not bool(preset.get("enabled", true)):
		blocking_issues.append(_issue(
			"export_preset_disabled",
			"Arcade export preset is disabled."
		))

	var export_path: String = str(preset.get("exportPath", "")).strip_edges()
	if export_path.is_empty():
		blocking_issues.append(_issue(
			"missing_export_path",
			"Arcade export preset must define an export path."
		))
	elif export_path.get_file() != ArcadeProjectConfig.DEFAULT_ENTRY_PATH:
		blocking_issues.append(_issue(
			"invalid_export_output",
			"Arcade export preset output must be index.html."
		))

	if bool(preset.get("threadSupport", false)):
		blocking_issues.append(_issue(
			"threads_not_supported",
			"Threaded web exports are not supported by KillaTamata Arcade V1."
		))

	return {
		"ok": blocking_issues.is_empty(),
		"blockingIssues": blocking_issues,
		"warnings": warnings,
		"presetSummary": preset,
	}

func validate_arcade_project(emit_logs: bool = false) -> Dictionary:
	var raw_config: Dictionary = _config_store.load_raw_config()
	var config_exists: bool = _config_store.config_exists()
	var config: Dictionary = _effective_config()
	var manifest_preview: Dictionary = _config_store.generate_manifest(config)
	var preset_validation: Dictionary = validate_arcade_web_export_preset(config, emit_logs)
	var csharp_detection: Dictionary = detect_csharp_project()

	var blocking_issues: Array = []
	var warnings: Array = preset_validation.get("warnings", []).duplicate()
	var inferred_values: Dictionary = {}

	if emit_logs:
		emit_signal("message_logged", "Running arcade project validation.")

	if not config_exists:
		blocking_issues.append(_issue(
			"missing_arcade_config",
			"Project is missing killatamata.arcade.json."
		))

	if str(config.get("title", "")).is_empty():
		blocking_issues.append(_issue("missing_title", "Arcade title is required."))
	if str(config.get("shortDescription", "")).is_empty():
		blocking_issues.append(_issue("missing_short_description", "Short description is required."))
	if str(config.get("description", "")).is_empty():
		blocking_issues.append(_issue("missing_description", "Long description is required."))
	if str(config.get("version", "")).is_empty():
		blocking_issues.append(_issue("missing_version", "Version is required."))

	var raw_slug: String = str(raw_config.get("gameSlug", config.get("gameSlug", ""))).strip_edges()
	var normalized_slug: String = _config_store.normalize_slug(raw_slug if not raw_slug.is_empty() else str(config.get("gameSlug", "")))
	if raw_slug.is_empty():
		inferred_values["gameSlug"] = str(config.get("gameSlug", ""))
	elif raw_slug != normalized_slug:
		blocking_issues.append(_issue(
			"slug_not_normalized",
			"Arcade slug must be lower-case hyphenated ASCII.",
			{
				"current": raw_slug,
				"normalized": normalized_slug,
			}
		))

	var cover_image_source: String = str(config.get("coverImageSource", "")).strip_edges()
	if cover_image_source.is_empty():
		blocking_issues.append(_issue(
			"missing_cover_image",
			"Cover image is required because arcade.release.json must reference a bundled cover asset."
		))
	elif not FileAccess.file_exists(cover_image_source):
		blocking_issues.append(_issue(
			"cover_image_not_found",
			"Configured cover image path does not exist.",
			{"path": cover_image_source}
		))

	if bool(config.get("supportsThreads", false)):
		blocking_issues.append(_issue(
			"supports_threads_enabled",
			"supportsThreads must remain false for KillaTamata Arcade V1."
		))

	if bool(csharp_detection.get("detected", false)):
		blocking_issues.append(_issue(
			"csharp_not_supported",
			"Godot 4 C# web exports are not supported by KillaTamata Arcade V1.",
			{"matches": csharp_detection.get("matches", [])}
		))

	if int(config.get("launchPriceUsdMicros", 0)) == 0:
		warnings.append(_issue(
			"zero_launch_price",
			"Launch price is zero. Review this before submission if the game should be paid."
		))

	var controls: Dictionary = config.get("controls", {})
	if not bool(controls.get("gamepad", false)) and not bool(controls.get("touch", false)):
		warnings.append(_issue(
			"input_support_unset",
			"Gamepad and touch support are both disabled. Confirm this is intentional."
		))

	if not _has_path(raw_config, ["display", "width"]) or not _has_path(raw_config, ["display", "height"]):
		warnings.append(_issue(
			"display_size_defaulted",
			"Display width and height are using defaults. Review them before submission."
		))

	_capture_inferred_value(raw_config, ["entryPath"], str(config.get("entryPath", "")), inferred_values)
	_capture_inferred_value(raw_config, ["supportsThreads"], bool(config.get("supportsThreads", false)), inferred_values)
	_capture_inferred_value(raw_config, ["exportPresetName"], str(config.get("exportPresetName", "")), inferred_values)
	_capture_inferred_value(raw_config, ["stagingBaseDir"], str(config.get("stagingBaseDir", "")), inferred_values)
	_capture_inferred_value(raw_config, ["display", "mode"], str(config.get("display", {}).get("mode", "")), inferred_values)
	_capture_inferred_value(raw_config, ["display", "backgroundColor"], str(config.get("display", {}).get("backgroundColor", "")), inferred_values)

	for issue in preset_validation.get("blockingIssues", []):
		blocking_issues.append(issue)

	var result: Dictionary = {
		"ok": blocking_issues.is_empty(),
		"blockingIssues": blocking_issues,
		"warnings": warnings,
		"inferredValues": inferred_values,
		"manifestPreview": manifest_preview,
		"exportPresetSummary": preset_validation.get("presetSummary", {}),
		"csharpDetected": bool(csharp_detection.get("detected", false)),
		"csharpMatches": csharp_detection.get("matches", []),
		"configExists": config_exists,
		"configPath": _config_store.get_config_path(),
	}

	if emit_logs:
		emit_signal("message_logged", "Validation completed with %d blocking issues and %d warnings." % [
			blocking_issues.size(),
			warnings.size(),
		])

	return result

func detect_csharp_project() -> Dictionary:
	var matches: Array = []
	_scan_dir(ProjectSettings.globalize_path("res://"), matches, 20)
	return {
		"detected": not matches.is_empty(),
		"matches": matches,
	}

func _effective_config() -> Dictionary:
	var loaded: Variant = _config_store.load_config()
	if typeof(loaded) == TYPE_DICTIONARY:
		return loaded
	return _config_store.default_config()

func _find_preset_summary_by_name(preset_name: String) -> Dictionary:
	for preset in list_export_presets():
		if str(preset.get("name", "")) == preset_name:
			return preset
	return {}

func _scan_dir(path: String, matches: Array, limit: int) -> void:
	if matches.size() >= limit:
		return
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()
	while true:
		var entry: String = dir.get_next()
		if entry.is_empty():
			break
		if entry == "." or entry == "..":
			continue

		var child_path: String = path.path_join(entry)
		if dir.current_is_dir():
			if entry in [".git", ".godot", ".import"]:
				continue
			_scan_dir(child_path, matches, limit)
		elif _looks_like_csharp_artifact(entry):
			matches.append(ProjectSettings.localize_path(child_path))
			if matches.size() >= limit:
				break
	dir.list_dir_end()

func _looks_like_csharp_artifact(name: String) -> bool:
	var lowered: String = name.to_lower()
	return lowered.ends_with(".csproj") or lowered.ends_with(".sln") or lowered.ends_with(".cs")

func _issue(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {
		"code": code,
		"message": message,
		"details": details,
	}

func _capture_inferred_value(raw_config: Dictionary, path: Array, value: Variant, output: Dictionary) -> void:
	if _has_path(raw_config, path):
		return
	output[_join_path(path)] = value

func _has_path(data: Dictionary, path: Array) -> bool:
	var current: Variant = data
	for segment in path:
		if typeof(current) != TYPE_DICTIONARY or not current.has(segment):
			return false
		current = current.get(segment)
	return true

func _join_path(path: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for segment in path:
		parts.append(str(segment))
	return ".".join(parts)

func _sort_preset_summary(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("index", 0)) < int(b.get("index", 0))
