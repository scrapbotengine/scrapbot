package project

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

@(private)
SAVE_TRANSACTION_PENDING :: ".scrapbot-save.pending"
@(private)
SAVE_TRANSACTION_COMMITTED :: ".scrapbot-save.committed"
@(private)
SAVE_TRANSACTION_COMMIT_STAGE :: ".scrapbot-save.commit-stage"
@(private)
SAVE_TRANSACTION_STAGE_SUFFIX :: ".scrapbot-save.stage"
@(private)
SAVE_TRANSACTION_BACKUP_SUFFIX :: ".scrapbot-save.backup"
@(private)
SAVE_TRANSACTION_NEW_SUFFIX :: ".scrapbot-save.new"

Save_File_Action :: enum {
	Write,
	Delete,
}

Save_File :: struct {
	path: string,
	source: string,
	action: Save_File_Action,
	expect_missing: bool,
}

@(private)
Save_Transaction_Fault_Mode :: enum {
	None,
	Error,
	Crash,
}

@(private)
Save_Transaction_Control :: struct {
	fail_at: int,
	step: int,
	triggered: bool,
	mode: Save_Transaction_Fault_Mode,
}

destroy_owned_save_files :: proc(files: ^[dynamic]Save_File) {
	if files == nil {
		return
	}
	for &file in files^ {
		delete(file.path)
		delete(file.source)
	}
	delete(files^)
	files^ = nil
}

commit_project_save :: proc(root: string, files: []Save_File) -> string {
	err, _ := commit_project_save_controlled(root, files, nil)
	return err
}

recover_project_save :: proc(root: string) -> string {
	pending_path, pending_err := filepath.join({root, SAVE_TRANSACTION_PENDING})
	if pending_err != nil {
		return "failed to allocate project save recovery path"
	}
	defer delete(pending_path)
	committed_path, committed_err := filepath.join({root, SAVE_TRANSACTION_COMMITTED})
	if committed_err != nil {
		return "failed to allocate project save commit path"
	}
	defer delete(committed_path)
	commit_stage_path, commit_stage_err := filepath.join({root, SAVE_TRANSACTION_COMMIT_STAGE})
	if commit_stage_err != nil {
		return "failed to allocate project save staging path"
	}
	defer delete(commit_stage_path)

	if !os.exists(pending_path) && !os.exists(committed_path) {
		_ = os.remove(commit_stage_path)
		return ""
	}
	committed := os.exists(committed_path)
	if err := recover_save_artifacts(root, committed); err != "" {
		return err
	}
	_ = os.remove(commit_stage_path)
	_ = os.remove(committed_path)
	_ = os.remove(pending_path)
	return ""
}

@(private)
commit_project_save_controlled :: proc(
	root: string,
	files: []Save_File,
	control: ^Save_Transaction_Control,
) -> (
	err: string,
	crashed: bool,
) {
	if len(files) == 0 {
		return "", false
	}
	if recovery_err := recover_project_save(root); recovery_err != "" {
		return recovery_err, false
	}
	if validation_err := validate_save_files(root, files); validation_err != "" {
		return validation_err, false
	}

	pending_path, _ := filepath.join({root, SAVE_TRANSACTION_PENDING})
	defer delete(pending_path)
	committed_path, _ := filepath.join({root, SAVE_TRANSACTION_COMMITTED})
	defer delete(committed_path)
	commit_stage_path, _ := filepath.join({root, SAVE_TRANSACTION_COMMIT_STAGE})
	defer delete(commit_stage_path)

	if transaction_fault(control) {
		return finish_transaction_fault(root, control)
	}
	if write_err := os.write_entire_file(pending_path, "scrapbot project save pending\n");
	   write_err != nil {
		return fmt.tprintf("failed to begin project save transaction: %v", write_err), false
	}

	for file in files {
		if file.action == .Delete {
			continue
		}
		if parent_err := ensure_save_parent_directory(file.path); parent_err != "" {
			err = parent_err
			break
		}
		if !os.exists(file.path) {
			new_path := save_artifact_path(file.path, SAVE_TRANSACTION_NEW_SUFFIX)
			if new_path == "" {
				err = "failed to allocate project save creation marker path"
				break
			}
			if write_err := os.write_entire_file(new_path, "new\n"); write_err != nil {
				err = fmt.tprintf("failed to mark new project save file: %v", write_err)
				delete(new_path)
				break
			}
			delete(new_path)
		}
		stage_path := save_artifact_path(file.path, SAVE_TRANSACTION_STAGE_SUFFIX)
		if stage_path == "" {
			err = "failed to allocate project save stage path"
			break
		}
		if transaction_fault(control) {
			delete(stage_path)
			return finish_transaction_fault(root, control)
		}
		write_err := os.write_entire_file(stage_path, file.source)
		delete(stage_path)
		if write_err != nil {
			err = fmt.tprintf("failed to stage project save file: %v", write_err)
			break
		}
	}
	if err == "" {
		for file in files {
			if !os.exists(file.path) {
				continue
			}
			backup_path := save_artifact_path(file.path, SAVE_TRANSACTION_BACKUP_SUFFIX)
			if backup_path == "" {
				err = "failed to allocate project save backup path"
				break
			}
			if transaction_fault(control) {
				delete(backup_path)
				return finish_transaction_fault(root, control)
			}
			rename_err := os.rename(file.path, backup_path)
			delete(backup_path)
			if rename_err != nil {
				err = fmt.tprintf("failed to back up project save file: %v", rename_err)
				break
			}
		}
	}
	if err == "" {
		for file in files {
			if file.action == .Delete {
				continue
			}
			stage_path := save_artifact_path(file.path, SAVE_TRANSACTION_STAGE_SUFFIX)
			if stage_path == "" {
				err = "failed to allocate project save stage path"
				break
			}
			if transaction_fault(control) {
				delete(stage_path)
				return finish_transaction_fault(root, control)
			}
			rename_err := os.rename(stage_path, file.path)
			delete(stage_path)
			if rename_err != nil {
				err = fmt.tprintf("failed to install project save file: %v", rename_err)
				break
			}
		}
	}
	if err == "" {
		if transaction_fault(control) {
			return finish_transaction_fault(root, control)
		}
		if write_err := os.write_entire_file(commit_stage_path, "committed\n"); write_err != nil {
			err = fmt.tprintf("failed to mark project save committed: %v", write_err)
		}
	}
	if err == "" {
		if transaction_fault(control) {
			return finish_transaction_fault(root, control)
		}
		if rename_err := os.rename(commit_stage_path, committed_path); rename_err != nil {
			err = fmt.tprintf("failed to commit project save transaction: %v", rename_err)
		}
	}
	if err != "" {
		if recovery_err := recover_project_save(root); recovery_err != "" {
			return fmt.tprintf("%s; rollback failed: %s", err, recovery_err), false
		}
		return err, false
	}
	if control != nil && control.mode == .Crash && transaction_fault(control) {
		return transaction_fault_result(control)
	}

	_ = recover_project_save(root)
	return "", false
}

@(private)
ensure_save_parent_directory :: proc(path: string) -> string {
	separator := -1
	for value, index in path {
		if value == '/' || value == '\\' {
			separator = index
		}
	}
	if separator <= 0 {
		return ""
	}
	if os.exists(path[:separator]) {
		return ""
	}
	if make_err := os.make_directory_all(path[:separator]); make_err != nil {
		return fmt.tprintf("failed to create project save directory: %v", make_err)
	}
	return ""
}

@(private)
validate_save_files :: proc(root: string, files: []Save_File) -> string {
	seen := make(map[string]bool, len(files))
	defer delete(seen)
	for file in files {
		if file.path == "" {
			return "project save file path is empty"
		}
		relative, relative_err := filepath.rel(root, file.path)
		if relative_err != .None {
			return "project save file is outside the project root"
		}
		defer delete(relative)
		outside :=
			relative == ".." ||
			(len(relative) > 2 && relative[:2] == ".." && relative[2] == byte(filepath.SEPARATOR))
		if outside || filepath.is_abs(relative) {
			return "project save file is outside the project root"
		}
		if strings.has_suffix(file.path, SAVE_TRANSACTION_STAGE_SUFFIX) ||
		   strings.has_suffix(file.path, SAVE_TRANSACTION_BACKUP_SUFFIX) ||
		   strings.has_suffix(file.path, SAVE_TRANSACTION_NEW_SUFFIX) {
			return "project save file uses a reserved transaction suffix"
		}
		if seen[file.path] {
			return "project save contains the same file more than once"
		}
		if file.action == .Delete {
			if !os.exists(file.path) {
				return "project save cannot delete a missing source file"
			}
			if file.source != "" {
				return "project save deletion must not contain source"
			}
		} else if file.source == "" {
			return "project save write source is empty"
		} else if file.expect_missing && os.exists(file.path) {
			return "project save cannot create a file that already exists"
		}
		seen[file.path] = true
	}
	return ""
}

@(private)
recover_save_artifacts :: proc(root: string, committed: bool) -> string {
	return recover_save_artifacts_in_directory(root, committed, true)
}

@(private)
recover_save_artifacts_in_directory :: proc(
	directory: string,
	committed: bool,
	is_root: bool,
) -> string {
	entries, read_err := os.read_all_directory_by_path(directory, context.allocator)
	if read_err != nil {
		return fmt.tprintf("failed to inspect project save artifacts: %v", read_err)
	}
	defer os.file_info_slice_delete(entries, context.allocator)
	for entry in entries {
		if entry.type == .Directory {
			if is_root && (entry.name == ".git" || entry.name == "build") {
				continue
			}
			if err := recover_save_artifacts_in_directory(entry.fullpath, committed, false);
			   err != "" {
				return err
			}
			continue
		}
		if entry.type != .Regular {
			continue
		}
		if strings.has_suffix(entry.name, SAVE_TRANSACTION_STAGE_SUFFIX) {
			if remove_err := os.remove(entry.fullpath); remove_err != nil {
				return fmt.tprintf("failed to remove project save stage: %v", remove_err)
			}
			continue
		}
		if strings.has_suffix(entry.name, SAVE_TRANSACTION_NEW_SUFFIX) {
			destination := entry.fullpath[:len(entry.fullpath) - len(SAVE_TRANSACTION_NEW_SUFFIX)]
			if !committed && os.exists(destination) {
				if remove_err := os.remove(destination); remove_err != nil {
					return fmt.tprintf(
						"failed to remove incomplete new project save file: %v",
						remove_err,
					)
				}
			}
			if remove_err := os.remove(entry.fullpath); remove_err != nil {
				return fmt.tprintf("failed to remove project save creation marker: %v", remove_err)
			}
			continue
		}
		if !strings.has_suffix(entry.name, SAVE_TRANSACTION_BACKUP_SUFFIX) {
			continue
		}
		if committed {
			if remove_err := os.remove(entry.fullpath); remove_err != nil {
				return fmt.tprintf("failed to remove project save backup: %v", remove_err)
			}
			continue
		}
		destination := entry.fullpath[:len(entry.fullpath) - len(SAVE_TRANSACTION_BACKUP_SUFFIX)]
		if os.exists(destination) {
			if remove_err := os.remove(destination); remove_err != nil {
				return fmt.tprintf("failed to remove incomplete project save file: %v", remove_err)
			}
		}
		if rename_err := os.rename(entry.fullpath, destination); rename_err != nil {
			return fmt.tprintf("failed to restore project save backup: %v", rename_err)
		}
	}
	return ""
}

@(private)
save_artifact_path :: proc(path, suffix: string) -> string {
	result, err := strings.concatenate({path, suffix})
	if err != nil {
		return ""
	}
	return result
}

@(private)
transaction_fault :: proc(control: ^Save_Transaction_Control) -> bool {
	if control == nil || control.fail_at <= 0 || control.mode == .None {
		return false
	}
	control.step += 1
	if control.step != control.fail_at {
		return false
	}
	control.triggered = true
	return true
}

@(private)
transaction_fault_result :: proc(control: ^Save_Transaction_Control) -> (string, bool) {
	if control != nil && control.mode == .Crash {
		return "simulated project save crash", true
	}
	return "injected project save failure", false
}

@(private)
finish_transaction_fault :: proc(
	root: string,
	control: ^Save_Transaction_Control,
) -> (
	string,
	bool,
) {
	err, crashed := transaction_fault_result(control)
	if crashed {
		return err, true
	}
	if recovery_err := recover_project_save(root); recovery_err != "" {
		return fmt.tprintf("%s; rollback failed: %s", err, recovery_err), false
	}
	return err, false
}
