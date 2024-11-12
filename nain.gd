extends Node
@export var buffer_size:int=1048560*8
var ws =WebSocketPeer.new()
var last_state = WebSocketPeer.STATE_CLOSED
#var uid_list:Array[String]=[]
var stock_message=[0,0,0]  #总股数，总金，单股价格
#房间信息缓存
var room_message_cache:Array=[]
#房间信息缓存大小
var room_message_cache_size:int=30
#添加缓存
func put_room_cache(room_mes_dic:Dictionary):
	room_message_cache.append(room_mes_dic)
	if room_message_cache.size()>room_message_cache_size:
		room_message_cache.pop_front()

var inpackeg={
	"r":"66234e757a3ce", #房间标识
	"n":"",				#名字
	"p":"",				#密码
	"cp":"",
	"nt":"",
	"st":"n",
	"mo":"",
	"mb":"1",
	"mu":"01",
	"rp":"",
	"vc":"1092",
	"fp":"@"
}


@onready var R_thread:Thread=Thread.new()
var next_room:String=""
var is_login:bool=false
var is_in_logging:bool=false
signal connected_to_server
signal connection_closed(rea:Array)
signal message_received(pac:PackedByteArray)
signal login_success
signal room_message_received(arr:Array)
signal side_message_received(arr:Array)
signal bullet_message_received(arr:Array)
signal stock_update
#是否需要打印debug信息
var need_debug_message:bool=true
func re_init_export():
	inpackeg["p"]=inpackeg["p"].md5_text()
	inpackeg["fp"]="@"+str(randf()).md5_text()
##设置信息
func set_information(name_:String,p:String,room:String):
	inpackeg["r"]=room
	inpackeg["n"]=name_
	inpackeg["p"]=p
	re_init_export()
func set_buffer_size(innum:int):
	ws.inbound_buffer_size=innum
	ws.outbound_buffer_size=innum
func start_connect():
	ws=null
	is_in_logging=true
	ws=WebSocketPeer.new()
	set_buffer_size(buffer_size)
	last_state = WebSocketPeer.STATE_CLOSED
	is_login=false
	ws.connect_to_url("wss://m1.iirose.com:8778",TLSOptions.client())
	if need_debug_message:
		print("正在连接蔷薇ws服务器...")
func send_in_pack():
	if need_debug_message:
		print("正在向蔷薇发送登陆包...")
	if ws.get_ready_state()==WebSocketPeer.STATE_OPEN:
		var str=("*"+JSON.stringify(inpackeg)).to_utf8_buffer()
		ws.send(str)
		if need_debug_message:
			print("登录包发送成功.")
	else:
		if need_debug_message:
			print("错误：还未与蔷薇ws建立链接或链接已断开")
func _ready() -> void:
	set_buffer_size(buffer_size)
	R_thread.start(OS.read_string_from_stdin)
func _process(delta: float) -> void:
	if not R_thread.is_alive():
		var str:String=R_thread.wait_to_finish()
		R_thread.start(OS.read_string_from_stdin)
		process_cmd(str)
	poll()
func get_gzip(pkg:PackedByteArray):
	var gzip=StreamPeerGZIP.new()
	gzip.clear()
	gzip.start_compression(buffer_size)
	gzip.put_partial_data(pkg)
	var new_pck=PackedByteArray()
	gzip.finish()
	while(gzip.get_available_bytes()>0):
		new_pck.append_array(gzip.get_partial_data(gzip.get_available_bytes())[1])
	gzip.clear()
	return new_pck
func get_string_from_packeg(pkg:PackedByteArray):
	var text:String
	if pkg[0]==1:
		#text=get_ungzip(pkg).get_string_from_utf8()
		var new_pkg=pkg
		new_pkg.remove_at(0)
		new_pkg=new_pkg.decompress_dynamic(-1,3)
		text=new_pkg.get_string_from_utf8()
		pass
	else:
		text=pkg.get_string_from_utf8()
	exe_message(text)
	pass

func want_stock():
	if need_debug_message:
		print_rich("[color=yellow]》》》》尝试向蔷薇申请股票信息[/color]")
	sent_str(">#")
func _on_ping_timeout() -> void:
	if ws.get_ready_state()==WebSocketPeer.STATE_OPEN:
		ws.send_text("s")
	pass # Replace with function body.


func exe_message(txt:String):
	var dic:Array=[]
	if txt.begins_with('%*"'):
		match txt[3]:
			"*":
				if not is_login:
					if need_debug_message:
						print("登录成功！")
					is_login=true
					login_success.emit()
				#var spl=txt.split("<")
				#for i  in range(1,spl.size()) :
					##print(spl)
					#var new_spl=spl[i].split(">")
					#if new_spl.size()>=9:
						#uid_list.append(new_spl[8])D
			"s":
				if not is_login:
					if need_debug_message:
						print("房间错误，尝试与蔷薇服务器给予的新房间重新建立链接...")
					var new_room=txt.split(">")[0]
					new_room=new_room.right(new_room.length()-4)
					inpackeg["r"]=new_room
					ws.close()
		#%*"0	名字被占用
		#%*"1	用户不存在
		#%*"2	密码错误
		#%*"4	今日可尝试登录次数达到上限
		#%*"5	房间密码错误
		#%*"x(到期时间)#(原因)	账户被封禁
		#%*"6	房间不存在
			"0":
				if need_debug_message:
					print("名字被占用，请重新登录")
				is_in_logging=false
				ws.close()
				ws=null
				pass
			"1":
				if need_debug_message:
					print("用户不存在，请重新登录")
				is_in_logging=false
				ws.close()
				pass
			"2":
				if need_debug_message:
					print("密码错误，请重新登录")
				is_in_logging=false
				ws.close()
				pass
			"3":
				if need_debug_message:
					print("尝试登录次数达到上限")
				is_in_logging=false
				ws.close()
				pass
			"4":
				if need_debug_message:
					print("房间错误，请重新输入房间信息")
				is_in_logging=false
				ws.close()
				pass
			"5":
				if need_debug_message:
					print("房间密码错误")
				is_in_logging=false
				ws.close()
				pass
			"6":
				if need_debug_message:
					print("房间错误，请重新输入房间信息")
				is_in_logging=false
				ws.close()
	elif txt.begins_with('"'):
		
		var new_text=txt.right(txt.length()-1)
		if new_text.begins_with('"'):
			new_text=txt.right(txt.length()-1)
			#if need_debug_message:
				#print_rich("[color=white]《《《《私聊信息：[/color]"+new_text)
			var txt_arr=new_text.split("<")
			var side_dic_array:Array[Dictionary]=[]
			for i in txt_arr:
				var new_dic={}
				var spl=i.split(">")
				new_dic["name"]=spl[2]
				new_dic["message"]=spl[4]
				new_dic["head"]=spl[3]
				new_dic["uid"]=spl[1]
				side_dic_array.append(new_dic)
			#if need_debug_message:
				#print_rich("[color=white]《《《《私聊信息处理结果：[/color]",side_dic_array)
			side_message_received.emit(side_dic_array)
		else:
			#if need_debug_message:
				#print_rich("[color=yellow]《《《《房间信息：[/color]"+new_text)
			var txt_arr=new_text.split("<")
			var room_dic_array:Array[Dictionary]=[]
			for i in txt_arr:
				var new_dic={}
				var spl=i.split(">")
				new_dic["name"]=spl[2]
				new_dic["message"]=spl[3]
				new_dic["head"]=spl[1]
				new_dic["uid"]=spl[8]
				room_dic_array.append(new_dic)
			#if need_debug_message:
				#print_rich("[color=yellow]《《《《房间信息处理结果：[/color]",room_dic_array)
			room_message_received.emit(room_dic_array)
	elif txt.begins_with("="):
		var new_text=txt.right(txt.length()-1)
		#if need_debug_message:
			#print_rich("[color=blue]《《《《弹幕信息：[/color]"+new_text)
		var txt_arr=new_text.split("<")
		var bullet_dic_array:Array[Dictionary]=[]
		for i in txt_arr:
			var new_dic={}
			var spl=i.split(">")
			new_dic["name"]=spl[0]
			new_dic["message"]=spl[1]
			new_dic["head"]=spl[5]
			new_dic["uid"]=spl[7]
			bullet_dic_array.append(new_dic)
		bullet_message_received.emit(bullet_dic_array)
		#if need_debug_message:
			#print_rich("[color=blue]《《《《弹幕信息处理结果：[/color]",bullet_dic_array)
	elif txt.begins_with(">"):
		var new_text=txt.right(txt.length()-1)
		#if need_debug_message:
			#print_rich("[color=teal]《《《《股票消息：[/color]"+new_text)
		var spl=new_text.split('"')
		stock_message[0]=int(spl[0])
		stock_message[1]=float(spl[1])
		stock_message[2]=float(spl[2])
		#if need_debug_message:
			#print_rich("[color=teal]《《《《股票消息处理结果：[/color]",stock_message)
		stock_update.emit()
	elif txt.begins_with("m"):
		if txt.length()==1:
			inpackeg["r"]=next_room
			ws.close()
			pass
		
		pass
	else:
		if txt.length()>=100:
			if not is_login:
				if need_debug_message:
					print_rich("[color=green]》》》》登录成功！[/color]")
				is_login=true
				login_success.emit()
		else:
			#print(txt)
			#debug_message.emit(txt)
			pass
	pass
func poll() -> void:
	if ws.get_ready_state() != ws.STATE_CLOSED:
		ws.poll()
	var state = ws.get_ready_state()
	if last_state != state:
		last_state = state
		if state == ws.STATE_OPEN:
			connected_to_server.emit()
		elif state == ws.STATE_CLOSED:
			var code = ws.get_close_code()
			var reason = ws.get_close_reason()
			var res=[code, reason]
			connection_closed.emit(res)
	while ws.get_ready_state() == ws.STATE_OPEN and ws.get_available_packet_count():
		message_received.emit(get_message())
func get_message() -> PackedByteArray:
	if ws.get_available_packet_count() < 1:
		return PackedByteArray()
	var pkt = ws.get_packet()
	return pkt
func connected():
	if is_in_logging:
		send_in_pack()
func closed(res:Array):
	if is_in_logging:
		is_login=false
		ws.connect_to_url("wss://m1.iirose.com:8778",TLSOptions.client())
		if need_debug_message:
			print("断开链接")
			print(str(res))
func get_mes(pac:PackedByteArray):
	get_string_from_packeg(pac)
func sent_popup(mes:String):
	var x:Dictionary={
		"t":"test","c":"040b02","v":0
	}
	x["t"]=mes
	ws.send_text("~"+JSON.stringify(x))
func sent_tu(uid:String,mes:String=""):
	if need_debug_message:
		print("》》》》尝试给用户"+uid+"点赞")
	if ws.get_ready_state()==WebSocketPeer.STATE_OPEN:
		sent_str("+*"+uid+""+mes)
func sent_str(txt:String):
	if ws.get_ready_state()==WebSocketPeer.STATE_OPEN:
		var err=ws.send_text(txt)
func sent_room_message(mes:String,color:String="ffffff"):
	if need_debug_message:
		print("》》》》尝试向蔷薇发送房间消息："+mes)
	var room_dic={}	 #{"m":"(消息内容)","mc":"(消息颜色)","i":"(随机数)"}	
	room_dic["m"]=mes
	room_dic["mc"]=color
	var z=str(randf())
	z=z.left(14)
	z=z.right(z.length()-2)
	room_dic["i"]=z
	sent_str(JSON.stringify(room_dic))
func sent_bullet_message(mes:String,color:String="ffffff"):
	if need_debug_message:
		print("》》》》尝试向蔷薇发送弹幕消息："+mes)
	var bullet_dic={} #~{"t":"(消息内容)","c":"(消息颜色)","v":0}
	bullet_dic["t"]=mes
	bullet_dic["c"]=color
	bullet_dic["v"]=0
	sent_str("~"+JSON.stringify(bullet_dic))
func sent_side_message(uid:String,mes:String,color:String="ffffff"):
	if need_debug_message:
		print("》》》》尝试向用户["+uid+"]发送私聊消息："+mes)
	var side_dic={} 
	side_dic["g"]=uid
	side_dic["m"]=mes
	side_dic["mc"]=color
	var z=str(randf())
	z=z.left(14)
	z=z.right(z.length()-2)
	side_dic["i"]=z
	sent_str(JSON.stringify(side_dic))
func ping():
	if ws.get_ready_state()==WebSocketPeer.STATE_OPEN:
		sent_str("s")
func get_self_name()->String:
	return inpackeg["n"]



func move_to_room(r:String):
	next_room=r
	sent_str("m"+r)


func _on_timer_timeout() -> void:
	ping()
	pass # Replace with function body.


##去除字符串两边的换行tab空格
func remove_tab(str:String)->String:
	var s:String=str
	while s.begins_with("\t") or s.begins_with("\r") or s.begins_with("\n") or s.begins_with(" "):
		s=s.right(s.length()-1)
	while s.ends_with("\t") or s.ends_with("\r") or s.ends_with("\n")  or s.ends_with(" "):
		s=s.left(s.length()-1)
	return s

##处理指令行
func process_cmd(str:String):
	var s=remove_tab(str)
	var arr:PackedStringArray=s.split(" ")
	if not arr.is_empty() and arr[0] in cmd_func_dic:
		var function=cmd_func_dic[arr[0]]
		if function is Callable:
			function.call(arr)
		else:
			print("无法识别的指令")
var cmd_func_dic:Dictionary={
	"help":help,
	"login":login,
	"mes":mes,
	"quit":quit_login,
}
const help_mes:String="""
	"help":帮助
	"login 用户名 密码 房间":登录
	"mes":查看当前登录状态
	"quit"：退出登录
"""
func mes(arr:PackedStringArray):
	print("当前登录状态："+str(is_login))
	if is_login:
		print("当前登录用户："+str(inpackeg["n"]))
	
	pass

func login(arr:PackedStringArray):
	if arr.size()<4:
		return 
	set_information(arr[1],arr[2],arr[3])
	start_connect()
	pass

func quit_login(arr:PackedStringArray):
	print("退出登录")
	is_login=false
	ws.close()
	ws=null
	is_in_logging=false
	ws=WebSocketPeer.new()
	set_buffer_size(buffer_size)
	pass
func help(arr:PackedStringArray):
	print(help_mes)
