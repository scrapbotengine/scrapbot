package diagnostic

Severity :: enum {
	Info,
	Warning,
	Error,
}

Diagnostic :: struct {
	code:     string,
	severity: string,
	message:  string,
	path:     string `json:"path,omitempty"`,
}

error :: proc(code, message: string, path: string = "") -> Diagnostic {
	return Diagnostic{code=code, severity="error", message=message, path=path}
}
