extends CharacterBody2D

@export var speed            : int = 150
@export var grnd_friction    : float = 0.8
@export var air_friction     : float = 0.95
@export var gravity          : int = 900
@export var wall_slide_speed : int = 100
@export var wall_jmp_x       : int = 500
@export var wall_jmp_y_amp   : float = 2
@export var jumpForce        : int = 400
@export var max_jumps        :int = 2
var jumps                    : int = max_jumps
@export var double_jump_amp  : float = 0.75
var wall_jumps                : int = 0
@export var max_wall_jumps    : int = 0

func _physics_process(delta):

	var direction = Input.get_axis("Left", "Right")		        #not needed anymore, maybe remove
	var moving = false                                          #variable for easily checking if player is moving, is set to false at the beginning of frame every frame and updated accordingly later

	if Input.is_action_pressed("Left"):                         #checks for if player is moving left, needs to be handled differently than moving right to make phyics of player moving work
		if grnd_friction == 0: velocity.x = -speed              #if friction is set to 0, move without physics
		else: velocity.x -= speed                               #else, move with physics
		
		$Smoothing2D/AnimatedSprite2D.play("Walk")
		moving = true
		
	if Input.is_action_pressed("Right"):                        #same as left, just inverted
		if grnd_friction == 0: velocity.x = speed
		else: velocity.x += speed
		
		$Smoothing2D/AnimatedSprite2D.play("Walk")
		moving = true

	velocity.x = clamp(velocity.x,-speed,speed)
		
	if is_on_floor():                                              #interactions for if the player is on the floor
		wall_jumps = 0
		if not moving:                                             #if the player is not moving, reduce velocity using friction
			$Smoothing2D/AnimatedSprite2D.play("Idle")
			velocity.x *= grnd_friction
	elif not moving:                                                          #if the player is not on the floor, add air_friction
			velocity.x *= air_friction 
	if abs(velocity.x) < 10:                               #if player velocity is less than 10 velocity in either direction, set to 0, this is so that the player doesnt slide an infinitely small amount infinitely
		velocity.x = 0
		
	# Rotation
	if direction == 1:
		$Smoothing2D/AnimatedSprite2D.flip_h = false
	elif direction == -1:
		$Smoothing2D/AnimatedSprite2D.flip_h = true

	# Gravity
	if not is_on_floor():
		var pos_delta = get_position_delta()
		if is_on_wall():                                       #handles interactions if the player is on a wall, used for wall jumping, here it simply makes the player fall down slower if touching a wall
			#$Smoothing2D/AnimatedSprite2D.play("WallSliding") #update animation here
			velocity.y = wall_slide_speed
		else:                                                  #if the player is not touching a wall, then they will fall according to gravity
			velocity.y += gravity * delta
		
		if pos_delta.y > 0:
			$Smoothing2D/AnimatedSprite2D.play("Fall")
		
	else:
		jumps = max_jumps                                      #resets amount of jumps back to max

	# Jumping stuff
	if Input.is_action_just_pressed("Jump"):                                #will run if the player has more than 0 jumps and pressed jump, this checks if the player has MORE THAN 0 jumps, this is important because if the value somehow becomes negative, the player could infinitely jump
			
			if is_on_wall() and wall_jumps != max_wall_jumps:                              #if the player is touching a wall, set jumps to max, effectively reseting their amount of jumps
				#$Smoothing2D/AnimatedSprite2D.play("WallJump") update animation here
				jumps = max_jumps
				wall_jumps += 1

				velocity.x += wall_jmp_x * get_wall_normal()[0]                           #adds wall jump value to velocity x and sets it to negative based on the direction the player hits the wall from (if the player is coming from the left, send them to the right and vice versa)
				velocity.y = -jumpForce * wall_jmp_y_amp                                  #sends the player up and multipies it with an amplifier, letting us edit how powerful wall jumps are easily

			if jumps == max_jumps:                                                      #only runs if player is not on a wall, checks if the jump is the first jump, this is for using different animations for double and normal jumps
				velocity.y = -jumpForce
				$Smoothing2D/AnimatedSprite2D.play("Jump")
			elif jumps > 0:                                                                         #runs when the player has double jumped
				velocity.y = -jumpForce * double_jump_amp
				#$Smoothing2D/AnimatedSprite2D.play("DoubleJump")                         #update animation here
				
			jumps -= 1                                                                    #removes one jump from amount player can use, when this is equal to 0, player can no longer jump

	move_and_slide()
