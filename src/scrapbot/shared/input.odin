package shared

Input_Key :: enum {
	Unknown,
	A,
	B,
	C,
	D,
	E,
	F,
	G,
	H,
	I,
	J,
	K,
	L,
	M,
	N,
	O,
	P,
	Q,
	R,
	S,
	T,
	U,
	V,
	W,
	X,
	Y,
	Z,
	Digit_0,
	Digit_1,
	Digit_2,
	Digit_3,
	Digit_4,
	Digit_5,
	Digit_6,
	Digit_7,
	Digit_8,
	Digit_9,
	Left,
	Right,
	Up,
	Down,
	Space,
	Enter,
	Escape,
	Tab,
	Backspace,
	Delete,
	Home,
	End,
	Page_Up,
	Page_Down,
	Left_Shift,
	Right_Shift,
	Left_Control,
	Right_Control,
	Left_Alt,
	Right_Alt,
	Left_Meta,
	Right_Meta,
	F1,
	F2,
	F3,
	F4,
	F5,
	F6,
	F7,
	F8,
	F9,
	F10,
	F11,
	F12,
	Period,
	Count,
}

Input_Pointer_Button :: enum {
	Primary,
	Secondary,
	Middle,
	Back,
	Forward,
	Count,
}

Input_Button_State :: struct {
	down: [2]u64,
	pressed: [2]u64,
	released: [2]u64,
}

Keyboard_Input_Component :: struct {
	available: bool,
	focused: bool,
	buttons: Input_Button_State,
}

Pointer_Input_Component :: struct {
	available: bool,
	captured: bool,
	position: Vec2,
	delta: Vec2,
	wheel: Vec2,
	buttons: Input_Button_State,
}

Input_Frame :: struct {
	keyboard: Keyboard_Input_Component,
	pointer: Pointer_Input_Component,
}

// Text composition and repeated text-navigation edges remain outside the ECS
// gameplay snapshot. They are sampled beside Input_Frame and routed only to UI.
Text_Input :: struct {
	text: string,
	left, right, up, down, home, end: bool,
	backspace, delete_forward: bool,
	tab, enter, escape: bool,
}

input_button_set :: proc "contextless" (buttons: ^[2]u64, index: int) {
	if buttons == nil || index < 0 || index >= 128 {
		return
	}
	buttons[index / 64] |= u64(1) << u64(index % 64)
}

input_button_has :: proc "contextless" (buttons: [2]u64, index: int) -> bool {
	if index < 0 || index >= 128 {
		return false
	}
	return buttons[index / 64] & (u64(1) << u64(index % 64)) != 0
}

input_key_state :: proc "contextless" (
	input: Keyboard_Input_Component,
	key: Input_Key,
) -> (
	down, pressed, released: bool,
) {
	down = input_button_has(input.buttons.down, int(key))
	pressed = input_button_has(input.buttons.pressed, int(key))
	released = input_button_has(input.buttons.released, int(key))
	return
}

input_pointer_button_state :: proc "contextless" (
	input: Pointer_Input_Component,
	button: Input_Pointer_Button,
) -> (
	down, pressed, released: bool,
) {
	down = input_button_has(input.buttons.down, int(button))
	pressed = input_button_has(input.buttons.pressed, int(button))
	released = input_button_has(input.buttons.released, int(button))
	return
}

input_key_from_name :: proc "contextless" (name: string) -> (Input_Key, bool) {
	switch name {
		case "a":
			return .A, true
		case "b":
			return .B, true
		case "c":
			return .C, true
		case "d":
			return .D, true
		case "e":
			return .E, true
		case "f":
			return .F, true
		case "g":
			return .G, true
		case "h":
			return .H, true
		case "i":
			return .I, true
		case "j":
			return .J, true
		case "k":
			return .K, true
		case "l":
			return .L, true
		case "m":
			return .M, true
		case "n":
			return .N, true
		case "o":
			return .O, true
		case "p":
			return .P, true
		case "q":
			return .Q, true
		case "r":
			return .R, true
		case "s":
			return .S, true
		case "t":
			return .T, true
		case "u":
			return .U, true
		case "v":
			return .V, true
		case "w":
			return .W, true
		case "x":
			return .X, true
		case "y":
			return .Y, true
		case "z":
			return .Z, true
		case "0":
			return .Digit_0, true
		case "1":
			return .Digit_1, true
		case "2":
			return .Digit_2, true
		case "3":
			return .Digit_3, true
		case "4":
			return .Digit_4, true
		case "5":
			return .Digit_5, true
		case "6":
			return .Digit_6, true
		case "7":
			return .Digit_7, true
		case "8":
			return .Digit_8, true
		case "9":
			return .Digit_9, true
		case "left":
			return .Left, true
		case "right":
			return .Right, true
		case "up":
			return .Up, true
		case "down":
			return .Down, true
		case "space":
			return .Space, true
		case "enter", "return":
			return .Enter, true
		case "escape":
			return .Escape, true
		case "tab":
			return .Tab, true
		case "backspace":
			return .Backspace, true
		case "delete":
			return .Delete, true
		case "home":
			return .Home, true
		case "end":
			return .End, true
		case "page_up":
			return .Page_Up, true
		case "page_down":
			return .Page_Down, true
		case ".", "period":
			return .Period, true
		case "left_shift":
			return .Left_Shift, true
		case "right_shift":
			return .Right_Shift, true
		case "left_control":
			return .Left_Control, true
		case "right_control":
			return .Right_Control, true
		case "left_alt":
			return .Left_Alt, true
		case "right_alt":
			return .Right_Alt, true
		case "left_meta":
			return .Left_Meta, true
		case "right_meta":
			return .Right_Meta, true
		case "f1":
			return .F1, true
		case "f2":
			return .F2, true
		case "f3":
			return .F3, true
		case "f4":
			return .F4, true
		case "f5":
			return .F5, true
		case "f6":
			return .F6, true
		case "f7":
			return .F7, true
		case "f8":
			return .F8, true
		case "f9":
			return .F9, true
		case "f10":
			return .F10, true
		case "f11":
			return .F11, true
		case "f12":
			return .F12, true
	}
	return .Unknown, false
}
