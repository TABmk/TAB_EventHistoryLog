# TODO

example:

```gdscript
extends Node2D


func _ready() -> void:
	var counter := 1

	while is_inside_tree():
		EventHistory.emit_event("demo", "tick", {
			"counter": counter,
		})
		counter += 1
		await Utils.wait(1.0)

```