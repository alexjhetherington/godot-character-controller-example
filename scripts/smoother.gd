extends Node3D

@export var target : Node3D
var currTransform: Transform3D
var prevTransform: Transform3D

# Called when the node enters the scene tree for the first time.
func _ready():
	currTransform = Transform3D()
	prevTransform = Transform3D()
	set_process_priority(100)
	set_as_top_level(true)
	Engine.set_physics_jitter_fix(0.0)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if target == null: 
		return
	var f = Engine.get_physics_interpolation_fraction()
	var tr: Transform3D = Transform3D()
	
	var ptDiff = currTransform.origin - prevTransform.origin
	tr.origin = prevTransform.origin + (ptDiff * f)
	
	tr.basis = _LerpBasis(prevTransform.basis, currTransform.basis, f)

	transform = tr
	
func _physics_process(delta):	
	prevTransform = currTransform
	currTransform = target.global_transform


func _LerpBasis(from: Basis, to: Basis, f: float) -> Basis:
	var res: Basis = Basis()
	res.x = from.x.lerp(to.x, f)
	res.y = from.y.lerp(to.y, f)
	res.z = from.z.lerp(to.z, f)
	return res
