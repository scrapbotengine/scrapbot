package file_browser

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

MAX_ENTRIES :: 4096

Entry_Kind :: enum {
	Directory,
	File,
}

Entry :: struct {
	name: string,
	path: string,
	kind: Entry_Kind,
	size: i64,
}

Filter :: struct {
	extensions: []string,
	show_hidden: bool,
	directories: bool,
	files: bool,
}

State :: struct {
	root: string,
	directory: string,
	entries: [dynamic]Entry,
	revision: u64,
	filter: Filter,
}

default_filter :: proc() -> Filter {
	return {directories = true, files = true}
}

init :: proc(state: ^State, root: string, filter: Filter) -> string {
	if state == nil || root == "" {
		return "file browser root is unavailable"
	}
	absolute, absolute_err := filepath.abs(root)
	if absolute_err != nil {
		return fmt.tprintf("failed to resolve file browser root: %v", absolute_err)
	}
	cleaned, clean_err := filepath.clean(absolute)
	delete(absolute)
	if clean_err != nil {
		return "failed to normalize file browser root"
	}
	if !os.is_dir(cleaned) {
		delete(cleaned)
		return "file browser root is not a directory"
	}
	state.root = cleaned
	state.filter = filter
	state.directory = ""
	if refresh_err := refresh(state); refresh_err != "" {
		destroy(state)
		return refresh_err
	}
	return ""
}

destroy :: proc(state: ^State) {
	if state == nil {
		return
	}
	clear_entries(state)
	delete(state.entries)
	delete(state.root)
	delete(state.directory)
	state^ = {}
}

clear_entries :: proc(state: ^State) {
	if state == nil {
		return
	}
	for &entry in state.entries {
		delete(entry.name)
		delete(entry.path)
	}
	clear(&state.entries)
}

path_is_safe_relative :: proc(path: string) -> bool {
	if path == "" || path == "." {
		return true
	}
	if filepath.is_abs(path) {
		return false
	}
	cleaned, err := filepath.clean(path, context.temp_allocator)
	if err != nil || cleaned == ".." {
		return false
	}
	return !strings.has_prefix(cleaned, "../") && !strings.has_prefix(cleaned, "..\\")
}

resolve :: proc(state: ^State, relative: string) -> (string, string) {
	if state == nil || state.root == "" || !path_is_safe_relative(relative) {
		return "", "path escapes the file browser root"
	}
	if relative == "" || relative == "." {
		result, err := strings.clone(state.root)
		if err != nil {
			return "", "failed to allocate browser path"
		}
		return result, ""
	}
	result, join_err := filepath.join({state.root, relative})
	if join_err != nil {
		return "", "failed to allocate browser path"
	}
	return result, ""
}

extension_matches :: proc(name: string, extensions: []string) -> bool {
	if len(extensions) == 0 {
		return true
	}
	for extension in extensions {
		if extension != "" &&
		   len(extension) <= len(name) &&
		   strings.equal_fold(name[len(name) - len(extension):], extension) {
			return true
		}
	}
	return false
}

fold_ascii :: proc(value: u8) -> u8 {
	if value >= 'A' && value <= 'Z' {
		return value + ('a' - 'A')
	}
	return value
}

compare_names :: proc(left, right: string) -> int {
	count := min(len(left), len(right))
	for index in 0 ..< count {
		left_byte := fold_ascii(left[index])
		right_byte := fold_ascii(right[index])
		if left_byte < right_byte { return -1 }
		if left_byte > right_byte { return 1 }
	}
	if len(left) < len(right) { return -1 }
	if len(left) > len(right) { return 1 }
	if left < right { return -1 }
	if left > right { return 1 }
	return 0
}

entry_less :: proc(left, right: Entry) -> bool {
	if left.kind != right.kind {
		return left.kind == .Directory
	}
	return compare_names(left.name, right.name) < 0
}

sort_entries :: proc(entries: []Entry) {
	slice.sort_by(entries, entry_less)
}

path_traverses_symlink :: proc(state: ^State, relative: string) -> bool {
	if state == nil || state.root == "" || relative == "" || relative == "." {
		return false
	}
	prefix := ""
	defer delete(prefix)
	component_start := 0
	for index in 0 ..= len(relative) {
		at_end := index == len(relative)
		if !at_end && !os.is_path_separator(relative[index]) {
			continue
		}
		if index == component_start {
			component_start = index + 1
			continue
		}
		component := relative[component_start:index]
		next_prefix, prefix_err := filepath.join({prefix, component})
		if prefix_err != nil {
			return true
		}
		delete(prefix)
		prefix = next_prefix
		resolved, resolve_err := resolve(state, prefix)
		if resolve_err != "" {
			return true
		}
		info, stat_err := os.lstat(resolved, context.temp_allocator)
		delete(resolved)
		if stat_err != nil {
			return true
		}
		is_symlink := info.type == .Symlink
		os.file_info_delete(info, context.temp_allocator)
		if is_symlink { return true }
		component_start = index + 1
	}
	return false
}

refresh :: proc(state: ^State) -> string {
	if state == nil || state.root == "" {
		return "file browser is unavailable"
	}
	full_directory, resolve_err := resolve(state, state.directory)
	if resolve_err != "" {
		return resolve_err
	}
	defer delete(full_directory)
	infos, read_err := os.read_all_directory_by_path(full_directory, context.temp_allocator)
	if read_err != nil {
		return fmt.tprintf("failed to read directory: %v", read_err)
	}
	defer os.file_info_slice_delete(infos, context.temp_allocator)
	next_entries := make([dynamic]Entry, 0, min(len(infos), MAX_ENTRIES))
	committed := false
	defer {
		if !committed {
			for &entry in next_entries {
				delete(entry.name)
				delete(entry.path)
			}
		}
		delete(next_entries)
	}
	for info in infos {
		if len(next_entries) >= MAX_ENTRIES {
			return fmt.tprintf("directory exceeds the %d-entry browser limit", MAX_ENTRIES)
		}
		if !state.filter.show_hidden && strings.has_prefix(info.name, ".") {
			continue
		}
		kind: Entry_Kind
		#partial switch info.type {
			case .Directory:
				if !state.filter.directories {
					continue
				}
				kind = .Directory
			case .Regular:
				if !state.filter.files || !extension_matches(info.name, state.filter.extensions) {
					continue
				}
				kind = .File
			case:
				continue
		}
		path := info.name
		owned_path := ""
		if state.directory != "" {
			joined, join_err := filepath.join({state.directory, info.name})
			if join_err != nil {
				return "failed to allocate browser entry path"
			}
			owned_path = joined
			path = joined
		}
		name, name_err := strings.clone(info.name)
		path_value, path_err := strings.clone(path)
		delete(owned_path)
		if name_err != nil || path_err != nil {
			delete(name)
			delete(path_value)
			return "failed to allocate browser entry"
		}
		append(&next_entries, Entry{name = name, path = path_value, kind = kind, size = info.size})
	}
	sort_entries(next_entries[:])
	clear_entries(state)
	reserve(&state.entries, len(next_entries))
	append(&state.entries, ..next_entries[:])
	committed = true
	state.revision += 1
	return ""
}

navigate :: proc(state: ^State, relative: string) -> string {
	if state == nil || !path_is_safe_relative(relative) {
		return "path escapes the file browser root"
	}
	resolved, resolve_err := resolve(state, relative)
	if resolve_err != "" {
		return resolve_err
	}
	defer delete(resolved)
	next := ""
	if relative != "" && relative != "." {
		cleaned, clean_err := filepath.clean(relative)
		if clean_err != nil {
			return "failed to normalize browser directory"
		}
		next = cleaned
	}
	if path_traverses_symlink(state, next) {
		delete(next)
		return "browser destination traverses a symbolic link"
	}
	if !os.is_dir(resolved) {
		delete(next)
		return "browser destination is not a directory"
	}
	previous, previous_err := strings.clone(state.directory)
	if previous_err != nil {
		delete(next)
		return "failed to allocate browser directory"
	}
	delete(state.directory)
	state.directory = next
	if refresh_err := refresh(state); refresh_err != "" {
		delete(state.directory)
		state.directory = previous
		return refresh_err
	}
	delete(previous)
	return ""
}

enter :: proc(state: ^State, name: string) -> string {
	if state == nil || name == "" || name == "." || name == ".." {
		return "invalid browser directory name"
	}
	relative := name
	owned := ""
	if state.directory != "" {
		joined, join_err := filepath.join({state.directory, name})
		if join_err != nil {
			return "failed to allocate browser directory"
		}
		owned = joined
		relative = joined
	}
	defer delete(owned)
	return navigate(state, relative)
}

parent :: proc(state: ^State) -> string {
	if state == nil || state.directory == "" {
		return ""
	}
	parent_path := filepath.dir(state.directory)
	if parent_path == "." {
		parent_path = ""
	}
	return navigate(state, parent_path)
}
