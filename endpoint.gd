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

func callout(name):
	friendly_name = name
	print("connecting to server")
	socket.connect_to_url("ws://127.0.0.1:9876")
	var state
	while state != WebSocketPeer.STATE_CLOSED:
		socket.poll()
		state = socket.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			socket.put_var(pack_data("id", name))
			while socket.get_available_packet_count():
				var listen = socket.get_var()
				if listen["purpose"] == "ack":
					print("connected to server")
					socket_connected = true
					return true
	return false
	

# user control logic
var thinking = 0
var menu = preload("res://menu.tscn")

func settings(c_mag, stamina):
	socket.put_var(pack_data("host", {"c_mag": c_mag, "stamina": stamina}))
	
	court_size = c_mag
	opponent_resources = stamina
	friendly_resources = stamina
	

func join_game(room_id):
	socket.put_var(pack_data("find", room_id))

func change_wager(amount):
	thinking += amount
	var ui_node : RichTextLabel = get_node("Control/bet amount")
	ui_node.text = "[center]" + str(thinking)
	

func end_game():
	pass

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
		var side = "host" if direction > 0 else "guest" # reversed, because implementation details
		
		socket.put_var(pack_data("play",{"room_id": room_id, "side": side, "wager": thinking}))
		
		friendly_wager = thinking
		friendly_ready = true
	else:
		print("only bet what you have")
	

func volley():
	if opponent_wager > friendly_wager:
		court_state -= direction
	elif opponent_wager < friendly_wager:
		court_state += direction
	
	friendly_resources -= friendly_wager
	opponent_resources -= opponent_wager
	friendly_ready = false
	opponent_ready = false
	
	# wincon
	if court_state < -court_size:
		if direction < 0:
			print("win!")
		else:
			print("lose...")
	elif court_state > court_size:
		if direction > 0:
			print("win!")
		else:
			print("lose...")
	
	if opponent_resources == 0 && friendly_resources == 0:
		if court_state > 0:
			print("narrow win")
		if court_state < 0:
			print("narrow loss")
		else:
			print("draw")
	

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
					room_id = incoming["message"]["room_id"]
				if incoming["purpose"] == "match":
					opponent_name = incoming["message"]["opponent"]
					var setting = incoming["message"]["settings"]
					court_size = setting["c_mag"]
					opponent_resources = setting["stamina"]
					friendly_resources = setting["stamina"]
				if incoming["purpose"] == "failure":
					print("room not found")
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
		pass
		
	if friendly_ready && opponent_ready:
		volley()
