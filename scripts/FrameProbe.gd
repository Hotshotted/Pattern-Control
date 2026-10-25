extends Node
## ?perf on the web: the last _process call of every frame; it hands Main the microseconds since the first one.

var main: Node

func _process(_delta: float) -> void:
	if main == null:
		return
	var ms: float = (Time.get_ticks_usec() - main._probe_t0) / 1000.0
	if main.screen == main.SCREEN_PLAY:
		main._log_process_time(ms)
	else:
		main._log_menu_frame(ms)
