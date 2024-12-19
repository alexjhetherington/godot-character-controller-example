extends PhysicsBody3D
class_name Player

## This physics body does not rotate
## Nominate a child object that will be rotated (side to side)
@export var orientation : Node3D

## Nominate a camera that will be rotated (up and down)
@export var camera : Camera3D

## A reference to the collision shape this physics body is using
## (It's just a bit easier rather than aquiring the reference via code)
@export var collision_shape : CollisionShape3D

## The character will be blocked from moving up slopes steeper than this angle
## The character will be not be flagged as 'grounded' when stood on slopes steeper than this angle
@export var slope_limit : float = 45

## The character will automatically adjust height to step over obstacles this high
@export var enable_step : bool = true

## Represents the players 'feet'
## When stepping is enabled, this is the height the player can step over
## It also controls collision logic; any collision above the 'feet' will be considered a wall
@export var bottom_height : float = 0.2

## When grounded, the character will snap down this distance
## This keeps the character on steps, slopes, and helps keep behaviour consistent
@export var snap_to_ground_distance :float = 0.2


@export_group("Advanced")
## Stop movement under this distance, but only if the movement touches at least 2 steep slopes
## The slope movement code in this class does not handle all edge cases; this is a hack to eliminate
## jitter movement
@export var steep_slope_jitter_reduce : float = 0.05

## The godot move_and_collide method has built in depenetration
## Higher values can eliminate jittery movement against obscure geometry, but in my experience
## this comes at the cost of making movement across flush collision planes a bit unreliable
@export var depenetration_margin : float = 0.003

## The distance under the player to check for ground at the start of movement
## This is in addition to the usual method of setting grounded state by collision
## In theory any value above the depentration margin should successfully detect ground, but
## if you notice errors on stairs etc, try increasing this
@export var ground_cast_distance : float = 0.01

## The movement code in this class tries to adjust translation to confirm to the collision plane
## This means the same plane should never be hit more than once within 1 frame
## This sometimes happens anyway, typically when there is a small safe margin
## If it happens, the movement will be blocked and the rest of the movement iterations will be
## consumed
## This is a little hack to slightly adjust the translation to break out of this infinite loop
@export var same_surface_adjust_distance : float = 0.001

## How many times to move_and_collide. The algorithm early exits for lateral movement but does
## not early exit for vertical movement
## The value of turning this up is to make movement in very complicated terrain more
## accurate. 4 is a decent number for low poly terrain!
@export var max_iteration_count : int = 4

## Stepping will go forward this distance after all other lateral iterations
## It means if the player is looking mostly into a wall they can still step up
@export var step_forward_final_iteration : float = 0.002

## After stepping give a final small nudge up (this is essentially manual depenetration)
@export var step_up_adjust : float = 0.015

## After stepping give a final small nudge forward  (this is essentially manual depenetration)
@export var step_forward_adjust : float = 0.03

## If the stepped amount is lower than this, don't step and just use normal movement
@export var step_minimum_height_times_10 : float = 0.01

var gravity : float = 9.8
var speed : float = 2
var mouse_sensitivity : float = 0.002  # radians/pixel

var _velocity : Vector3 = Vector3()

var grounded : bool = false
var ground_normal : Vector3
var steep_slope_normals : Array[Vector3]  = []
var total_stepped_height : float = 0
var _snapped_last_call : bool = false

var vertical_collisions : Array[KinematicCollision3D]
var lateral_collisions : Array[KinematicCollision3D]
var snap_collisions : Array[KinematicCollision3D]

enum MovementType {VERTICAL, LATERAL}

signal teleported

func _ready():
	lock_mouse()

func lock_mouse():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func unlock_mouse():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func release_inputs():
	Input.action_release("move_forward")
	Input.action_release("move_backward")
	Input.action_release("strafe_left")
	Input.action_release("strafe_right")

# TODO should this have an action associated?
# TODO should it be in unhandled?
func _input(_event):

	if _event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var event := _event as InputEventMouseMotion
		orientation.rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, -1.4, 1.4)

# TODO should this be in unhandled input?
# Input buffering? lol lmao
func get_input() -> Vector2:
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

func _physics_process(delta : float):

	# Before Move
	var _desired_horz_velocity := get_input()
	var desired_horz_velocity := Vector3.ZERO
	desired_horz_velocity.x = _desired_horz_velocity.x
	desired_horz_velocity.z = _desired_horz_velocity.y

	desired_horz_velocity *= speed

	var desired_vertical_velocity := Vector3.ZERO

	if !grounded:
		desired_vertical_velocity.y = _velocity.y

	desired_vertical_velocity.y -= gravity * delta

	# Could have calculated them together
	# But separating them makes it easier to experiment with different movement algorithms
	var desired_velocity := desired_horz_velocity + desired_vertical_velocity
	move(desired_velocity, delta)


# Entry point to moving
func move(intended_velocity : Vector3, delta : float):
	var start_position := position

	var initial_lateral_translation := horz(intended_velocity * delta)
	var initial_vertical_translation := vert(intended_velocity * delta)

	initialise_grounded(intended_velocity)
	
	var walk_lateral_translation := initial_lateral_translation
	var walk_lateral_iterations : int = 0
	while walk_lateral_translation.length() > 0 and walk_lateral_iterations < max_iteration_count:

		walk_lateral_translation = move_iteration(MovementType.LATERAL, lateral_collisions, initial_lateral_translation, walk_lateral_translation)
		walk_lateral_iterations += 1
		
		# De-jitter by just ignoring lateral movement
		# (multiple steep slopes have been collided, but movement is very small)
		if steep_slope_normals.size() > 1 and horz(position - start_position).length() < steep_slope_jitter_reduce:
			position = start_position

	var try_step = false
	if enable_step:
		for lateral_collision in lateral_collisions:
			if !collision_normal_walkable(lateral_collision.get_normal()):
				try_step = true
				break

	if try_step:
		var walk_position := position
		var walk_grounded := grounded
		var walk_steep_slope_normals := steep_slope_normals
		var walk_lateral_collisions := lateral_collisions
		
		position = start_position
		
		initialise_grounded(intended_velocity)
	
		var current_step_height := bottom_height
		var step_up_collisions := move_and_collide(Vector3.UP * bottom_height, false, 0)
		if (step_up_collisions):
			current_step_height = step_up_collisions.get_travel().length()

		var step_lateral_translation := initial_lateral_translation
		var step_lateral_iterations : int = 0
		var step_lateral_final_translation_direction : Vector3
		while step_lateral_translation.length() > 0 and step_lateral_iterations < max_iteration_count:

			step_lateral_final_translation_direction = step_lateral_translation.normalized()
			step_lateral_translation = move_iteration(
				MovementType.LATERAL, 
				lateral_collisions, 
				initial_lateral_translation, 
				step_lateral_translation
			)
			step_lateral_iterations += 1
		
		# Extra iteration
		move_iteration(
				MovementType.LATERAL, 
				lateral_collisions, 
				initial_lateral_translation, 
				step_lateral_final_translation_direction * step_forward_final_iteration
			)
		
		var down_collision := move_and_collide(Vector3.DOWN * current_step_height, false, 0)
		if (down_collision and collision_normal_walkable(down_collision_normal(down_collision)) and 
				position.y > start_position.y + (step_minimum_height_times_10 / 10)):
			total_stepped_height = position.y - start_position.y
			
			move_and_collide(Vector3.UP * step_up_adjust, false, 0)
			move_and_collide(step_lateral_final_translation_direction * step_forward_adjust, false, depenetration_margin)
		else:
			position = walk_position
			grounded = walk_grounded
			steep_slope_normals = walk_steep_slope_normals
			lateral_collisions = walk_lateral_collisions

	# === Iterate Movement Vertically
	var vertical_iterations : int = 0
	var vertical_translation := initial_vertical_translation
	while vertical_translation.length() > 0 and vertical_iterations < max_iteration_count:

		vertical_translation = move_iteration(MovementType.VERTICAL, vertical_collisions, initial_vertical_translation, vertical_translation)
		vertical_iterations += 1

	# Don't include step height in actual velocity
	var actual_translation := position - start_position
	var actual_translation_no_step := actual_translation - Vector3.UP * total_stepped_height
	var actual_velocity := actual_translation_no_step / delta

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

		# === Iterate Movement Vertically (Snap)
		# We allow snap to slide down slopes
		# It really helps reduce jitter on steep slopes
		var before_snap_pos := position
		var ground_snap_iterations : int = 0
		var ground_snap_translation := Vector3.DOWN * snap_to_ground_distance
		
		
		while ground_snap_translation.length() > 0 and ground_snap_iterations < max_iteration_count:

			ground_snap_translation = move_iteration(MovementType.VERTICAL, snap_collisions, Vector3.DOWN, ground_snap_translation)
			ground_snap_iterations += 1

		# Decide whether to keep the snap or not
		if snap_collisions.is_empty():
			var after_snap_ground_test := move_and_collide(Vector3.DOWN * ground_cast_distance, true, depenetration_margin)
			if after_snap_ground_test and collision_normal_walkable(down_collision_normal(after_snap_ground_test)):
				# There was no snap collisions, but there is ground underneath
				# This can be due to an edge case where the snap movement falls through the ground
				# Why does this check not fall through the ground? I don't know
				# In any case, manually set the y
				position.y = after_snap_ground_test.get_position(0).y
				_snapped_last_call = true
			else:
				# No snap collisions and no floor, reset
				position = before_snap_pos
				_snapped_last_call = false
		elif !(collision_normal_walkable(down_collision_normal(snap_collisions[snap_collisions.size() - 1]))):
			# Collided with steep ground, reset
			position = before_snap_pos
			_snapped_last_call = false
		else:
			_snapped_last_call = true


# Moves are composed of multiple iterates
# In each iteration, move until collision, then calculate and return the next movement
func move_iteration(
		movement_type: MovementType, 
		collision_array : Array, 
		initial_direction: Vector3, 
		translation: Vector3) -> Vector3:
		
	var collisions := move_and_collide(translation, false, depenetration_margin)

	# Moved all remaining distance
	if !collisions:
		return Vector3.ZERO
		
	var collision_normal : Vector3
	if movement_type == MovementType.VERTICAL and translation.y <= 0: 
		collision_normal = down_collision_normal(collisions)
	else:
		collision_normal = collisions.get_normal(0)

	collision_array.append(collisions)

	# If any ground collisions happen during movement, the character is grounded
	# Imporant to keep this up-to-date rather than just rely on the initial grounded state
	if collision_normal_walkable(collision_normal):
		grounded = true
		ground_normal = collision_normal

	# Surface Angle will be used to "block" movement in some directions
	var surface_angle := collision_normal.angle_to(Vector3.UP)

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
	var projection_normal := collision_normal

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
			projection_normal = horz(collision_normal).normalized()

			# Or, "Wall off" the slope by figuring out the seam with the ground
			if grounded and surface_angle < PI / 2:
				if !already_touched_slope_close_match(collision_normal):
					steep_slope_normals.append(collision_normal)

				var seam := collision_normal.cross(ground_normal)
				var temp_projection_plane := Plane(Vector3.ZERO, seam, seam + Vector3.UP)
				projection_normal = temp_projection_plane.normal

		if movement_type == MovementType.VERTICAL:
			# If vertical is blocked, you're on solid ground - just stop moving
			return Vector3.ZERO

	# Otherwise force the direction to align with input direction
	# (projecting translation over the normal of a slope does not align with input direction)
	elif movement_type == MovementType.LATERAL and surface_angle < (PI / 2):
		projection_normal = relative_slope_normal(collision_normal, translation)

	# Don't let one move call ping pong around
	var projection_plane := Plane(projection_normal)
	var continued_translation := projection_plane.project(collisions.get_remainder())
	var initial_influenced_translation := projection_plane.project(initial_direction)

	var next_translation : Vector3
	if initial_influenced_translation.dot(continued_translation) >= 0:
		next_translation = continued_translation
	else:
		next_translation = initial_influenced_translation.normalized() * continued_translation.length()

	# See same_surface_adjust_distance
	if next_translation.normalized() == translation.normalized():
		next_translation += collision_normal * same_surface_adjust_distance

	return next_translation


func already_touched_slope_close_match(normal : Vector3) -> bool:
	for steep_slope_normal in steep_slope_normals:
		if steep_slope_normal.distance_squared_to(normal) < 0.001:
			return true

	return false
	
# HACK Bottom collision on cylinders reports strange normals, so just raycast the collision point
# to find the correct normal (only when we are travelling down and expect the collision to be on the bottom)	
func down_collision_normal(collision: KinematicCollision3D) -> Vector3:
	var space_state = get_world_3d().direct_space_state
	var ray_params := PhysicsRayQueryParameters3D.create(collision.get_position() + Vector3.UP * 0.1, collision.get_position() - Vector3.UP * 0.1, 1)
	var result = space_state.intersect_ray(ray_params)
	
	if result and collision.get_position().y < position.y + bottom_height:
		return result["normal"]
	else:
		return collision.get_normal() # Should never be required... but sometimes it is (maybe if you accidentally exclude a collider)
		
		
func collision_normal_walkable(normal: Vector3) -> bool:
	return normal.angle_to(Vector3.UP) < deg_to_rad(slope_limit)

	
func initialise_grounded(translation: Vector3) -> void:
	steep_slope_normals = []
	total_stepped_height = 0

	vertical_collisions.clear()
	lateral_collisions.clear()
	snap_collisions.clear()
	
	# HACK Use last frames grounded state and normal
	# sometimes the algorithm snaps the player in a position that is not detected as grounded
	# for reasons I simple cannot fathom (collision physics)
	if _snapped_last_call:	
		return
	
	grounded = false

	# An initial grounded check is important because ground normal is used
	# to detect seams with steep slopes; which often are collided with before the ground
	if translation.y <= 0:
		var initial_grounded_collision := move_and_collide(Vector3.DOWN * ground_cast_distance, true, 0)
		if initial_grounded_collision && collision_normal_walkable(down_collision_normal(initial_grounded_collision)):
			grounded = true
			ground_normal = down_collision_normal(initial_grounded_collision)
	
			
# TODO maybe it should be slope intersection to get a line
# I wrote this a while ago in Unity
# I ported it here but I only have a vague grasp of how it works
func relative_slope_normal(slope_normal : Vector3, lateral_desired_direction : Vector3) -> Vector3:
	var slope_normal_horz := horz(slope_normal)
	var angle_to_straight := slope_normal_horz.angle_to(-lateral_desired_direction)
	var angle_to_up := slope_normal.angle_to(Vector3.UP)
	var complementary_angle_to_up := PI / 2 - angle_to_up

	if angle_to_up >= (PI / 2):
		push_error("Trying to calculate relative slope normal for a ceiling")

	# Geometry!

	# This is the component of the desired travel that points straight into the slope
	var straight_length := cos(angle_to_straight) * lateral_desired_direction.length()

	# Which helps us calculate the height on the slope at the end of the desired travel
	var height := straight_length / tan(complementary_angle_to_up)

	# Which gives us the actual desired movement
	var vector_up_slope := Vector3(lateral_desired_direction.x, height, lateral_desired_direction.z)

	# Due to the way the movement algorithm works we need to figure out the normal that defines
	# the plane that will give this result
	var rotation_axis := vector_up_slope.cross(Vector3.UP).normalized()
	var emulated_normal := vector_up_slope.rotated(rotation_axis, PI / 2)

	return emulated_normal.normalized()


func set_pos_rot(pos: Vector3, rot: Vector3):
	global_position = pos
	orientation.global_rotation = rot
	
	teleported.emit()

func horz(v:Vector3) -> Vector3:
	return Vector3(v.x,0,v.z)

func vert(v:Vector3) -> Vector3:
	return Vector3(0,v.y,0)
