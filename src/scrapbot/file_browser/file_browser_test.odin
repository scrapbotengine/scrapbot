package file_browser

import "core:os"
import "core:path/filepath"
import "core:testing"

write_fixture :: proc(t: ^testing.T, root, relative, contents: string) {
	path, path_err := filepath.join({root, relative})
	testing.expect(t, path_err == nil)
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, contents) == nil)
}

@(test)
test_rooted_browser_filters_sorts_and_navigates_without_reading_file_payloads :: proc(
	t: ^testing.T,
) {
	root, root_err := os.make_directory_temp("", "scrapbot-file-browser-*", context.temp_allocator)
	testing.expect(t, root_err == nil)
	if root_err != nil { return }
	defer os.remove_all(root)
	models, models_err := filepath.join({root, "Models"})
	testing.expect(t, models_err == nil)
	defer delete(models)
	testing.expect(t, os.mkdir(models) == nil)
	write_fixture(t, root, "zeta.resource.toml", "z")
	write_fixture(t, root, "Alpha.resource.toml", "alpha")
	write_fixture(t, root, "ignored.txt", "ignore")
	write_fixture(t, root, ".hidden.resource.toml", "hidden")
	write_fixture(t, models, "Rock.resource.toml", "rock")

	state: State
	filter := default_filter()
	filter.extensions = []string{".resource.toml"}
	testing.expect(t, init(&state, root, filter) == "")
	defer destroy(&state)
	testing.expect_value(t, len(state.entries), 3)
	if len(state.entries) == 3 {
		testing.expect(t, state.entries[0].kind == .Directory)
		testing.expect_value(t, state.entries[0].name, "Models")
		testing.expect_value(t, state.entries[1].name, "Alpha.resource.toml")
		testing.expect_value(t, state.entries[2].name, "zeta.resource.toml")
		testing.expect_value(t, state.entries[1].size, i64(5))
	}
	testing.expect(t, enter(&state, "Models") == "")
	testing.expect_value(t, state.directory, "Models")
	testing.expect_value(t, len(state.entries), 1)
	if len(state.entries) == 1 {
		expected, expected_err := filepath.join({"Models", "Rock.resource.toml"})
		testing.expect(t, expected_err == nil)
		defer delete(expected)
		testing.expect_value(t, state.entries[0].path, expected)
	}
	testing.expect(t, parent(&state) == "")
	testing.expect_value(t, state.directory, "")
}

@(test)
test_rooted_browser_rejects_escape_and_ignores_symlinks :: proc(t: ^testing.T) {
	root, root_err := os.make_directory_temp("", "scrapbot-file-browser-*", context.temp_allocator)
	testing.expect(t, root_err == nil)
	if root_err != nil { return }
	defer os.remove_all(root)
	outside, outside_err := os.make_directory_temp(
		"",
		"scrapbot-file-browser-outside-*",
		context.temp_allocator,
	)
	testing.expect(t, outside_err == nil)
	if outside_err != nil { return }
	defer os.remove_all(outside)
	link, link_err := filepath.join({root, "linked-outside"})
	testing.expect(t, link_err == nil)
	defer delete(link)
	testing.expect(t, os.symlink(outside, link) == nil)
	state: State
	testing.expect(t, init(&state, root, default_filter()) == "")
	defer destroy(&state)
	testing.expect_value(t, len(state.entries), 0)
	_, resolve_err := resolve(&state, "../outside")
	testing.expect(t, resolve_err != "")
	testing.expect(t, navigate(&state, "../outside") != "")
	testing.expect(t, navigate(&state, "linked-outside") != "")
	testing.expect_value(t, state.directory, "")
	testing.expect(t, enter(&state, "..") != "")
}
