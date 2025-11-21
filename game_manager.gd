extends Node


signal ally_tickets_changed(tickets: int)
signal enemy_tickets_changed(tickets: int)
signal game_over_triggered(winning_team: String)

const INITIAL_TICKETS = 50

var ally_tickets: int = INITIAL_TICKETS
var enemy_tickets: int = INITIAL_TICKETS

func _ready():
	add_to_group("game_manager")
	ally_tickets_changed.emit(ally_tickets)
	enemy_tickets_changed.emit(enemy_tickets)

func decrement_ally_tickets():
	ally_tickets -= 1
	ally_tickets = max(0, ally_tickets)
	ally_tickets_changed.emit(ally_tickets)
	
	if ally_tickets <= 0:
		_trigger_game_over("Enemy")

func decrement_enemy_tickets():
	enemy_tickets -= 1
	enemy_tickets = max(0, enemy_tickets)
	enemy_tickets_changed.emit(enemy_tickets)
	
	if enemy_tickets <= 0:
		_trigger_game_over("Ally")

func _trigger_game_over(winning_team: String):
	game_over_triggered.emit(winning_team)
	
	# Show game over screen
	var game_over = get_tree().get_first_node_in_group("game_over")
	if game_over:
		game_over.show_game_over(winning_team)

func can_ally_respawn() -> bool:
	return ally_tickets > 0

func can_enemy_respawn() -> bool:
	return enemy_tickets > 0

func get_ally_tickets() -> int:
	return ally_tickets

func get_enemy_tickets() -> int:
	return enemy_tickets

var current_max_enemies: int = 15
var current_enemy_max_tickets: int = 50

func restart_game(next_map: bool):
	if next_map:
		# Increase difficulty
		current_enemy_max_tickets += 25
		current_max_enemies += 5
		
		# Reset tickets for the new round
		ally_tickets = INITIAL_TICKETS
		enemy_tickets = current_enemy_max_tickets
		
		# Emit changes so UI updates immediately
		ally_tickets_changed.emit(ally_tickets)
		enemy_tickets_changed.emit(enemy_tickets)
	else:
		# Reset to default
		reset_game_state()
	
	# Reload the scene to generate a new map
	get_tree().paused = false
	get_tree().reload_current_scene()

func reset_game_state():
	current_enemy_max_tickets = 50
	current_max_enemies = 15
	
	ally_tickets = INITIAL_TICKETS
	enemy_tickets = current_enemy_max_tickets
	
	ally_tickets_changed.emit(ally_tickets)
	enemy_tickets_changed.emit(enemy_tickets)
