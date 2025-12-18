extends CharacterBody3D
class_name CogitoNPC

## Base NPC class for the Cogito game framework.
##
## This class provides NPC functionality including:
## - Movement and navigation
## - State machine management
## - Interaction system integration
## - Animation control
## - Persistence and saving
## - Damage and knockback systems
##
## @tutorial: See the Cogito documentation for NPC setup and usage.

## Emitted when the NPC receives damage. Used with the HitboxComponent.
## @param damage_value: The amount of damage received
signal damage_received(damage_value:float)

## Emitted when the NPC exits the scene tree.
signal object_exits_tree()

#region Cogito Interaction System Variables
## Variables required for integration with the Cogito interaction system

## Unique identifier for this NPC within the Cogito system.
## Defaults to the node's name if not specified.
@export var cogito_name : String = self.name

## Display name shown when interacting with the NPC.
## Leave blank to hide the display name during interaction.
@export var display_name : String

## Determines where the interaction prompt is displayed relative to the NPC.
enum PromptPositionMode{
	ORIGIN, ## Position the prompt at the NPC's origin point. Recommended for smaller NPCs.
	MARKER, ## Position the prompt at an assigned Marker3D node. Requires a marker to be assigned. Recommended for larger NPCs.
	AABB_CENTER, ## Position the prompt at the center of the calculated bounding box. Has a slight performance impact.
}

## Sets the position mode for interaction prompts.
@export var prompt_pos_mode : PromptPositionMode = PromptPositionMode.ORIGIN

## Marker3D node used for prompt positioning when using MARKER mode.
@export var prompt_marker : Marker3D

## Array of InteractionComponent nodes attached to this NPC.
var interaction_nodes : Array[Node]

## CogitoProperties component for this NPC's attributes and stats.
var cogito_properties : CogitoProperties = null

## Bitmask of properties for this NPC (used by the interaction system).
var properties : int
#endregion

## Patrol path for NPC navigation. Assign a CogitoPatrolPath node.
@export var patrol_path : CogitoPatrolPath

## Current target that has the NPC's attention (e.g., player, enemy).
var attention_target : Node3D

@export_group("Movement Settings", "move_")
## Base movement speed (m/s). Overridden by walk_speed if set.
var move_speed : float = 2

## Walking speed (m/s).
@export var walk_speed : float = 2

## Sprinting speed (m/s).
@export var sprint_speed : float = 4

## Acceleration rate for movement interpolation.
@export var acceleration : float = 10.0

## Rotation speed for turning towards targets.
@export var rotation_speed : float = 0.2

## Current knockback force being applied.
var knockback_force: Vector3 = Vector3.ZERO

## Timer tracking remaining knockback duration.
var knockback_timer: float = 0.0

## Duration of knockback effect in seconds.
@export var knockback_duration: float = 0.5

## Strength multiplier for knockback force.
@export var knockback_strength: float = 10.0

## Last movement direction (used for animation and state tracking).
var last_direction

@export_group("Head LookAt System")
## Neck bone node for head rotation.
@export var neck : Node3D

## Target node for the NPC to look at.
@export var look_object : Node3D

## Offset applied to the look-at target position.
@export var look_at_offset : Vector3 = Vector3.ZERO

## Skeleton node for bone manipulation.
@export var skeleton : Skeleton3D

## Name of the neck bone in the skeleton.
@export var skeleton_neck_bone: String

## Calculated rotation for the neck bone.
var new_rotation

## Smoothed rotation value for bone animation.
var bone_smooth_rotation = 0.0

@export_group("Footstep System")
## Enable or disable footstep sounds for this NPC.
@export var footsteps_enabled: bool = true

## Volume in decibels for walking footsteps.
@export var walk_volume_db: float = -12

## Volume in decibels for sprinting footsteps.
@export var sprint_volume_db: float = -4

## Frequency multiplier for footstep sounds during walking.
## Higher values = more frequent footsteps.
@export var WIGGLE_ON_WALKING_SPEED: float = 12.0

## Frequency multiplier for footstep sounds during sprinting.
## Higher values = more frequent footsteps.
@export var WIGGLE_ON_SPRINTING_SPEED: float = 16.0

## Flag indicating if a footstep sound can be played.
var can_play_footstep: bool = true

## Vector used for footstep timing calculation.
var wiggle_vector : Vector2 = Vector2.ZERO

## Index used for footstep timing calculation.
var wiggle_index : float = 0.0

# Cached node references
@onready var footstep_player = $FootstepPlayer
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var navigation_agent_3d: NavigationAgent3D = $NavigationAgent3D
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var velocity_debug_shape: MeshInstance3D = $VelocityDebugShape

# NPC State Machine
@onready var npc_state_machine: Node = $NPC_State_Machine

## Path to the patrol path node (used for persistence).
var patrol_path_nodepath : NodePath

## Saved state name for persistence system.
var saved_enemy_state : String


func _ready() -> void:
	"""
	Called when the node enters the scene tree.
	Initializes the NPC by:
	1. Adding to necessary groups
	2. Finding interaction components
	3. Finding Cogito properties
	"""
	
	# Add to interactable group for Cogito interaction system
	self.add_to_group("interactable")
	
	# Add to persist group for save/load functionality
	self.add_to_group("Persist")
	
	# Initialize interaction system components
	find_interaction_nodes()
	find_cogito_properties()


func find_interaction_nodes() -> void:
	"""
	Finds and caches all InteractionComponent nodes attached to this NPC.
	These components handle player interactions with the NPC.
	"""
	
	interaction_nodes = find_children("", "InteractionComponent", true)


func find_cogito_properties() -> void:
	"""
	Finds and caches the CogitoProperties component attached to this NPC.
	This component manages the NPC's attributes, stats, and properties.
	"""
	
	var property_nodes = find_children("", "CogitoProperties", true)
	if property_nodes:
		cogito_properties = property_nodes[0]


func _process(delta: float) -> void:
	"""
	Called every frame. Handles continuous updates that don't involve physics.
	
	@param delta: Time elapsed since the last frame (in seconds)
	"""
	
	# Update head look-at target if one is assigned
	if look_object:
		head_lock_at(delta)


func _physics_process(delta: float) -> void:
	"""
	Called every physics frame. Handles movement, physics, and continuous updates.
	
	@param delta: Time elapsed since the last physics frame (in seconds)
	"""
	
	# Handle knockback effect if active
	if knockback_timer > 0:
		knockback_timer -= delta
		velocity = knockback_force
		knockback_force = lerp(knockback_force, Vector3.ZERO, delta * 5)
		move_and_slide()
		return
	
	# Play footstep sounds if enabled
	if footsteps_enabled:
		npc_footsteps(delta)
	
	# Note: move_and_slide() is called in state machine or specific movement functions


func update_animations(_delta: float) -> void:
	"""
	Updates the animation tree based on the NPC's current velocity.
	
	@param _delta: Time elapsed since last frame (unused but kept for consistency)
	"""
	
	# Convert global velocity to local space and normalize
	var relative_velocity = self.global_basis.inverse() * ((self.velocity * Vector3(1,0,1)) / sprint_speed)
	var rel_velocity_xz = Vector2(relative_velocity.x, -relative_velocity.z)
	
	# Update debug visualization
	velocity_debug_shape.position = relative_velocity
	
	# Update animation blend space
	if rel_velocity_xz.length_squared() > 0:
		animation_tree.set("parameters/Movement/blend_position", rel_velocity_xz)
	else:
		animation_tree.set("parameters/Movement/blend_position", 0)


func set_upper_body_state(state_name: String) -> void:
	"""
	Sets the upper body animation state.
	
	@param state_name: Name of the animation state to transition to
	"""
	
	var upper_body_state_machine = animation_tree.get("parameters/UpperBodyState/playback")
	upper_body_state_machine.travel(state_name)


func face_direction(face_direction: Vector3) -> void:
	"""
	Rotates the NPC to face a specific direction.
	
	@param face_direction: The global position or direction vector to face towards
	"""
	
	var face_at_target = global_position.direction_to(face_direction)
	var face_at_target_xz := Vector3(face_at_target.x, 0, face_at_target.z)
	
	if face_at_target_xz != Vector3.ZERO:
		var target_basis = Basis.looking_at(face_at_target_xz, Vector3.UP, false)
		basis = basis.slerp(target_basis, rotation_speed)


func head_lock_at(_delta:float) -> void:
	"""
	Updates head rotation to look at the target object.
	Applies bone rotation to the skeleton for natural head movement.
	
	@param _delta: Time elapsed since last frame (unused but kept for consistency)
	"""
	
	var neck_bone = skeleton.find_bone(skeleton_neck_bone)
	
	# Make the neck look at the target with offset
	neck.look_at(look_object.global_position + look_at_offset, Vector3.UP, true)
	
	# Clamp rotation to natural limits
	var marker_rotation_deg = neck.rotation_degrees
	marker_rotation_deg.x = clamp(marker_rotation_deg.x, -90, 90)
	marker_rotation_deg.y = clamp(marker_rotation_deg.y, -45, 45)
	
	# Smooth the rotation
	bone_smooth_rotation = lerp_angle(bone_smooth_rotation, deg_to_rad(marker_rotation_deg.y), 3 * _delta)
	
	# Apply rotation to skeleton bone
	new_rotation = Quaternion.from_euler(Vector3(deg_to_rad(marker_rotation_deg.x), deg_to_rad(marker_rotation_deg.y), 0))
	skeleton.set_bone_pose_rotation(neck_bone, new_rotation)


func npc_footsteps(delta: float) -> void:
	"""
	Handles footstep sound playback based on NPC movement.
	Uses a sine wave calculation to determine footstep timing.
	
	@param delta: Time elapsed since last frame
	"""
	
	# Check if NPC is sprinting (using rounded velocity to account for fluctuations)
	if round(velocity.length()) >= sprint_speed:
		wiggle_vector.y = sin(wiggle_index)
		wiggle_index += WIGGLE_ON_SPRINTING_SPEED * delta
		
		# Play footstep sound at peak of sine wave
		if can_play_footstep and wiggle_vector.y > 0.9:
			footstep_player.volume_db = sprint_volume_db
			footstep_player._play_interaction("footstep")
			can_play_footstep = false
		
		# Reset flag after sound completes
		if !can_play_footstep and wiggle_vector.y < 0.9:
			can_play_footstep = true
	
	# Check if NPC is walking
	elif velocity.length() >= 0.2:
		wiggle_vector.y = sin(wiggle_index)
		wiggle_index += WIGGLE_ON_WALKING_SPEED * delta
		
		# Play footstep sound at peak of sine wave
		if can_play_footstep and wiggle_vector.y > 0.9:
			footstep_player.volume_db = walk_volume_db
			footstep_player._play_interaction("footstep")
			can_play_footstep = false
		
		# Reset flag after sound completes
		if !can_play_footstep and wiggle_vector.y < 0.9:
			can_play_footstep = true


func apply_knockback(direction: Vector3) -> void:
	"""
	Applies knockback force to the NPC.
	
	@param direction: The direction vector for the knockback
	"""
	
	knockback_force = direction.normalized() * knockback_strength
	knockback_timer = knockback_duration


func set_state() -> void:
	"""
	Restores NPC state after loading from a save file.
	Called by the persistence system when loading game state.
	"""
	
	# Re-find properties after load
	find_cogito_properties()
	
	# Restore patrol path
	load_patrol_points()
	
	# Restore saved state machine state
	npc_state_machine.goto(saved_enemy_state)


func save() -> Dictionary:
	"""
	Saves the NPC's current state for persistence.
	Called by the persistence system when saving game state.
	
	@return: Dictionary containing all serializable NPC data
	"""
	
	# Store patrol path reference
	if patrol_path:
		patrol_path_nodepath = patrol_path.get_path()
	
	# Store current state
	saved_enemy_state = npc_state_machine.current
	
	# Build save data dictionary
	var node_data = {
		"filename": get_scene_file_path(),
		"parent": get_parent().get_path(),
		"pos_x": position.x,
		"pos_y": position.y,
		"pos_z": position.z,
		"rot_x": rotation.x,
		"rot_y": rotation.y,
		"rot_z": rotation.z,
		"patrol_path_nodepath": patrol_path_nodepath,
		"saved_enemy_state": saved_enemy_state,
	}
	
	return node_data


func load_patrol_points() -> void:
	"""
	Loads patrol path from saved node path.
	Called during state restoration.
	"""
	
	if patrol_path_nodepath:
		CogitoGlobals.debug_log(
			true, 
			"cogito_basic_enemy.gd", 
			"Loading patrol path: " + str(patrol_path_nodepath)
		)
		patrol_path = get_node(patrol_path_nodepath)


func _on_hitbox_component_got_hit() -> void:
	"""
	Called when the NPC's hitbox component detects a hit.
	Triggers the hit animation.
	"""
	
	animation_tree.set("parameters/Transition/transition_request", "hit")


func _on_security_camera_object_detected(object: Node3D) -> void:
	"""
	Called when a security camera detects this NPC.
	Sets the NPC as the attention target for AI behaviors.
	
	@param object: The camera or detecting object
	"""
	
	attention_target = object
