extends Node

signal state_changed(new_step: Step)
signal data_ready_for_ground(sample_color: Color, is_actual_success: bool)
signal task_completed(next_mission_effects: Dictionary)

enum Step {
	GO_TO_STORAGE,      # 0: Pick up fungal culture packs in Storage Room
	GO_TO_HEATER,       # 1: Carry packs to the heating machine
	HEATING,            # 2: Machine running in background while player walks
	COLLECT_HEATED,     # 3: Heating done, retrieve pack from machine
	GO_TO_CENTRIFUGE,   # 4: Take heated culture to Centrifuge / Lab
	AWAITING_GROUND,    # 5: Telemetry sent, waiting for Ground Base verdict
	COMPLETED           # 6: Research task finished
}

var current_step: Step = Step.GO_TO_STORAGE
var heating_timer: float = 0.0
const HEATING_DURATION: float = 15.0

var sample_color: Color = Color.WHITE
var is_actual_success: bool = false

func _process(delta: float) -> void:
	if current_step == Step.HEATING:
		heating_timer -= delta
		if heating_timer <= 0.0:
			heating_timer = 0.0
			set_step(Step.COLLECT_HEATED)

func set_step(new_step: Step) -> void:
	current_step = new_step
	state_changed.emit(current_step)

func start_heating() -> void:
	heating_timer = HEATING_DURATION
	set_step(Step.HEATING)

func generate_centrifuge_result() -> void:
	# 70% chance of successful beta-carotene synthesis (bright orange)
	is_actual_success = randf() <= 0.70
	if is_actual_success:
		sample_color = Color(1.0, 0.55, 0.0) # Vibrant Orange (Success)
	else:
		sample_color = Color(0.35, 0.55, 0.25) # Murky Green (Contaminated)

func send_to_ground() -> void:
	set_step(Step.AWAITING_GROUND)
	data_ready_for_ground.emit(sample_color, is_actual_success)
