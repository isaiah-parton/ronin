package ronin

import "base:intrinsics"
import "base:runtime"
import "core:container/small_array"
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:mem"
import "core:reflect"
import "core:strings"
import "core:time"
import kn "local:katana"
import "tedit"

MAX_CLICK_DELAY :: time.Millisecond * 450

Object_Flag :: enum u8 {
	Is_Input,
	Hover_Through,
	Sticky_Press,
	Sticky_Hover,
	No_Tab_Cycle,
}

Object_Flags :: bit_set[Object_Flag;u8]

Object_Status :: enum u8 {
	Hovered,
	Focused,
	Pressed,
	Changed,
	Clicked,
	Open,
	Active,
	Dragged,
}

Object_Status_Set :: bit_set[Object_Status;u8]

OBJECT_STATE_ALL :: Object_Status_Set {
	.Hovered,
	.Focused,
	.Pressed,
	.Changed,
	.Clicked,
	.Open,
	.Active,
}

Object_Options :: struct {
	rounded_corners:  [4]f32,
	background_color: kn.Color,
	disabled:         bool,
}

Object_Variant :: union {
	Button,
	Boolean,
	Container,
	Color_Picker,
	Date_Picker,
	Calendar,
	Graph,
	Range_Slider,
	Slider,
	Carousel,
}

Object :: struct {
	variant:       Object_Variant,
	input:         Input_State,
	click:         Object_Click,
	animation:     Object_Animation,
	state:         Object_State,
	box:           Box,
	cut_size:      [2]f32,
	size:          [2]f32,
	layer:         ^Layer,
	hovered_time:  time.Time,
	call_index:    int,
	frames:        int,
	id:            Id,
	size_is_fixed: bool,
	dead:          bool,
	disabled:      bool,
	isolated:      bool,
	flags:         Object_Flags,
	side:          Side,
}

Object_State :: struct {
	current:     Object_Status_Set,
	next:        Object_Status_Set,
	previous:    Object_Status_Set,
	input_mask:  Object_Status_Set,
	output_mask: Object_Status_Set,
}

Object_Click :: struct {
	count:        int,
	release_time: time.Time,
	press_time:   time.Time,
	point:        [2]f32,
	button:       Mouse_Button,
	mods:         Mod_Keys,
}

Object_Animation :: struct {
	hover, press: f32,
}

Mod_Key :: enum {
	Control,
	Alt,
	Shift,
}
Mod_Keys :: bit_set[Mod_Key]

clean_up_objects :: proc() {
	for object, index in ctx.objects {
		if object.dead {
			destroy_object(object)
			delete_key(&ctx.object_map, object.id)
			unordered_remove(&ctx.objects, index)
			free(object)
			draw_frames(1)
		} else {
			object.dead = true
		}
	}
}

animate :: proc(value, duration: f32, condition: bool) -> f32 {
	value := value

	if condition {
		if value < 1 {
			draw_frames(2)
			value = min(1, value + ctx.delta_time * (1 / duration))
		}
	} else if value > 0 {
		draw_frames(2)
		value = max(0, value - ctx.delta_time * (1 / duration))
	}

	return value
}

animate_lerp :: proc(value, speed, target: f32) -> f32 {
	value := value

	diff := target - value
	draw_frames(int(abs(diff) > 0.01) * 2)

	value += diff * ctx.delta_time * speed

	return value
}

update_object_references :: proc() {
	if ctx.dragged_object != 0 {
		ctx.next_hovered_object = ctx.dragged_object
	}
	ctx.last_hovered_object = ctx.hovered_object
	ctx.hovered_object = ctx.next_hovered_object
	ctx.next_hovered_object = 0

	if ctx.mouse_bits - ctx.last_mouse_bits != {} {
		ctx.next_focused_object = ctx.hovered_object
	}

	ctx.last_focused_object = ctx.focused_object
	ctx.focused_object = ctx.next_focused_object
}

get_current_object :: proc() -> (^Object, bool) {
	if ctx.object_stack.height > 0 {
		return ctx.object_stack.items[ctx.object_stack.height - 1], true
	}
	return nil, false
}

last_object :: proc() -> Maybe(^Object) {
	return ctx.object_stack.items[ctx.object_stack.height]
}

new_object :: proc(id: Id) -> ^Object {
	object := new(Object)

	assert(object != nil)

	object.id = id
	object.state.output_mask = OBJECT_STATE_ALL

	append(&ctx.objects, object)
	ctx.object_map[id] = object

	draw_frames(1)

	return object
}

destroy_object :: proc(object: ^Object) {
	destroy_input(&object.input)
	object^ = {}
}

make_object_children_array :: proc() -> [dynamic]^Object {
	return make_dynamic_array_len_cap([dynamic]^Object, 0, 16, allocator = context.temp_allocator)
}

get_object :: proc(id: Id) -> ^Object {
	object := ctx.object_map[id] or_else new_object(id)
	return object
}

object_is_visible :: proc(object: ^Object) -> bool {
	return(
		ctx.visible &&
		get_clip(get_current_clip(), object.box) != .Full &&
		(object.box.lo.x < object.box.hi.x || object.box.lo.y < object.box.hi.y) \
	)
}

update_object_state :: proc(o: ^Object) {
	o.state.previous = o.state.current
	o.state.current -= {.Dragged, .Clicked, .Focused, .Changed, .Hovered}
	o.state.current += o.state.next
	o.state.next = {}

	if ctx.focused_object == o.id {
		o.state.current += {.Focused}
	}

	// if id, ok := ctx.object_to_activate.?; ok {
	// 	if id == object.id {
	// 		object.state.current += {.Active}
	// 		ctx.last_activated_object = object.id
	// 	} else {
	// 		object.state.current -= {.Active}
	// 	}
	// }

	if ctx.hovered_object == o.id {
		if get_current_options().hover_to_focus {
			if .Pressed not_in o.state.current {
				o.click.press_time = time.now()
				ctx.next_focused_object = o.id
			}
			o.state.current += {.Pressed}
			o.click.count = max(o.click.count, 1)
		}


		o.state.current += {.Hovered}

		pressed_buttons := ctx.mouse_bits - ctx.last_mouse_bits
		if pressed_buttons != {} {
			if o.click.button == ctx.mouse_button &&
			   time.since(o.click.release_time) <= MAX_CLICK_DELAY {
				o.click.count = max((o.click.count + 1) % 4, 1)
			} else {
				o.click.count = 1
			}

			o.click.mods = {}
			if key_down(.Left_Control) || key_down(.Right_Control) {
				o.click.mods += {.Control}
			}
			if key_down(.Right_Shift) || key_down(.Left_Shift) {
				o.click.mods += {.Shift}
			}
			if key_down(.Left_Alt) || key_down(.Right_Alt) {
				o.click.mods += {.Alt}
			}

			o.click.button = ctx.mouse_button
			o.click.point = ctx.mouse_pos
			o.click.press_time = time.now()

			o.state.current += {.Pressed}
			if .Sticky_Hover in o.flags {
				ctx.dragged_object = o.id
			}
			ctx.next_focused_object = o.id
			ctx.pressed_object = o.id

			draw_frames(1)
		}
		// TODO: Lose click if mouse moved too much (allow for dragging containers by their contents)
		// if !info.sticky && linalg.length(core.click_mouse_pos - core.mouse_pos) > 8 {
		// 	object.state -= {.Pressed}
		// 	object.click_count = 0
		// }
	} else {
		if ctx.dragged_object != o.id {
			o.state.current -= {.Hovered}
			o.click.count = 0
		}
		if .Sticky_Press not_in o.flags {
			o.state.current -= {.Pressed}
		}
	}

	if o.state.current >= {.Pressed} {
		released_buttons := ctx.last_mouse_bits - ctx.mouse_bits
		if released_buttons != {} {
			o.state.current += {.Clicked}
			o.state.current -= {.Pressed, .Dragged}
			o.click.release_time = time.now()
			ctx.dragged_object = 0
		}
	}
}

begin_object :: proc(object: ^Object) -> bool {
	assert(object != nil)

	object.call_index = ctx.object_index
	ctx.object_index += 1
	object.dead = false

	if object.frames >= ctx.frames {
		when ODIN_DEBUG {
			fmt.printfln("Object ID collision: %i", object.id)
		}
		return false
	}
	object.frames = ctx.frames

	if next_box, ok := ctx.next_box.?; ok {
		object.box = next_box
		ctx.next_box = nil
	} else {
		current_layout := get_current_layout()
		object.side = current_layout.side
		object.box = place_object_in_layout(object, current_layout)
		if object.box.lo.x >= object.box.hi.x || object.box.lo.y >= object.box.hi.y {
			return false
		}
	}

	object.layer = current_layer().? or_return

	update_object_state(object)

	if ctx.focus_next {
		ctx.focus_next = false
		object.state.current += {.Active}
		ctx.next_focused_object = object.id
	}

	if ctx.disable_objects do object.disabled = true

	push_stack(&ctx.object_stack, object) or_return

	return true
}

end_object :: proc() {
	if object, ok := get_current_object(); ok {
		if .Active in (object.state.current - object.state.previous) {
			ctx.last_activated_object = object.id
		}

		if group, ok := current_group().?; ok {
			group.current_state += object.state.current
			group.previous_state += object.state.previous
		}

		object.layer.state += object.state.current

		pop_stack(&ctx.object_stack)

		if parent, ok := get_current_object(); ok {
			parent.state.current += object_state_output(object.state) & parent.state.input_mask
		}
	}
}

@(deferred_out = __do_object)
do_object :: proc(object: ^Object) -> bool {
	return begin_object(object)
}

@(private)
__do_object :: proc(ok: bool) {
	if ok {
		end_object()
	}
}

object_state_output :: proc(state: Object_State) -> Object_Status_Set {
	return state.current & state.output_mask
}

new_state :: proc(state: Object_State) -> Object_Status_Set {
	return state.current - state.previous
}

lost_state :: proc(state: Object_State) -> Object_Status_Set {
	return state.previous - state.current
}

hover_object :: proc(object: ^Object) {
	if object.disabled do return
	if object.layer.index < ctx.hovered_layer_index do return
	if !point_in_box(ctx.mouse_pos, get_current_clip()) do return
	ctx.next_hovered_object = object.id
	ctx.next_hovered_layer = object.layer.id
	ctx.hovered_layer_index = object.layer.index
}

focus_object :: proc(object: ^Object) {
	ctx.next_focused_object = object.id
}

foreground :: proc(loc := #caller_location) {
	object := get_object(hash(loc))
	set_next_box(get_current_layout().box)
	if begin_object(object) {
		defer end_object()
		object.state.input_mask = OBJECT_STATE_ALL
		style := get_current_style()
		draw_shadow(object.box)
		kn.add_box(object.box, get_current_options().radius, paint = style.color.foreground)
		kn.add_box_lines(
			object.box,
			style.line_width,
			get_current_options().radius,
			paint = style.color.lines,
		)
		if point_in_box(ctx.mouse_pos, object.box) {
			hover_object(object)
		}
	}
}

background :: proc(loc := #caller_location) {
	object := get_object(hash(loc))
	set_next_box(get_current_layout().box)
	if begin_object(object) {
		defer end_object()
		object.state.input_mask = OBJECT_STATE_ALL
		style := get_current_style()
		kn.add_box(object.box, get_current_options().radius, paint = style.color.background)
		kn.add_box_lines(
			object.box,
			style.line_width,
			get_current_options().radius,
			paint = style.color.lines,
		)
		if point_in_box(ctx.mouse_pos, object.box) {
			hover_object(object)
		}
	}
}

spinner :: proc(loc := #caller_location) {
	object := get_object(hash(loc))
	object.size = get_current_style().scale
	if begin_object(object) {
		defer end_object()
		kn.add_spinner(
			box_center(object.box),
			box_height(object.box) * 0.3,
			get_current_style().color.content,
		)
		draw_frames(1)
	}
}

draw_skeleton :: proc(box: Box, rounding: f32) {
	kn.add_box(box, rounding, get_current_style().color.button)
	kn.add_box(box, rounding, kn.Paint{kind = .Skeleton})

	draw_frames(1)
}

divider :: proc() {
	layout := get_current_layout()
	style := get_current_style()
	line_box := cut_box(&layout.box, layout.side, style.line_width)
	j := 1 - int(layout.side) / 2
	line_box.lo[j] = layout.bounds.lo[j]
	line_box.hi[j] = layout.bounds.hi[j]
	kn.add_box(line_box, paint = kn.fade(style.color.lines, 0.5))
}

object_is_in_front_of :: proc(object: ^Object, other: ^Object) -> bool {
	if (object == nil) || (other == nil) do return true
	return (object.call_index > other.call_index) && (object.layer.index >= other.layer.index)
}

add_object_state_for_next_frame :: proc(object: ^Object, state: Object_Status_Set) {
	object.state.current += state
}

do_dummy :: proc(loc := #caller_location) {
	object := get_object(hash(loc))
	do_object(object)
}

