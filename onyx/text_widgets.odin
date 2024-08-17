package onyx

Label_Info :: struct {
	using _:     Generic_Widget_Info,
	font_style:  Font_Style,
	font_size:   f32,
	text:        string,
	__text_info: Text_Info,
}

make_label :: proc(info: Label_Info, loc := #caller_location) -> Label_Info {
	info := info
	info.id = hash(loc)
	info.__text_info = Text_Info {
		text    = info.text,
		size    = info.font_size,
		font    = core.style.fonts[info.font_style],
		align_h = .Left,
		align_v = .Top,
	}
	info.fixed_size = true
	info.desired_size = measure_text(info.__text_info)
	return info
}

add_label :: proc(info: Label_Info) {
	widget, ok := get_widget(info)
	if !ok do return
	widget.box = next_widget_box(info)

	if widget.visible {
		draw_text(widget.box.lo, info.__text_info, core.style.color.content)
	}
}

do_label :: proc(info: Label_Info) {
	add_label(make_label(info))
}
