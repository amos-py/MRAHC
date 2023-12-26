extends CharacterBody2D

@export var speed     : int = 150
@export var gravity   : int = 900
@export var jumpForce : int = 255

func _physics_process(delta):
	var direction = Input.get_axis("Left", "Right")

	if direction:
		velocity.x = direction * speed
		$AnimatedSprite2D.play("Walk")
		
	else:
		velocity.x = 0
		if is_on_floor():
			$AnimatedSprite2D.play("Idle")
		
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
	
	move_and_slide()
