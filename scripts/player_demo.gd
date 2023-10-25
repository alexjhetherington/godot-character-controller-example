extends PhysicsBody3D

@export var head : Node3D
@export var orientation : Node3D
@export var camera : Camera3D

@export var collision_shape : CollisionShape3D

@export var slope_limit : float = 45

@export var step_height = 0.2
@export var snap_to_ground_distance = 0.2

# Stop movement when the character touches at least 2 steep slopes in one
# movement and movement is under this threshold.
@export var steep_slope_jitter_reduce = 0.03

# The godot move_and_collide method has built in depenetration
@export var safe_margin = 0.001

# If a collision happens within this distance of the bottom of the collider
# it's considered the "bottom"
# This value is used to determine if slopes should actually make the player
# rise, or if they should be considered a wall, in the case where the slope
# is above the players feet
@export var bottom_height = 0.05

# How many times to move_and_collide. The algorithm early exits anyway
# The value of turning this up is to make movement in very complicated terrain more
# accurate. 4 is a decent number!
@export var max_iteration_count = 4


var gravity = 9.8
var max_speed = 8
var slow_speed = 2
var mouse_sensitivity = 0.002  # radians/pixel

var _velocity : Vector3 = Vector3()
var at_max_speed : bool = true

var grounded : bool = false
var ground_normal : Vector3
var steep_slope_normals : Array[Vector3]  = []
var total_stepped_height : float = 0

var escape_pressed : int

enum MovementType {VERTICAL, LATERAL}

func _ready():
	lock_mouse()

func lock_mouse():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func unlock_mouse():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# TODO should this have an action associated?
# TODO should it be in unhandled?
func _input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		orientation.rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, -1.2, 1.2)

# TODO should this be in unhandled input?
# Input buffering? lol lmao
func get_input() -> Vector2:
	if !Input.is_key_pressed(KEY_ESCAPE) && escape_pressed == 1:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			unlock_mouse()
		else:
			lock_mouse()
	
	if Input.is_key_pressed(KEY_ESCAPE):
		escape_pressed = 1
	elif !Input.is_key_pressed(KEY_ESCAPE):
		escape_pressed = 0
		
		
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return Vector2(0,0)
	
	if Input.is_action_just_pressed("sprint"):
		at_max_speed = !at_max_speed
	var input_dir : Vector2 = Vector2()
	if Input.is_action_pressed("move_forward"):
		input_dir += Vector2.UP
	if Input.is_action_pressed("move_backward"):
		input_dir -= Vector2.UP
	if Input.is_action_pressed("strafe_left"):
		input_dir += Vector2.LEFT
	if Input.is_action_pressed("strafe_right"):
		input_dir -= Vector2.LEFT
	input_dir = input_dir.normalized()
	# Local rotation is fine given the parent isn't rotating ever
	return input_dir.rotated(-orientation.rotation.y)

func _physics_process(delta):
	# Before Move
	var _desired_horz_velocity = get_input()
	var desired_horz_velocity := Vector3.ZERO
	desired_horz_velocity.x = _desired_horz_velocity.x
	desired_horz_velocity.z = _desired_horz_velocity.y

	if at_max_speed:
		desired_horz_velocity *= max_speed
	else:
		desired_horz_velocity *= slow_speed

	var desired_vertical_velocity := Vector3.ZERO

	if !grounded:
		desired_vertical_velocity.y = _velocity.y

	desired_vertical_velocity.y -= gravity * delta

	# Could have calculated them together
	# But separating them makes it easier to experiment with different movement algorithms
	var desired_velocity = desired_horz_velocity + desired_vertical_velocity
	move(desired_velocity, delta)


# Entry point to moving
func move(intended_velocity : Vector3, delta : float):
	var start_position := position

	var lateral_translation = horz(intended_velocity) * delta 
	var initial_lateral_translation = lateral_translation
	var vertical_translation = vert(intended_velocity) * delta
	var initial_vertical_translation = vertical_translation

	grounded = false
	steep_slope_normals = []
	total_stepped_height = 0

	# An initial grounded check is important because ground normal is used
	# to detect seams with steep slopes; which often are collided with before the ground
	if vertical_translation.y <= 0:
		var initial_grounded_collision := move_and_collide(Vector3.DOWN * safe_margin * 4, true, safe_margin)
		if initial_grounded_collision:
			if initial_grounded_collision.get_normal(0).angle_to(Vector3.UP) < deg_to_rad(slope_limit):
				grounded = true
				ground_normal = initial_grounded_collision.get_normal(0)

	# === Iterate Movement Laterally
	var lateral_iterations = 0
	while lateral_translation.length() > 0 and lateral_iterations < max_iteration_count:

		lateral_translation = move_iteration(MovementType.LATERAL, initial_lateral_translation, lateral_translation)
		lateral_iterations += 1

		# De-jitter by just ignoring lateral movement
		# (multiple steep slopes have been collided, but movement is very small)
		if steep_slope_normals.size() > 1 and horz(position - start_position).length() < steep_slope_jitter_reduce:
			position = start_position

	# === Iterate Movement Vertically
	var vertical_iterations = 0
	while vertical_translation.length() > 0 and vertical_iterations < max_iteration_count:

		vertical_translation = move_iteration(MovementType.VERTICAL, initial_vertical_translation, vertical_translation)
		vertical_iterations += 1

	# Don't include step height in actual velocity
	var actual_translation = position - start_position
	var actual_translation_no_step = actual_translation - Vector3.UP * total_stepped_height
	var actual_velocity = actual_translation_no_step / delta

	# HACK!
	# For some reason it's difficult to accumulate velocity when sliding down steep slopes
	# Here I just ignore the actual velocity in favour of:
	# "If intended travel was down, and actual travel was down, just keep the intended velocity"
	# This means the user is responsible for resetting vertical velocity when grounded
	if intended_velocity.y < 0 and actual_velocity.y < 0:
		_velocity = Vector3(actual_velocity.x, intended_velocity.y, actual_velocity.z)
	else:
		_velocity = actual_velocity

	# Snap Down
	# Happens last so it doesn't affect velocity
	# Keeps the character on slopes and on steps when travelling down
	if grounded:
		camera.damp()

		# === Iterate Movement Vertically (Snap)
		# We allow snap to slide down slopes
		# It really helps reduce jitter on steep slopes
		var before_snap_pos = position
		var ground_snap_iterations = 0
		var ground_snap_translation = Vector3.DOWN * snap_to_ground_distance
		while ground_snap_translation.length() > 0 and ground_snap_iterations < max_iteration_count:

			ground_snap_translation = move_iteration(MovementType.VERTICAL, Vector3.DOWN, ground_snap_translation)
			ground_snap_iterations += 1

		# If snap doesn't end by touching the ground - don't snap
		var after_snap_ground_test := move_and_collide(Vector3.DOWN * safe_margin * 4, true, safe_margin)
		if !(after_snap_ground_test and after_snap_ground_test.get_normal(0).angle_to(Vector3.UP) < deg_to_rad(slope_limit)):
			position = before_snap_pos
	else:
		camera.donmp()

func horz(v:Vector3):
	return Vector3(v.x,0,v.z)
func vert(v:Vector3):
	return Vector3(0,v.y,0)

# Moves are composed of multiple iterates
# In each iteration, move until collision, then calculate and return the next movement
func move_iteration(movement_type: MovementType, initial_direction: Vector3, translation: Vector3):

	var collisions : KinematicCollision3D

	# If Lateral movement, try stepping
	if movement_type == MovementType.LATERAL:
		var do_step = false
		var temp_position = position

		var walk_test_collision = move_and_collide(translation, true, safe_margin)

		var current_step_height = step_height
		var step_up_collisions := move_and_collide(Vector3.UP * step_height, false, safe_margin)
		if (step_up_collisions):
			current_step_height = step_up_collisions.get_travel().length()
		var _raised_forward_collisions := move_and_collide(translation, false, safe_margin)
		var down_collision := move_and_collide(Vector3.DOWN * current_step_height, false, safe_margin)

		# Only step if the step algorithm landed on a walkable surface
		# AND the walk *doesn't* land on a walkable surface
		# This stops stepping up ramps
		if (down_collision and
				down_collision.get_normal(0).angle_to(Vector3.UP) < deg_to_rad(slope_limit) and
				(!walk_test_collision or
				!walk_test_collision.get_normal(0).angle_to(Vector3.UP) < deg_to_rad(slope_limit))):
			do_step = true

		if do_step: # Keep track of stepepd distance to cancel it out later
			total_stepped_height += position.y - temp_position.y
			camera.damp()
		else: # Reset and move normally
			position = temp_position
			collisions = move_and_collide(translation, false, safe_margin)

	# If Vertical movement, just move; no need to step
	else:
		collisions = move_and_collide(translation, false, safe_margin)

	# Moved all remaining distance
	if !collisions:
		return Vector3.ZERO

	# If any ground collisions happen during movement, the character is grounded
	# Imporant to keep this up-to-date rather than just rely on the initial grounded state
	if collisions.get_normal(0).angle_to(Vector3.UP) < deg_to_rad(slope_limit):
		grounded = true
		ground_normal = collisions.get_normal(0)

	# Surface Angle will be used to "block" movement in some directions
	var surface_angle = collisions.get_normal(0).angle_to(Vector3.UP)

	# For Vertical, blocking angle is between 0 - slopeLimit
	# For Lateral, blocking angle is slopeLimit - 360 (grounded) or 90 (not grounded)
	#	The latter allows players to slide down ceilings while in the air
	#
	# These values shouldn't be calculated every frame; they only need to change
	# when the user defines the slope limit
	# But I'm lazy :)
	var min_block_angle : float
	var max_block_angle : float
	if movement_type == MovementType.LATERAL:
		min_block_angle = deg_to_rad(slope_limit)
		if grounded:
			max_block_angle = 2 * PI
		else:
			max_block_angle = PI / 2
	if movement_type == MovementType.VERTICAL:
		min_block_angle = 0
		max_block_angle = deg_to_rad(slope_limit)


	# This algorithm for determining where to move on a collisions uses "projection plane"
	# Whatever surface the character hits, we generate a blocking "plane" that we will slide along
	#
	# We calculate the normal of the plane we want to use, projection_normal, then
	# transform into a plane at the end
	#
	# By default, projection normal is just the normal of the surface
	# This may be unecessary after we account for all edge cases
	# I'm leaving it here to help understand the algorithm
	var projection_normal = collisions.get_normal(0)

	var cylinder := collision_shape.shape as CylinderShape3D
	var collision_point := collisions.get_position(0)

	# If collision happens on the "side" of the cylinder, treat it as a vertical
	# wall in all cases (we use the tangent of the cylinder)
	if (movement_type == MovementType.LATERAL and
		(collision_point.y > (collision_shape.global_position.y - cylinder.height / 2) + bottom_height)):
			projection_normal = collision_shape.global_position - collision_point
			projection_normal.y = 0
			projection_normal = projection_normal.normalized()

	# Otherwise, determine if the surface is a blocking surface
	elif surface_angle >= min_block_angle and surface_angle <= max_block_angle:
		if movement_type == MovementType.LATERAL:
			# "Wall off" the slope
			projection_normal = horz(collisions.get_normal(0)).normalized()

			# Or, "Wall off" the slope by figuring out the seam with the ground
			if grounded and surface_angle < PI / 2:
				if !already_touched_slope_close_match(collisions.get_normal(0)):
					steep_slope_normals.append(collisions.get_normal(0))

				var seam = collisions.get_normal(0).cross(ground_normal)
				var temp_projection_plane = Plane(Vector3.ZERO, seam, seam + Vector3.UP)
				projection_normal = temp_projection_plane.normal

		if movement_type == MovementType.VERTICAL:
			# If vertical is blocked, you're on solid ground - just stop moving
			return Vector3.ZERO

	# Otherwise force the direction to align with input direction
	# (projecting translation over the normal of a slope does not align with input direction)
	elif movement_type == MovementType.LATERAL and surface_angle < (PI / 2):
		projection_normal = relative_slope_normal(collisions.get_normal(0), translation)

	# Don't let one move call ping pong around
	var projection_plane = Plane(projection_normal)
	var continued_translation = projection_plane.project(collisions.get_remainder())
	var initial_influenced_translation = projection_plane.project(initial_direction)

	if initial_influenced_translation.dot(continued_translation) >= 0:
		return continued_translation
	else:
		return initial_influenced_translation.normalized() * continued_translation.length()


func already_touched_slope_close_match(normal : Vector3) -> bool:
	for steep_slope_normal in steep_slope_normals:
		if steep_slope_normal.distance_squared_to(normal) < 0.001:
			return true

	return false

# I wrote this a while ago in Unity
# I ported it here but I only have a vague grasp of how it works
func relative_slope_normal(slope_normal : Vector3, lateral_desired_direction : Vector3) -> Vector3:
	var slope_normal_horz = horz(slope_normal)
	var angle_to_straight = slope_normal_horz.angle_to(-lateral_desired_direction)
	var angle_to_up = slope_normal.angle_to(Vector3.UP)
	var complementary_angle_to_up = PI / 2 - angle_to_up

	if angle_to_up >= (PI / 2):
		push_error("Trying to calculate relative slope normal for a ceiling")

	# Geometry!

	# This is the component of the desired travel that points straight into the slope
	var straight_length = cos(angle_to_straight) * lateral_desired_direction.length()

	# Which helps us calculate the height on the slope at the end of the desired travel
	var height = straight_length / tan(complementary_angle_to_up)

	# Which gives us the actual desired movement
	var vector_up_slope = Vector3(lateral_desired_direction.x, height, lateral_desired_direction.z)

	# Due to the way the movement algorithm works we need to figure out the normal that defines
	# the plane that will give this result
	var rotation_axis = vector_up_slope.cross(Vector3.UP).normalized()
	var emulated_normal = vector_up_slope.rotated(rotation_axis, PI / 2)

	return emulated_normal.normalized()
