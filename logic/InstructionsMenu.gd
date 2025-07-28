extends Popup

# This is the logic for the instructions displayed on first launch.

@onready var tab_container = $MarginContainer/VBoxContainer/TabContainer

func _ready():
	var animation_library = AnimationLibrary.new()
	var animation = Animation.new()
	var track_index = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track_index, String(self.get_path()) + ":modulate:a")
	animation.track_insert_key(track_index, 0.0, 1.0)
	animation.track_insert_key(track_index, 0.3, 0.0)
	animation_library.add_animation("fadeout", animation)
	
	animation = Animation.new()
	track_index = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track_index, str(self.get_path()) + ":modulate:a")
	animation.track_insert_key(track_index, 0.0, 0.0)
	animation.track_insert_key(track_index, 0.3, 1.0)
	animation_library.add_animation("fadein", animation)
	
	$AnimationPlayer.add_animation_library("", animation_library)
func _on_CloseButton_pressed():
	$AnimationPlayer.play("fadeout")

func _on_NextButton_pressed():
	tab_container.current_tab += 1


func _on_PrevButton_pressed():
	tab_container.current_tab -= 1


func _on_PopupDialog_visibility_changed():
	if visible and is_node_ready():
		$AnimationPlayer.play("fadein")


func _on_AnimationPlayer_animation_finished(anim_name):
	if anim_name == "fadeout":
		hide()
