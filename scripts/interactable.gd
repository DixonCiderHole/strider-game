extends Node3D
## Something you can use with E. The scene's Overlay finds the nearest one
## in range, shows its prompt and calls `action` when you press E.

var prompt := "Interact"
var action: Callable
var reach := 2.6
var enabled := true


func _ready() -> void:
	add_to_group("interactable")


## Prompt text right now (pickups override this, e.g. "needs a hatchet").
func get_prompt() -> String:
	return prompt


func interact() -> void:
	if action.is_valid():
		action.call()
