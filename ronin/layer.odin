package ronin
// Layers exist only for object drawing and interaction to be arbitrarily ordered
// Layers have no interaction of their own, but clicking or hovering a object in a given layer, will update its
// state.
//
// Layer ordering is somewhat complex
// some layers are attached to their parent and are therefore always one index above it
//
// All layers are stored contiguously in the order they are to be rendered
// a layer's index is an important value and must always be valid
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:slice"
import kn "local:katana"

Layer_Sort_Method :: enum {
	Back,
	Floating,
	Front,
}

Layer_Option :: enum {
	In_Front_Of_Parent,
	Isolated,
	No_Sorting,
	Invisible,
}

Layer_Options :: bit_set[Layer_Option]

Layer :: struct {
	id:                            Id,
	parent:                        ^Layer,
	state:                         Object_Status_Set,
	last_state:                    Object_Status_Set,
	options:                       Layer_Options,
	dead:                          bool,
	next_sort_method, sort_method: Layer_Sort_Method,
	index:                         int,
	min_index:                     int,
	floating_index:                int,
	next_floating_index:           Maybe(int),
	frames:                        int,
}

update_layers :: proc() {
	for layer, i in ctx.layer_array {
		if layer.dead {
			ordered_remove(&ctx.layer_array, i)
			delete_key(&ctx.layer_map, layer.id)
			free(layer)
			draw_frames(1)
		} else {
			layer.dead = true

			switch layer.sort_method {
			case .Floating:
				if layer.next_sort_method == .Back {
					for other in ctx.layer_array {
						if other.sort_method == .Floating &&
						   other.floating_index > layer.floating_index {
							other.floating_index -= 1
						}
					}
					layer.floating_index = 0
				} else if next_floating_index, ok := layer.next_floating_index.?; ok {
					for &other in ctx.layer_array {
						if other.id != layer.id &&
						   other.sort_method == .Floating &&
						   other.floating_index > layer.floating_index &&
						   other.floating_index <= next_floating_index {
							other.floating_index -= 1
						}
					}
					layer.floating_index = next_floating_index
					layer.next_floating_index = nil
				}
			case .Back:
				if layer.next_sort_method == .Floating {
					for other in ctx.layer_array {
						if other.sort_method == .Floating {
							other.floating_index += 1
						}
					}
					layer.floating_index = 0
				}
			case .Front:
				if layer.next_sort_method == .Floating {
					layer.floating_index = ctx.layer_counts[.Floating]
				}
			}

			layer.sort_method = layer.next_sort_method
		}
	}

	ctx.last_layer_counts = ctx.layer_counts
	ctx.layer_counts = {}
}

update_layer_references :: proc() {
	ctx.hovered_layer_index = 0
	ctx.last_hovered_layer = ctx.hovered_layer

	ctx.hovered_layer = ctx.next_hovered_layer
	ctx.next_hovered_layer = 0
	ctx.last_highest_layer_index = ctx.highest_layer_index
	ctx.highest_layer_index = 0

	if (ctx.mouse_bits - ctx.last_mouse_bits) > {} {
		ctx.focused_layer = ctx.hovered_layer
	}
}

current_layer :: proc(loc := #caller_location) -> Maybe(^Layer) {
	if ctx.layer_stack.height > 0 {
		return ctx.layer_stack.items[ctx.layer_stack.height - 1]
	}
	return nil
}

create_layer :: proc(id: Id) -> (layer: ^Layer, ok: bool) {
	layer = new(Layer)
	layer.id = id
	if id in ctx.layer_map do return
	ctx.layer_map[id] = layer
	append(&ctx.layer_array, layer)
	ok = true
	return
}

destroy_layer :: proc(layer: ^Layer) {

}

get_layer :: proc(id: Id) -> (layer: ^Layer, ok: bool) {
	layer, ok = get_layer_by_id(id)
	if !ok {
		layer, ok = create_layer(id)
	}
	return
}

begin_layer :: proc(
	sort_method: Layer_Sort_Method,
	options: Layer_Options = {},
	loc := #caller_location,
) -> bool {
	id := hash(loc)

	layer := get_layer(id) or_return

	if layer.frames == ctx.frames {
		when ODIN_DEBUG {
			fmt.println("Layer ID collision: %i", id)
		}
		return false
	}

	if .In_Front_Of_Parent in options {
		if parent, ok := current_layer().?; ok {
			layer.min_index = parent.index
		}
	}

	layer.next_sort_method = sort_method

	if layer.frames == 0 {
		layer.sort_method = sort_method
		layer.floating_index = ctx.layer_counts[.Floating]
	}

	switch sort_method {
	case .Back:
		layer.index = ctx.layer_counts[.Back]
	case .Floating:
		layer.index = layer.floating_index + 512
	case .Front:
		layer.index = ctx.layer_counts[.Front] + 1024
	}

	ctx.layer_counts[sort_method] += 1

	layer.id = id
	layer.dead = false
	layer.options = options
	layer.frames = ctx.frames

	layer.last_state = layer.state
	layer.state = {}

	if ctx.hovered_layer == layer.id {
		layer.state += {.Hovered}
		if mouse_pressed(.Left) && layer.sort_method == .Floating {
			layer.next_floating_index = ctx.last_layer_counts[.Floating] - 1
		}
	}

	layer.index = max(layer.index, layer.min_index)

	if ctx.focused_layer == layer.id {
		layer.state += {.Focused}
	}

	ctx.highest_layer_index = max(ctx.highest_layer_index, layer.index)

	push_stack(&ctx.layer_stack, layer)
	kn.set_draw_order(layer.index)

	return true
}

end_layer :: proc() {
	pop_stack(&ctx.layer_stack)
	if layer, ok := current_layer().?; ok {
		kn.set_draw_order(layer.index)
	}
}

@(deferred_out = __do_layer)
do_layer :: proc(
	sort_method: Layer_Sort_Method,
	options: Layer_Options = {},
	loc := #caller_location,
) -> bool {
	return begin_layer(sort_method, options, loc)
}

@(private)
__do_layer :: proc(ok: bool) {
	if ok {
		end_layer()
	}
}

get_layer_by_id :: proc(id: Id) -> (result: ^Layer, ok: bool) {
	return ctx.layer_map[id]
}

