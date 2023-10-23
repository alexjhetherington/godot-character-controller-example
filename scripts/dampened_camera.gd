extends Camera3D

@export var target : Node3D
@export var damping : bool

# Called when the node enters the scene tree for the first time.
func _ready():
	damping = false
	set_process_priority(100)
	set_as_top_level(true)
	Engine.set_physics_jitter_fix(0.0)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if target == null:
		pass
	global_rotation = target.global_rotation
	var target_pos = target.global_position
	if not damping:
		global_position = target_pos
		pass

	target_pos.y = lerp(global_position.y, target_pos.y, 20 * delta)
	global_position = target_pos

func damp():
	damping = true

func donmp():
	damping = false
