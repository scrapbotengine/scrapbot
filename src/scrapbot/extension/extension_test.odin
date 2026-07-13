package extension

import "core:testing"
import raw "../extension_api"

@(test)
test_system_trampoline_invokes_contextless_callback_with_project_userdata :: proc(t: ^testing.T) {
	called := false
	binding := System_Binding{callback = test_contextless_system, userdata = &called}
	ctx := raw.System_Context{userdata = &binding}
	err := system_trampoline(&ctx)
	testing.expect(t, err == nil)
	testing.expect(t, called)
}

test_contextless_system :: proc "contextless" (ctx: ^System_Context) -> cstring {
	if ctx == nil || ctx.userdata == nil {return "missing test userdata"}
	called := cast(^bool)ctx.userdata
	called^ = true
	return nil
}
