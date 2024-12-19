extends Node3D
class_name ViewBob

@export
var player : Player

var vertical_time : float = 0
var verticle_cycle : int = -1

var horizontal_time : float = 0

signal finished_cycle

# Depends on speed the player is moving?
func _process(delta):
	var move_speed = horz(player._velocity).length()
	var grounded = player.grounded

	# Inline variables so they can be adjusted while the game is running
	var vertical_magnitude : float = 0.035
	var vertical_speed : float = 8 + (move_speed)

	var horizontal_magnitude: float = 0.03
	var horizontal_speed : float = vertical_speed / 2

	if grounded and move_speed > 0.01:
		vertical_time += delta * vertical_speed
		horizontal_time += delta * horizontal_speed

		# Do head bob
		position.y = sin(vertical_time) * vertical_magnitude
		position.x = sin(horizontal_time) * horizontal_magnitude

		# Calculate cycle
		var next_vertical_cycle = cycle(vertical_time)
		if next_vertical_cycle > verticle_cycle:
			verticle_cycle = next_vertical_cycle
			finished_cycle.emit()


func cycle(time : float) -> int:
	var with_offset = time - ((3 * PI) / 2)
	with_offset = with_offset - PI / 5 # a little bit of spice
	return floor(with_offset / (2 * PI))
	
func horz(v:Vector3):
	return Vector3(v.x,0,v.z)
