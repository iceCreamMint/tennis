extends Node2D

# networking
var room_id = -1
var socket = WebSocketPeer.new()
var socket_connected = false
@export var ip_address: String
@export var port: int

func pack_data(purpose, message):
	return {"purpose": purpose, "message": message}

# player 						| 							server
# "id", name 					-> 
# 								<- 							"ack", []
# "host", settings 				->
# 								<- 							"host", room_id
# "find", room_id 				->
# 								<- 							"match", name
# "play", wager 				->
# 								<- 							"play", wager
# "close", room_id 				->

func callout(u_name):
	friendly_name = u_name
	print("connecting to server at %s port %d" % [ip_address, port])
	socket.connect_to_url("ws://"+ip_address+":"+str(port))
	var state
	while state != WebSocketPeer.STATE_CLOSED:
		socket.poll()
		state = socket.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			socket.put_var(pack_data("id", u_name))
			while socket.get_available_packet_count():
				var listen = socket.get_var()
				if listen["purpose"] == "ack":
					print("connected to server")
					socket_connected = true
					return true
	return false
	

# user control logic
var thinking = 0
var exit_game = false

func settings(c_mag, stamina):
	socket.put_var(pack_data("host", {"c_mag": c_mag, "stamina": stamina}))
	
	direction = -1
	

func join_game(join_room_id):
	room_id = join_room_id
	socket.put_var(pack_data("find", room_id))
	direction = 1

func change_wager(amount):
	thinking += amount
	if thinking > friendly_resources:
		thinking = friendly_resources
	elif thinking < 0:
		thinking = 0
	var ui_node : RichTextLabel = get_node("play/bet amount")
	ui_node.text = "[center]" + str(thinking)
	

func leave_matching():
	socket.put_var(pack_data("exit", room_id))
	socket.close()
	exit_game = true

func forfeit_game():
	socket.put_var(pack_data("exit", {"room_id": room_id, "ff_side": "host" if direction < 0 else "guest"}))
	socket.close()
	exit_game = true

# game logic
var court_size
var opponent_resources
var friendly_resources
var court_state = 0
var friendly_name
var opponent_name

var opponent_wager
var opponent_ready = false
var friendly_ready = false
var friendly_wager

var direction # -1 for host, 1 for guest

func wager():
	if thinking >= 0 && thinking <= friendly_resources:
		var side = "host" if direction < 0 else "guest"
		
		socket.put_var(pack_data("play",{"room_id": room_id, "side": side, "wager": thinking}))
		
		friendly_wager = thinking
		friendly_ready = true
		
		get_node("play/button group").visible = false
	else:
		print("only bet what you have")
	

func volley():
	friendly_ready = false
	opponent_ready = false
	get_node("play/opp bet").text = "[center]"+str(opponent_wager)
	await get_tree().create_timer(0.5).timeout
	if opponent_wager > friendly_wager:
		get_node("play/announcement").text = "wager lost"
		court_state -= direction
	elif opponent_wager < friendly_wager:
		get_node("play/announcement").text = "wager won"
		court_state += direction
	friendly_resources -= friendly_wager
	opponent_resources -= opponent_wager
	get_node("play/opp resources").text = "[center]"+str(opponent_resources)
	get_node("play/resources").text = "[center]"+str(friendly_resources)
	await get_tree().create_timer(0.5).timeout
	get_node("play/court").text = "[center]"+str(court_state)
	get_node("play/announcement").text = ""
	
	get_node("play/button group").visible = true
	
	# wincon
	if court_state < -court_size:
		if direction < 0:
			get_node("play/announcement").text = "match won"
		else:
			get_node("play/announcement").text = "match lost"
		if direction < 0:
			socket.put_var(pack_data("exit", room_id))
		socket.close()
		await get_tree().create_timer(1).timeout
		exit_game = true
		
	elif court_state > court_size:
		if direction > 0:
			get_node("play/announcement").text = "match won"
		else:
			get_node("play/announcement").text = "match lost"
		if direction < 0:
			socket.put_var(pack_data("exit", room_id))
		socket.close()
		await get_tree().create_timer(1).timeout
		exit_game = true
	
	if opponent_resources == 0 && friendly_resources == 0:
		if court_state > 0:
			get_node("play/announcement").text = "match won"
		if court_state < 0:
			get_node("play/announcement").text = "match lost"
		else:
			get_node("play/announcement").text = "draw"
		if direction < 0:
			socket.put_var(pack_data("exit", room_id))
		socket.close()
		await get_tree().create_timer(1).timeout
		exit_game = true

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if socket_connected:
		socket.poll()
		var state = socket.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			while socket.get_available_packet_count():
				var incoming = socket.get_var()
				if incoming["purpose"] == "host":
					get_node("play").visible = false
					get_node("wait").visible = true
					room_id = incoming["message"]
					get_node("wait/flavor").text = "[center]"+str(room_id)
					
				if incoming["purpose"] == "match":
					opponent_name = incoming["message"]["opponent"]
					var setting = incoming["message"]["settings"]
					court_size = setting["c_mag"]
					opponent_resources = setting["stamina"]
					friendly_resources = setting["stamina"]
					
					get_node("play/bet amount").text = "[center]0"
					get_node("play/resources").text = "[center]"+str(friendly_resources)
					get_node("play/opp resources").text = "[center]"+str(opponent_resources)
					get_node("wait").visible = false
					get_node("play").visible = true
					
				if incoming["purpose"] == "failure":
					print("room not found")
					socket.close()
					var menu_node = load("res://menu.tscn").instantiate()
					get_tree().root.add_child(menu_node)
					self.queue_free()
				
				if incoming["purpose"] == "play":
					opponent_wager = incoming["message"]
					opponent_ready = true
					
		elif state == WebSocketPeer.STATE_CLOSING:
			# Keep polling to achieve proper close.
			pass
		elif state == WebSocketPeer.STATE_CLOSED:
			var code = socket.get_close_code()
			var reason = socket.get_close_reason()
			print("WebSocket closed with code: %d, reason %s. Clean: %s" % [code, reason, code != -1])
			socket_connected = false
		
	if friendly_ready && opponent_ready:
		volley()
	if exit_game:
		var menu_node = load("res://menu.tscn").instantiate()
		get_tree().root.add_child(menu_node)
		self.queue_free()
		
