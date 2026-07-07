package platform

import "core:c"
import "core:fmt"
import "core:strings"
import sdl "vendor:sdl3"

runtime_window: ^sdl.Window
runtime_window_ready: bool

runtime_window_flags :: proc(hidden: bool) -> sdl.WindowFlags {
	flags := sdl.WindowFlags{.RESIZABLE}
	when ODIN_OS == .Darwin {
		flags += sdl.WINDOW_METAL
	}
	if hidden {
		flags += sdl.WINDOW_HIDDEN
	}
	return flags
}

open_runtime_window :: proc(title: string, width, height: int) -> string {
	return open_runtime_window_with_visibility(title, width, height, false)
}

open_hidden_runtime_window :: proc(title: string, width, height: int) -> string {
	return open_runtime_window_with_visibility(title, width, height, true)
}

open_runtime_window_with_visibility :: proc(title: string, width, height: int, hidden: bool) -> string {
	if runtime_window_ready {
		return ""
	}

	if !sdl.Init(sdl.INIT_VIDEO) {
		return fmt.tprintf("failed to initialize SDL3 video: %s", sdl.GetError())
	}

	title_c := strings.clone_to_cstring(title)
	defer delete(title_c)

	runtime_window = sdl.CreateWindow(title_c, c.int(width), c.int(height), runtime_window_flags(hidden))
	if runtime_window == nil {
		err := fmt.tprintf("failed to create SDL3 window: %s", sdl.GetError())
		sdl.Quit()
		return err
	}

	runtime_window_ready = true
	return ""
}

close_runtime_window :: proc() {
	if runtime_window != nil {
		sdl.DestroyWindow(runtime_window)
		runtime_window = nil
	}
	if runtime_window_ready {
		sdl.Quit()
		runtime_window_ready = false
	}
}

runtime_window_pixel_size :: proc() -> (width, height: int, ok: bool) {
	if runtime_window == nil {
		return 0, 0, false
	}

	w, h: c.int
	if !sdl.GetWindowSizeInPixels(runtime_window, &w, &h) {
		return 0, 0, false
	}
	return int(w), int(h), true
}

pump_runtime_window_events :: proc() -> bool {
	should_quit := false
	event: sdl.Event
	for sdl.PollEvent(&event) {
		if event.type == .QUIT || event.type == .WINDOW_CLOSE_REQUESTED {
			should_quit = true
		}
	}
	return should_quit
}
