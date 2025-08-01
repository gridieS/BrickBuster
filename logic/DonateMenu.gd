extends Popup

# This menu contains some information and donation buttons.
# These buttons open the operating system's default browser to a donation page.
# TODO: Make these invoke Google Play payment on Android.

func _ready():
	var animation_library = AnimationLibrary.new()
	var animation = Animation.new()
	var track_index = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track_index, String(self.get_path()) + ":modulate:a")
	animation.track_insert_key(track_index, 0.0, 1.0)
	animation.track_insert_key(track_index, 0.3, 0.0)
	animation_library.add_animation("fadeout", animation)
	$AnimationPlayer.add_animation_library("", animation_library)
	$AnimationPlayer.connect("animation_finished", Callable(self, "on_Fadeout_finished"))

func _on_CloseButton_pressed():
	$AnimationPlayer.play("fadeout")

func on_Fadeout_finished(_anim_name):
	hide()


func _on_LearnMeButton_toggled(_button_pressed):
	OS.shell_open("https://github.com/claucambra")


func _on_LearnGodotButton_pressed():
	OS.shell_open("https://godotengine.org/")


func _on_MeDonateButton_pressed():
	OS.shell_open("https://liberapay.com/claucambra/")


func _on_GodotDonateButton_pressed():
	OS.shell_open("https://godotengine.org/donate")
