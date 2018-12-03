var _output_dir = null
var _stubber = null
var _double_count = 0
var _use_unique_names = true
var _spy = null

const LOCAL_METHOD = 1
const SUPER_METHOD = 2

# These methods should not be doubled, EVEN if they are overloaded.
var _blacklist = [
	# # from Object
	# 'add_user_signal',
	# 'has_user_signal',
	# 'emit_signal',
	# 'get_signal_connection_list',
	# 'connect',
	# 'disconnect',
	# 'is_connected',
	#
	# # from Node2D
	# 'draw_char',
	#
	# # found during other testing.
	# 'call',
	# '_ready',
	
	'has_method',
	'get_script',
	'get',
	'_notification',
	'get_path',
	'_enter_tree',
	'_exit_tree',
]

var ARGS = 'args'
var FLAGS = 'flags'
var NAME = 'name'
# ###############
# Private
# ###############
func _get_indented_line(indents, text):
	var to_return = ''
	for i in range(indents):
		to_return += "\t"
	return str(to_return, text, "\n")

func _write_file(target_path, dest_path, override_path=null):
	var script_methods = _get_methods(target_path)

	var metadata = _get_stubber_metadata_text(target_path)
	if(override_path):
		metadata = _get_stubber_metadata_text(override_path)

	var f = File.new()
	f.open(dest_path, f.WRITE)
	f.store_string(str("extends '", target_path, "'\n"))
	f.store_string(metadata)
	for i in range(script_methods.local.size()):
		f.store_string(_get_func_text(script_methods.local[i], LOCAL_METHOD))
	f.store_string("# ------\n")
	f.store_string("# start super methods\n")
	f.store_string("# ------\n")
	for i in range(script_methods.super.size()):
		f.store_string(_get_func_text(script_methods.super[i], SUPER_METHOD))

	f.close()

func _double_scene_and_script(target_path, dest_path):
	var dir = Directory.new()
	dir.copy(target_path, dest_path)

	var inst = load(target_path).instance()
	var script_path = null
	if(inst.get_script()):
		script_path = inst.get_script().get_path()
	inst.free()

	if(script_path):
		var double_path = _double(script_path, target_path)
		var dq = '"'
		var f = File.new()
		f.open(dest_path, f.READ)
		var source = f.get_as_text()
		f.close()

		source = source.replace(dq + script_path + dq, dq + double_path + dq)

		f.open(dest_path, f.WRITE)
		f.store_string(source)
		f.close()

	return script_path

class SimpleObject:
	var a = 'a'

func _get_methods(target_path):
	var all_methods = {
		local = [],
		super = []
	}
	var object_methods = SimpleObject.new().get_method_list()
	var methods_in_object = []
	for i in range(object_methods.size()):
		methods_in_object.append(object_methods[i][NAME])


	var obj = load(target_path).new()
	# hold just the names so we can avoid duplicates.
	var method_names = []

	var methods = obj.get_method_list()

	# get all the locally defined methods first
	for i in range(methods.size()):
		# 65 is a magic number for methods in script, though documentation
		# says 64.  This picks up local overloads of base class methods too.
		var flag = methods[i][FLAGS]
		var name = methods[i][NAME]
		if(flag == 65 and !method_names.has(name)):
			all_methods.local.append(methods[i])
			method_names.append(name)

	# anything we haven't already added to local methods we then add
	# to the super's methods
	for i in range(methods.size()):
		var flag = methods[i][FLAGS]
		var name = methods[i][NAME]
		if(!method_names.has(name) and !_blacklist.has(name)):
			all_methods.super.append(methods[i])
			method_names.append(name)

	return all_methods

func _get_inst_id_ref_str(inst):
	var ref_str = 'null'
	if(inst):
		ref_str = str('instance_from_id(', inst.get_instance_id(),')')
	return ref_str

func _get_stubber_metadata_text(target_path):
	return "var __gut_metadata_ = {\n" + \
           "\tpath='" + target_path + "',\n" + \
		   "\tstubber=" + _get_inst_id_ref_str(_stubber) + ",\n" + \
		   "\tspy=" + _get_inst_id_ref_str(_spy) + "\n" + \
           "}\n"

func _get_callback_parameters(method_hash):
	var called_with = 'null'
	if(method_hash[ARGS].size() > 0):
		called_with = '['
		for i in range(method_hash[ARGS].size()):
			called_with += 'p_' + method_hash[ARGS][i][NAME]
			if(i < method_hash[ARGS].size() - 1):
				called_with += ', '
		called_with += ']'
	return called_with

func _get_super_call_parameters(method_hash):
	var params = ''
	for i in range(method_hash[ARGS].size()):
		params += 'p_' + method_hash[ARGS][i][NAME]
		if(method_hash[ARGS].size() > 1 and i != method_hash[ARGS].size() -1):
			params += ', '
	return params

func _get_func_text(method_hash, method_type):
	var ftxt = str('func ', method_hash[NAME], '(')
	ftxt += str(_get_arg_text(method_hash[ARGS]), "):\n")

	var called_with = _get_callback_parameters(method_hash)
	if(_spy):
		var call_spy = "__gut_metadata_.spy.add_call(self, '" + method_hash[NAME] + "', " + called_with + ")"
		ftxt += _get_indented_line(1, call_spy)

	var return_stubbed_value = "return __gut_metadata_.stubber.get_return(self, '" + method_hash[NAME] + "', " + called_with + ")\n"
	if(method_type == LOCAL_METHOD):
		if(_stubber):
			ftxt += _get_indented_line(1, return_stubbed_value)
		elif(!_spy):
			ftxt += _get_indented_line(1, "pass")

	var call_super_text = str("return .", method_hash[NAME], "(", _get_super_call_parameters(method_hash), ")\n")
	if(method_type == SUPER_METHOD):
		if(_stubber):
			ftxt += _get_indented_line(1, str("if(__gut_metadata_.stubber.is_stubbed(self,\"", method_hash[NAME], "\")):"))
			ftxt += _get_indented_line(2, return_stubbed_value)
			ftxt += _get_indented_line(1, "else:")
			ftxt += _get_indented_line(2, call_super_text)

		else:
			ftxt += _get_indented_line(1, call_super_text)

	return ftxt

func _get_arg_text(args):
	var text = ''
	for i in range(args.size()):
		text += 'p_' + args[i][NAME] + ' = null'
		if(i != args.size() -1):
			text += ', '
	return text

func _get_temp_path(path):
	var file_name = path.get_file()
	if(_use_unique_names):
		file_name = file_name.get_basename() + \
		            str('__dbl', _double_count, '__.') + file_name.get_extension()
	var to_return = _output_dir.plus_file(file_name)
	return to_return

func _double(obj, override_path=null):
	var temp_path = _get_temp_path(obj)
	_write_file(obj, temp_path, override_path)
	_double_count += 1
	return temp_path

# ###############
# Public
# ###############
func get_output_dir():
	return _output_dir

func set_output_dir(output_dir):
	_output_dir = output_dir
	var d = Directory.new()
	d.make_dir_recursive(output_dir)

func get_spy():
	return _spy

func set_spy(spy):
	_spy = spy

func get_stubber():
	return _stubber

func set_stubber(stubber):
	_stubber = stubber

func double_scene(path):
	var temp_path = _get_temp_path(path)
	_double_scene_and_script(path, temp_path)
	return load(temp_path)

func double(path):
	return load(_double(path))

func clear_output_directory():
	var d = Directory.new()
	d.open(_output_dir)
	d.list_dir_begin(true)
	var files = []
	var f = d.get_next()
	while(f != ''):
		d.remove(f)
		f = d.get_next()

func delete_output_directory():
	clear_output_directory()
	var d = Directory.new()
	d.remove(_output_dir)

func set_use_unique_names(should):
	_use_unique_names = should
