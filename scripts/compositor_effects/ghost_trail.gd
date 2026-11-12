@tool
extends CompositorEffect
class_name CompositorEffectGhostTrail

# shader path
const SHADER_PATH := "res://shaders/compositor_effects/ghost_trail.glsl"

# user params
@export_range(0.0, 100.0, 0.1) var gain: float = 50.0
@export_range(0.01, 0.99, 0.01) var length: float = 0.9
@export var glow_color: Color = Color(0.0, 0.0, 1.0, 1.0)

var rd: RenderingDevice
var shader: RID
var pipeline: RID

func _make_image_uniform(binding: int, image: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = binding
	uniform.add_id(image)
	return uniform
	
func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	needs_motion_vectors = true # we need motion vectors!

	rd = RenderingServer.get_rendering_device()
	if rd == null:
		push_error("This effect requires a renderer compatible with RenderingDevice.")
		return

func _ensure_shader() -> bool:
	if pipeline.is_valid():
		return true
	if not rd:
		return false

	var shader_source := load(SHADER_PATH) as RDShaderFile
	if not shader_source:
		push_error("Could not load %s as RDShaderFile." % SHADER_PATH)
		return false

	shader = rd.shader_create_from_spirv(shader_source.get_spirv())
	if not shader.is_valid():
		push_error("Error compiling shader: %s." % SHADER_PATH)		
		return false

	pipeline = rd.compute_pipeline_create(shader)
	return pipeline.is_valid()

func _render_callback(_callback_type: int, render_data: RenderData) -> void:
	if rd == null or not _ensure_shader():
		return

	# get scene buffers
	var scene_buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if scene_buffers == null:
		return

	# get resolution
	var viewport_size: Vector2i = scene_buffers.get_internal_size()
	if viewport_size.x == 0 or viewport_size.y == 0:
		return

	# create (or retrieve existing) persistent previous-frame texture.
	# (create_texture returns the cached RID if it already exists with this name)
	var usage_bits := (
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	)
	scene_buffers.create_texture(
		&"accum_blur", &"prev_frame",
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
		usage_bits,
		RenderingDevice.TEXTURE_SAMPLES_1,
		viewport_size, 1, 1, false, false
	)
	
	# setup work groups
	var dispatch_x := (viewport_size.x + 7) / 8
	var dispatch_y := (viewport_size.y + 7) / 8

	# this loop if for stereo rendering (vr)
	for view in range(scene_buffers.get_view_count()):
		# get image buffers and check if all of them are valid
		var velocity_image := scene_buffers.get_velocity_layer(view)
		var color_image := scene_buffers.get_color_layer(view)
		var prev_image: RID = scene_buffers.get_texture_slice(
			&"accum_blur", &"prev_frame", view, 0, 1, 1
		)		

		if not color_image.is_valid() or not prev_image.is_valid() or not velocity_image.is_valid():
			continue

		# create image uniforms + build an uniform set
		var color_uniform := _make_image_uniform(0, color_image)
		var prev_uniform := _make_image_uniform(1, prev_image)
		var velocity_uniform := _make_image_uniform(2, velocity_image)
		var uniform_set := UniformSetCacheRD.get_cache(
			shader, 0, [color_uniform, prev_uniform, velocity_uniform]
		)

		# setup other uniforms 
		var push_constants := PackedFloat32Array([
			float(viewport_size.x),
			float(viewport_size.y),
			gain,
			length,
			glow_color.r,
			glow_color.g,
			glow_color.b,
			0.0 # unused (padding for 32bytes [don't know if this is needed])
		])

		var compute_list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
		rd.compute_list_set_push_constant(compute_list, push_constants.to_byte_array(), push_constants.size() * 4)
		rd.compute_list_dispatch(compute_list, dispatch_x, dispatch_y, 1)
		rd.compute_list_end()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and rd != null:
		if pipeline.is_valid():
			rd.free_rid(pipeline)
		if shader.is_valid():
			rd.free_rid(shader)
