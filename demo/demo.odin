package demo

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:mem"
import "core:reflect"
import "core:strings"
import "core:time"

import "extra:onyx/onyx"
import sapp "extra:sokol-odin/sokol/app"
import sg "extra:sokol-odin/sokol/gfx"

Option :: enum {
	Process,
	Wave,
	Manifold,
	Function,
}

Component :: enum {
	Button,
	Data_Input,
	Checkbox,
	Graph,
	Slider,
	Scroll_Zone,
}

Component_Section :: struct {
	component: Component,
}

Component_Showcase :: struct {
	light_mode:   bool,
	section:      Component_Section,
	checkboxes:   [Option]bool,
	text_builder: strings.Builder,
	slider_value: f32,
	start_time:   time.Time,
	option:       Option,
	date_range:   [2]Maybe(onyx.Date),
	month_offset: int,
}

State :: struct {
	component_showcase: Component_Showcase,
	images:             [4]onyx.Image,
}

do_component_showcase :: proc(state: ^Component_Showcase) {
	using onyx

	layer_box := shrink_box(view_box(), 100)
	begin_layer({box = layer_box, kind = .Background})
	foreground()
	begin_layout({size = 65, side = .Top, show_lines = true})
	shrink(15)
	if index, ok := do_breadcrumb({index = int(state.section.component), options = reflect.enum_field_names(Component)}).index.?;
	   ok {
		state.section.component = Component(index)
	}
	set_side(.Right)
	state.light_mode = do_switch({on = state.light_mode}).on
	end_layout()
	shrink(30)

	#partial switch state.section.component {
	case .Scroll_Zone:
		set_side(.Left)
		set_width(300)
		set_height_fill()
		if do_container({size = 1000}) {

		}

	case .Slider:
		set_side(.Top)
		state.slider_value =
			do_slider(Slider_Info(f32){value = state.slider_value}).value.? or_else state.slider_value

	case .Button:
		set_side(.Top)
		do_label({text = "Fit to label", font_style = .Bold, font_size = 24})
		add_space(10)
		if do_layout({size = 30}) {
			set_width_auto()
			for member, m in Button_Kind {
				push_id(m)
				if m > 0 {
					add_space(10)
				}
				if was_clicked(do_button({text = tmp_print(member), kind = member})) {

				}
				pop_id()
			}
		}
		add_space(10)
		if do_selector({text = "Combo"}) {
			shrink(3)
			set_side(.Top)
			set_width_fill()
			for option, o in Option {
				push_id(o)
				if was_clicked(
					do_selector_option({text = tmp_print(option), state = state.option == option}),
				) {
					state.option = option
				}
				pop_id()
			}
		}
		calendar := make_calendar(
			{selection = state.date_range, month_offset = state.month_offset},
		)
		if do_layout(
			{box = align_inner(layout_box(), calendar.desired_size, {.Middle, .Middle})},
		) {
			result := add_calendar(calendar)
			state.month_offset = result.month_offset
			state.date_range = result.selection
		}

	case .Checkbox:
		set_side(.Top)
		do_label({text = "Checkboxes", font_style = .Bold, font_size = 24})
		add_space(10)
		for member, m in Option {
			push_id(m)
			if m > 0 {
				add_space(10)
			}
			if was_clicked(
				do_checkbox({text = tmp_print(member), value = state.checkboxes[member]}),
			) {
				state.checkboxes[member] = !state.checkboxes[member]
			}
			pop_id()
		}

	case .Data_Input:
		set_side(.Top)
		set_width(200)
		set_height(120)
		do_text_input(
			{builder = &state.text_builder, placeholder = "Type something", multiline = true},
		)
		add_space(10)
		do_text_input({builder = &state.text_builder})

	case .Graph:
		set_side(.Left)
		set_width_percent(50)
		set_height(100)
		if do_layout({}) {
			shrink(30)
			set_width_fill()
			set_height_fill()
			do_graph(
				Graph_Info(int) {
					lo = 0,
					hi = 30,
					increment = 5,
					spacing = 10,
					kind = Bar_Graph{value_labels = true, show_tooltip = true},
					label_tooltip = true,
					fields = {{"Minecraft", {255, 25, 96, 255}}, {"Terraria", {0, 58, 255, 255}}},
					entries = {
						{"Feb 2nd", {1, 5}},
						{"Feb 3rd", {4, 2}},
						{"Feb 4th", {6, 5}},
						{"Feb 5th", {2, 8}},
						{"Feb 6th", {3, 12}},
						{"Feb 7th", {4, 13}},
						{"Feb 8th", {4, 10}},
						{"Feb 9th", {5, 10}},
						{"Feb 10th", {7, 7}},
						{"Feb 11th", {8, 6}},
						{"Feb 12th", {11, 6}},
						{"Feb 13th", {12, 7}},
						{"Feb 14th", {9, 4}},
					},
				},
			)
		}
		if do_layout({}) {
			shrink(30)
			set_width_fill()
			set_height_fill()
			do_graph(
				Graph_Info(int) {
					lo = 0,
					hi = 30,
					increment = 5,
					spacing = 10,
					kind = Line_Graph{show_dots = false},
					label_tooltip = true,
					fields = {{"Minecraft", {255, 25, 96, 255}}, {"Terraria", {0, 58, 255, 255}}},
					entries = {
						{label = "Jan 5th", values = {1, 5, 9}},
						{label = "Jan 6th", values = {4, 2, 2}},
						{label = "Jan 7th", values = {6, 5, 10}},
						{label = "Jan 8th", values = {2, 6, 1}},
						{label = "Jan 9th", values = {4, 7, 2}},
						{label = "Jan 10th", values = {2, 4, 8}},
						{label = "Jan 11th", values = {8, 5, 8}},
						{label = "Jan 12th", values = {18, 6, 8}},
						{label = "Jan 13th", values = {15, 7, 8}},
						{label = "Jan 14th", values = {14, 8, 8}},
						{label = "Jan 15th", values = {11, 6, 8}},
					},
				},
			)
		}
	}
	end_layer()
}

allocator: runtime.Allocator

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	} else {
		allocator = runtime.default_allocator()
	}

	state: State

	state.component_showcase.date_range = {onyx.Date{2024, 2, 17}, onyx.Date{2024, 3, 2}}

	sapp.run(
		sapp.Desc {
			user_data = &state,
			init_userdata_cb = proc "c" (userdata: rawptr) {
				context = runtime.default_context()
				context.allocator = allocator
				state := transmute(^State)userdata

				onyx.init()
				onyx.set_style_font(.Medium, "fonts/Geist-Medium.ttf")
				onyx.set_style_font(.Bold, "fonts/Geist-Bold.ttf")
				onyx.set_style_font(.Light, "fonts/Geist-Light.ttf")
				onyx.set_style_font(.Regular, "fonts/Geist-Regular.ttf")
				onyx.set_style_font(.Icon, "fonts/remixicon.ttf")

				// for i in 0 ..< 4 {
				// 	state.images[i] =
				// 		onyx.load_image_from_file(fmt.aprintf("%i.png", i + 1)) or_else panic(
				// 			"failed lol",
				// 		)
				// }
			},
			frame_userdata_cb = proc "c" (userdata: rawptr) {
				context = runtime.default_context()
				context.allocator = allocator
				state := transmute(^State)userdata

				using onyx

				begin_frame()
				do_component_showcase(&state.component_showcase)

				end_frame()
			},
			cleanup_cb = proc "c" () {
				context = runtime.default_context()
				context.allocator = allocator

				onyx.uninit()
			},
			event_cb = proc "c" (e: ^sapp.Event) {
				context = runtime.default_context()
				context.allocator = allocator

				onyx.handle_event(e)
			},
			enable_clipboard = true,
			enable_dragndrop = true,
			sample_count = 4,
			width = 1800,
			height = 960,
			// fullscreen = true,
			window_title = "o n y x",
			// icon = sapp.Icon_Desc{
			// 	images = {
			// 		0 = {
			// 			width = 2,
			// 			height = 2,
			// 			pixels = {

			// 			},
			// 		},
			// 	},
			// },
		},
	)
}
