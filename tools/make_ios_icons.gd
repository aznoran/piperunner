## Resizes the master icon into every size the iOS export asks for.
##
##   godot --headless --path . --script res://tools/make_ios_icons.gd
extends SceneTree

const SIZES := {
	"icon_1024x1024": 1024,
	"ios_128x128": 128,
	"ios_136x136": 136,
	"ios_192x192": 192,
	"ipad_152x152": 152,
	"ipad_167x167": 167,
	"iphone_120x120": 120,
	"iphone_180x180": 180,
	"notification_114x114": 114,
	"notification_40x40": 40,
	"notification_60x60": 60,
	"notification_76x76": 76,
	"settings_58x58": 58,
	"settings_87x87": 87,
	"spotlight_120x120": 120,
	"spotlight_80x80": 80,
}


func _initialize() -> void:
	var master := Image.load_from_file("res://art/icon.png")
	if master == null:
		print("no master icon at res://art/icon.png")
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://art/ios"))
	for name: String in SIZES:
		var side: int = SIZES[name]
		var scaled := master.duplicate()
		scaled.resize(side, side, Image.INTERPOLATE_LANCZOS)
		var path := "res://art/ios/%s.png" % name
		if scaled.save_png(path) != OK:
			print("failed: %s" % path)
	print("wrote %d icons" % SIZES.size())
	quit()
