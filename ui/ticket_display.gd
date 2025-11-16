extends Control

@onready var ally_label: Label = $AllyTicketsLabel
@onready var enemy_label: Label = $EnemyTicketsLabel

func _ready():
	# Connect to game manager signals
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager:
		game_manager.ally_tickets_changed.connect(_on_ally_tickets_changed)
		game_manager.enemy_tickets_changed.connect(_on_enemy_tickets_changed)
		
		# Initialize display
		_on_ally_tickets_changed(game_manager.get_ally_tickets())
		_on_enemy_tickets_changed(game_manager.get_enemy_tickets())

func _on_ally_tickets_changed(tickets: int):
	if ally_label:
		ally_label.text = "Ally Tickets: " + str(tickets)

func _on_enemy_tickets_changed(tickets: int):
	if enemy_label:
		enemy_label.text = "Enemy Tickets: " + str(tickets)

