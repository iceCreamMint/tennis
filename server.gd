extends Node2D

@export var port: int

var wsocket = WebSocketPeer.new()
var tserver = TCPServer.new()

var connection_list = []
var room_list: Dictionary = {}
var taken_rooms = []

func pack_data(purpose, message):
	return {"purpose": purpose, "message": message}
	

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var listen_signal = tserver.listen(port)
	if listen_signal != OK:
		print("something is wrong %d" % listen_signal)
	pass


func handshake(ws_connection):
	print("accepting connection")
	var state
	while ws_connection.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		ws_connection.poll()
		state = ws_connection.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			while ws_connection.get_available_packet_count():
				var listen = ws_connection.get_var()
				if listen["purpose"] == "id":
					ws_connection.put_var(pack_data("ack", []))
					connection_list.append({"connector": ws_connection, "name": listen["message"]})
					print("%s connected" % listen["message"])
					return
					

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	# listen for available connections
	if tserver.is_connection_available():
		var ear = tserver.take_connection()
		var new_ws_connection = WebSocketPeer.new()
		new_ws_connection.accept_stream(ear)
		
	for n in len(connection_list):
		connection_list[n]["connector"].poll()
		var state = connection_list[n]["connector"].get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			while connection_list[n]["connector"].get_available_packet_count():
				var incoming = connection_list[n]["connector"].get_var()
				if incoming["purpose"] == "host":
					var settings = incoming["message"]
					var new_id = randi_range(1000, 9999)
					while room_list.find_key(new_id) != null:
						new_id = randi_range(1000, 9999)
					room_list[new_id] = {"host": n, "settings": settings}
					connection_list[n]["connector"].put_var(pack_data("host", new_id))
				elif incoming["purpose"] == "find":
					var id = incoming["message"]
					if room_list.find_key(id) != null:
						room_list[id]["guest"] = n
						var host = room_list[id]["host"]
						var host_name = connection_list[host]["name"]
						var settings = room_list[id]["settings"]
						connection_list[n]["connector"].put_var(pack_data("match", {"opponent": host_name, "settings": settings}))
					else:
						connection_list[n]["connector"].put_var(pack_data("failure", []))
				elif incoming["purpose"] == "play":
					var room_id = incoming["message"]["room_id"]
					var side = incoming["message"]["side"] # reversed, because implementation details
					var wager = incoming["message"]["wager"]
					var peer = connection_list[room_list[room_id][side]]["connector"]
					peer.put_var(pack_data("play", wager))
					pass
				
		elif state == WebSocketPeer.STATE_CLOSING:
			# Keep polling to achieve proper close.
			pass
		elif state == WebSocketPeer.STATE_CLOSED:
			var code = connection_list[n]["connector"].get_close_code()
			var reason = connection_list[n]["connector"].get_close_reason()
			print("WebSocket closed with code: %d, reason %s. Clean: %s" % [code, reason, code != -1])
			connection_list.remove_at(n)
		pass
	
