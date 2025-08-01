# This file contains most of the functionality and the variables that are 
# universal to all of BrickBuster's gamemodes. This functionality includes:
#
# - Saving and loading the game
# - Launch line calculations and drawing
# - Destroyable creation (and destroyable line creation) and behaviour
# - Live ball and live destroyable storage
# - Ball launching and launch cadence, and repositioning after launch
# - Updating score and ammo labels
# - Game over procedure and dead ball and destroyable instance handling
#
# Aspects of the game loop that vary depending on the game mode are left to the
# specific scripts that handle that game mode. These game mode scripts are
# handled, selected, and applied to the Board node by ModeSelector.gd (which is
# attached to the GameModeSelector node of this scene.
#
# GameMode scripts have the responsibility of handling the following:
#
# - Drag enabled state (i.e. when input is accepted) and when the user can
#	launch balls
# - How destroyables are relocated around the board during the game
# - How (or if) rounds are implemented and how they affect the game state

extends Node2D

signal game_prepped
signal reset_triggered
signal ball_died(dead_ball)
signal ball_no_contact_timeout(ball_position, ball_linear_velocity)

# <---------------------------- MEMBER VARIABLES ---------------------------->
var game_over = false
var game_over_on_screen = false
var game_over_fadeout = false
var resetting = false
# These variables are used to keep track of what stage of the round we are in
# This is used to decide input state and acceptance
var drag_enabled = false
var mouse_in_controlarea = false
var mouse_position = Vector2(0,0)
var line_direction = Vector2(0,0)
var first_click_position = Vector2(0,0)
var reasonable_angle = false
# draw_touch_marker is read by DrawNode, which handles drawing the marker
var draw_touch_marker = false
# launched is used to differentiate between states when there are no live balls
# i.e. idling vs just after all balls have returned to bottom of screen
var launched = false
var all_balls_launched = false
var round_in_progress = false
var repositioning_ball = false
# live_destroyables is used to simplify the saving procedure.
# DO NOT use it to handle the bricks during the game. Unexpected breakage will
# most likely happen.
var live_destroyables = []
# live_balls is used for labels. Again, don't touch it.
var live_balls = []
var score = 0
var ammo = 1
var lighting_enabled = true
var ball_color = "#ffffff"

var ball = null

@onready var global = get_node("/root/Global")
@onready var meta_area = $Board/CanvasLayer/MetaArea
@onready var bottom_panel = $Board/CanvasLayer/BottomPanel
@onready var current_score_label = $Board/CanvasLayer/MetaArea/MarginContainer/HBoxContainer/CurrentScoreLabel
@onready var high_score_label = $Board/CanvasLayer/MetaArea/MarginContainer/HBoxContainer/VBoxContainer/HighScoreLabel
@onready var ammo_label = $Board/CanvasLayer/BottomPanel/CenterContainer/AmmoLabel
@onready var game_over_label = $Board/CanvasLayer/GameOverLabel
@onready var brick_scene = load("res://scenes/Brick.tscn")
@onready var slanted_brick_scene = load("res://scenes/SlantedBrick.tscn")
@onready var specials_scene = load("res://scenes/Specials.tscn")
@onready var laserbeam_scene = load("res://scenes/LaserBeam.tscn")
# We use a ball instance to mark where our balls will launch from.
# This ball remains throughout the game, 
# moving position to where the last ball of the last round fell.
@onready var launch_line = $Board/CanvasLayer/LaunchLine
@onready var launch_line_raycast = $Board/LaunchRayCast2D
@onready var launch_cadence_wait = $Board/LaunchCadenceTimer
@onready var game_over_timer = $Board/GameOverTimer
@onready var columns = [
	$Board/Column0,
	$Board/Column1,
	$Board/Column2,
	$Board/Column3,
	$Board/Column4,
	$Board/Column5,
	$Board/Column6
]

class DestroyableRequest:
	var request_name = "DestroyableRequest" # get_class() method returns native class name
	var column_vert_point: int
	var column_num: int
	var specific_position: Vector2
	var from_save: bool

class BrickRequest extends DestroyableRequest:
	func _init():
		request_name = "BrickRequest"
	var rotation_degrees: int
	var shape: String
	var mega: bool
	var health: int

class SpecialRequest extends DestroyableRequest:
	func _init():
		request_name = "SpecialRequest"
	var mode: String
	var laserbeam_direction: String

# <-------------------------- GAME SAVING FUNCTIONS -------------------------->
func save():
	# This is save_dict is saved in JSON format in our savefile
	var save_dict = {
		"game_mode": $GameModeSelector.selected_game_mode,
		"score": score,
		"past_scores": global.save_game_data["past_scores"],
		"ammo": ammo,
		"launch_ball_position_x": ball.position.x,
		"launch_ball_position_y": ball.position.y,
		"destroyables" : []
	}
	
	for destroyable in live_destroyables:
		var save_destroyable = {
			"name": destroyable.name,
			"column_num": destroyable.column_num,
			"column_vert_point": destroyable.column_vert_point,
			"position_x": destroyable.position.x,
			"position_y": destroyable.position.y,
			"health": null,
			"mega": null,
			"special_mode": null,
			"rotation": destroyable.rotation,
			"laserbeam_direction": null
		}
		if "Brick" in destroyable.name:
			save_destroyable.health = destroyable.health
			save_destroyable.mega = destroyable.mega
		elif "Special" in destroyable.name:
			save_destroyable.special_mode = destroyable.mode
			if destroyable.mode == "laser":
				save_destroyable.laserbeam_direction = destroyable.laserbeam_direction
		save_dict.destroyables.append(save_destroyable)
	
	# 'user://' data path varies by OS
	var save_game = FileAccess.open("user://savegame.save", FileAccess.WRITE)
	
	# Store the save dictionary as a new line in the save file.
	save_game.store_line(JSON.new().stringify(save_dict))
	save_game.close()
	global.reload_save_data()

func load_game():
	global.reload_save_data()
	var game_mode = global.save_game_data["game_mode"]
	score = global.save_game_data["score"]
	ammo = global.save_game_data["ammo"]
	ball.position = Vector2(global.save_game_data["launch_ball_position_x"], global.save_game_data["launch_ball_position_y"])
	
	for destroyable in global.save_game_data["destroyables"]:
		var new_destroyable_request
		if "Brick" in destroyable.name:
			new_destroyable_request = BrickRequest.new()
			new_destroyable_request.shape = destroyable.name
			new_destroyable_request.health = destroyable.health
			new_destroyable_request.mega = destroyable.mega
			new_destroyable_request.rotation_degrees = destroyable.rotation
			
		elif "Special" in destroyable.name:
			new_destroyable_request = SpecialRequest.new()
			new_destroyable_request.mode = destroyable.special_mode
			if destroyable.laserbeam_direction:
				new_destroyable_request.laserbeam_direction = destroyable.laserbeam_direction
		else:
			continue
		
		new_destroyable_request.column_vert_point = destroyable.column_vert_point - 1 # To get swanky move down on load
		new_destroyable_request.column_num = destroyable.column_num
		new_destroyable_request.specific_position = Vector2(destroyable["position_x"], destroyable["position_y"])
		new_destroyable_request.from_save = true
		
		new_destroyable(new_destroyable_request, game_mode)








# <-------------------------- GAME HELPER FUNCTIONS -------------------------->
func launch_line_calc():
	mouse_position = get_global_mouse_position()
	line_direction = first_click_position - mouse_position
	# We can calculate a minimum coordinate set for the launch line to stop us scoring against ourselves
	if line_direction.normalized().x > -0.998 and line_direction.normalized().x < 0.998 and line_direction.normalized().y < 0:
		reasonable_angle = true
	else:
		reasonable_angle = false

func setup_line():
	launch_line_raycast.position = ball.position
	launch_line_raycast.target_position = line_direction.normalized()*100000
	launch_line.set_point_position(0, ball.position)
	launch_line.set_point_position(1, launch_line_raycast.get_collision_point())
	if launch_line.modulate.a < 1:
		launch_line.modulate.a += 0.1

func launch_balls(direction = line_direction.normalized(), amount = ammo):
	all_balls_launched = false
	for i in amount:
		var next_ball = global.selected_ball_scene.instantiate()
		next_ball.get_node("PointLight2D").enabled = lighting_enabled
		next_ball.set_color(ball_color)
		add_child(next_ball)
		next_ball.connect("ball_no_contact_timeout", Callable(self, "on_ball_no_contact_timeout"))
		next_ball.connect("ball_died", Callable(self, "on_ball_died"))
		next_ball.position = ball.position
		next_ball.launch(direction)
		live_balls.append(next_ball)
		launch_cadence_wait.start()
		await launch_cadence_wait.timeout
	all_balls_launched = true

func new_destroyable(destroyable_request, game_mode = "standard"):
	if destroyable_request.get_class():
		var request_type = destroyable_request.request_name
		var next_destroyable
		
		if request_type == "BrickRequest":
			if destroyable_request.shape == "SlantedBrick":
				next_destroyable = slanted_brick_scene.instantiate()
				if destroyable_request.rotation_degrees == null:
					global.rng.randomize()
					next_destroyable.rotation_degrees = global.rng.randi_range(0,3) * 90
				else:
					next_destroyable.rotation_degrees = rotation_degrees
			else:
				next_destroyable = brick_scene.instantiate()
			
			next_destroyable.mega = destroyable_request.mega
			if destroyable_request.mega and destroyable_request.from_save:
				next_destroyable.health = destroyable_request.health / 2
			else:
				next_destroyable.health = destroyable_request.health
			next_destroyable.max_possible_health = score + 1
			next_destroyable.connect("brick_killed", Callable(self, "on_destroyable_killed"))
			
		elif request_type == "SpecialRequest":
			next_destroyable = specials_scene.instantiate()
			next_destroyable.get_node("PointLight2D").enabled = lighting_enabled
			next_destroyable.mode = destroyable_request.mode
			next_destroyable.laserbeam_direction = destroyable_request.laserbeam_direction
			next_destroyable.connect("special_area_entered", Callable(self, "on_special_area_entered"))
			next_destroyable.connect("special_killed", Callable(self, "on_destroyable_killed"))
		
		next_destroyable.column_num = destroyable_request.column_num
		next_destroyable.column_vert_point = destroyable_request.column_vert_point
		add_child(next_destroyable)
		# We set it at 0 and then add 1 to vert position to get swanky movement down
		next_destroyable.set_position(columns[destroyable_request.column_num].get_point_position(destroyable_request.column_vert_point))
		# Add exception for bounce specials introduced in middle of round
		if destroyable_request.request_name == "SpecialRequest" and destroyable_request.mode == "bounce_nc":
			next_destroyable.mode = "bounce"
			next_destroyable.hit = true
		else:
			next_destroyable.column_vert_point += 1
		
		if game_mode != "standard":
			next_destroyable.position = destroyable_request.specific_position
		live_destroyables.append(next_destroyable)
	else:
		print("BAD DESTROYABLE REQUEST.")
		return

func add_bricks_on_line(free_columns, health, vert_point, mega):
	for column in columns:
		global.rng.randomize()
		if global.rng.randi_range(0,2) > 0 and free_columns.size() > 1: 
			free_columns.erase(column)
			
			var new_brick_request = BrickRequest.new()
			new_brick_request.column_vert_point = vert_point
			new_brick_request.column_num = columns.find(column)
			new_brick_request.health = health
			new_brick_request.mega = mega
			
			if global.rng.randi_range(0,3) == 3:
				new_brick_request.shape = "SlantedBrick"
			else:
				new_brick_request.shape = "Brick"
			
			new_destroyable(new_brick_request)
	
	if free_columns.size() == 7: # In case, by chance, no bricks have been added
		var random_free_column_index = global.rng.randi_range(0, (free_columns.size() - 1))
		var column = free_columns[random_free_column_index]
		free_columns.erase(column)
		
		var new_brick_request = BrickRequest.new()
		new_brick_request.column_vert_point = vert_point
		new_brick_request.column_num = columns.find(column)
		new_brick_request.health = health
		new_brick_request.mega = mega
		new_brick_request.shape = "Brick"
			
		if global.rng.randi_range(0,3) == 3:
			new_brick_request.shape = "SlantedBrick"
		
		new_destroyable(new_brick_request)

func add_special_on_line(free_columns, vert_point):
	var random_free_column_index = global.rng.randi_range(0, (free_columns.size() - 1))
	var bounce_special_column = free_columns[random_free_column_index]
	var actual_column_index = columns.find(bounce_special_column)
	
	free_columns.erase(bounce_special_column)
	global.rng.randomize()
	
	var new_special_request = SpecialRequest.new()
	new_special_request.column_vert_point = vert_point
	new_special_request.column_num = actual_column_index
	
	var decider = global.rng.randi_range(0, 1)
	if decider == 1:
		new_special_request.mode = "laser"
		
		global.rng.randomize()
		if global.rng.randi_range(0,1) == 1:
			new_special_request.laserbeam_direction = "vertical"
		else:
			new_special_request.laserbeam_direction = "horizontal"
		
	else:
		new_special_request.mode = "bounce"
	
	new_destroyable(new_special_request)

func smoothly_reposition_ball(delta, ball_to_reposition, destination):
	# <---- SMOOTHLY REPOSITION INDICATOR BALL AFTER FIRST BALL RETURN ---->
	repositioning_ball = true
	var reposition = ball_to_reposition.position - destination
	# Snap ball into position when they are imperceptibly close
	# Otherwise they will never reach the intended position
	# We also don't want to go to the Y position of the dead ball, only the X
	if destination.distance_to(Vector2(ball_to_reposition.position.x, destination.y)) < 0.5:
		ball_to_reposition.position.x = destination.x
		repositioning_ball = false
	else:
		var reposition_velocity = reposition * 6 * delta
		ball_to_reposition.position.x -= reposition_velocity.x

func update_score_labels():
	var game_mode = $GameModeSelector.selected_game_mode
	ammo_label.text = "x" + str(ammo)
	current_score_label.text = str(score)
	var past_scores = global.save_game_data.past_scores
	if not past_scores.has(game_mode) or past_scores[game_mode].is_empty() or score > past_scores[game_mode].max():
		high_score_label.text = str(score)
	else:
		high_score_label.text = str(past_scores[game_mode].max())

func game_over_title_fadein_and_fadeout_init():
	if game_over_label.modulate.a < 1:
		game_over_label.modulate.a += 0.05
	
	elif not game_over_on_screen:
		game_over_on_screen = true
		game_over_timer.start()
		await game_over_timer.timeout
		game_over_fadeout = true
		
func game_over_title_fadeout_and_reset():
	if game_over_label.modulate.a > 0:
		game_over_label.modulate.a -= 0.05
	else:
		reset()

func end_game():
	if not game_over_on_screen:
		game_over_title_fadein_and_fadeout_init()
	if game_over_fadeout:
		game_over_title_fadeout_and_reset()

func reset():
	$AnimationPlayer.play("fadeout")
	await $AnimationPlayer.animation_finished
	if score != 0:
		if global.save_game_data.past_scores.has($GameModeSelector.selected_game_mode):
			global.save_game_data.past_scores[$GameModeSelector.selected_game_mode].append(score)
		else:
			global.save_game_data.past_scores[$GameModeSelector.selected_game_mode] = [score]
	resetting = true
	emit_signal("reset_triggered")
	for live_element in get_children():
		if "Brick" in live_element.name or "Special" in live_element.name:
			live_element.queue_free()
		elif "Ball" in live_element.name and live_element != ball:
			live_element.queue_free()
	live_balls.clear()
	live_destroyables.clear()
	launched = false
	all_balls_launched = false
	round_in_progress = false
	score = 0
	ammo = 1
	ball.position = Vector2(360, 1072)
	repositioning_ball = false
	update_score_labels()
	game_over = false
	resetting = false
	save()
	get_tree().reload_current_scene()









# <----------------------------- SIGNAL HANDLERS ----------------------------->
func on_pause_menu_toggled(popup_open):
	get_tree().paused = popup_open

# This should only be used once, on first run.
# This is so on closing the help menu the game continues after showing the help 
# menu on first run.
func on_help_menu_visibility_changed():
	get_tree().paused = meta_area.help_popup.visible
	global.first_run = false

func on_restart_button_clicked():
	reset()

func on_quit_to_menu_button_clicked():
	$AnimationPlayer.play("fadeout")
	await $AnimationPlayer.animation_finished
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func on_destroyable_killed(destroyable):
	live_destroyables.erase(destroyable)

func on_special_area_entered(special):
	if special.mode == "add-ball":
		ammo += 1
	if special.mode == "laser":
		var laserbeam = laserbeam_scene.instantiate()
		if special.laserbeam_direction == "vertical":
			laserbeam.position = Vector2(special.global_position.x, 0)
			laserbeam.rotation_degrees = 90
		elif special.laserbeam_direction == "horizontal":
			laserbeam.position = Vector2(0, special.global_position.y)
		add_child(laserbeam)


func on_ball_no_contact_timeout(ball_position, ball_linear_velocity):
	emit_signal("ball_no_contact_timeout", ball_position, ball_linear_velocity)

func on_ball_died(dead_ball):
	emit_signal("ball_died", dead_ball)
	live_balls.erase(dead_ball)

func _on_ControlArea_mouse_entered():
	mouse_in_controlarea = true

func _on_ControlArea_mouse_exited():
	mouse_in_controlarea = false








# <--------------------------- STANDARD GAME FUNCS --------------------------->
func _ready():
	if global.err == OK:
		ball = global.selected_ball_scene.instantiate()
		lighting_enabled = global.config.get_value("lighting", "enabled")
		ball_color = global.config.get_value("ball", "color")
	else: # Emergency defaults
		ball = load("res://scenes/Balls/Ball.tscn").instantiate()
		lighting_enabled = false
		ball_color = "#ffffff"
	ball.marker_ball = true
	
	meta_area.process_mode = Node.PROCESS_MODE_ALWAYS
	meta_area.connect("pause_menu_toggled", Callable(self, "on_pause_menu_toggled"))
	meta_area.connect("restart_button_clicked", Callable(self, "on_restart_button_clicked"))
	meta_area.connect("quit_to_menu_button_clicked", Callable(self, "on_quit_to_menu_button_clicked"))
	
	launch_line.add_point(Vector2(0,0), 0)
	launch_line.add_point(Vector2(0,0), 1)
	launch_line.default_color = global.config.get_value("theme", "launch_line_color")
	launch_line_raycast.add_exception(ball)
	ball.get_node("PointLight2D").enabled = lighting_enabled
	ball.set_color(ball_color)
	add_child(ball)
	
	launch_cadence_wait.wait_time = 0.1
	launch_cadence_wait.one_shot = true
	game_over_timer.wait_time = 2
	game_over_timer.one_shot = true
	
	emit_signal("game_prepped")
	
	if global.first_run:
		meta_area.help_popup.visible = true
		get_tree().paused = true
		meta_area.help_popup.connect("visibility_changed", Callable(self, "on_help_menu_visibility_changed"))

func _process(_delta):

	if game_over:
		drag_enabled = false
		launch_line.modulate.a -= 0.1
		
		var all_transparent = true
		for live_destroyable in live_destroyables:
			if "Brick" in live_destroyable.name:
				live_destroyable.health = 0
				# Setting health to 0 makes bricks queue_free themselves
			elif live_destroyable.modulate.a > 0:
				live_destroyable.modulate.a -= 0.05
				all_transparent = false
			else:
				live_destroyable.queue_free()
				live_destroyables.erase(live_destroyable)
		
		if all_transparent:
			end_game()
	
	else:
		# <------------- UPDATE AMMO LABEL AS BALLS TOUCH BOTTOM ------------->
		ammo_label.text = "x" + str(ammo - live_balls.size())
		
		# <-------------- CALCULATE LAUNCH LINE AND BALL ANGLES -------------->
		launch_line_calc()
		
		# <-------------- SETTING LAUNCH LINE AND LAUNCHING BALL -------------->
		# "click" is defined in input map
		# Allow clicks when mouse is in the game area
		if not mouse_in_controlarea:
			drag_enabled = false
		
		if Input.is_action_just_pressed("click"):
			first_click_position = get_global_mouse_position()
		
		if Input.is_action_pressed("click"):
			draw_touch_marker = true
			
			if reasonable_angle and drag_enabled:
				setup_line()
			else:
				if launch_line.modulate.a > 0:
					launch_line.modulate.a -= 0.1
		else:
			draw_touch_marker = false
			if launch_line.modulate.a > 0:
				launch_line.modulate.a -= 0.1
