class_name DevMenu
extends Node
## The hidden dev menu: four tabs (Career, Scenario, Time, Save) over the paused game, to reach any part of the game in minutes. It exists only when
## Dev.available(): ?dev in the page address (a DEV button top-right) or five quick taps on the build stamp (any build). Players never see a trace of it.
## Built the first time it opens (a plain Godot panel like the tuning panel's; nothing in the normal screens knows about it), and it is never part of
## the player states of tools/ui_overlap_check.gd (that check opens it on purpose in its own states).

signal closed

const TABS := ["Career", "Scenario", "Time", "Save"]
const CHECKPOINTS := 3

static var _button_rect := Rect2()

## True if a touch at `pos` is on the DEV button (the game ignores it).
static func button_hit(pos: Vector2) -> bool:
	return _button_rect.has_point(pos)

var main: Node
var is_open := false
var tab := 0
var out_text := ""                       # the status line (the tests read it)
var scenario_ap := 0
var sc_student := false
var sc_wind := 0
var sc_weather := 0
var sc_challenge := 0                    # 0 none, 1 Bad Pilot Day, 2 No engines
var sc_event := 0                        # 0 the real week's, then Rhythm.EVENTS
var sc_heavy := false
var sc_hangar := false
var buttons := {}                        # id -> Button (the tests press these)

var _layer: CanvasLayer
var _button_layer: CanvasLayer
var _panel: Control
var _dev_button: Button
var _scroll: KScroll
var _pages: Array[VBoxContainer] = []
var _tab_buttons: Array[Button] = []
var _out: Label
var _level_labels: Array[Label] = []
var _code_edit: TextEdit
var _scenario_labels := {}
var _speed_buttons := {}
var _checkpoint_labels: Array[Label] = []
var _built := false

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## The DEV button (with ?dev, or once five taps have opened the menu). Cheap: one button on its own layer.
func ensure_button() -> void:
	if _button_layer != null:
		return
	_button_layer = CanvasLayer.new()
	_button_layer.layer = 21
	add_child(_button_layer)
	_dev_button = _make_button("DEV", 30)
	_dev_button.name = "DevButton"
	_dev_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_dev_button.offset_left = -380.0
	_dev_button.offset_right = -210.0
	_dev_button.offset_top = 20.0
	_dev_button.offset_bottom = 96.0
	_dev_button.focus_mode = Control.FOCUS_NONE
	_dev_button.pressed.connect(toggle)
	_button_layer.add_child(_dev_button)

func set_available(on: bool) -> void:
	if on:
		ensure_button()
	if _dev_button != null:
		_dev_button.visible = on and not _hidden_for_boot

var _hidden_for_boot := false

func _process(_delta: float) -> void:
	_button_rect = _dev_button.get_global_rect() if _dev_button != null and _dev_button.visible else Rect2()
	if Dev.speed != 1 and _dev_button != null:
		_dev_button.text = "DEV x%d" % Dev.speed
	elif _dev_button != null and not is_open:
		_dev_button.text = "DEV"

func _input(event: InputEvent) -> void:
	if is_open and (event is InputEventScreenTouch or event is InputEventScreenDrag):
		KScroll.feed(event)            # (the game is paused behind the menu, so its own input is off: the menu feeds its list itself)

func toggle() -> void:
	if is_open:
		close()
	else:
		open()

func open() -> void:
	ensure_button()
	_build()
	is_open = true
	_layer.layer = 20
	_panel.visible = true
	_dev_button.text = "CLOSE"
	_refresh()
	get_tree().paused = true

func close() -> void:
	if not is_open:
		return
	is_open = false
	_panel.visible = false
	_layer.layer = 0
	_dev_button.text = "DEV"
	get_tree().paused = false
	closed.emit()

func set_tab(i: int) -> void:
	tab = clampi(i, 0, TABS.size() - 1)
	for k in _pages.size():
		_pages[k].visible = k == tab
		_tab_buttons[k].button_pressed = k == tab
	_scroll.jump_to(0.0)
	_scroll.queue_sort()

func say(text: String) -> void:
	out_text = text
	if _out != null:
		_out.text = text

# ---------- building ----------

func _build() -> void:
	if _built:
		return
	_built = true
	_layer = CanvasLayer.new()
	_layer.layer = 0
	add_child(_layer)
	_panel = Control.new()
	_panel.name = "DevPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.visible = false
	_layer.add_child(_panel)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.11, 0.99)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	margin.add_theme_constant_override("margin_top", 24)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var title := _make_label("DEV MENU", 44, HORIZONTAL_ALIGNMENT_LEFT)
	title.custom_minimum_size = Vector2(0, 80)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column.add_child(title)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	column.add_child(tabs)
	for i in TABS.size():
		var b := _make_button(TABS[i], 30)
		b.toggle_mode = true
		b.pressed.connect(set_tab.bind(i))
		tabs.add_child(b)
		_tab_buttons.append(b)
	_scroll = KScroll.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	var host := VBoxContainer.new()
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(host)
	for i in TABS.size():
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 12)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.visible = false
		host.add_child(page)
		_pages.append(page)
	_build_career(_pages[0])
	_build_scenario(_pages[1])
	_build_time(_pages[2])
	_build_save(_pages[3])
	_out = _make_label("", 26, HORIZONTAL_ALIGNMENT_LEFT)
	_out.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_out.custom_minimum_size = Vector2(0, 120)
	_out.add_theme_color_override("font_color", Color(0.55, 1.0, 0.7))
	column.add_child(_out)
	set_tab(0)

func _section(page: Control, text: String) -> void:
	var l := _make_label(text, 30, HORIZONTAL_ALIGNMENT_LEFT)
	l.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	l.custom_minimum_size = Vector2(0, 52)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	page.add_child(l)

func _row(page: Control) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	page.add_child(hb)
	return hb

func _btn(parent: Control, id: String, text: String, cb: Callable, size: int = 28) -> Button:
	var b := _make_button(text, size)
	b.name = id
	b.pressed.connect(cb)
	parent.add_child(b)
	buttons[id] = b
	return b

func _note(page: Control, text: String) -> void:
	var l := _make_label(text, 24, HORIZONTAL_ALIGNMENT_LEFT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(0.7, 0.74, 0.82))
	page.add_child(l)

func _build_career(page: VBoxContainer) -> void:
	_section(page, "Jump to a career point (matches the average bot)")
	var hb: HBoxContainer = null
	for i in Dev.PRESETS.size():
		if i % 2 == 0:
			hb = _row(page)
		var p: Dictionary = Dev.PRESETS[i]
		_btn(hb, "preset_" + str(p["id"]), str(p["label"]), _on_preset.bind(str(p["id"])))
	if Dev.PRESETS.size() % 2 == 1:
		var pad := Control.new()
		pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(pad)
	_note(page, "Coins, airport levels, stars, mastery, tower and improvement purchases and unlocks are set to the average bot's at that point (docs/content_audit.md 10, 11). Tips count as seen, except in Fresh start.")
	_section(page, "Manual")
	var r1 := _row(page)
	_btn(r1, "coins_1k", "+1,000 coins", _on_coins.bind(1000))
	_btn(r1, "coins_10k", "+10,000 coins", _on_coins.bind(10000))
	var r2 := _row(page)
	_btn(r2, "unlock_all", "Unlock all airports", _on_unlock_all)
	_section(page, "Airport levels")
	for a in Save.AIRPORT_SLOTS:
		var rr := _row(page)
		var l := _make_label("", 28, HORIZONTAL_ALIGNMENT_LEFT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rr.add_child(l)
		_level_labels.append(l)
		_btn(rr, "lv_down_%d" % a, "-", _on_level.bind(a, -1)).custom_minimum_size = Vector2(90, _tap())
		_btn(rr, "lv_up_%d" % a, "+", _on_level.bind(a, 1)).custom_minimum_size = Vector2(90, _tap())
		_btn(rr, "lv_max_%d" % a, "20", _on_level.bind(a, 99)).custom_minimum_size = Vector2(110, _tap())

func _cycle_row(page: Control, id: String, labels: Array, cb: Callable) -> void:
	var b := _btn(page, id, "", cb)
	_scenario_labels[id] = [b, labels]

func _build_scenario(page: VBoxContainer) -> void:
	_section(page, "Start a shift with a forced condition")
	var r0 := _row(page)
	_btn(r0, "ap_prev", "<", _on_ap.bind(-1)).custom_minimum_size = Vector2(110, _tap())
	var al := _make_label("", 32, HORIZONTAL_ALIGNMENT_CENTER)
	al.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	al.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	r0.add_child(al)
	_scenario_labels["ap"] = al
	_btn(r0, "ap_next", ">", _on_ap.bind(1)).custom_minimum_size = Vector2(110, _tap())
	_cycle_row(page, "sc_student", ["Student arrival in the first 20 s: off", "Student arrival in the first 20 s: ON"], _on_sc.bind("student"))
	_cycle_row(page, "sc_wind", Dev.WINDS, _on_sc.bind("wind"))
	_cycle_row(page, "sc_weather", Dev.WEATHER, _on_sc.bind("weather"))
	_cycle_row(page, "sc_challenge", ["Challenge: none", "Challenge: Bad Pilot Day", "Challenge: No engines"], _on_sc.bind("challenge"))
	_cycle_row(page, "sc_event", ["Weekly event: this week's"], _on_sc.bind("event"))
	_cycle_row(page, "sc_heavy", ["Heavy traffic: off", "Heavy traffic: ON (2.5x arrivals)"], _on_sc.bind("heavy"))
	_cycle_row(page, "sc_hangar", ["Near-full hangar: off", "Near-full hangar: ON (2 from full)"], _on_sc.bind("hangar"))
	var go := _btn(page, "sc_start", "START SHIFT", _on_start, 34)
	go.custom_minimum_size = Vector2(0, _tap() + 20.0)
	go.add_theme_color_override("font_color", Color(0.5, 1.0, 0.65))
	_note(page, "Conditions combine. A forced wind holds steady for the shift (a student needs a legal end, so none is sent into the forced crosswind: the game never sends one). The gusty crosswind closes a runway, so it needs an airport with two or more.")

func _build_time(page: VBoxContainer) -> void:
	_section(page, "Game speed (in a shift)")
	var rs := _row(page)
	for s in [1, 2, 4]:
		_speed_buttons[s] = _btn(rs, "speed_%d" % s, "x%d" % s, _on_speed.bind(s), 32)
		(_speed_buttons[s] as Button).toggle_mode = true
	_section(page, "Skip the shift to the results")
	var rk := _row(page)
	for i in 2:
		var sd: Array = Dev.SCORES[i]
		_btn(rk, "skip_" + str(sd[0]), str(sd[1]), _on_skip.bind(str(sd[0])))
	var rk2 := _row(page)
	for i in range(2, 4):
		var sd2: Array = Dev.SCORES[i]
		_btn(rk2, "skip_" + str(sd2[0]), str(sd2[1]), _on_skip.bind(str(sd2[0])))
	_note(page, "In a shift it ends at once with that score; from a menu it starts a shift at the Scenario tab's airport first.")
	_section(page, "Pretend the game was closed (the welcome-back screen)")
	var ro := _row(page)
	for h in [1, 8, 24]:
		_btn(ro, "offline_%d" % h, "%d h away" % h, _on_offline.bind(h))
	_section(page, "Days")
	var rd := _row(page)
	_btn(rd, "next_day", "Advance one day", _on_next_day)
	_btn(rd, "today", "Back to today", _on_today)
	var rd2 := _row(page)
	_btn(rd2, "reset_daily", "Reset daily goals", _on_reset_daily)
	_note(page, "A new day gives new daily goals, a streak step when one is finished, and the weekly event of that week (every 7 days).")

func _build_save(page: VBoxContainer) -> void:
	_section(page, "Save code")
	var r1 := _row(page)
	_btn(r1, "export", "Export (copy)", _on_export)
	_btn(r1, "import", "Import the code below", _on_import)
	var r2 := _row(page)
	_btn(r2, "paste", "Paste from clipboard", _on_paste)
	_btn(r2, "clear_code", "Clear", func(): _code_edit.text = "")
	_code_edit = TextEdit.new()
	_code_edit.custom_minimum_size = Vector2(0, 260)
	_code_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_code_edit.add_theme_font_size_override("font_size", 22)
	_code_edit.placeholder_text = "PW1.... (a save code)"
	page.add_child(_code_edit)
	_section(page, "Checkpoints (kept on this device)")
	for i in CHECKPOINTS:
		var rr := _row(page)
		var l := _make_label("", 26, HORIZONTAL_ALIGNMENT_LEFT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rr.add_child(l)
		_checkpoint_labels.append(l)
		_btn(rr, "cp_save_%d" % i, "Save", _on_cp_save.bind(i)).custom_minimum_size = Vector2(150, _tap())
		_btn(rr, "cp_load_%d" % i, "Load", _on_cp_load.bind(i)).custom_minimum_size = Vector2(150, _tap())
	_note(page, "A tester sends you their code; you import it and play from their exact state. Importing replaces the save on this device.")

# ---------- state shown ----------

func _refresh() -> void:
	for a in _level_labels.size():
		var open := Save.airport_open(a)
		_level_labels[a].text = "%s   Lv %d%s" % [Airports.airport_name(a), Save.ap_level(a), "" if open else "  (locked)"]
	(_scenario_labels["ap"] as Label).text = Airports.airport_name(scenario_ap)
	_set_cycle("sc_student", 1 if sc_student else 0)
	_set_cycle("sc_wind", sc_wind)
	_set_cycle("sc_weather", sc_weather)
	_set_cycle("sc_challenge", sc_challenge)
	_set_cycle("sc_event", sc_event)
	_set_cycle("sc_heavy", 1 if sc_heavy else 0)
	_set_cycle("sc_hangar", 1 if sc_hangar else 0)
	for s in _speed_buttons:
		(_speed_buttons[s] as Button).button_pressed = Dev.speed == s
	for i in _checkpoint_labels.size():
		_checkpoint_labels[i].text = "Checkpoint %d: %s" % [i + 1, _checkpoint_info(i)]

func _event_labels() -> Array:
	var out := ["Weekly event: this week's"]
	for e in Rhythm.EVENTS:
		out.append("Weekly event: " + str(e["name"]))
	return out

func _set_cycle(id: String, i: int) -> void:
	var pair: Array = _scenario_labels[id]
	var labels: Array = _event_labels() if id == "sc_event" else pair[1]
	var item = labels[clampi(i, 0, labels.size() - 1)]
	(pair[0] as Button).text = str(item[1]) if item is Array else str(item)

# ---------- actions ----------

func _after_change(text: String) -> void:
	main.dev_refresh()
	_refresh()
	say(text)

func _on_preset(id: String) -> void:
	if id == "fresh":
		main.debug_fresh_tutorial_quiet()
		_refresh()
		say("Fresh start: a new save, Day 1 tutorial on.")
		return
	_after_change(Dev.apply_preset(id))

func _on_coins(n: int) -> void:
	Dev.add_coins(n)
	main.dev_refresh_coins()
	say("Coins: %d" % Save.coins)

func _on_unlock_all() -> void:
	Dev.unlock_all_airports()
	_after_change("All airports unlocked.")

func _on_level(a: int, d: int) -> void:
	var to := 20 if d >= 99 else Save.ap_level(a) + d
	Dev.set_level(a, to)
	_after_change("%s is level %d." % [Airports.airport_name(a), Save.ap_level(a)])

func _on_ap(d: int) -> void:
	scenario_ap = posmod(scenario_ap + d, Airports.COUNT)
	_refresh()

func _on_sc(which: String) -> void:
	match which:
		"student":
			sc_student = not sc_student
		"wind":
			sc_wind = (sc_wind + 1) % Dev.WINDS.size()
		"weather":
			sc_weather = (sc_weather + 1) % Dev.WEATHER.size()
		"challenge":
			sc_challenge = (sc_challenge + 1) % 3
		"event":
			sc_event = (sc_event + 1) % (Rhythm.EVENTS.size() + 1)
		"heavy":
			sc_heavy = not sc_heavy
		"hangar":
			sc_hangar = not sc_hangar
	_refresh()

## What the Scenario tab is set to, as the dictionary Main.dev_start reads.
func scenario() -> Dictionary:
	return {
		"airport": scenario_ap,
		"student20": sc_student,
		"wind": str(Dev.WINDS[sc_wind][0]),
		"weather": str(Dev.WEATHER[sc_weather][0]),
		"bad": sc_challenge == 1,
		"no_engines": sc_challenge == 2,
		"event": "" if sc_event == 0 else str(Rhythm.EVENTS[sc_event - 1]["id"]),
		"heavy": sc_heavy,
		"hangar": sc_hangar,
	}

func _on_start() -> void:
	var sc := scenario()
	close()
	say(main.dev_start(sc))

func _on_speed(s: int) -> void:
	Dev.speed = s
	_refresh()
	say("Game speed x%d." % s)

func _on_skip(score_id: String) -> void:
	var sc := scenario()
	close()
	say(main.dev_skip_shift(score_id, sc))

func _on_offline(h: int) -> void:
	Dev.fake_offline(float(h))
	close()
	main.dev_offline_now()

func _on_next_day() -> void:
	var d := Dev.advance_day()
	main.dev_new_day()
	_refresh()
	say("Day %d (%s). Daily goals, streak and the weekly event follow it." % [d, Rhythm.event_for_week(Rhythm.week_of(d))["name"]])

func _on_today() -> void:
	Save.day_override = -1
	Save.sync_event()
	main.dev_new_day()
	say("Back to today's date.")

func _on_reset_daily() -> void:
	main.debug_reset_daily()
	main.dev_new_day()
	say("Daily goals, streak and Bad Pilot Day reset.")

func _on_export() -> void:
	var code := Save.export_code()
	_code_edit.text = code
	DisplayServer.clipboard_set(code)
	say("Save code copied (%d characters). Paste it in a message." % code.length())

func _on_paste() -> void:
	_code_edit.text = DisplayServer.clipboard_get()
	say("Pasted %d characters." % _code_edit.text.length())

func _on_import() -> void:
	var err := Save.import_code(_code_edit.text)
	if err != "":
		say(err)
		return
	main.dev_refresh()
	_refresh()
	say("Imported: %d coins, levels %s." % [Save.coins, Dev.levels_text()])

func _checkpoint_path(i: int) -> String:
	return "user://dev_checkpoint_%d.txt" % (i + 1)

func _checkpoint_info(i: int) -> String:
	var p := _checkpoint_path(i)
	if not FileAccess.file_exists(p):
		return "empty"
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return "empty"
	var lines := f.get_as_text().split("\n", false, 1)
	return str(lines[0]) if lines.size() > 0 else "empty"

func _on_cp_save(i: int) -> void:
	var f := FileAccess.open(_checkpoint_path(i), FileAccess.WRITE)
	if f == null:
		say("Could not write the checkpoint.")
		return
	f.store_string("%s, %d coins, levels %s\n%s" % [Time.get_datetime_string_from_system(false, true), Save.coins, Dev.levels_text(), Save.export_code()])
	f.close()
	_refresh()
	say("Checkpoint %d saved." % (i + 1))

func _on_cp_load(i: int) -> void:
	var p := _checkpoint_path(i)
	if not FileAccess.file_exists(p):
		say("Checkpoint %d is empty." % (i + 1))
		return
	var f := FileAccess.open(p, FileAccess.READ)
	var parts := f.get_as_text().split("\n", false, 1)
	var err := Save.import_code(str(parts[1])) if parts.size() > 1 else "Empty."
	if err != "":
		say(err)
		return
	main.dev_refresh()
	_refresh()
	say("Checkpoint %d loaded." % (i + 1))

# ---------- widgets ----------

## A button is at least a finger tall (44 points), whatever the phone.
func _tap() -> float:
	return maxf(76.0, Style.tap_px())

func _make_label(text: String, size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _make_button(text: String, size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(150, _tap())
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _box(Color(0.17, 0.22, 0.32)))
	b.add_theme_stylebox_override("hover", _box(Color(0.21, 0.27, 0.39)))
	b.add_theme_stylebox_override("pressed", _box(Color(0.25, 0.55, 0.4)))
	b.add_theme_stylebox_override("hover_pressed", _box(Color(0.25, 0.55, 0.4)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b

func _box(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb
