extends CharacterBody2D

@export var speed     : int = 150
@export var gravity   : int = 900
@export var jumpForce : int = 255

var isAttacking = false
var isWalking = false

func _physics_process(delta):
	var direction = Input.get_axis("Left", "Right")

	if direction:
		velocity.x = direction * speed
		
		if is_on_floor() and isAttacking == false:
			$AnimatedSprite2D.play("Walk")
			isWalking = true
			#print("Walking!")
		
	else:
		velocity.x = 0
		if is_on_floor() and isAttacking == false:
			$AnimatedSprite2D.play("Idle")
			isWalking == false
			#print("Not walking!")
		
	# Rotation
	if direction == 1:
		$AnimatedSprite2D.flip_h = false
	elif direction == -1:
		$AnimatedSprite2D.flip_h = true
		
	# Gravity
	if not is_on_floor():
		velocity.y += gravity * delta
		
		# Fall Animation
		if velocity.y > 0:
			$AnimatedSprite2D.play("Fall")
	
	# Jump
	if Input.is_action_just_pressed("Jump") and is_on_floor():
			velocity.y -= jumpForce
			$AnimatedSprite2D.play("Jump")
			
	# Attack
	if Input.is_action_just_pressed("Attack") and is_on_floor():
		isAttacking = true
		if isWalking == false:
			$AnimatedSprite2D.play("Attack")
			await $AnimatedSprite2D.animation_finished
			isAttacking = false
			
		elif isWalking == true:
			$AnimatedSprite2D.play("WalkAttack")
			isWalking = false
			await $AnimatedSprite2D.animation_finished
			isAttacking = false
			
	
	move_and_slide()
