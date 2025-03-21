package ronin

import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:reflect"
import kn "local:katana"

Carousel :: struct {
	offset:      [2]f32,
	last_offset: [2]f32,
	timer:       f32,
	last_page:   int,
	page:        int,
	page_count:  int,
}

find_object_variant_in_stack :: proc($T: typeid) -> (result: ^T, ok: bool) {
	for index := ctx.object_stack.height - 1; index >= 0; index -= 1 {
		result, ok = &ctx.object_stack.items[index].variant.(T)
		if ok {
			break
		}
	}
	return
}

pages_proceed :: proc() -> bool {
	carousel := find_object_variant_in_stack(Carousel) or_return
	carousel.page += 1
	return true
}

pages_go_back :: proc() -> bool {
	carousel := find_object_variant_in_stack(Carousel) or_return
	carousel.page -= 1
	return true
}

begin_carousel :: proc(loc := #caller_location) -> bool {
	object := get_object(hash(loc))
	if object.variant == nil {
		object.variant = Carousel{}
	}
	// object.state.input_mask = OBJECT_STATE_ALL
	carousel := &object.variant.(Carousel)
	carousel.page_count = 0
	carousel.last_page = carousel.page
	begin_object(object) or_return
	if point_in_box(mouse_point(), object.box) {
		hover_object(object)
	}
	layout_box := move_box(object.box, -carousel.offset)
	layout_box.hi.y -= get_current_style().scale * 1
	begin_layout(with_box(layout_box), left_to_right, is_dynamic) or_return
	set_size(exactly(box_width(object.box)))
	return true
}

end_carousel :: proc() {
	if object, ok := get_current_object(); ok {
		carousel := &object.variant.(Carousel)

		last_page := carousel.page
		if .Hovered in object.state.current {
			if key_pressed(.Left) {
				carousel.page -= 1
			} else if key_pressed(.Right) {
				carousel.page += 1
			}
			carousel.page += int(ctx.mouse_scroll.y)
		}

		// Draw dots
		{
			dot_margin := get_current_style().scale * 1.5
			dot_spacing := get_current_style().scale * golden_ratio
			dots_width := dot_spacing * f32(carousel.page_count)
			dots_left_origin := box_center_x(object.box) - dots_width / 2
			for page_index in 0 ..< carousel.page_count {
				dot_position := [2]f32 {
					dots_left_origin + f32(page_index) * dot_spacing,
					object.box.hi.y - dot_margin,
				}
				push_id(page_index)
				if pagination_dot(dot_position, carousel.page == page_index) {
					carousel.page = page_index
				}
				pop_id()
			}
		}

		carousel.page = clamp(carousel.page, 0, carousel.page_count - 1)
		if carousel.last_page != carousel.page {
			carousel.last_page = carousel.page
			carousel.last_offset = carousel.offset
			carousel.timer = 0
		}

		animation_time := ease.circular_in_out(carousel.timer)
		carousel.offset.x =
			carousel.last_offset.x +
			(box_width(object.box) * f32(carousel.page) - carousel.last_offset.x) * animation_time
		carousel.timer = min(1, carousel.timer + ctx.delta_time * 5)
		draw_frames(int(animation_time < 1) * 3)

		end_layout()
		end_object()
	}
}

pagination_dot :: proc(point: [2]f32, active: bool, loc := #caller_location) -> (clicked: bool) {
	object := get_object(hash(loc))
	radius :: 3
	box_half_size :: radius * golden_ratio
	set_next_box(Box{point - box_half_size, point + box_half_size})
	if do_object(object) {
		if point_in_box(mouse_point(), object.box) {
			hover_object(object)
		}
		if object_is_visible(object) {
			kn.add_circle(
				point,
				radius *
				math.lerp(f32(1), golden_ratio, ease.quadratic_in_out(object.animation.hover)),
				paint = get_current_style().color.content,
			)
		}
		if .Hovered in object.state.current {
			set_cursor(.Pointing_Hand)
		}
		object.animation.hover = animate(
			object.animation.hover,
			0.2,
			(.Hovered in object.state.current) || active,
		)
		clicked = .Clicked in object.state.current
	}
	return
}

@(deferred_out = __do_carousel)
do_carousel :: proc(loc := #caller_location) -> bool {
	return begin_carousel(loc)
}

@(private)
__do_carousel :: proc(ok: bool) {
	if ok {
		end_carousel()
	}
}

begin_page :: proc(props: ..Layout_Property) -> bool {
	parent_object := get_current_object() or_return
	carousel := (&parent_object.variant.(Carousel)) or_return
	set_size(box_size(parent_object.box))
	begin_layout(..props) or_return
	carousel.page_count += 1
	return true
}

end_page :: proc() {
	end_layout()
}

@(deferred_out = __do_page)
do_page :: proc(props: ..Layout_Property) -> bool {
	return begin_page(..props)
}

@(private)
__do_page :: proc(ok: bool) {
	if ok {
		end_page()
	}
}

