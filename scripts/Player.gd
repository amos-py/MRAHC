extends CharacterBody2D
#
@export var walk_speed       : int = 150
@export var run_speed        : int = 350
@export var run_accel        : float = 0.1
@export var grnd_friction    : float = 0.8
@export var air_friction     : float = 0.95
@export var gravity          : int = 900
@export var wall_slide_speed : int = 100
@export var wall_jmp_x       : int = 500
@export var wall_jmp_y_amp   : float = 2
@export var jumpForce        : int = 400
@export var max_jumps        : int = 2
@export var double_jump_amp  : float = 0.75
@export var max_wall_jumps   : int = 0
@export var sliding_time     : float = 0.35

var jumps                    : int = max_jumps
var wall_jumps               : int = 0
var moving                   : bool = false                                          #variable for easily checking if player is moving, is set to false at the beginning of frame every frame and updated accordingly later
var running                  : bool = false                                          #basically the same as moving variable but for running

func move_dir(dir):
	moving = true
	if running:
		if dir == 1: move_right(run_speed)
		elif dir == -1: move_left(run_speed)
	else:
		if dir == 1: move_right(walk_speed)
		elif dir == -1: move_left(walk_speed)

func move_left(move_speed):
	if grnd_friction == 0: velocity.x = -move_speed              #if friction is set to 0, move without physics
	else: velocity.x -= move_speed                               #else, move with physics

func move_right(move_speed):
	if grnd_friction == 0: velocity.x = move_speed
	else: velocity.x += move_speed
	
func jump():
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
		
	jumps -= 1    

func make_timer(seconds):
	return time+seconds

var old_dir = 0
var time = 0.0
var sliding_timer = 0

func _physics_process(delta):
	time += delta
	
	moving = false
	running = false
	var allow_rotation = false
	
	var direction = Input.get_axis("Left", "Right")
	
	if Input.is_action_pressed("Run"):     #sets running to true if... running
		running = true
	
	if Input.is_action_pressed("Left") or Input.is_action_pressed("Right"):                     #checks if the player has input a movement
		if old_dir != 0 and old_dir != direction and running == true and is_on_floor():           #basically checks if you were running one side and instantly changed direction while running on the ground
			sliding_timer = make_timer(0.35)                                                     #starts a timer that lasts 350 milliseconds
	
		if not (sliding_timer > time and running):    #if the timer is less than the time and the player is not running, allow movement
			move_dir(direction)
			allow_rotation = true                     #makes it so that the player does not rotate while sliding, this would make animation impossible if not added
		else:
			#$Smoothing2D/AnimatedSprite2D.play("Slipping")
			pass #remove when animation added
	
	
	if running:        #sets the maximum speed the player is allowed to have, maybe this will be revamped later, since currently the player cannot exceed these limits at all, making speedrunning kind of boring
		velocity.x = clamp(velocity.x,-run_speed,run_speed)
	else:
		velocity.x = clamp(velocity.x,-walk_speed,walk_speed)
		
	if velocity.x != 0:                                                          #if the player is not on the floor, add air_friction
		$Smoothing2D/AnimatedSprite2D.play("Walk")
	
	if is_on_floor():                                              #interactions for if the player is on the floor
		wall_jumps = 0
	
	if not moving:                                             #if the player is not moving, reduce velocity using friction
		$Smoothing2D/AnimatedSprite2D.play("Idle")
		velocity.x *= grnd_friction
	
	elif not moving:
		velocity.x *= air_friction 
		
	if abs(velocity.x) < 10:                               #if player velocity is less than 10 velocity in either direction, set to 0, this is so that the player doesnt slide an infinitely small amount infinitely
		velocity.x = 0
		
	# Rotation
	if allow_rotation:
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
	if Input.is_action_just_pressed("Jump"):                              #will run if the player has more than 0 jumps and pressed jump, this checks if the player has MORE THAN 0 jumps, this is important because if the value somehow becomes negative, the player could infinitely jump
		jump()                                                            #removes one jump from amount player can use, when this is equal to 0, player can no longer jump

	old_dir = direction
	move_and_slide()
