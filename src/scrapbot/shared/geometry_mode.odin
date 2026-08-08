package shared

geometry_mode_name :: proc "contextless" (mode: Geometry_Mode) -> string {
	switch mode {
		case .Inherit:
			return "inherit"
		case .Auto:
			return "auto"
		case .Conventional:
			return "conventional"
		case .Virtual:
			return "virtual"
	}
	return "inherit"
}

geometry_mode_from_name :: proc "contextless" (name: string) -> (Geometry_Mode, bool) {
	switch name {
		case "inherit":
			return .Inherit, true
		case "auto":
			return .Auto, true
		case "conventional":
			return .Conventional, true
		case "virtual":
			return .Virtual, true
	}
	return .Inherit, false
}

geometry_mode_resolve :: proc "contextless" (modes: ..Geometry_Mode) -> Geometry_Mode {
	mode := geometry_mode_override(..modes)
	return .Auto if mode == .Inherit else mode
}

geometry_mode_override :: proc "contextless" (modes: ..Geometry_Mode) -> Geometry_Mode {
	for mode in modes {
		if mode != .Inherit {
			return mode
		}
	}
	return .Inherit
}
