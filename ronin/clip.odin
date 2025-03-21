package ronin

push_clip :: proc(box: Box) {
	push_stack(&ctx.clip_stack, box)
}
pop_clip :: proc() {
	pop_stack(&ctx.clip_stack)
}
get_current_clip :: proc() -> Box {
	if ctx.clip_stack.height > 0 {
		return ctx.clip_stack.items[ctx.clip_stack.height - 1]
	}
	return view_box()
}

