package ronin

Form :: struct {
	first: ^Object,
	last:  ^Object,
}

begin_form :: proc() {
	ctx.form_active = true
	ctx.form = {}
}

end_form :: proc() {
	// if ctx.form.first != nil {
	// 	ctx.form.first.prev = ctx.form.last
	// }
	ctx.form_active = false

}

