package project

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

@(test)
test_project_save_transaction_rolls_back_every_precommit_failure :: proc(t: ^testing.T) {
	for fail_at in 1 ..= 9 {
		root, first_path, second_path, ok := make_save_transaction_fixture(t)
		if !ok {
			return
		}
		control := Save_Transaction_Control {
			fail_at = fail_at,
			mode = .Error,
		}
		files := []Save_File {
			{path = first_path, source = "new scene\n"},
			{path = second_path, source = "new resource\n"},
		}
		err, crashed := commit_project_save_controlled(root, files, &control)
		testing.expectf(t, control.triggered, "failure step %d was not reached", fail_at)
		testing.expect(t, err != "")
		testing.expect(t, !crashed)
		expect_save_file_text(t, first_path, "old scene\n")
		expect_save_file_text(t, second_path, "old resource\n")
		expect_no_save_transaction_artifacts(t, root, first_path, second_path)
		destroy_save_transaction_fixture(root, first_path, second_path)
	}
}

@(test)
test_project_save_transaction_recovers_crashes_before_and_after_commit :: proc(t: ^testing.T) {
	for fail_at in 1 ..= 10 {
		root, first_path, second_path, ok := make_save_transaction_fixture(t)
		if !ok {
			return
		}
		control := Save_Transaction_Control {
			fail_at = fail_at,
			mode = .Crash,
		}
		files := []Save_File {
			{path = first_path, source = "new scene\n"},
			{path = second_path, source = "new resource\n"},
		}
		err, crashed := commit_project_save_controlled(root, files, &control)
		testing.expectf(t, control.triggered, "crash step %d was not reached", fail_at)
		testing.expect(t, err != "")
		testing.expect(t, crashed)
		testing.expectf(
			t,
			recover_project_save(root) == "",
			"recovery failed after crash step %d",
			fail_at,
		)
		if fail_at == 10 {
			expect_save_file_text(t, first_path, "new scene\n")
			expect_save_file_text(t, second_path, "new resource\n")
		} else {
			expect_save_file_text(t, first_path, "old scene\n")
			expect_save_file_text(t, second_path, "old resource\n")
		}
		expect_no_save_transaction_artifacts(t, root, first_path, second_path)
		destroy_save_transaction_fixture(root, first_path, second_path)
	}
}

@(test)
test_project_save_transaction_commits_all_files_together :: proc(t: ^testing.T) {
	root, first_path, second_path, ok := make_save_transaction_fixture(t)
	if !ok {
		return
	}
	defer destroy_save_transaction_fixture(root, first_path, second_path)
	files := []Save_File {
		{path = first_path, source = "new scene\n"},
		{path = second_path, source = "new resource\n"},
	}
	testing.expect(t, commit_project_save(root, files) == "")
	expect_save_file_text(t, first_path, "new scene\n")
	expect_save_file_text(t, second_path, "new resource\n")
	expect_no_save_transaction_artifacts(t, root, first_path, second_path)
}

@(test)
test_project_load_recovers_interrupted_project_save_before_parsing :: proc(t: ^testing.T) {
	failure_steps := [?]int{6, 10}
	for fail_at in failure_steps {
		parent, temp_err := os.make_directory_temp(
			"",
			"scrapbot-project-load-recovery-*",
			context.allocator,
		)
		testing.expect(t, temp_err == nil)
		if temp_err != nil {
			return
		}
		root, root_err := filepath.join({parent, "project"})
		testing.expect(t, root_err == nil)
		if root_err != nil {
			_ = os.remove_all(parent)
			delete(parent)
			return
		}
		testing.expect(t, init_project(root, "Recovery Fixture") == "")
		scene_path, _ := filepath.join({root, DEFAULT_SCENE})
		resource_path, _ := filepath.join({root, "resources", "default.resource.toml"})
		old_scene := read_save_file_text(t, scene_path)
		old_resource := read_save_file_text(t, resource_path)
		new_scene, _ := strings.concatenate({old_scene, "\n"})
		new_resource, _ := strings.concatenate({old_resource, "\n"})
		files := []Save_File {
			{path = scene_path, source = new_scene},
			{path = resource_path, source = new_resource},
		}
		control := Save_Transaction_Control {
			fail_at = fail_at,
			mode = .Crash,
		}
		_, crashed := commit_project_save_controlled(root, files, &control)
		testing.expect(t, crashed)
		loaded := load_project(root)
		testing.expectf(t, loaded.err == "", "load recovery failed: %s", loaded.err)
		destroy_project_load_result(&loaded)
		if fail_at == 10 {
			expect_save_file_text(t, scene_path, new_scene)
			expect_save_file_text(t, resource_path, new_resource)
		} else {
			expect_save_file_text(t, scene_path, old_scene)
			expect_save_file_text(t, resource_path, old_resource)
		}
		expect_no_save_transaction_artifacts(t, root, scene_path, resource_path)
		delete(new_resource)
		delete(new_scene)
		delete(old_resource)
		delete(old_scene)
		delete(resource_path)
		delete(scene_path)
		_ = os.remove_all(parent)
		delete(root)
		delete(parent)
	}
}

@(private)
make_save_transaction_fixture :: proc(
	t: ^testing.T,
) -> (
	root, first_path, second_path: string,
	ok: bool,
) {
	temp_root, temp_err := os.make_directory_temp("", "scrapbot-project-save-*", context.allocator)
	testing.expect(t, temp_err == nil)
	if temp_err != nil {
		return "", "", "", false
	}
	root = temp_root
	first, first_err := filepath.join({root, "scene.toml"})
	second, second_err := filepath.join({root, "resource.toml"})
	first_path = first
	second_path = second
	if first_err != nil || second_err != nil {
		delete(first_path)
		delete(second_path)
		os.remove_all(root)
		delete(root)
		testing.expect(t, false)
		return "", "", "", false
	}
	if os.write_entire_file(first_path, "old scene\n") != nil ||
	   os.write_entire_file(second_path, "old resource\n") != nil {
		destroy_save_transaction_fixture(root, first_path, second_path)
		testing.expect(t, false)
		return "", "", "", false
	}
	return root, first_path, second_path, true
}

@(private)
destroy_save_transaction_fixture :: proc(root, first_path, second_path: string) {
	_ = os.remove_all(root)
	delete(first_path)
	delete(second_path)
	delete(root)
}

@(private)
expect_save_file_text :: proc(t: ^testing.T, path, expected: string) {
	actual := read_save_file_text(t, path)
	defer delete(actual)
	testing.expect_value(t, actual, expected)
}

@(private)
read_save_file_text :: proc(t: ^testing.T, path: string) -> string {
	bytes, read_err := os.read_entire_file(path, context.temp_allocator)
	testing.expect(t, read_err == nil)
	if read_err != nil {
		return ""
	}
	result, clone_err := strings.clone(string(bytes))
	testing.expect(t, clone_err == nil)
	return result
}

@(private)
expect_no_save_transaction_artifacts :: proc(
	t: ^testing.T,
	root, first_path, second_path: string,
) {
	pending_path, _ := filepath.join({root, SAVE_TRANSACTION_PENDING})
	committed_path, _ := filepath.join({root, SAVE_TRANSACTION_COMMITTED})
	commit_stage_path, _ := filepath.join({root, SAVE_TRANSACTION_COMMIT_STAGE})
	first_stage := save_artifact_path(first_path, SAVE_TRANSACTION_STAGE_SUFFIX)
	first_backup := save_artifact_path(first_path, SAVE_TRANSACTION_BACKUP_SUFFIX)
	second_stage := save_artifact_path(second_path, SAVE_TRANSACTION_STAGE_SUFFIX)
	second_backup := save_artifact_path(second_path, SAVE_TRANSACTION_BACKUP_SUFFIX)
	defer delete(pending_path)
	defer delete(committed_path)
	defer delete(commit_stage_path)
	defer delete(first_stage)
	defer delete(first_backup)
	defer delete(second_stage)
	defer delete(second_backup)
	testing.expect(t, !os.exists(pending_path))
	testing.expect(t, !os.exists(committed_path))
	testing.expect(t, !os.exists(commit_stage_path))
	testing.expect(t, !os.exists(first_stage))
	testing.expect(t, !os.exists(first_backup))
	testing.expect(t, !os.exists(second_stage))
	testing.expect(t, !os.exists(second_backup))
}
