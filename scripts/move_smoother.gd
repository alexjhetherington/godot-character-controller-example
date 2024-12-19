extends Node3D

var last_global_position := Vector3.ZERO
var next_global_position := Vector3.ZERO
var parent: Node3D

func _ready() -> void:
	parent = get_parent()
	last_global_position = global_position
	next_global_position = global_position


# Camera smoothing in physics process to ensure camera smoothing is
# not influenced by frame rate
func _physics_process(_delta: float) -> void:
	last_global_position = next_global_position
	
	var next_x := parent.global_position.x
	var next_z := parent.global_position.z
	var next_y := lerpf(next_global_position.y, parent.global_position.y, 0.2)
	
	next_global_position = Vector3(next_x, next_y, next_z)


# Ensure smooth camera movement is actually smooth :)
func _process(_delta: float) -> void:
	var fraction := Engine.get_physics_interpolation_fraction()
	global_position = last_global_position.lerp(next_global_position, fraction)
	
	
