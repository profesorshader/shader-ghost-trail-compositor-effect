extends Node3D

@export var amplitude: float = 1.0
@export var speed_r: float = 180.0
@export var speed_x: float = 1.0
@export var speed_y: float = 1.234
@export var rotate: bool = false

var initial_position: Vector3
var time: float = 0.0

func _ready():
	initial_position = global_position

func _process(delta):
	time += delta
	global_position.y = initial_position.y + sin(time * speed_x) * amplitude
	global_position.x = initial_position.x + cos(time * speed_y) * amplitude
	if rotate:
		rotation_degrees.z += speed_r * delta
		rotation_degrees.y += speed_r * delta
	
