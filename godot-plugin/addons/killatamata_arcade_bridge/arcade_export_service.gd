@tool
extends RefCounted
class_name ArcadeExportService

signal message_logged(text: String)

const MAX_ZIP_BYTES := 64 * 1024 * 1024
const MAX_FILE_COUNT := 256

var _config_store: ArcadeProjectConfig
var _validation_service: ArcadeValidationService

func _init(config_store: ArcadeProjectConfig = null, validation_service: ArcadeValidationService = null) -> void:
	_config_store = config_store if config_store != null else ArcadeProjectConfig.new()
	_validation_service = validation_service if validation_service != null else ArcadeValidationService.new(_config_store)

func build_arcade_release() -> Dictionary:
	emit_signal("message_logged", "Starting arcade release build.")
	var validation: Dictionary = _validation_service.validate_arcade_project(true)
	if not bool(validation.get("ok", false)):
		return {
			"success": false,
			"errorCode": "validation_failed",
			"errorMessage": "Arcade project validation failed.",
			"details": validation,
		}

	var config: Dictionary = _current_config()
	var staging_res: String = _config_store.resolve_staging_dir(config)
	var staging_abs: String = _config_store.resolve_staging_dir_absolute(config)
	var html_abs: String = staging_abs.path_join(ArcadeProjectConfig.DEFAULT_ENTRY_PATH)
	var manifest: Dictionary = validation.get("manifestPreview", {})
	var manifest_res: String = staging_res.path_join("arcade.release.json")
	var manifest_abs: String = ProjectSettings.globalize_path(manifest_res)

	DirAccess.make_dir_recursive_absolute(staging_abs)
	_config_store.write_json(manifest_res, manifest)
	emit_signal("message_logged", "Wrote manifest preview to %s." % manifest_res)

	var export_result: Dictionary = _run_export(str(config.get("exportPresetName", ArcadeProjectConfig.DEFAULT_PRESET_NAME)), html_abs)
	if not bool(export_result.get("success", false)):
		return export_result

	var cover_stage_result: Dictionary = _stage_cover_image(config, manifest, staging_abs)
	if not bool(cover_stage_result.get("success", false)):
		return cover_stage_result

	var inventory: Array = _collect_file_inventory(staging_abs, staging_abs, true)
	var verification: Dictionary = _verify_inventory(inventory, manifest)
	if not bool(verification.get("ok", false)):
		return {
			"success": false,
			"errorCode": "export_verification_failed",
			"errorMessage": "Export completed but required arcade files were missing.",
			"details": verification,
		}

	var zip_res: String = _config_store.resolve_zip_path(config)
	var zip_abs: String = _config_store.resolve_zip_path_absolute(config)
	var zip_result: Dictionary = _create_zip(zip_abs, staging_abs, inventory)
	if not bool(zip_result.get("success", false)):
		return zip_result

	var zip_size: int = int(FileAccess.get_file_len(zip_abs))
	if zip_size > MAX_ZIP_BYTES:
		return {
			"success": false,
			"errorCode": "zip_too_large",
			"errorMessage": "Generated ZIP exceeds the 64 MB KillaTamata Arcade limit.",
			"details": {
				"zipPath": zip_res,
				"zipSizeBytes": zip_size,
			},
		}

	emit_signal("message_logged", "Build finished. ZIP created at %s." % zip_res)

	return {
		"success": true,
		"stagingDirectory": staging_res,
		"stagingDirectoryAbsolute": staging_abs,
		"manifestPath": manifest_res,
		"manifestPathAbsolute": manifest_abs,
		"zipPath": zip_res,
		"zipPathAbsolute": zip_abs,
		"zipSizeBytes": zip_size,
		"manifest": manifest,
		"exportedFileInventory": inventory,
		"coverImagePath": str(config.get("coverImageSource", "")),
		"coverImageAbsolutePath": _config_store.resolve_cover_image_absolute(config),
		"stagedCoverImagePath": str(cover_stage_result.get("stagedCoverImagePath", "")),
		"stagedCoverImageAbsolutePath": str(cover_stage_result.get("stagedCoverImageAbsolutePath", "")),
		"exportCommand": export_result,
	}

func reveal_arcade_build() -> Dictionary:
	var config: Dictionary = _current_config()
	var staging_res: String = _config_store.resolve_staging_dir(config)
	var staging_abs: String = _config_store.resolve_staging_dir_absolute(config)
	var err: int = OS.shell_open(staging_abs)
	if err != OK:
		return {
			"success": false,
			"errorCode": "reveal_failed",
			"errorMessage": "Failed to reveal arcade build directory.",
			"details": {
				"path": staging_abs,
				"errorCode": err,
				"errorName": error_string(err),
			},
		}
	return {
		"success": true,
		"stagingDirectory": staging_res,
		"stagingDirectoryAbsolute": staging_abs,
	}

func generate_manifest_preview() -> Dictionary:
	return _config_store.generate_manifest(_current_config())

func _current_config() -> Dictionary:
	var loaded: Variant = _config_store.load_config()
	if typeof(loaded) == TYPE_DICTIONARY:
		return loaded
	return _config_store.default_config()

func _stage_cover_image(config: Dictionary, manifest: Dictionary, staging_abs: String) -> Dictionary:
	var cover_relative_path: String = str(manifest.get("coverImage", "")).strip_edges()
	if cover_relative_path.is_empty():
		return {
			"success": false,
			"errorCode": "missing_cover_image_manifest_path",
			"errorMessage": "Arcade manifest is missing a cover image path.",
			"details": {
				"manifest": manifest,
			},
		}

	var source_abs: String = _config_store.resolve_cover_image_absolute(config)
	if source_abs.is_empty():
		return {
			"success": false,
			"errorCode": "missing_cover_image_source",
			"errorMessage": "Arcade build requires a configured cover image source.",
			"details": {
				"coverImagePath": str(config.get("coverImageSource", "")),
				"manifestCoverImage": cover_relative_path,
			},
		}

	if not FileAccess.file_exists(source_abs):
		return {
			"success": false,
			"errorCode": "cover_image_not_found",
			"errorMessage": "Configured cover image path does not exist.",
			"details": {
				"coverImageAbsolutePath": source_abs,
				"manifestCoverImage": cover_relative_path,
			},
		}

	var staged_cover_abs: String = staging_abs.path_join(cover_relative_path)
	DirAccess.make_dir_recursive_absolute(staged_cover_abs.get_base_dir())

	var source_file: FileAccess = FileAccess.open(source_abs, FileAccess.READ)
	if source_file == null:
		var read_error: Error = FileAccess.get_open_error()
		return {
			"success": false,
			"errorCode": "cover_image_read_failed",
			"errorMessage": "Failed to read configured cover image.",
			"details": {
				"coverImageAbsolutePath": source_abs,
				"errorCode": read_error,
				"errorName": error_string(read_error),
			},
		}
	var source_bytes: PackedByteArray = source_file.get_buffer(source_file.get_length())

	var staged_file: FileAccess = FileAccess.open(staged_cover_abs, FileAccess.WRITE)
	if staged_file == null:
		var open_error: Error = FileAccess.get_open_error()
		return {
			"success": false,
			"errorCode": "cover_image_stage_failed",
			"errorMessage": "Failed to stage cover image into the arcade build folder.",
			"details": {
				"coverImageAbsolutePath": source_abs,
				"stagedCoverImageAbsolutePath": staged_cover_abs,
				"errorCode": open_error,
				"errorName": error_string(open_error),
			},
		}

	staged_file.store_buffer(source_bytes)
	emit_signal("message_logged", "Staged cover image at %s." % ProjectSettings.localize_path(staged_cover_abs))
	return {
		"success": true,
		"stagedCoverImagePath": ProjectSettings.localize_path(staged_cover_abs),
		"stagedCoverImageAbsolutePath": staged_cover_abs,
	}

func _run_export(preset_name: String, html_abs: String) -> Dictionary:
	var executable_path: String = OS.get_executable_path()
	if executable_path.is_empty():
		return {
			"success": false,
			"errorCode": "missing_executable",
			"errorMessage": "Could not resolve the current Godot executable path.",
			"details": {},
		}

	var args: Array = [
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"--export-release",
		preset_name,
		html_abs,
	]
	var output: Array = []
	emit_signal("message_logged", "Exporting web build with preset %s." % preset_name)
	var exit_code: int = OS.execute(executable_path, args, output, true, false)
	if exit_code != OK:
		return {
			"success": false,
			"errorCode": "export_failed",
			"errorMessage": "Godot export command failed.",
			"details": {
				"exitCode": exit_code,
				"output": output,
				"args": args,
			},
		}
	return {
		"success": true,
		"args": args,
		"output": output,
	}

func _collect_file_inventory(root_abs: String, current_abs: String, skip_zip: bool) -> Array:
	var results: Array = []
	var dir: DirAccess = DirAccess.open(current_abs)
	if dir == null:
		return results
	dir.list_dir_begin()
	while true:
		var entry: String = dir.get_next()
		if entry.is_empty():
			break
		if entry == "." or entry == "..":
			continue

		var child_abs: String = current_abs.path_join(entry)
		if dir.current_is_dir():
			for nested in _collect_file_inventory(root_abs, child_abs, skip_zip):
				results.append(nested)
		else:
			if skip_zip and entry.to_lower().ends_with(".zip"):
				continue
			results.append({
				"relativePath": _relative_path(root_abs, child_abs),
				"absolutePath": child_abs,
				"sizeBytes": int(FileAccess.get_file_len(child_abs)),
			})
	dir.list_dir_end()

	results.sort_custom(Callable(self, "_sort_inventory_item"))
	return results

func _verify_inventory(inventory: Array, manifest: Dictionary) -> Dictionary:
	var has_index: bool = false
	var has_js: bool = false
	var has_wasm: bool = false
	var has_pck: bool = false
	var has_manifest: bool = false
	var has_cover: bool = false
	var expected_cover_path: String = str(manifest.get("coverImage", "")).strip_edges()

	for item in inventory:
		var relative_path: String = str(item.get("relativePath", ""))
		if relative_path == "index.html":
			has_index = true
		elif relative_path.ends_with(".js"):
			has_js = true
		elif relative_path.ends_with(".wasm"):
			has_wasm = true
		elif relative_path.ends_with(".pck"):
			has_pck = true
		elif relative_path == "arcade.release.json":
			has_manifest = true
		if not expected_cover_path.is_empty() and relative_path == expected_cover_path:
			has_cover = true

	var blocking_issues: Array = []
	if not has_index:
		blocking_issues.append(_issue("missing_index_html", "Exported build is missing index.html."))
	if not has_js:
		blocking_issues.append(_issue("missing_js", "Exported build is missing a Godot-generated .js file."))
	if not has_wasm:
		blocking_issues.append(_issue("missing_wasm", "Exported build is missing a Godot-generated .wasm file."))
	if not has_pck:
		blocking_issues.append(_issue("missing_pck", "Exported build is missing a .pck file."))
	if not has_manifest:
		blocking_issues.append(_issue("missing_manifest", "Exported build is missing arcade.release.json."))
	if expected_cover_path.is_empty():
		blocking_issues.append(_issue("missing_cover_image_path", "Arcade release manifest is missing coverImage."))
	elif not has_cover:
		blocking_issues.append(_issue(
			"missing_cover_image",
			"Exported build is missing the manifest cover image.",
			{"coverImage": expected_cover_path}
		))
	if inventory.size() > MAX_FILE_COUNT:
		blocking_issues.append(_issue(
			"too_many_files",
			"Exported build exceeds the maximum extracted file count.",
			{"count": inventory.size(), "limit": MAX_FILE_COUNT}
		))

	return {
		"ok": blocking_issues.is_empty(),
		"blockingIssues": blocking_issues,
		"fileCount": inventory.size(),
	}

func _create_zip(zip_abs: String, staging_abs: String, inventory: Array) -> Dictionary:
	var zipper: ZIPPacker = ZIPPacker.new()
	var err: int = zipper.open(zip_abs)
	if err != OK:
		return {
			"success": false,
			"errorCode": "zip_open_failed",
			"errorMessage": "Failed to open arcade ZIP for writing.",
			"details": {
				"path": zip_abs,
				"errorCode": err,
				"errorName": error_string(err),
			},
		}

	for item in inventory:
		var relative_path: String = str(item.get("relativePath", ""))
		var absolute_path: String = str(item.get("absolutePath", ""))
		var start_err: int = zipper.start_file(relative_path)
		if start_err != OK:
			zipper.close()
			return {
				"success": false,
				"errorCode": "zip_write_failed",
				"errorMessage": "Failed to add file to arcade ZIP.",
				"details": {
					"path": relative_path,
					"errorCode": start_err,
					"errorName": error_string(start_err),
				},
			}
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(absolute_path)
		zipper.write_file(bytes)
		zipper.close_file()

	zipper.close()
	emit_signal("message_logged", "Created ZIP archive at %s." % ProjectSettings.localize_path(zip_abs))
	return {
		"success": true,
		"zipPath": ProjectSettings.localize_path(zip_abs),
		"stagingDirectoryAbsolute": staging_abs,
	}

func _issue(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {
		"code": code,
		"message": message,
		"details": details,
	}

func _relative_path(root_abs: String, child_abs: String) -> String:
	var normalized_root: String = root_abs
	if normalized_root.ends_with("/"):
		normalized_root = normalized_root.left(normalized_root.length() - 1)
	var prefix: String = normalized_root + "/"
	if child_abs.begins_with(prefix):
		return child_abs.substr(prefix.length())
	return child_abs

func _sort_inventory_item(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("relativePath", "")) < str(b.get("relativePath", ""))
