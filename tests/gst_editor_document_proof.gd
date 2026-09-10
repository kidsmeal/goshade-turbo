@tool
extends RefCounted

const PROBE_GROUP: StringName = &"shader_tabs_shutdown_probe"
const HOST_SCENE_PATH: String = "res://tests/fixtures/shader_tabs_host.tscn"
const NAMED_STACK_PATH: String = "res://tabs-proof-named.tres"
const SAVE_AS_STACK_PATH: String = "res://tabs-proof-save-as.tres"
const FIRST_DOCUMENT_PATH: String = "res://tabs-proof-first-document.tres"
const SECOND_DOCUMENT_PATH: String = "res://tabs-proof-second-document.tres"
const FORCED_SAVE_STACK_PATH: String = "res://tabs-proof-forced-save-stack.tres"
const FORCED_SAVE_AS_STACK_PATH: String = "res://tabs-proof-forced-save-as-stack.tres"
const PENDING_SHUTDOWN_STACK_PATH: String = "res://tabs-proof-pending-shutdown-stack.tres"

var _pass_count: int = 0
var _fail_count: int = 0
var _row_count: int = 0


class UndoRouter extends Control:
	var active_history: UndoRedo = null
	var owns_focus: bool = false
	var undo_count: int = 0
	var redo_count: int = 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _input(event: InputEvent) -> void:
		if not (event is InputEventKey):
			return
		var key: InputEventKey = event as InputEventKey
		if not owns_focus or not key.pressed or not key.ctrl_pressed or key.keycode != KEY_Z or active_history == null:
			return
		if key.shift_pressed:
			redo_count += 1
			active_history.redo()
		else:
			undo_count += 1
			active_history.undo()
		get_viewport().set_input_as_handled()


func run(plugin: EditorPlugin) -> void:
	var probe: EditorPlugin = await _find_probe(plugin)
	if probe == null:
		_check("probe", false, "shutdown probe plugin is not active")
		_finish(plugin)
		return
	var editor_ready: bool = await _settle_editor(plugin)
	if not editor_ready:
		_check("editor_ready", false, "Loading editor dialog remained visible after 10 seconds")
		_finish(plugin)
		return
	var stage: String = String(probe.call("get_stage"))
	if stage == "confirmed_quit_complete":
		await _verify_fresh_open(plugin, probe)
		return
	if stage == "awaiting_confirmed_quit":
		await _drive_confirmed_quit(plugin, probe)
		return
	await _run_native_undo_proof(plugin, probe)


func _run_native_undo_proof(plugin: EditorPlugin, probe: EditorPlugin) -> void:
	probe.call("reset_unsaved_documents")
	EditorInterface.open_scene_from_path(HOST_SCENE_PATH)
	await _frames(plugin, 5)
	var host_scene: Node = plugin.get_tree().edited_scene_root
	_check("host_scene", host_scene != null and host_scene.scene_file_path == HOST_SCENE_PATH, "scene=%s" % [host_scene.scene_file_path if host_scene != null else "null"])
	var router: UndoRouter = UndoRouter.new()
	plugin.get_tree().root.add_child(router)
	var first_target: GSTTabsProofTarget = GSTTabsProofTarget.new()
	var second_target: GSTTabsProofTarget = GSTTabsProofTarget.new()
	var first_saved: Error = ResourceSaver.save(first_target, FIRST_DOCUMENT_PATH)
	var second_saved: Error = ResourceSaver.save(second_target, SECOND_DOCUMENT_PATH)
	first_target.set_path(FIRST_DOCUMENT_PATH)
	second_target.set_path(SECOND_DOCUMENT_PATH)
	var first: Dictionary = await _make_bound_property(plugin, first_target, UndoRedo.new(), TYPE_FLOAT, &"scalar", PROPERTY_HINT_RANGE, "0,1,0.01")
	var second: Dictionary = await _make_bound_property(plugin, second_target, UndoRedo.new(), TYPE_FLOAT, &"scalar", PROPERTY_HINT_RANGE, "0,1,0.01")
	var first_history: UndoRedo = first["history"] as UndoRedo
	var second_history: UndoRedo = second["history"] as UndoRedo
	first_target = first["target"] as GSTTabsProofTarget
	second_target = second["target"] as GSTTabsProofTarget
	_record_row("first", first["property"] as EditorProperty)
	_record_row("second", second["property"] as EditorProperty)
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png("res://tabs-proof-native-rows.png")
	_check("private_histories", first_saved == OK and second_saved == OK and not first_target.resource_path.is_empty() and not second_target.resource_path.is_empty() and first_history != null and second_history != null and first_history != second_history, "first_path=%s second_path=%s distinct=%s" % [first_target.resource_path, second_target.resource_path, first_history != second_history])
	_register_structural_action(first_history, first_target, 1)
	_register_structural_action(second_history, second_target, 2)
	var host_history: UndoRedo = _register_host_action(plugin.get_undo_redo(), host_scene)
	_check("structural_isolation", first_target.structural_value == 1 and second_target.structural_value == 2 and host_history != null and host_history.has_undo(), "first=%d second=%d host_undo=%s" % [first_target.structural_value, second_target.structural_value, host_history.has_undo() if host_history != null else false])
	var first_scalar_input: Dictionary = await _drive_float_drag(plugin, first["property"] as EditorProperty, first["state"] as Dictionary)
	var second_scalar_input: Dictionary = await _drive_float_drag(plugin, second["property"] as EditorProperty, second["state"] as Dictionary)
	_check("native_float", int(first_scalar_input["value_count"]) >= 2 and int(second_scalar_input["value_count"]) >= 2 and int(first["state"]["actions"]) == 1 and int(second["state"]["actions"]) == 1 and first_target.scalar > 0.25 and second_target.scalar > 0.25 and first_history.has_undo() and second_history.has_undo(), "first=%s second=%s first_actions=%d second_actions=%d" % [first_scalar_input["values"], second_scalar_input["values"], int(first["state"]["actions"]), int(second["state"]["actions"])])
	first_target.scalar = 0.20
	(first["property"] as EditorProperty).update_property()
	await _drive_float_drag(plugin, first["property"] as EditorProperty, first["state"] as Dictionary)
	var middle_gesture_value: float = first_target.scalar
	first_target.scalar = 0.30
	(first["property"] as EditorProperty).update_property()
	await _drive_float_drag(plugin, first["property"] as EditorProperty, first["state"] as Dictionary, 1.0)
	var final_gesture_value: float = first_target.scalar
	first_history.undo()
	var undo_latest: bool = is_equal_approx(first_target.scalar, 0.30)
	var undo_latest_value: float = first_target.scalar
	first_history.undo()
	var undo_previous: bool = is_equal_approx(first_target.scalar, 0.20)
	var undo_previous_value: float = first_target.scalar
	first_history.redo()
	first_history.redo()
	_check("repeated_float_gestures", int(first["state"]["actions"]) == 3 and undo_latest and undo_previous and is_equal_approx(first_target.scalar, final_gesture_value), "actions=%d middle=%s final=%s undo_latest=%s value=%s undo_previous=%s value=%s" % [int(first["state"]["actions"]), middle_gesture_value, final_gesture_value, undo_latest, undo_latest_value, undo_previous, undo_previous_value])
	var first_spin: Range = _find_range(first["property"] as EditorProperty)
	var text_original: float = first_target.scalar
	var text_actions_before: int = int(first["state"]["actions"])
	var text_order_start: int = (first["state"]["order"] as Array).size()
	var text_grabbed: bool = await _begin_non_drag_text_entry(plugin, first_spin)
	var first_edit: LineEdit = _find_editable_line(first["property"] as EditorProperty)
	if first_edit != null:
		await _replace_line_edit(plugin, first_edit, "0.55")
	var text_final: float = first_target.scalar
	first_history.undo()
	var text_undo_original: bool = is_equal_approx(first_target.scalar, text_original)
	first_history.redo()
	var text_redo_final: bool = is_equal_approx(first_target.scalar, text_final)
	var text_order: Array = (first["state"]["order"] as Array).slice(text_order_start)
	var text_grab_index: int = text_order.find("grabbed")
	var text_value_index: int = text_order.find("value")
	var text_finish_index: int = text_order.find("finish")
	var text_session_ok: bool = text_grab_index == 0 and text_value_index != -1 and text_grab_index < text_value_index and (text_finish_index == -1 or text_finish_index > text_value_index)
	_check("native_text_focus", first_edit != null and text_grabbed and text_session_ok and int(first["state"]["actions"]) == text_actions_before + 1 and is_equal_approx(text_final, 0.55) and text_undo_original and text_redo_final, "edit=%s grabbed=%s original=%s final=%s actions=%d undo_original=%s redo_final=%s order=%s" % [first_edit != null, text_grabbed, text_original, text_final, int(first["state"]["actions"]), text_undo_original, text_redo_final, text_order])
	var vector_target: GSTTabsProofTarget = GSTTabsProofTarget.new()
	var vector_row: Dictionary = await _make_bound_property(plugin, vector_target, UndoRedo.new(), TYPE_VECTOR3, &"vector", PROPERTY_HINT_NONE, "")
	var vector_input: Dictionary = await _drive_vector_input(plugin, vector_row["property"] as EditorProperty, vector_row["state"] as Dictionary)
	var vector_history: UndoRedo = vector_row["history"] as UndoRedo
	var vector_final: Vector3 = vector_target.vector
	var vector_has_undo_before: bool = vector_history.has_undo()
	vector_history.undo()
	var vector_undo_original: Vector3 = vector_target.vector
	var vector_has_redo_after_undo: bool = vector_history.has_redo()
	vector_history.redo()
	var vector_redo_final: Vector3 = vector_target.vector
	var vector_has_undo_after_redo: bool = vector_history.has_undo()
	_check("native_vector", int(vector_input["value_count"]) >= 2 and int(vector_row["state"]["actions"]) == 1 and not is_equal_approx(vector_final.x, 0.1) and is_equal_approx(vector_final.y, 0.2) and is_equal_approx(vector_final.z, 0.3) and vector_has_undo_before and vector_undo_original.is_equal_approx(Vector3(0.1, 0.2, 0.3)) and vector_has_redo_after_undo and vector_redo_final.is_equal_approx(vector_final) and vector_has_undo_after_redo, "values=%s vector=%s actions=%d has_undo_before=%s undo_original=%s has_redo_after_undo=%s redo_final=%s has_undo_after_redo=%s" % [vector_input["values"], vector_final, int(vector_row["state"]["actions"]), vector_has_undo_before, vector_undo_original, vector_has_redo_after_undo, vector_redo_final, vector_has_undo_after_redo])
	var rgb_target: GSTTabsProofTarget = GSTTabsProofTarget.new()
	var rgb_row: Dictionary = await _make_bound_property(plugin, rgb_target, UndoRedo.new(), TYPE_COLOR, &"rgb", PROPERTY_HINT_COLOR_NO_ALPHA, "")
	var rgb_original: Vector3 = rgb_target.rgb_storage
	var rgb_changed: bool = await _drive_rgb_input(plugin, rgb_row["property"] as EditorProperty)
	var expected_rgb: Vector3 = Vector3(0x33 / 255.0, 0x66 / 255.0, 0xcc / 255.0)
	var rgb_history: UndoRedo = rgb_row["history"] as UndoRedo
	rgb_history.undo()
	var rgb_undo_original: bool = rgb_target.rgb_storage.is_equal_approx(rgb_original)
	rgb_history.redo()
	var rgb_redo_final: bool = rgb_target.rgb_storage.is_equal_approx(expected_rgb)
	_check("native_rgb", rgb_changed and int(rgb_row["state"]["actions"]) == 1 and rgb_redo_final and rgb_undo_original, "changed=%s storage=%s expected=%s actions=%d undo_original=%s redo_final=%s signals=%s" % [rgb_changed, rgb_target.rgb_storage, expected_rgb, int(rgb_row["state"]["actions"]), rgb_undo_original, rgb_redo_final, rgb_row["state"]["signals"]])
	var popup_shortcut_rows: Array[Dictionary] = await _prove_popup_shortcuts(plugin, router, second_target, second_history)
	var forced_finish_rows: Array[Dictionary] = await _prove_forced_finish_ordering(plugin, probe)
	var fallback_rows: Array[Dictionary] = await _prove_changing_fallback(plugin)
	router.active_history = second_history
	router.owns_focus = true
	_push_key(second["property"] as Control, KEY_Z, true)
	await _frames(plugin, 2)
	var active_undo: bool = second_target.scalar <= 0.25 and first_target.structural_value == 1
	_push_key(second["property"] as Control, KEY_Z, true, true)
	await _frames(plugin, 2)
	var active_redo: bool = second_target.scalar > 0.25 and first_target.structural_value == 1
	router.owns_focus = false
	var host_before_undo: Variant = host_scene.get_meta(&"shader_tabs_host_value", -1)
	_push_key(EditorInterface.get_base_control(), KEY_Z, true)
	await _frames(plugin, 2)
	var host_undone: bool = host_scene.get_meta(&"shader_tabs_host_value", -1) == 0 and first_target.structural_value == 1 and second_target.structural_value == 2
	_push_key(EditorInterface.get_base_control(), KEY_Z, true, true)
	await _frames(plugin, 2)
	_check("shortcut_and_host_isolation", active_undo and active_redo and host_before_undo == 1 and host_undone and host_scene.get_meta(&"shader_tabs_host_value", -1) == 1, "active_undo=%s active_redo=%s undo_count=%d redo_count=%d host_before=%s host_undone=%s host_redo=%s" % [active_undo, active_redo, router.undo_count, router.redo_count, host_before_undo, host_undone, host_scene.get_meta(&"shader_tabs_host_value", -1)])
	var host_save_error: Error = EditorInterface.save_scene()
	await _frames(plugin, 3)
	_check("host_scene_saved", host_save_error == OK, "error=%s" % error_string(host_save_error))
	probe.call("reset_unsaved_documents")
	probe.call("mark_unsaved_documents_dirty")
	var first_undo_before_close: bool = first_history.has_undo()
	var second_undo_before_close: bool = second_history.has_undo()
	_push_key(EditorInterface.get_base_control(), KEY_W, true, true)
	await _frames(plugin, 5)
	var closed_host_scene: Node = plugin.get_tree().edited_scene_root
	var host_closed: bool = closed_host_scene != host_scene and (closed_host_scene == null or closed_host_scene.scene_file_path != HOST_SCENE_PATH)
	_check("host_scene_closed", host_closed and first_undo_before_close and second_undo_before_close and first_history.has_undo() and second_history.has_undo(), "closed_scene=%s first_undo=%s second_undo=%s" % [closed_host_scene.scene_file_path if closed_host_scene != null else "null", first_history.has_undo(), second_history.has_undo()])
	EditorInterface.open_scene_from_path(HOST_SCENE_PATH)
	await _frames(plugin, 3)
	# Snapshot both histories' PRE-navigation state (each already holds a
	# structural action from _register_structural_action and a real native
	# property action from the native_float drag above) before Save As and
	# the scene switches, so retention can be proven against what already
	# existed rather than against actions registered after navigation.
	var first_pre_nav_value: float = first_target.scalar
	var first_pre_nav_structural: int = first_target.structural_value
	var first_pre_nav_has_undo: bool = first_history.has_undo()
	var second_pre_nav_value: float = second_target.scalar
	var second_pre_nav_vector: Vector3 = second_target.vector
	var second_pre_nav_structural: int = second_target.structural_value
	var second_pre_nav_has_undo: bool = second_history.has_undo()
	var named_stack: GSTStack = GSTStack.new()
	named_stack.next_id = 7
	var named_result: Dictionary = GSTStackIO.save(named_stack, NAMED_STACK_PATH)
	var loaded_named: GSTStack = ResourceLoader.load(NAMED_STACK_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as GSTStack
	# Save As on an actual history-owning target (second_target, already
	# path-bearing at SECOND_DOCUMENT_PATH, the one whose history was walked
	# above), not an unrelated empty GSTStack. second_target is now typed as
	# GSTTabsProofTarget, a standalone tests/fixtures/shader_tabs_proof_target.gd
	# script (not a script-local inner class), so ResourceSaver.save writes a
	# real external script reference and ResourceLoader.load can resolve it
	# back to a typed instance for a genuine round-trip assertion.
	var save_as_error: Error = ResourceSaver.save(second_target, SAVE_AS_STACK_PATH)
	var save_as_reloaded: GSTTabsProofTarget = ResourceLoader.load(SAVE_AS_STACK_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as GSTTabsProofTarget
	EditorInterface.open_scene_from_path("res://addons/goshade_turbo/ui/gst_main_panel.tscn")
	await _frames(plugin, 3)
	EditorInterface.open_scene_from_path(HOST_SCENE_PATH)
	await _frames(plugin, 3)
	# Verify the PRE-navigation structural and property actions survive Save
	# As and the scene switches by walking every action to the bottom and
	# back, before any new action is registered. Fresh actions registered
	# before this check would make has_undo() pass even if navigation had
	# silently cleared the earlier history.
	var first_actions_walked: int = 0
	while first_history.has_undo():
		first_history.undo()
		first_actions_walked += 1
	var first_fully_undone_ok: bool = is_equal_approx(first_target.scalar, 0.25) and first_target.structural_value == 0 and not first_history.has_undo() and first_history.has_redo()
	while first_history.has_redo():
		first_history.redo()
	var first_restored_ok: bool = is_equal_approx(first_target.scalar, first_pre_nav_value) and first_target.structural_value == first_pre_nav_structural
	var second_actions_walked: int = 0
	while second_history.has_undo():
		second_history.undo()
		second_actions_walked += 1
	var second_fully_undone_ok: bool = is_equal_approx(second_target.scalar, 0.25) and second_target.structural_value == 0 and not second_history.has_undo() and second_history.has_redo()
	while second_history.has_redo():
		second_history.redo()
	var second_restored_ok: bool = is_equal_approx(second_target.scalar, second_pre_nav_value) and second_target.structural_value == second_pre_nav_structural
	var pre_navigation_retention_ok: bool = first_pre_nav_has_undo and second_pre_nav_has_undo and first_actions_walked >= 2 and second_actions_walked >= 2 and first_fully_undone_ok and first_restored_ok and second_fully_undone_ok and second_restored_ok
	var first_structural_before: int = first_target.structural_value
	_register_structural_transition(first_history, first_target, first_structural_before, 3)
	var first_structural_after_action: int = first_target.structural_value
	first_history.undo()
	var first_structural_after_undo: int = first_target.structural_value
	first_history.redo()
	var first_structural_after_redo: int = first_target.structural_value
	var second_structural_before: int = second_target.structural_value
	_register_structural_transition(second_history, second_target, second_structural_before, 4)
	var second_structural_after_action: int = second_target.structural_value
	second_history.undo()
	var second_structural_after_undo: int = second_target.structural_value
	second_history.redo()
	var second_structural_after_redo: int = second_target.structural_value
	_check("resource_and_scene_retention", pre_navigation_retention_ok and bool(named_result.get("ok", false)) and loaded_named != null and loaded_named.next_id == 7 and save_as_error == OK and save_as_reloaded != null and is_equal_approx(save_as_reloaded.scalar, second_pre_nav_value) and save_as_reloaded.vector.is_equal_approx(second_pre_nav_vector) and first_history.has_undo() and second_history.has_undo() and first_structural_after_action == 3 and first_structural_after_undo == first_structural_before and first_structural_after_redo == 3 and second_structural_after_action == 4 and second_structural_after_undo == second_structural_before and second_structural_after_redo == 4, "pre_nav_ok=%s first_walked=%d second_walked=%d first_pre=%s first_restored=%s second_pre=%s second_restored=%s named=%s save_as_error=%s save_as_path=%s save_as_reloaded_scalar=%s save_as_reloaded_vector=%s first_undo=%s second_undo=%s first_structural=%d->%d->%d second_structural=%d->%d->%d" % [pre_navigation_retention_ok, first_actions_walked, second_actions_walked, first_pre_nav_value, first_restored_ok, second_pre_nav_value, second_restored_ok, named_result, error_string(save_as_error), SAVE_AS_STACK_PATH, save_as_reloaded.scalar if save_as_reloaded != null else -1.0, save_as_reloaded.vector if save_as_reloaded != null else Vector3.ZERO, first_history.has_undo(), second_history.has_undo(), first_structural_before, first_structural_after_undo, first_structural_after_redo, second_structural_before, second_structural_after_undo, second_structural_after_redo])
	var status_empty: String = String(probe.call("call_unsaved_status", ""))
	var status_scene: String = String(probe.call("call_unsaved_status", HOST_SCENE_PATH))
	_check("shutdown_status", status_empty.contains("Named proof document") and status_empty.contains("Untitled proof document") and status_scene.is_empty(), "empty='%s' scene='%s'" % [status_empty, status_scene])
	first_target.set_path("")
	second_target.set_path("")
	var rows_to_cleanup: Array[Dictionary] = [first, second, vector_row, rgb_row]
	rows_to_cleanup.append_array(forced_finish_rows)
	rows_to_cleanup.append_array(popup_shortcut_rows)
	rows_to_cleanup.append_array(fallback_rows)
	await _cleanup_rows(plugin, rows_to_cleanup)
	rows_to_cleanup.clear()
	forced_finish_rows.clear()
	popup_shortcut_rows.clear()
	fallback_rows.clear()
	first_history = null
	second_history = null
	host_history = null
	first_target = null
	second_target = null
	vector_target = null
	rgb_target = null
	named_stack = null
	loaded_named = null
	router.active_history = null
	router.queue_free()
	await _frames(plugin, 3)
	if _fail_count > 0:
		_finish(plugin)
		return
	probe.call("prepare_confirmed_quit")
	print("TABS_PROOF READY_FOR_CONFIRMED_QUIT")
	await _drive_confirmed_quit(plugin, probe)


func _drive_confirmed_quit(plugin: EditorPlugin, probe: EditorPlugin) -> void:
	_push_key(EditorInterface.get_base_control(), KEY_Q, true, true)
	await _frames(plugin, 60)
	var dialog: ConfirmationDialog = _find_quit_dialog(plugin.get_tree().root)
	if dialog == null or not dialog.visible:
		_dump_visible_dialogs(plugin.get_tree().root)
		_check("quit_confirmation", false, "Ctrl+Shift+Q did not expose a visible ConfirmationDialog")
		_finish(plugin)
		return
	dialog.get_viewport().get_texture().get_image().save_png("res://tabs-proof-quit-confirmation.png")
	var status_text: String = _visible_dialog_text(dialog)
	_check("quit_confirmation", status_text.contains("Named proof document") and status_text.contains("Untitled proof document"), "text='%s'" % status_text)
	var save_quit: Button = _find_button(dialog, "Save and Quit")
	if save_quit == null:
		save_quit = _find_button(dialog, "Save & Quit")
	if save_quit == null:
		_check("save_and_quit_control", false, "Save and Quit button was absent")
		_finish(plugin)
		return
	save_quit.grab_focus()
	await _frames(plugin, 2)
	var focused: Control = save_quit.get_viewport().gui_get_focus_owner()
	_check("save_and_quit_control", focused == save_quit, "button=%s focus=%s window_id=%d rect=%s viewport=%s" % [save_quit.text, focused.get_class() if focused != null else "null", save_quit.get_window().get_window_id(), save_quit.get_global_rect(), save_quit.get_viewport().get_visible_rect()])
	if focused != save_quit:
		_finish(plugin)
		return
	_queue_key(save_quit, KEY_ENTER)
	print("TABS_PROOF SAVE_AND_QUIT_ACTIVATION_DISPATCHED window_id=%d" % save_quit.get_window().get_window_id())


func _verify_fresh_open(plugin: EditorPlugin, probe: EditorPlugin) -> void:
	var recovery: Dictionary = probe.call("read_recovery_record") as Dictionary
	var recovered_stack: GSTStack = probe.call("load_recovery_stack") as GSTStack
	var failed_named_recovered_stack: GSTStack = probe.call("load_failed_named_recovery_stack") as GSTStack
	var mixed_shutdown: Dictionary = probe.call("get_mixed_shutdown_state") as Dictionary
	var save_count: int = int(probe.call("get_save_count"))
	var named_loaded: GSTStack = ResourceLoader.load(NAMED_STACK_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as GSTStack
	var documents: Array = recovery.get("documents", []) as Array
	_check("confirmed_shutdown_recovery", save_count >= 1 and bool(mixed_shutdown.get("named_ok", false)) and not bool(mixed_shutdown.get("failed_named_ok", true)) and bool(mixed_shutdown.get("failed_named_recovery_ok", false)) and bool(mixed_shutdown.get("recovery_ok", false)) and named_loaded != null and named_loaded.next_id == 7 and failed_named_recovered_stack != null and failed_named_recovered_stack.next_id == 29 and recovered_stack != null and recovered_stack.next_id == 42 and documents.size() == 3, "save_count=%d state=%s records=%d named_next_id=%s failed_recovered_next_id=%s untitled_recovered_next_id=%s" % [save_count, mixed_shutdown, documents.size(), named_loaded.next_id if named_loaded != null else -1, failed_named_recovered_stack.next_id if failed_named_recovered_stack != null else -1, recovered_stack.next_id if recovered_stack != null else -1])
	var pending_stack: GSTStack = probe.call("load_pending_shutdown_stack") as GSTStack
	var pending_rotation: float = pending_stack.layers[0].coord.rotation if pending_stack != null and pending_stack.layers.size() == 1 and pending_stack.layers[0].coord != null else 0.0
	var pending_recorded_value: float = float(mixed_shutdown.get("pending_shutdown_value", 0.0))
	_check("pending_shutdown_edit_persisted", bool(mixed_shutdown.get("pending_shutdown_finished", false)) and int(mixed_shutdown.get("pending_shutdown_actions", 0)) == 1 and bool(mixed_shutdown.get("pending_shutdown_stack_ok", false)) and not is_zero_approx(pending_recorded_value) and pending_stack != null and is_equal_approx(pending_rotation, pending_recorded_value), "finished=%s actions=%s stack_ok=%s recorded_value=%s persisted_rotation=%s path=%s" % [mixed_shutdown.get("pending_shutdown_finished", false), mixed_shutdown.get("pending_shutdown_actions", 0), mixed_shutdown.get("pending_shutdown_stack_ok", false), pending_recorded_value, pending_rotation, mixed_shutdown.get("pending_shutdown_stack_path", "")])
	probe.call("force_write_failure")
	probe.call("call_save_external_data")
	var forced_path: String = String(probe.call("get_forced_failure_path"))
	var forced_error: String = String(probe.call("get_forced_failure_error"))
	_check("forced_write_failure", not forced_error.is_empty() and not FileAccess.file_exists(forced_path), "path=%s error=%s exists=%s" % [forced_path, forced_error, FileAccess.file_exists(forced_path)])
	_check("void_callback", int(probe.call("get_save_count")) >= save_count + 1, "save_count_before=%d save_count_after=%d" % [save_count, int(probe.call("get_save_count"))])
	probe.call("mark_complete")
	_finish(plugin)


func _make_bound_property(plugin: EditorPlugin, target: Object, history: UndoRedo, type: Variant.Type, property_name: StringName, hint: PropertyHint, hint_string: String) -> Dictionary:
	var row: EditorProperty = EditorInspector.instantiate_property_editor(target, type, String(property_name), hint, hint_string, PROPERTY_USAGE_DEFAULT, false)
	var host: VBoxContainer = VBoxContainer.new()
	host.custom_minimum_size = Vector2(360.0, 42.0)
	EditorInterface.get_base_control().add_child(host)
	host.position = Vector2(160.0, 380.0 + _row_count * 54.0)
	host.size = Vector2(360.0, 42.0)
	host.add_child(row)
	row.set_object_and_property(target, property_name)
	row.update_property()
	_row_count += 1
	var state: Dictionary = {"original": target.get(property_name), "final": target.get(property_name), "active": false, "boundary": "", "value_count_at_begin": 0, "retired": false, "signals": [], "values": [], "actions": 0, "order": [], "operations": []}
	row.property_changed.connect(_on_bound_property_changed.bind(history, target, property_name, state, row))
	for spin_node: Node in row.find_children("*", "EditorSpinSlider", true, false):
		var spin: EditorSpinSlider = spin_node as EditorSpinSlider
		spin.grabbed.connect(_begin_native_interaction.bind(target, property_name, state, "grabbed"))
		spin.ungrabbed.connect(_finish_native_interaction.bind(history, target, property_name, state, row, "ungrabbed"))
		spin.value_focus_entered.connect(_begin_native_interaction.bind(target, property_name, state, "value_focus_entered"))
		spin.value_focus_exited.connect(_finish_native_interaction.bind(history, target, property_name, state, row, "value_focus_exited"))
	await _frames(plugin, 3)
	return {"history": history, "target": target, "property": row, "host": host, "state": state}


func _on_bound_property_changed(property: StringName, value: Variant, field: StringName, changing: bool, history: UndoRedo, target: Object, property_name: StringName, state: Dictionary, row: EditorProperty) -> void:
	state["signals"].append({"property": property, "value": value, "field": field, "changing": changing})
	if bool(state["retired"]) or property != property_name:
		return
	var new_value: Variant = _merge_component_value(target.get(property_name), value, field)
	state["values"].append(new_value)
	if bool(state["active"]):
		target.set(property_name, new_value)
		state["final"] = new_value
		state["order"].append("value")
		row.update_property()
		if not changing and String(state["boundary"]) == "changing":
			_finish_native_interaction(history, target, property_name, state, row, "changing_false")
		return
	if changing:
		_begin_native_interaction(target, property_name, state, "changing")
		target.set(property_name, new_value)
		state["final"] = new_value
		state["order"].append("value")
		return
	_register_property_action(history, target, property_name, target.get(property_name), new_value, state, row, "discrete")


func _begin_native_interaction(target: Object, property_name: StringName, state: Dictionary, boundary: String) -> void:
	state["order"].append(boundary)
	if bool(state["active"]):
		return
	state["original"] = target.get(property_name)
	state["final"] = state["original"]
	state["active"] = true
	state["boundary"] = boundary
	state["value_count_at_begin"] = (state["values"] as Array).size()


func _finish_native_interaction(history: UndoRedo, target: Object, property_name: StringName, state: Dictionary, row: EditorProperty, boundary: String) -> void:
	state["order"].append(boundary)
	if not bool(state["active"]):
		return
	if boundary == "ungrabbed" and String(state["boundary"]) == "grabbed" and (state["values"] as Array).size() == int(state["value_count_at_begin"]):
		return
	_register_property_action(history, target, property_name, state["original"], state["final"], state, row, boundary)


func _register_property_action(history: UndoRedo, target: Object, property_name: StringName, old_value: Variant, new_value: Variant, state: Dictionary, row: EditorProperty, boundary: String) -> void:
	if not is_equal_approx_or_equal(old_value, new_value):
		history.create_action("proof %s %s" % [String(property_name), boundary], UndoRedo.MERGE_DISABLE)
		history.add_do_method(target.set.bind(property_name, new_value))
		history.add_undo_method(target.set.bind(property_name, old_value))
		history.commit_action(false)
		state["actions"] = int(state["actions"]) + 1
	target.set(property_name, new_value)
	state["final"] = new_value
	state["active"] = false
	state["boundary"] = ""
	state["order"].append("finish")
	row.update_property()


func is_equal_approx_or_equal(first: Variant, second: Variant) -> bool:
	if first is float and second is float:
		return is_equal_approx(first, second)
	if first is Vector3 and second is Vector3:
		return (first as Vector3).is_equal_approx(second as Vector3)
	if first is Color and second is Color:
		return (first as Color).is_equal_approx(second as Color)
	return first == second


func _merge_component_value(current: Variant, value: Variant, field: StringName) -> Variant:
	if current is Vector3 and field == &"x":
		var vector: Vector3 = current as Vector3
		if value is Vector3:
			vector.x = (value as Vector3).x
		else:
			vector.x = value
		return vector
	return value


func _register_structural_action(history: UndoRedo, target: GSTTabsProofTarget, value: int) -> void:
	history.create_action("proof structural")
	history.add_do_method(target.set_structural_value.bind(value))
	history.add_undo_method(target.set_structural_value.bind(0))
	history.commit_action()


func _register_structural_transition(history: UndoRedo, target: GSTTabsProofTarget, old_value: int, new_value: int) -> void:
	history.create_action("proof structural transition")
	history.add_do_method(target.set_structural_value.bind(new_value))
	history.add_undo_method(target.set_structural_value.bind(old_value))
	history.commit_action()


func _register_host_action(manager: EditorUndoRedoManager, host_scene: Node) -> UndoRedo:
	if host_scene == null:
		return null
	manager.create_action("host scene proof", UndoRedo.MERGE_DISABLE, host_scene)
	manager.add_do_method(host_scene, &"set_meta", &"shader_tabs_host_value", 1)
	manager.add_undo_method(host_scene, &"set_meta", &"shader_tabs_host_value", 0)
	manager.commit_action()
	return manager.get_history_undo_redo(manager.get_object_history_id(host_scene))


func _drive_float_drag(plugin: EditorPlugin, row: EditorProperty, state: Dictionary, direction: float = 1.0) -> Dictionary:
	var initial_count: int = (state["values"] as Array).size()
	var range: Range = _find_range(row)
	if range != null:
		await _drag_spin(plugin, range, direction)
	await _frames(plugin, 4)
	var values: Array = (state["values"] as Array).slice(initial_count)
	return {"values": values, "value_count": _distinct_value_count(values), "signals": state["signals"]}


func _begin_non_drag_text_entry(plugin: EditorPlugin, spin: Range) -> bool:
	if spin == null:
		return false
	var control: Control = spin as Control
	var start: Vector2 = control.get_global_rect().get_center()
	# A press/release with no motion in between is a non-drag grab.
	# EditorSpinSlider::_grab_end (Godot 4.4 editor/gui/editor_spin_slider.cpp)
	# calls _focus_entered() directly for that case, which shows and focuses
	# the internal LineEdit via a deferred call. Calling grab_focus()/Enter on
	# the outer control here would steal that focus back and reopen a second
	# session; instead wait for the deferred focus to land.
	_push_mouse(control, start, MOUSE_BUTTON_LEFT, true)
	await plugin.get_tree().process_frame
	_push_mouse(control, start, MOUSE_BUTTON_LEFT, false)
	await _frames(plugin, 3)
	return true


func _drive_vector_input(plugin: EditorPlugin, row: EditorProperty, state: Dictionary) -> Dictionary:
	var spins: Array[Node] = row.find_children("*", "EditorSpinSlider", true, false)
	if spins.is_empty():
		return {"values": [], "value_count": 0}
	var initial_count: int = (state["values"] as Array).size()
	await _drag_spin(plugin, spins[0] as Control)
	await _frames(plugin, 3)
	var values: Array = (state["values"] as Array).slice(initial_count)
	return {"values": values, "value_count": _distinct_value_count(values)}


func _drive_rgb_input(plugin: EditorPlugin, row: EditorProperty) -> bool:
	var button: ColorPickerButton = _find_color_button(row)
	if button == null:
		return false
	button.grab_focus()
	_push_key(button, KEY_SPACE)
	await _frames(plugin, 2)
	var hex_edit: LineEdit = _find_hex_line_edit(button.get_picker())
	if hex_edit == null:
		return false
	await _replace_line_edit(plugin, hex_edit, "3366cc")
	button.get_popup().hide()
	button.grab_focus()
	await _frames(plugin, 3)
	return true


func _prove_popup_shortcuts(plugin: EditorPlugin, router: UndoRouter, inactive_target: GSTTabsProofTarget, inactive_history: UndoRedo) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var active_target: GSTTabsProofTarget = GSTTabsProofTarget.new()
	var active_row: Dictionary = await _make_bound_property(plugin, active_target, UndoRedo.new(), TYPE_COLOR, &"rgb", PROPERTY_HINT_COLOR_NO_ALPHA, "")
	rows.append(active_row)
	var active_history: UndoRedo = active_row["history"] as UndoRedo
	var active_button: ColorPickerButton = _find_color_button(active_row["property"] as EditorProperty)
	var active_changed: bool = await _drive_rgb_input(plugin, active_row["property"] as EditorProperty)
	var active_final: Vector3 = active_target.rgb_storage
	var inactive_before: float = inactive_target.scalar
	if active_button != null:
		active_button.grab_focus()
		_push_key(active_button, KEY_SPACE)
		await _frames(plugin, 2)
	var popup: Popup = active_button.get_popup() if active_button != null else null
	var popup_router: UndoRouter = UndoRouter.new()
	if popup != null and popup.visible:
		popup.add_child(popup_router)
	popup_router.active_history = active_history
	popup_router.owns_focus = true
	var popup_focus: Control = popup.get_viewport().gui_get_focus_owner() if popup != null else null
	if popup_focus != null:
		_push_key(popup_focus, KEY_Z, true)
		await _frames(plugin, 2)
	var popup_undo: bool = active_target.rgb_storage.is_equal_approx(Vector3(0.2, 0.4, 0.6))
	if popup_focus != null:
		_push_key(popup_focus, KEY_Z, true, true)
		await _frames(plugin, 2)
	var popup_redo: bool = active_target.rgb_storage.is_equal_approx(active_final)
	var inactive_unchanged: bool = is_equal_approx(inactive_target.scalar, inactive_before) and inactive_history.has_undo()
	_check("popup_shortcut_isolation", active_changed and popup != null and popup.visible and popup_focus != null and popup_focus.get_window() == popup and popup_router.undo_count == 1 and popup_router.redo_count == 1 and popup_undo and popup_redo and inactive_unchanged, "popup_visible=%s focus=%s undo=%d redo=%d popup_undo=%s popup_redo=%s inactive_before=%s inactive_after=%s" % [popup != null and popup.visible, popup_focus.get_class() if popup_focus != null else "null", popup_router.undo_count, popup_router.redo_count, popup_undo, popup_redo, inactive_before, inactive_target.scalar])
	if popup != null and popup.visible:
		popup.hide()
	popup_router.queue_free()
	return rows


func _prove_changing_fallback(plugin: EditorPlugin) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var target: GSTTabsProofTarget = GSTTabsProofTarget.new()
	var row: Dictionary = await _make_bound_property(plugin, target, UndoRedo.new(), TYPE_FLOAT, &"scalar", PROPERTY_HINT_RANGE, "0,1,0.01")
	rows.append(row)
	var state: Dictionary = row["state"] as Dictionary
	var history: UndoRedo = row["history"] as UndoRedo
	var property: EditorProperty = row["property"] as EditorProperty
	_on_bound_property_changed(&"scalar", 0.40, &"", true, history, target, &"scalar", state, property)
	_on_bound_property_changed(&"scalar", 0.65, &"", false, history, target, &"scalar", state, property)
	var action_count: int = int(state["actions"])
	var ended: bool = not bool(state["active"]) and is_equal_approx(target.scalar, 0.65)
	history.undo()
	var undo_original: bool = is_equal_approx(target.scalar, 0.25)
	history.redo()
	var redo_final: bool = is_equal_approx(target.scalar, 0.65)
	_check("changing_fallback_finish", action_count == 1 and ended and undo_original and redo_final, "actions=%d active=%s final=%s undo_original=%s redo_final=%s order=%s" % [action_count, state["active"], target.scalar, undo_original, redo_final, state["order"]])
	return rows


func _prove_forced_finish_ordering(plugin: EditorPlugin, probe: EditorPlugin) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var rebind_target: GSTTabsProofTarget = GSTTabsProofTarget.new()
	var rebind_row: Dictionary = await _make_bound_property(plugin, rebind_target, UndoRedo.new(), TYPE_FLOAT, &"scalar", PROPERTY_HINT_RANGE, "0,1,0.01")
	rows.append(rebind_row)
	var rebind_spin: Range = _find_range(rebind_row["property"] as EditorProperty)
	var rebind_started: bool = await _start_pending_drag(plugin, rebind_spin)
	var rebind_state: Dictionary = rebind_row["state"] as Dictionary
	var rebind_history: UndoRedo = rebind_row["history"] as UndoRedo
	var rebind_actions_before: int = int(rebind_state["actions"])
	await _force_finish_numeric(plugin, rebind_history, rebind_target, &"scalar", rebind_state, rebind_row["property"] as EditorProperty, "forced_before_rebind")
	rebind_state["operations"].append("rebind")
	var rebound_target: GSTTabsProofTarget = GSTTabsProofTarget.new()
	rebind_state["retired"] = true
	(rebind_row["property"] as EditorProperty).set_object_and_property(rebound_target, &"scalar")
	var late_signals_before: int = (rebind_state["signals"] as Array).size()
	if rebind_spin != null:
		var rebind_control: Control = rebind_spin as Control
		_push_drag(rebind_control, rebind_control.get_global_rect().get_center() + Vector2(12.0, 0.0), Vector2(4.0, 0.0))
	await _release_pending_drag(plugin, rebind_spin)
	await _frames(plugin, 2)
	var late_signal_delivered: bool = (rebind_state["signals"] as Array).size() > late_signals_before
	var rebind_ok: bool = rebind_started and late_signal_delivered and int(rebind_state["actions"]) == rebind_actions_before + 1 and not bool(rebind_state["active"]) and is_equal_approx(rebound_target.scalar, 0.25) and _operation_precedes(rebind_state, "forced_finish", "rebind")

	var save_stack: GSTStack = GSTStack.new()
	var save_layer: GSTLayer = GSTLayer.new()
	var save_target: GSTCoordBlock = GSTCoordBlock.new()
	save_layer.coord = save_target
	save_stack.layers.append(save_layer)
	var save_row: Dictionary = await _make_bound_property(plugin, save_target, UndoRedo.new(), TYPE_FLOAT, &"rotation", PROPERTY_HINT_RANGE, "-3.14,3.14,0.01")
	rows.append(save_row)
	var save_spin: Range = _find_range(save_row["property"] as EditorProperty)
	var save_started: bool = await _start_pending_drag(plugin, save_spin)
	var save_state: Dictionary = save_row["state"] as Dictionary
	await _force_finish_numeric(plugin, save_row["history"] as UndoRedo, save_target, &"rotation", save_state, save_row["property"] as EditorProperty, "forced_before_save")
	await _release_pending_drag(plugin, save_spin)
	save_state["operations"].append("save_as")
	var save_result: Dictionary = GSTStackIO.save(save_stack, FORCED_SAVE_AS_STACK_PATH)
	var saved_stack: GSTStack = ResourceLoader.load(FORCED_SAVE_AS_STACK_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as GSTStack
	var saved_rotation: float = saved_stack.layers[0].coord.rotation if saved_stack != null and saved_stack.layers.size() == 1 and saved_stack.layers[0].coord != null else 0.0
	var save_ok: bool = save_started and bool(save_result.get("ok", false)) and saved_stack != null and is_equal_approx(saved_rotation, save_target.rotation) and not is_zero_approx(save_target.rotation) and _operation_precedes(save_state, "forced_finish", "save_as")

	var undo_target: GSTTabsProofTarget = GSTTabsProofTarget.new()
	var undo_row: Dictionary = await _make_bound_property(plugin, undo_target, UndoRedo.new(), TYPE_FLOAT, &"scalar", PROPERTY_HINT_RANGE, "0,1,0.01")
	rows.append(undo_row)
	var undo_spin: Range = _find_range(undo_row["property"] as EditorProperty)
	var undo_started: bool = await _start_pending_drag(plugin, undo_spin)
	var undo_state: Dictionary = undo_row["state"] as Dictionary
	var undo_history: UndoRedo = undo_row["history"] as UndoRedo
	await _force_finish_numeric(plugin, undo_history, undo_target, &"scalar", undo_state, undo_row["property"] as EditorProperty, "forced_before_undo")
	await _release_pending_drag(plugin, undo_spin)
	undo_state["operations"].append("undo")
	undo_history.undo()
	var undo_ok: bool = undo_started and is_equal_approx(undo_target.scalar, 0.25) and _operation_precedes(undo_state, "forced_finish", "undo")

	var redo_target: GSTTabsProofTarget = GSTTabsProofTarget.new()
	var redo_row: Dictionary = await _make_bound_property(plugin, redo_target, UndoRedo.new(), TYPE_FLOAT, &"scalar", PROPERTY_HINT_RANGE, "0,1,0.01")
	rows.append(redo_row)
	var redo_history: UndoRedo = redo_row["history"] as UndoRedo
	await _drive_float_drag(plugin, redo_row["property"] as EditorProperty, redo_row["state"] as Dictionary)
	var redo_final: float = redo_target.scalar
	redo_history.undo()
	var redo_spin: Range = _find_range(redo_row["property"] as EditorProperty)
	var redo_started: bool = await _start_pending_noop_grab(plugin, redo_spin)
	var redo_state: Dictionary = redo_row["state"] as Dictionary
	var redo_actions_before: int = int(redo_state["actions"])
	await _force_finish_numeric(plugin, redo_history, redo_target, &"scalar", redo_state, redo_row["property"] as EditorProperty, "forced_before_redo")
	await _release_pending_drag(plugin, redo_spin)
	redo_state["operations"].append("redo")
	redo_history.redo()
	var redo_ok: bool = redo_started and int(redo_state["actions"]) == redo_actions_before and is_equal_approx(redo_target.scalar, redo_final) and _operation_precedes(redo_state, "forced_finish", "redo")

	var focus_target: GSTTabsProofTarget = GSTTabsProofTarget.new()
	var focus_row: Dictionary = await _make_bound_property(plugin, focus_target, UndoRedo.new(), TYPE_FLOAT, &"scalar", PROPERTY_HINT_RANGE, "0,1,0.01")
	rows.append(focus_row)
	var focus_history: UndoRedo = focus_row["history"] as UndoRedo
	var focus_state: Dictionary = focus_row["state"] as Dictionary
	var focus_original: float = focus_target.scalar
	var focus_spin: Range = _find_range(focus_row["property"] as EditorProperty)
	if focus_spin != null:
		(focus_spin as Control).grab_focus()
		_push_key(focus_spin as Control, KEY_ENTER)
		await _frames(plugin, 2)
	var focus_edit: LineEdit = _find_editable_line(focus_row["property"] as EditorProperty)
	if focus_edit != null:
		focus_edit.grab_focus()
		await _frames(plugin, 2)
		# Type a changed value WITHOUT submitting: the field must still hold
		# pending, uncommitted text when the forced finish runs.
		await _replace_line_edit(plugin, focus_edit, "0.7", false)
	var focus_typed_uncommitted: bool = focus_edit != null and is_equal_approx(focus_target.scalar, focus_original) and focus_edit.text == "0.7"
	var focus_actions_before: int = int(focus_state["actions"])
	await _force_finish_numeric(plugin, focus_history, focus_target, &"scalar", focus_state, focus_row["property"] as EditorProperty, "forced_before_focus_rebind", focus_edit)
	var focus_final_delivered: bool = is_equal_approx(focus_target.scalar, 0.7) and is_equal_approx(float(focus_state["final"]), 0.7)
	var focus_action_registered: bool = int(focus_state["actions"]) == focus_actions_before + 1
	focus_state["operations"].append("focus_rebind")
	focus_history.undo()
	var focus_undo_original: bool = is_equal_approx(focus_target.scalar, focus_original)
	focus_history.redo()
	var focus_redo_final: bool = is_equal_approx(focus_target.scalar, 0.7)
	var focus_rebound_target: GSTTabsProofTarget = GSTTabsProofTarget.new()
	focus_state["retired"] = true
	(focus_row["property"] as EditorProperty).set_object_and_property(focus_rebound_target, &"scalar")
	if focus_spin != null:
		(focus_spin as Control).grab_focus()
		_push_key(focus_spin as Control, KEY_ENTER)
		await _frames(plugin, 2)
	var focus_late_edit: LineEdit = _find_editable_line(focus_row["property"] as EditorProperty)
	if focus_late_edit != null:
		focus_late_edit.grab_focus()
		await _frames(plugin, 2)
		await _replace_line_edit(plugin, focus_late_edit, "0.9", false)
		focus_late_edit.release_focus()
		await _frames(plugin, 2)
	var focus_late_original_unchanged: bool = is_equal_approx(focus_target.scalar, 0.7)
	var focus_late_rebound_unchanged: bool = is_equal_approx(focus_rebound_target.scalar, 0.25)
	var focus_ok: bool = focus_edit != null and focus_typed_uncommitted and focus_final_delivered and focus_action_registered and not bool(focus_state["active"]) and focus_undo_original and focus_redo_final and focus_late_edit != null and focus_late_original_unchanged and focus_late_rebound_unchanged and _operation_precedes(focus_state, "forced_finish", "focus_rebind")

	var color_target: GSTTabsProofTarget = GSTTabsProofTarget.new()
	var color_row: Dictionary = await _make_bound_property(plugin, color_target, UndoRedo.new(), TYPE_COLOR, &"rgb", PROPERTY_HINT_COLOR_NO_ALPHA, "")
	rows.append(color_row)
	var color_button: ColorPickerButton = _find_color_button(color_row["property"] as EditorProperty)
	var color_popup_open: bool = await _enter_rgb_popup_value(plugin, color_button, "3366cc")
	var color_state: Dictionary = color_row["state"] as Dictionary
	var color_history: UndoRedo = color_row["history"] as UndoRedo
	var color_original: Vector3 = color_target.rgb_storage
	var color_actions_before: int = int(color_state["actions"])
	var color_signal_count: int = (color_state["signals"] as Array).size()
	await _force_close_color_popup(plugin, color_button, color_state)
	var color_signal_count_after: int = (color_state["signals"] as Array).size()
	var color_actions_after: int = int(color_state["actions"])
	var color_final_signal: Dictionary = color_state["signals"].back() as Dictionary if color_signal_count_after > color_signal_count else {}
	color_history.undo()
	var color_undo_original: bool = color_target.rgb_storage.is_equal_approx(color_original)
	color_history.redo()
	var color_redo_final: bool = color_target.rgb_storage.is_equal_approx(Vector3(0x33 / 255.0, 0x66 / 255.0, 0xcc / 255.0))
	color_state["operations"].append("color_rebind")
	var color_rebound_target: GSTTabsProofTarget = GSTTabsProofTarget.new()
	color_state["retired"] = true
	(color_row["property"] as EditorProperty).set_object_and_property(color_rebound_target, &"rgb")
	await _frames(plugin, 2)
	var expected_color: Vector3 = Vector3(0x33 / 255.0, 0x66 / 255.0, 0xcc / 255.0)
	var color_ok: bool = color_popup_open and not color_button.get_popup().visible and color_signal_count_after == color_signal_count + 1 and color_actions_after == color_actions_before + 1 and StringName(color_final_signal.get("property", &"")) == &"rgb" and (color_final_signal.get("value", Color.BLACK) as Color).is_equal_approx(Color(expected_color.x, expected_color.y, expected_color.z, 1.0)) and color_undo_original and color_redo_final and color_target.rgb_storage.is_equal_approx(expected_color) and color_rebound_target.rgb_storage.is_equal_approx(Vector3(0.2, 0.4, 0.6)) and _operation_precedes(color_state, "color_popup_closed", "color_rebind")

	# The shutdown case is left genuinely pending, not force-finished here: a
	# stack-owned GSTCoordBlock, a bound Callable that performs the finish,
	# and the target save path are handed to the probe. The probe invokes the
	# Callable and saves the stack from inside its own _save_external_data,
	# the same synchronous-quit callback production code will use, so the
	# forced-finish-before-shutdown-save ordering is exercised by the real
	# shutdown path instead of by this proof script beforehand. shutdown_row
	# is deliberately excluded from the returned `rows` so its history/host
	# survive until the confirmed quit actually runs _save_external_data;
	# the handed-off Callable frees the UndoRedo and queues the host free
	# once it has finished the edit, since UndoRedo is a plain Object and
	# does not get released by scene-tree teardown on quit.
	var shutdown_stack: GSTStack = GSTStack.new()
	var shutdown_layer: GSTLayer = GSTLayer.new()
	var shutdown_coord: GSTCoordBlock = GSTCoordBlock.new()
	shutdown_layer.coord = shutdown_coord
	shutdown_stack.layers.append(shutdown_layer)
	var shutdown_row: Dictionary = await _make_bound_property(plugin, shutdown_coord, UndoRedo.new(), TYPE_FLOAT, &"rotation", PROPERTY_HINT_RANGE, "-3.14,3.14,0.01")
	var shutdown_spin: Range = _find_range(shutdown_row["property"] as EditorProperty)
	var shutdown_started: bool = await _start_pending_drag(plugin, shutdown_spin)
	var shutdown_state: Dictionary = shutdown_row["state"] as Dictionary
	var shutdown_history: UndoRedo = shutdown_row["history"] as UndoRedo
	var shutdown_property: EditorProperty = shutdown_row["property"] as EditorProperty
	var shutdown_host: Node = shutdown_row["host"] as Node
	shutdown_state["operations"].append("shutdown_save_prepared")
	var shutdown_finish: Callable = func() -> Dictionary:
		await _force_finish_numeric(plugin, shutdown_history, shutdown_coord, &"rotation", shutdown_state, shutdown_property, "forced_before_shutdown_save")
		var result: Dictionary = {"actions": int(shutdown_state["actions"]), "value": shutdown_coord.rotation}
		shutdown_history.clear_history()
		shutdown_history.free()
		if shutdown_host != null:
			shutdown_host.queue_free()
		return result
	probe.call("set_pending_shutdown_target", shutdown_stack, PENDING_SHUTDOWN_STACK_PATH, shutdown_finish)
	var shutdown_ok: bool = shutdown_started and not is_zero_approx(shutdown_coord.rotation)
	_check("forced_finish_ordering", rebind_ok and save_ok and undo_ok and redo_ok and focus_ok and color_ok and shutdown_ok, "rebind=%s late=%s save_as=%s undo=%s redo=%s focus=%s color=%s shutdown=%s rebind_order=%s save_order=%s undo_order=%s redo_order=%s focus_order=%s color_order=%s shutdown_order=%s" % [rebind_ok, late_signal_delivered, save_ok, undo_ok, redo_ok, focus_ok, color_ok, shutdown_ok, rebind_state["operations"], save_state["operations"], undo_state["operations"], redo_state["operations"], focus_state["operations"], color_state["operations"], shutdown_state["operations"]])
	return rows


func _start_pending_drag(plugin: EditorPlugin, spin: Range) -> bool:
	if spin == null:
		return false
	var control: Control = spin as Control
	var rect: Rect2 = control.get_global_rect()
	var start: Vector2 = rect.get_center()
	_push_mouse(control, start, MOUSE_BUTTON_LEFT, true)
	await plugin.get_tree().process_frame
	_push_drag(control, start + Vector2(4.0, 0.0), Vector2(4.0, 0.0))
	await plugin.get_tree().process_frame
	_push_drag(control, start + Vector2(8.0, 0.0), Vector2(4.0, 0.0))
	await plugin.get_tree().process_frame
	return true


func _start_pending_noop_grab(plugin: EditorPlugin, spin: Range) -> bool:
	if spin == null:
		return false
	var control: Control = spin as Control
	_push_mouse(control, control.get_global_rect().get_center(), MOUSE_BUTTON_LEFT, true)
	await plugin.get_tree().process_frame
	return true


func _force_finish_numeric(plugin: EditorPlugin, history: UndoRedo, target: Object, property_name: StringName, state: Dictionary, row: EditorProperty, boundary: String, pending_edit: LineEdit = null) -> void:
	state["operations"].append("forced_finish")
	if pending_edit != null and is_instance_valid(pending_edit) and pending_edit.is_inside_tree():
		# Commit the pending native text (EditorSpinSlider::_value_focus_exited,
		# Godot 4.4 editor/gui/editor_spin_slider.cpp calls _evaluate_input_text()
		# before emitting value_focus_exited) before finalizing the history
		# action, so a typed-but-unsubmitted value reaches the original target.
		pending_edit.release_focus()
		await _frames(plugin, 3)
	_finish_native_interaction(history, target, property_name, state, row, boundary)


func _release_pending_drag(plugin: EditorPlugin, spin: Range) -> void:
	if spin == null:
		return
	var control: Control = spin as Control
	_push_mouse(control, control.get_global_rect().get_center() + Vector2(8.0, 0.0), MOUSE_BUTTON_LEFT, false)
	await plugin.get_tree().process_frame


func _enter_rgb_popup_value(plugin: EditorPlugin, button: ColorPickerButton, hex_value: String) -> bool:
	if button == null:
		return false
	button.grab_focus()
	_push_key(button, KEY_SPACE)
	await _frames(plugin, 2)
	var hex_edit: LineEdit = _find_hex_line_edit(button.get_picker())
	if hex_edit == null:
		return false
	await _replace_line_edit(plugin, hex_edit, hex_value, false)
	await _frames(plugin, 2)
	return button.get_popup().visible


func _force_close_color_popup(plugin: EditorPlugin, button: ColorPickerButton, state: Dictionary) -> void:
	if button != null and button.get_popup().visible:
		# Commit pending hex text before hiding. ColorPicker::_html_focus_exit
		# (Godot 4.4 scene/gui/color_picker.cpp) applies the field only while
		# the picker is visible in tree; after hide() it discards the text.
		# EditorPropertyColor::_popup_closed then emits the one final
		# property_changed(changing=false) because pick_color != last_color.
		var picker: ColorPicker = button.get_picker()
		var focused: Control = picker.get_viewport().gui_get_focus_owner()
		if focused is LineEdit and picker.is_ancestor_of(focused):
			focused.release_focus()
			await _frames(plugin, 1)
		button.get_popup().hide()
	state["operations"].append("color_popup_closed")
	await _frames(plugin, 2)


func _operation_precedes(state: Dictionary, first: String, second: String) -> bool:
	var operations: Array = state["operations"] as Array
	return operations.find(first) != -1 and operations.find(second) != -1 and operations.find(first) < operations.find(second)


func _find_probe(plugin: EditorPlugin) -> EditorPlugin:
	for i: int in range(12):
		var probes: Array[Node] = plugin.get_tree().get_nodes_in_group(PROBE_GROUP)
		if not probes.is_empty():
			return probes[0] as EditorPlugin
		await plugin.get_tree().process_frame
	return null


func _find_range(node: Node) -> Range:
	if node is Range:
		return node as Range
	for child: Node in node.get_children():
		var found: Range = _find_range(child)
		if found != null:
			return found
	return null


func _record_row(name: String, row: EditorProperty) -> void:
	var spin: Range = _find_range(row)
	print("TABS_PROOF row=%s visible=%s rect=%s spin=%s spin_visible=%s spin_rect=%s spin_filter=%s" % [name, row.is_visible_in_tree(), row.get_global_rect(), spin.get_class() if spin != null else "null", spin.is_visible_in_tree() if spin != null else false, spin.get_global_rect() if spin != null else Rect2(), spin.mouse_filter if spin != null else -1])


func _find_color_button(node: Node) -> ColorPickerButton:
	if node is ColorPickerButton:
		return node as ColorPickerButton
	for child: Node in node.get_children():
		var found: ColorPickerButton = _find_color_button(child)
		if found != null:
			return found
	return null


func _find_hex_line_edit(picker: ColorPicker) -> LineEdit:
	var expected: String = picker.color.to_html(false).to_lower()
	for node: Node in picker.find_children("*", "LineEdit", true, false):
		var edit: LineEdit = node as LineEdit
		if edit.is_visible_in_tree() and edit.editable and edit.text.strip_edges().trim_prefix("#").to_lower() == expected:
			return edit
	return null


func _find_editable_line(node: Node) -> LineEdit:
	for line_node: Node in node.find_children("*", "LineEdit", true, false):
		var line: LineEdit = line_node as LineEdit
		if line.visible and line.editable:
			return line
	return null


func _find_quit_dialog(node: Node) -> ConfirmationDialog:
	if node is ConfirmationDialog:
		var dialog: ConfirmationDialog = node as ConfirmationDialog
		if _find_button(dialog, "Save and Quit") != null or _find_button(dialog, "Save & Quit") != null:
			return dialog
	for child: Node in node.get_children():
		var found: ConfirmationDialog = _find_quit_dialog(child)
		if found != null:
			return found
	return null


func _find_button(node: Node, text: String) -> Button:
	for child: Node in node.find_children("*", "Button", true, false):
		var button: Button = child as Button
		if button.visible and button.text == text:
			return button
	return null


func _dump_visible_dialogs(node: Node) -> void:
	if node is Window and (node as Window).visible:
		var labels: PackedStringArray = []
		for label_node: Node in node.find_children("*", "Label", true, false):
			var label: Label = label_node as Label
			if label.visible and not label.text.is_empty():
				labels.append(label.text)
		var buttons: PackedStringArray = []
		for button_node: Node in node.find_children("*", "Button", true, false):
			var button: Button = button_node as Button
			if button.visible and not button.text.is_empty():
				buttons.append(button.text)
		print("TABS_PROOF visible_window class=%s title=%s labels=%s buttons=%s" % [node.get_class(), (node as Window).title, labels, buttons])
	for child: Node in node.get_children():
		_dump_visible_dialogs(child)


func _visible_dialog_text(dialog: ConfirmationDialog) -> String:
	var visible_text: PackedStringArray = []
	for node: Node in dialog.find_children("*", "Label", true, false):
		var label: Label = node as Label
		if label.visible:
			visible_text.append(label.text)
	return "\n".join(visible_text)


func _replace_line_edit(plugin: EditorPlugin, edit: LineEdit, text: String, submit: bool = true) -> void:
	edit.grab_focus()
	await plugin.get_tree().process_frame
	_push_key(edit, KEY_A, true)
	for index: int in range(text.length()):
		var event: InputEventKey = InputEventKey.new()
		event.unicode = text.unicode_at(index)
		event.pressed = true
		event.window_id = edit.get_window().get_window_id()
		edit.get_viewport().push_input(event, true)
		event = event.duplicate()
		event.pressed = false
		edit.get_viewport().push_input(event, true)
	if submit:
		_push_key(edit, KEY_ENTER)
	await _frames(plugin, 2)


func _drag_spin(plugin: EditorPlugin, spin: Control, direction: float = 1.0) -> void:
	var rect: Rect2 = spin.get_global_rect()
	var start: Vector2 = rect.get_center()
	_push_mouse(spin, start, MOUSE_BUTTON_LEFT, true)
	await plugin.get_tree().process_frame
	_push_drag(spin, start + Vector2(4.0 * direction, 0.0), Vector2(4.0 * direction, 0.0))
	await plugin.get_tree().process_frame
	_push_drag(spin, start + Vector2(8.0 * direction, 0.0), Vector2(4.0 * direction, 0.0))
	await plugin.get_tree().process_frame
	_push_drag(spin, start + Vector2(12.0 * direction, 0.0), Vector2(4.0 * direction, 0.0))
	await plugin.get_tree().process_frame
	_push_mouse(spin, start + Vector2(12.0 * direction, 0.0), MOUSE_BUTTON_LEFT, false)
	await plugin.get_tree().process_frame


func _push_key(target: Control, keycode: Key, ctrl: bool = false, shift: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	event.window_id = target.get_window().get_window_id()
	target.get_viewport().push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	target.get_viewport().push_input(event, true)


func _queue_key(target: Control, keycode: Key) -> void:
	var press: InputEventKey = InputEventKey.new()
	press.keycode = keycode
	press.pressed = true
	press.window_id = target.get_window().get_window_id()
	target.get_viewport().call_deferred(&"push_input", press, true)
	var release: InputEventKey = press.duplicate()
	release.pressed = false
	target.get_viewport().call_deferred(&"push_input", release, true)


func _push_mouse(target: Control, position: Vector2, button: MouseButton, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = button
	event.pressed = pressed
	event.window_id = target.get_window().get_window_id()
	target.get_viewport().push_input(event, false)


func _push_drag(target: Control, position: Vector2, relative: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.window_id = target.get_window().get_window_id()
	target.get_viewport().push_input(event, false)


func _distinct_value_count(values: Array) -> int:
	var distinct: Array = []
	for value: Variant in values:
		if distinct.is_empty() or not is_equal_approx_or_equal(distinct.back(), value):
			distinct.append(value)
	return distinct.size()


func _frames(plugin: EditorPlugin, count: int) -> void:
	for i: int in range(count):
		await plugin.get_tree().process_frame


func _settle_editor(plugin: EditorPlugin) -> bool:
	var deadline: int = Time.get_ticks_msec() + 10000
	var clear_frames: int = 0
	while Time.get_ticks_msec() < deadline:
		if _has_startup_modal(plugin.get_tree().root):
			clear_frames = 0
		else:
			clear_frames += 1
		if clear_frames >= 30:
			return true
		await plugin.get_tree().process_frame
	return not _has_startup_modal(plugin.get_tree().root)


func _has_startup_modal(node: Node) -> bool:
	if node is Label:
		var label: Label = node as Label
		var text: String = label.text.to_lower()
		if label.is_visible_in_tree() and (text.contains("loading editor") or text.contains("importing") or text.contains("pre-import") or text.contains("scanning files") or text.contains("please wait")):
			return true
	for child: Node in node.get_children():
		if _has_startup_modal(child):
			return true
	return false


func _cleanup_rows(plugin: EditorPlugin, rows: Array[Dictionary]) -> void:
	for row: Dictionary in rows:
		var history: UndoRedo = row.get("history", null) as UndoRedo
		if history != null:
			history.clear_history()
			history.free()
		var state: Dictionary = row.get("state", {}) as Dictionary
		state.clear()
		var host: Node = row["host"] as Node
		if host != null:
			host.queue_free()
		row.clear()
	await _frames(plugin, 3)


func _check(item: String, ok: bool, detail: String) -> void:
	if ok:
		_pass_count += 1
		print("TABS_PROOF %s PASS %s" % [item, detail])
	else:
		_fail_count += 1
		print("TABS_PROOF %s FAIL %s" % [item, detail])


func _finish(plugin: EditorPlugin) -> void:
	print("TABS_PROOF SUMMARY pass=%d fail=%d" % [_pass_count, _fail_count])
	plugin.get_tree().quit(1 if _fail_count > 0 else 0)
