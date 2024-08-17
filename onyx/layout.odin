package onyx

import "core:math"
import "core:math/linalg"

Layout_Info :: struct {
	box:        Maybe(Box),
	side:       Side,
	size:       f32,
	show_lines: bool,
}

// Layout
Layout :: struct {
	original_box, box: Box, // Original box// Current box to cut from
	next_side:         Side, // Next side to cut from
	next_size:         [2]f32, // Next cut size
	content_size:      [2]f32,
	spacing_size:      [2]f32,
	show_lines:        bool,
	side:              Maybe(Side), // What side was the layout cut from (if it was cut)
}

current_layout :: proc(loc := #caller_location) -> Maybe(^Layout) {
	if core.layout_stack.height > 0 {
		return &core.layout_stack.items[core.layout_stack.height - 1]
	}
	return nil
}

layout_box :: proc() -> Box {
	return current_layout().?.box
}

cut_layout :: proc(layout: ^Layout, side: Maybe(Side) = nil, size: Maybe([2]f32) = nil) -> Box {
	side := side.? or_else layout.next_side
	size := size.? or_else layout.next_size
	box := cut_box(&layout.box, side, size[1 - int(side) / 2])
	return box
}

next_widget_box :: proc(info: Generic_Widget_Info) -> Box {
	layout := current_layout().?
	size := linalg.min(
		info.desired_size if info.fixed_size else linalg.max(layout.next_size, info.desired_size),
		layout.box.hi - layout.box.lo,
	)
	box := cut_layout(layout, nil, size)
	if int(layout.next_side) > 1 {
		if size.y < box_height(box) {
			box.lo.y = box_center_y(box) - size.y / 2
			box.hi.y = box.lo.y + size.y
		}
	} else {
		if size.x < box_width(box) {
			box.hi.x = box.lo.x + size.x
		}
	}
	return {linalg.floor(box.lo), linalg.floor(box.hi)}
}

push_layout :: proc(layout: Layout) -> bool {
	return push_stack(&core.layout_stack, layout)
}

pop_layout :: proc() {
	pop_stack(&core.layout_stack)
}

begin_layout :: proc(info: Layout_Info) -> bool {
	box := info.box.? or_else cut_layout(current_layout().? or_return, info.side, info.size)
	layout := Layout {
		box          = box,
		original_box = box,
		side         = info.side,
		show_lines   = info.show_lines,
		next_side    = .Left if int(info.side) < 2 else .Top,
	}
	return push_layout(layout)
}

end_layout :: proc() {
	layout := current_layout().?
	pop_layout()

	// ya
	if new_layout, ok := current_layout().?; ok {
		add_layout_content_size(new_layout, layout.content_size + layout.spacing_size)
	}

	// Draw layout lines
	if layout.show_lines {
		if side, ok := layout.side.?; ok {
			box := layout.original_box
			switch layout.side {

			case .Top:
				draw_box_fill({{box.lo.x, box.hi.y - 1}, box.hi}, core.style.color.substance)

			case .Bottom:
				draw_box_fill({box.lo, {box.hi.x, box.lo.y + 1}}, core.style.color.substance)

			case .Left:
				draw_box_fill({{box.hi.x - 1, box.lo.y}, box.hi}, core.style.color.substance)

			case .Right:
				draw_box_fill({box.lo, {box.lo.x + 1, box.hi.y}}, core.style.color.substance)
			}
		}
	}
}

@(deferred_out = __do_layout)
do_layout :: proc(info: Layout_Info) -> (ok: bool) {
	return begin_layout(info)
}

@(private)
__do_layout :: proc(ok: bool) {
	if ok {
		end_layout()
	}
}

side :: proc(side: Side) {
	layout := current_layout().?
	layout.next_side = side
}

set_width :: proc(width: f32) {
	current_layout().?.next_size.x = width
}
set_width_auto :: proc() {
	current_layout().?.next_size.x = 0
}
set_width_fill :: proc() {
	layout := current_layout().?
	layout.next_size.x = box_width(layout.box)
}
set_width_percent :: proc(width: f32) {
	layout := current_layout().?
	layout.next_size.x = box_width(layout.box) * (width / 100)
}
set_height :: proc(height: f32) {
	current_layout().?.next_size.y = height
}
set_height_auto :: proc() {
	current_layout().?.next_size.y = 0
}
set_height_fill :: proc() {
	layout := current_layout().?
	layout.next_size.y = box_height(layout.box)
}
set_height_percent :: proc(height: f32) {
	layout := current_layout().?
	layout.next_size.y = box_height(layout.box) * (height / 100)
}

shrink :: proc(amount: f32) {
	layout := current_layout().?
	layout.box.lo += amount
	layout.box.hi -= amount
	layout.spacing_size += amount * 2
}

shrink_x :: proc(amount: f32) {
	layout := current_layout().?
	layout.box.lo.x += amount
	layout.box.hi.x -= amount
}

shrink_y :: proc(amount: f32) {
	layout := current_layout().?
	layout.box.lo.y += amount
	layout.box.hi.y -= amount
}

space :: proc(amount: f32) {
	layout := current_layout().?
	cut_box(&layout.box, layout.next_side, amount)
	layout.spacing_size[1 - int(layout.next_side) / 2] += amount
}

layout_is_vertical :: proc(layout: ^Layout) -> bool {
	return int(layout.next_side) < 2
}

add_layout_content_size :: proc(layout: ^Layout, size: [2]f32) {
	if int(layout.next_side) > 1 {
		layout.content_size.y = max(layout.content_size.y, size.y)
		layout.content_size.x += size.x
	} else {
		layout.content_size.x = max(layout.content_size.x, size.x)
		layout.content_size.y += size.y
	}
}
