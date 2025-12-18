extends Node

"""
Attack state for NPC state machine in the Cogito framework.

This state handles NPC attack behaviors including:
- Targeting and engaging enemies
- Playing attack animations
- Applying damage and knockback
- Managing attack cooldowns
- Sound effect playback

This state is designed to be used within a StateMachine node.
"""

# These will be autofilled by the StateMachine
## Reference to the parent NPC character (CharacterBody3D).
var Host

## Reference to the parent StateMachine node.
var States

## The state to transition to after the attack completes.
@export var state_after_attack : String

@export_group("Attack Properties", "attack_")
## Duration of the attack animation and wind-up in seconds.
@export var attack_duration : float = 0.5

## Damage value applied to the target on hit.
@export var attack_damage : int = 1

## Force applied to the target for knockback/stagger effect.
@export var attack_stagger : float = 8.0

## Sound effect played when attacking.
@export var attack_sound : AudioStream

## Current attack target (typically the player or another NPC).
var target : Node3D = null

## Timer counting down until attack completion.
var count_down : float = 0


func _state_enter() -> void:
	"""
	Called when this state is entered.
	Initializes the attack by:
	1. Getting the attention target from the Host
	2. Starting the attack timer
	3. Beginning the attack animation
	
	If no target is available, returns to the previous state.
	"""
	
	target = Host.attention_target
	
	if !target:
		CogitoGlobals.debug_log(true, "NPC State Attack", 
			"Target was null, going to previous state...")
		States.load_previous_state()
	else:
		count_down = attack_duration
		attempt_attack()


func _state_exit() -> void:
	"""
	Called when this state is exited.
	Useful for cleanup operations if needed.
	"""
	pass


func _physics_process(_delta: float) -> void:
	"""
	Called every physics frame while this state is active.
	Handles:
	- Velocity decay (slowing down movement)
	- Attack timer management
	- State transitions after attack completion
	
	@param _delta: Time elapsed since last physics frame (in seconds)
	"""
	
	# Gradually reduce velocity to simulate attack wind-up
	Host.velocity.x = move_toward(Host.velocity.x, 0, _delta * Host.move_speed)
	Host.velocity.z = move_toward(Host.velocity.z, 0, _delta * Host.move_speed)
	Host.move_and_slide()
	
	# Check if attack timer has expired
	if count_down <= 0:
		attempt_attack()
		States.goto(state_after_attack)
	else:
		count_down -= _delta


func attempt_attack() -> void:
	"""
	Initiates an attack sequence.
	This function:
	1. Resets the attack timer
	2. Triggers the attack animation
	3. Calls the actual attack logic if target is in range
	"""
	
	count_down = attack_duration
	
	# Trigger attack animation regardless of target reach
	Host.animation_tree.set(
		"parameters/UpperBodyState/RaisedFists/attack/request", 
		AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
	)
	
	# Only apply damage if target is within attack range (1.5 units)
	if Host.global_position.distance_to(target.global_position) <= 1.5:
		attack(target)


func attack(target: Node3D) -> void:
	"""
	Executes the attack on a specific target.
	Applies damage, knockback, and plays sound effects.
	
	@param target: The Node3D to attack (typically CogitoPlayer or another NPC)
	"""
	
	var dir = Host.global_position.direction_to(target.global_position)
	
	# Brief delay to synchronize damage with animation impact frame
	await get_tree().create_timer(0.15).timeout
	
	# Play attack sound at NPC's position
	Audio.play_sound_3d(attack_sound).global_position = Host.global_position
	
	# Handle player target specifically
	if target is CogitoPlayer:
		# TODO: Replace direct method calls with signal-based system
		target.apply_external_force(dir * attack_stagger)
		
		CogitoGlobals.debug_log(
			true, 
			"NPC State Attack", 
			"Attacking player. Applying vector " + 
			str(dir * attack_stagger) + 
			" to target. Target.main_velocity = " + 
			str(target.main_velocity)
		)
		
		target.decrease_attribute("health", attack_damage)
	
	# Handle other damageable targets via signals
	elif target.has_signal("damage_received"):
		var damage_direction = (self.global_position + target.global_position).abs()
		
		CogitoGlobals.debug_log(
			true, 
			"npc_state_attack.gd", 
			self.name + ": dealing damage amount " + 
			str(attack_damage) + 
			" on target " + target.name + 
			" in direction " + str(damage_direction)
		)
		
		target.damage_received.emit(attack_damage, damage_direction)
		return
	
	# Fallback for other target types (e.g., via HitboxComponent)
	else:
		# Apply damage using hitbox container logic if available
		# This might need implementation based on your game's architecture
		pass
