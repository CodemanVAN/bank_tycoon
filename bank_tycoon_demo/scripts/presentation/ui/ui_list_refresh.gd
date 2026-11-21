class_name UiListRefresh
extends RefCounted

## Shared helpers for snapshot-driven lists of buttons (drawers / modals).
##
## Why this exists: `refresh()` used to remove and `free()` every row on each
## `snapshot_changed`. A mouse click spans at least two input events (press, release) and
## usually two frames, so a rebuild between them destroys the Button that was pressed and
## the release never produces `pressed` - the player has to click several times.
##
## Rules for list owners:
##   1. Only rebuild when the structural signature actually changed (see `signature`).
##   2. Never rebuild while a button in the list is held (`any_button_held`); set a pending
##      flag and retry from `watch_release`'s callback instead.
##   3. Free rows through `clear_children` (`queue_free`), never `free()` from a signal
##      handler - Godot reports "freed while a signal is being emitted".


static func signature(parts: Array) -> String:
	var out: PackedStringArray = PackedStringArray()
	for part: Variant in parts:
		out.append(str(part))
	return "|".join(out)


static func any_button_held(root: Node) -> bool:
	if root == null:
		return false
	if root is BaseButton and (root as BaseButton).is_pressed():
		return true
	for child in root.get_children():
		if any_button_held(child):
			return true
	return false


static func clear_children(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


## Calls `on_release` once the button is released (deferred, so the button's own `pressed`
## handler has already run). Used to flush a rebuild that was postponed mid-click.
static func watch_release(button: BaseButton, on_release: Callable) -> void:
	if button == null or not on_release.is_valid():
		return
	if not button.button_up.is_connected(on_release):
		button.button_up.connect(on_release, CONNECT_DEFERRED)


## Connects `on_release` to every button under `root` (call once after building a list).
static func watch_tree(root: Node, on_release: Callable) -> void:
	if root == null:
		return
	if root is BaseButton:
		watch_release(root as BaseButton, on_release)
	for child in root.get_children():
		watch_tree(child, on_release)
