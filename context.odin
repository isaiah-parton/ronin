package ronin

import kn "../katana"
import "base:runtime"
import "core:container/small_array"
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:sys/windows"
import "core:time"
import "tedit"
import "vendor:fontstash"
import "vendor:glfw"
import "vendor:wgpu"
import "vendor:wgpu/glfwglue"

EMBED_DEFAULT_FONTS :: #config(RONIN_EMBED_FONTS, false)
FONT_PATH :: #config(RONIN_FONT_PATH, "fonts")
MAX_IDS :: 32
MAX_LAYERS :: 100
MAX_LAYOUTS :: 100
MAX_PANELS :: 100
DEFAULT_DESIRED_FPS :: 75

Stack :: struct($T: typeid, $N: int) {
	items:  [N]T,
	height: int,
}

push_stack :: proc(stack: ^Stack($T, $N), item: T) -> bool {
	if stack.height >= N {
		return false
	}
	stack.items[stack.height] = item
	stack.height += 1
	return true
}

pop_stack :: proc(stack: ^Stack($T, $N)) {
	stack.height -= 1
}

inject_stack :: proc(stack: ^Stack($T, $N), at: int, item: T) -> bool {
	if at == stack.height {
		return push_stack(stack, item)
	}
	copy(stack.items[at + 1:], stack.items[at:])
	stack.items[at] = item
	stack.height += 1
	return true
}

clear_stack :: proc(stack: ^Stack($T, $N)) {
	stack.height = 0
}

Wave_Effect :: struct {
	point: [2]f32,
	time:  f32,
}

ctx: Context

Context :: struct {
	ready:                    bool,
	window:                   glfw.WindowHandle,
	window_x:                 i32,
	window_y:                 i32,
	window_width:             i32,
	window_height:            i32,
	debug:                    Debug_State,
	view:                     [2]f32,
	desired_fps:              int,
	platform:                 kn.Platform,
	disable_frame_skip:       bool,
	delta_time:               f32,
	last_frame_time:          time.Time,
	start_time:               time.Time,
	last_second:              time.Time,
	frame_duration:           time.Duration,
	frames_so_far:            int,
	frames_this_second:       int,
	id_stack:                 Stack(Id, MAX_IDS),
	objects:                  [2048]Maybe(Object),
	object_map:               map[Id]^Object,
	object_stack:             Stack(^Object, 128),
	object_index:             int,
	last_hovered_object:      Id,
	hovered_object:           Id,
	next_hovered_object:      Id,
	last_activated_object:    Id,
	last_focused_object:      Id,
	focused_object:           Id,
	next_focused_object:      Id,
	dragged_object:           Id,
	pressed_object:           Id,
	disable_objects:          bool,
	drag_offset:              [2]f32,
	mouse_press_point:        [2]f32,
	form:                     Form,
	form_active:              bool,
	tooltip_boxes:            [dynamic]Box,
	panels:                   [MAX_PANELS]Maybe(Panel),
	panel_map:                map[Id]^Panel,
	panel_stack:              Stack(^Panel, MAX_PANELS),
	panel_snapping:           Panel_Snap_State,
	layout_stack:             Stack(Layout, MAX_LAYOUTS),
	options_stack:            Stack(Options, MAX_LAYOUTS),
	next_box:                 Maybe(Box),
	press_on_hover:           bool,
	next_id:                  Maybe(Id),
	group_stack:              Stack(Group, 32),
	focus_next:               bool,
	layer_array:              [dynamic]^Layer,
	layer_map:                map[Id]^Layer,
	layer_stack:              Stack(^Layer, MAX_LAYERS),
	last_layer_counts:        [Layer_Sort_Method]int,
	layer_counts:             [Layer_Sort_Method]int,
	hovered_layer_index:      int,
	highest_layer_index:      int,
	last_highest_layer_index: int,
	last_hovered_layer:       Id,
	hovered_layer:            Id,
	next_hovered_layer:       Id,
	focused_layer:            Id,
	clip_stack:               Stack(Box, 128),
	current_object_clip:      Box,
	cursor_type:              Mouse_Cursor,
	mouse_button:             Mouse_Button,
	last_mouse_pos:           [2]f32,
	mouse_pos:                [2]f32,
	click_mouse_pos:          [2]f32,
	mouse_delta:              [2]f32,
	mouse_scroll:             [2]f32,
	mouse_bits:               Mouse_Bits,
	last_mouse_bits:          Mouse_Bits,
	mouse_release_time:       time.Time,
	keys, last_keys:          #sparse[Keyboard_Key]bool,
	runes:                    [dynamic]rune,
	visible:                  bool,
	focused:                  bool,
	style:                    Style,
	user_images:              [100]Maybe(Box),
	text_editor:              tedit.Editor,
	frames_to_draw:           int,
	frames:                   int,
	drawn_frames:             int,
	cursors:                  [Mouse_Cursor]glfw.CursorHandle,
	text_content_builder:     Text_Content_Builder,
}

seconds :: proc() -> f64 {
	return time.duration_seconds(time.diff(ctx.start_time, ctx.last_frame_time))
}

draw_frames :: proc(how_many: int) {
	ctx.frames_to_draw = max(ctx.frames_to_draw, how_many)
}

view_box :: proc() -> Box {
	return Box{{}, ctx.view}
}

view_width :: proc() -> f32 {
	return ctx.view.x
}

view_height :: proc() -> f32 {
	return ctx.view.y
}

focus_next_object :: proc() {
	ctx.focus_next = true
}

load_default_fonts :: proc() -> bool {
	DEFAULT_FONT :: "Roboto-Regular"
	BOLD_FONT :: "Roboto-Medium"
	MONOSPACE_FONT :: "RobotoMono-Regular"
	HEADER_FONT :: "RobotoSlab-Regular"
	ICON_FONT :: "icons"

	DEFAULT_FONT_IMAGE :: #load(FONT_PATH + "/" + DEFAULT_FONT + ".png", []u8)
	BOLD_FONT_IMAGE :: #load(FONT_PATH + "/" + BOLD_FONT + ".png", []u8)
	MONOSPACE_FONT_IMAGE :: #load(FONT_PATH + "/" + MONOSPACE_FONT + ".png", []u8)
	HEADER_FONT_IMAGE :: #load(FONT_PATH + "/" + HEADER_FONT + ".png", []u8)
	ICON_FONT_IMAGE :: #load(FONT_PATH + "/" + ICON_FONT + ".png", []u8)

	DEFAULT_FONT_JSON :: #load(FONT_PATH + "/" + DEFAULT_FONT + ".json", []u8)
	BOLD_FONT_JSON :: #load(FONT_PATH + "/" + BOLD_FONT + ".json", []u8)
	MONOSPACE_FONT_JSON :: #load(FONT_PATH + "/" + MONOSPACE_FONT + ".json", []u8)
	HEADER_FONT_JSON :: #load(FONT_PATH + "/" + HEADER_FONT + ".json", []u8)
	ICON_FONT_JSON :: #load(FONT_PATH + "/" + ICON_FONT + ".json", []u8)

	ctx.style.default_font = kn.load_font_from_slices(
		DEFAULT_FONT_IMAGE,
		DEFAULT_FONT_JSON,
	) or_return
	ctx.style.bold_font = kn.load_font_from_slices(BOLD_FONT_IMAGE, BOLD_FONT_JSON) or_return
	ctx.style.monospace_font = kn.load_font_from_slices(
		MONOSPACE_FONT_IMAGE,
		MONOSPACE_FONT_JSON,
	) or_return
	// ctx.style.header_font = kn.load_font_from_slices(
	// 	HEADER_FONT_IMAGE,
	// 	HEADER_FONT_JSON,
	// ) or_return
	ctx.style.header_font = ctx.style.bold_font
	ctx.style.icon_font = kn.load_font_from_slices(
		ICON_FONT_IMAGE,
		ICON_FONT_JSON,
		// true,
	) or_return

	kn.set_fallback_font(ctx.style.icon_font)

	return true
}

start :: proc(window: glfw.WindowHandle, style: Maybe(Style) = nil) -> bool {
	if window == nil do return false

	ctx.window = window
	width, height := glfw.GetWindowSize(ctx.window)

	ctx.visible = true
	ctx.focused = true
	ctx.view = {f32(width), f32(height)}
	ctx.last_frame_time = time.now()
	ctx.start_time = time.now()

	ctx.cursors[.Normal] = glfw.CreateStandardCursor(glfw.ARROW_CURSOR)
	ctx.cursors[.Crosshair] = glfw.CreateStandardCursor(glfw.CROSSHAIR_CURSOR)
	ctx.cursors[.Pointing_Hand] = glfw.CreateStandardCursor(glfw.POINTING_HAND_CURSOR)
	ctx.cursors[.I_Beam] = glfw.CreateStandardCursor(glfw.IBEAM_CURSOR)
	ctx.cursors[.Resize_EW] = glfw.CreateStandardCursor(glfw.RESIZE_EW_CURSOR)
	ctx.cursors[.Resize_NS] = glfw.CreateStandardCursor(glfw.RESIZE_NS_CURSOR)
	ctx.cursors[.Resize_NESW] = glfw.CreateStandardCursor(glfw.RESIZE_NESW_CURSOR)
	ctx.cursors[.Resize_NWSE] = glfw.CreateStandardCursor(glfw.RESIZE_NWSE_CURSOR)

	glfw.SetWindowIconifyCallback(
		ctx.window,
		proc "c" (_: glfw.WindowHandle, _: i32) {ctx.visible = false},
	)
	glfw.SetWindowFocusCallback(
		ctx.window,
		proc "c" (_: glfw.WindowHandle, _: i32) {ctx.visible = true},
	)
	glfw.SetWindowMaximizeCallback(
		ctx.window,
		proc "c" (_: glfw.WindowHandle, _: i32) {ctx.visible = true},
	)
	glfw.SetScrollCallback(ctx.window, proc "c" (_: glfw.WindowHandle, x, y: f64) {
		context = runtime.default_context()
		ctx.mouse_scroll = {f32(x), f32(y)}
		draw_frames(2)
	})
	glfw.SetWindowSizeCallback(ctx.window, proc "c" (_: glfw.WindowHandle, width, height: i32) {
		context = runtime.default_context()

		width := max(width, 1)
		height := max(height, 1)

		ctx.platform.surface_config.width = u32(width)
		ctx.platform.surface_config.height = u32(height)
		wgpu.SurfaceConfigure(ctx.platform.surface, &ctx.platform.surface_config)

		ctx.view = {f32(width), f32(height)}
		draw_frames(1)
	})
	glfw.SetCharCallback(ctx.window, proc "c" (_: glfw.WindowHandle, char: rune) {
		context = runtime.default_context()
		append(&ctx.runes, char)
		draw_frames(2)
	})
	glfw.SetKeyCallback(ctx.window, proc "c" (_: glfw.WindowHandle, key, _, action, _: i32) {
		context = runtime.default_context()
		draw_frames(2)
		if key < 0 {
			return
		}
		switch action {
		case glfw.PRESS:
			ctx.keys[Keyboard_Key(key)] = true
			ctx.mouse_press_point = mouse_point()
		case glfw.RELEASE:
			ctx.keys[Keyboard_Key(key)] = false
		case glfw.REPEAT:
			ctx.keys[Keyboard_Key(key)] = true
			ctx.last_keys[Keyboard_Key(key)] = false
		}
	})
	glfw.SetCursorPosCallback(ctx.window, proc "c" (_: glfw.WindowHandle, x, y: f64) {
		context = runtime.default_context()
		ctx.mouse_pos = {f32(x), f32(y)}
		draw_frames(2)
	})
	glfw.SetMouseButtonCallback(
		ctx.window,
		proc "c" (_: glfw.WindowHandle, button, action, _: i32) {
			context = runtime.default_context()
			draw_frames(2)
			switch action {
			case glfw.PRESS:
				ctx.mouse_button = Mouse_Button(button)
				ctx.mouse_bits += {Mouse_Button(button)}
				ctx.click_mouse_pos = ctx.mouse_pos
			case glfw.RELEASE:
				ctx.mouse_release_time = time.now()
				ctx.mouse_bits -= {Mouse_Button(button)}
			}
		},
	)

	ctx.platform = kn.make_platform_glfwglue(ctx.window)

	kn.start_on_platform(ctx.platform)

	if style == nil {
		ctx.style.color = dark_color_scheme()
		ctx.style.shape = default_style_shape()
		if !load_default_fonts() {
			fmt.printfln(
				"Fatal: failed to load default fonts from '%s'",
				filepath.abs(FONT_PATH) or_else "",
			)
			return false
		}
	} else {
		ctx.style = style.?
	}

	ctx.ready = true
	draw_frames(1)

	return true
}

new_frame :: proc() {
	if !ctx.disable_frame_skip {
		time.sleep(
			max(
				0,
				time.Duration(time.Second) /
					time.Duration(max(ctx.desired_fps, DEFAULT_DESIRED_FPS)) -
				time.since(ctx.last_frame_time),
			),
		)
	}

	profiler_scope(.New_Frame)

	now := time.now()
	ctx.frame_duration = time.diff(ctx.last_frame_time, now)
	ctx.delta_time = f32(time.duration_seconds(ctx.frame_duration))
	ctx.last_frame_time = now
	ctx.frames += 1
	ctx.frames_so_far += 1
	if time.since(ctx.last_second) >= time.Second {
		ctx.last_second = time.now()
		ctx.frames_this_second = ctx.frames_so_far
		ctx.frames_so_far = 0
	}

	reset_input()
	glfw.PollEvents()

	ctx.layer_stack.height = 0
	ctx.object_stack.height = 0
	ctx.panel_stack.height = 0
	ctx.options_stack.items[0] = default_options()

	reset_panel_snap_state(&ctx.panel_snapping)

	ctx.object_index = 0

	clear(&ctx.debug.hovered_objects)

	if (key_down(.Left_Control) || key_down(.Right_Control)) && key_pressed(.C) {
		set_clipboard_string(string(ctx.text_content_builder.buf[:]))
	}
	text_content_builder_reset(&ctx.text_content_builder)

	update_layers()
	update_layer_references()
	clean_up_objects()
	update_object_references()

	clear(&ctx.tooltip_boxes)

	if key_pressed(.Tab) {
		cycle_object_active(1 - int(key_down(.Left_Shift)) * 2)
	}

	if key_pressed(.Escape) {
		ctx.focused_object = 0
	}

	if key_pressed(.F3) {
		ctx.debug.enabled = !ctx.debug.enabled
		draw_frames(1)
	}

	if key_pressed(.F11) {
		monitor := glfw.GetWindowMonitor(ctx.window)
		if monitor == nil {
			monitor = glfw.GetPrimaryMonitor()
			mode := glfw.GetVideoMode(monitor)
			ctx.window_x, ctx.window_y = glfw.GetWindowPos(ctx.window)
			ctx.window_width, ctx.window_height = glfw.GetWindowSize(ctx.window)
			glfw.SetWindowMonitor(
				ctx.window,
				monitor,
				0,
				0,
				mode.width,
				mode.height,
				mode.refresh_rate,
			)
		} else {
			glfw.SetWindowMonitor(
				ctx.window,
				nil,
				ctx.window_x,
				ctx.window_y,
				ctx.window_width,
				ctx.window_height,
				0,
			)
		}
	}

	kn.new_frame()

	ctx.id_stack.height = 0
	ctx.layout_stack.height = 0
	ctx.object_stack.height = 0
	ctx.layer_stack.height = 0
	ctx.panel_stack.height = 0

	push_stack(&ctx.id_stack, FNV1A32_OFFSET_BASIS)
	begin_layer(.Back)
	push_stack(&ctx.layout_stack, Layout{box = view_box(), bounds = view_box(), side = .Top})

	profiler_begin_scope(.Construct)
}

cycle_object_active :: proc(increment: int = 1) {
	objects: [dynamic]^Object
	defer delete(objects)

	for &object in ctx.objects {
		if object, ok := &object.?; ok {
			if .Is_Input in object.flags {
				append(&objects, object)
			}
		}
	}

	slice.sort_by(objects[:], proc(i, j: ^Object) -> bool {
		return i.call_index < j.call_index
	})

	for i in 0 ..< len(objects) {
		objects[i].state.current -= {.Active}
		if objects[i].id == ctx.last_activated_object {
			j := i + increment
			for j < 0 do j += len(objects)
			for j >= len(objects) do j -= len(objects)
			object := objects[j]
			object.state.next += {.Active}
			object.input.editor.selection = {len(object.input.builder.buf), 0}
			break
		}
	}
}

present :: proc() {
	profiler_end_scope(.Construct)
	profiler_scope(.Render)

	when DEBUG {
		if ctx.debug.enabled {
			set_cursor(.Crosshair)
			if key_pressed(.F6) {
				ctx.disable_frame_skip = !ctx.disable_frame_skip
			}
			if key_pressed(.F7) {
				ctx.debug.wireframe = !ctx.debug.wireframe
			}
			draw_debug_stuff(&ctx.debug)
		}
	}

	if ctx.cursor_type == .None {
		glfw.SetInputMode(ctx.window, glfw.CURSOR, glfw.CURSOR_HIDDEN)
	} else {
		glfw.SetInputMode(ctx.window, glfw.CURSOR, glfw.CURSOR_NORMAL)
		glfw.SetCursor(ctx.window, ctx.cursors[ctx.cursor_type])
	}
	ctx.cursor_type = .Normal

	if ctx.frames_to_draw > 0 && ctx.visible {
		kn.present()
		ctx.drawn_frames += 1
		ctx.frames_to_draw -= 1
	}
}

shutdown :: proc() {
	if !ctx.ready {
		return
	}

	for &object in ctx.objects {
		if object, ok := &object.?; ok {
			destroy_object(object)
		}
	}
	delete(ctx.object_map)

	for layer in ctx.layer_array {
		destroy_layer(layer)
		free(layer)
	}

	delete(ctx.layer_array)
	delete(ctx.panel_map)
	delete(ctx.layer_map)
	delete(ctx.runes)

	kn.destroy_font(&ctx.style.default_font)
	kn.destroy_font(&ctx.style.monospace_font)
	kn.destroy_font(&ctx.style.icon_font)
	if font, ok := ctx.style.header_font.?; ok {
		kn.destroy_font(&font)
	}

	destroy_debug_state(&ctx.debug)

	kn.shutdown()

	kn.destroy_platform(&ctx.platform)
}

delta_time :: proc() -> f32 {
	return ctx.delta_time
}

should_close_window :: proc() -> bool {
	return bool(glfw.WindowShouldClose(ctx.window))
}

set_rounded_corners :: proc(corners: Corners) {
	get_current_options().radius = rounded_corners(corners)
}

user_focus_just_changed :: proc() -> bool {
	return ctx.focused_object != ctx.last_focused_object
}

set_clipboard_string :: proc(str: string) {
	cstr := strings.clone_to_cstring(str)
	defer delete(cstr)
	glfw.SetClipboardString(ctx.window, cstr)
}

__set_clipboard_string :: proc(_: rawptr, str: string) -> bool {
	cstr := strings.clone_to_cstring(str)
	defer delete(cstr)
	glfw.SetClipboardString(ctx.window, cstr)
	return true
}

__get_clipboard_string :: proc(_: rawptr) -> (str: string, ok: bool) {
	str = glfw.GetClipboardString(ctx.window)
	ok = len(str) > 0
	return
}

draw_shadow :: proc(box: kn.Box) {
	if kn.disable_scissor() {
		kn.add_box_shadow(
			move_box(box, 3),
			ctx.style.rounding,
			6,
			get_current_style().color.shadow,
		)
	}
}

