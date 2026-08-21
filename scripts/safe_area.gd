## Safe-area insets, in viewport units.
##
## DisplayServer reports the whole display as "safe" on desktop, which on a
## windowed build works out to a huge bogus inset — enough to push the queue bar
## off the bottom of the screen. So the insets only apply on mobile, and are
## clamped even there.
class_name SafeArea
extends RefCounted

## Never trust an inset larger than this fraction of the window.
const MAX_FRACTION := 0.25


## Returns (left, top, right, bottom).
static func insets(viewport_size: Vector2) -> Vector4:
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var window := DisplayServer.window_get_size()
	if window.x <= 0 or window.y <= 0:
		return Vector4.ZERO

	var safe := DisplayServer.get_display_safe_area()
	var scale := Vector2(viewport_size.x / window.x, viewport_size.y / window.y)
	var limit_x := window.x * MAX_FRACTION
	var limit_y := window.y * MAX_FRACTION

	return Vector4(
		clampf(safe.position.x, 0.0, limit_x) * scale.x,
		clampf(safe.position.y, 0.0, limit_y) * scale.y,
		clampf(window.x - safe.position.x - safe.size.x, 0.0, limit_x) * scale.x,
		clampf(window.y - safe.position.y - safe.size.y, 0.0, limit_y) * scale.y)
