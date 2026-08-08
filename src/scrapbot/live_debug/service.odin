package live_debug

import "core:crypto"
import "core:encoding/cbor"
import "core:encoding/hex"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"

SCHEMA_VERSION :: 1
MAX_CAPTURE_FRAMES :: 16

Codec :: enum {
	JSON,
	CBOR,
}

Capture_Status :: enum {
	None,
	Pending,
	Capturing,
	Complete,
	Failed,
}

Capture_Artifact :: enum {
	Color,
	Depth,
	Visibility,
}

Capture_Artifacts :: bit_set[Capture_Artifact]

Vec3 :: struct {
	x, y, z: f32,
}

Rect :: struct {
	x, y, width, height: f32,
}

Camera_Snapshot :: struct {
	available: bool,
	entity_uuid: string,
	position: Vec3,
	rotation: Vec3,
	forward: Vec3,
	fov: f32,
	near: f32,
	far: f32,
	debug_view: string,
}

Renderer_Snapshot :: struct {
	backend: string,
	frame_index: u64,
	output_width: u32,
	output_height: u32,
	render_width: u32,
	render_height: u32,
	pixel_density: f32,
	viewport: Rect,
	draw_batches: int,
	conventional_batches: int,
	virtual_batches: int,
	conventional_instances: int,
	virtual_instances: int,
	visible_batches: u32,
	visible_meshlet_draws: u32,
	visible_virtual_clusters: u32,
	visible_virtual_blend_clusters: u32,
	virtual_rejected_clusters: u32,
	virtual_geometry_page_budget_bytes: u64,
	virtual_geometry_page_resident_bytes: u64,
	virtual_geometry_pages: int,
	virtual_geometry_resident_pages: int,
	virtual_geometry_pinned_pages: int,
	virtual_geometry_prefetched_pages: int,
	virtual_geometry_page_requests: u32,
	virtual_geometry_page_prefetches: u32,
	virtual_geometry_page_request_overflow: u32,
	virtual_geometry_page_uploads: u64,
	virtual_geometry_page_evictions: u64,
	virtual_geometry_group_uploads: u64,
	virtual_geometry_group_activations: u64,
	virtual_geometry_transitioning_groups: u32,
	virtual_geometry_group_evictions: u64,
	virtual_geometry_deferred_groups: u64,
	gpu_timestamps_valid: bool,
	gpu_frame_ms: f64,
	gpu_scene_ms: f64,
}

Snapshot :: struct {
	schema_version: int,
	process_id: int,
	project_root: string,
	phase: string,
	frame_index: u64,
	world_uuid: string,
	entity_count: int,
	editor_visible: bool,
	camera: Camera_Snapshot,
	renderer: Renderer_Snapshot,
}

Capture_Request :: struct {
	frames: u32,
	artifacts: []string,
}

Capture_Job :: struct {
	schema_version: int,
	id: u64,
	status: string,
	frames_requested: u32,
	frames_captured: u32,
	directory: string,
	manifest: string,
	error: string,
	artifacts: []string,
}

Capture_Frame_Plan :: struct {
	active: bool,
	id: u64,
	frame_number: u32,
	directory: string,
	artifacts: Capture_Artifacts,
}

Capture_Artifact_Manifest :: struct {
	kind: string,
	media_type: string,
	pattern: string,
}

Capture_Manifest :: struct {
	schema_version: int,
	id: u64,
	frames: u32,
	first_frame_index: u64,
	last_frame_index: u64,
	snapshot_pattern: string,
	artifacts: []Capture_Artifact_Manifest,
}

Error_Response :: struct {
	schema_version: int,
	code: string,
	message: string,
}

Service :: struct {
	mutex: sync.Mutex,
	root: string,
	discovery_path: string,
	capture_root: string,
	token: string,
	process_id: int,
	port: int,
	running: bool,
	snapshot: Snapshot,
	next_capture_id: u64,
	capture: Capture_Job,
	capture_status: Capture_Status,
	capture_first_frame_index: u64,
	capture_artifacts: Capture_Artifacts,
	capture_artifacts_ready: bool,
}

init_service :: proc(service: ^Service, root: string) -> string {
	if service == nil {
		return "live debug service is unavailable"
	}
	service^ = {}
	service.root = strings.clone(root)
	process_info, process_err := os.current_process_info({}, context.temp_allocator)
	defer os.free_process_info(process_info, context.temp_allocator)
	if process_err != nil {
		return fmt.tprintf("failed to inspect the live debug process: %v", process_err)
	}
	service.process_id = process_info.pid
	token_bytes: [24]byte
	crypto.rand_bytes(token_bytes[:])
	token_builder: strings.Builder
	strings.builder_init(&token_builder)
	defer strings.builder_destroy(&token_builder)
	hex.encode_into_writer(strings.to_writer(&token_builder), token_bytes[:])
	service.token = strings.clone(strings.to_string(token_builder))
	live_root, live_err := filepath.join({root, ".scrapbot", "live"})
	if live_err != nil {
		return "failed to allocate live debug directory"
	}
	defer delete(live_root)
	if make_err := ensure_directory(live_root); make_err != nil {
		return fmt.tprintf("failed to create live debug directory: %v", make_err)
	}
	capture_process_name := fmt.aprintf("%d", service.process_id)
	defer delete(capture_process_name)
	capture_root, capture_err := filepath.join({live_root, "captures", capture_process_name})
	if capture_err != nil {
		return "failed to allocate live debug capture directory"
	}
	service.capture_root = capture_root
	if make_err := ensure_directory(service.capture_root); make_err != nil {
		return fmt.tprintf("failed to create live debug capture directory: %v", make_err)
	}
	discovery_name := fmt.aprintf("%d.json", service.process_id)
	defer delete(discovery_name)
	discovery_path, discovery_err := filepath.join({live_root, discovery_name})
	if discovery_err != nil {
		return "failed to allocate live debug discovery path"
	}
	service.discovery_path = discovery_path
	service.next_capture_id = 1
	service.snapshot = {
		schema_version = SCHEMA_VERSION,
		process_id = service.process_id,
		project_root = strings.clone(service.root),
		phase = strings.clone("starting"),
	}
	return ""
}

destroy_service :: proc(service: ^Service) {
	if service == nil {
		return
	}
	delete(service.capture.error)
	delete(service.capture.manifest)
	delete(service.capture.directory)
	delete(service.capture.artifacts)
	destroy_snapshot_strings(&service.snapshot)
	delete(service.token)
	delete(service.capture_root)
	delete(service.discovery_path)
	delete(service.root)
	service^ = {}
}

publish_snapshot :: proc(service: ^Service, snapshot: Snapshot) {
	if service == nil {
		return
	}
	sync.mutex_lock(&service.mutex)
	defer sync.mutex_unlock(&service.mutex)
	project_root := service.snapshot.project_root
	phase := service.snapshot.phase
	world_uuid := service.snapshot.world_uuid
	camera_uuid := service.snapshot.camera.entity_uuid
	debug_view := service.snapshot.camera.debug_view
	backend := service.snapshot.renderer.backend
	service.snapshot = snapshot
	service.snapshot.project_root = project_root
	service.snapshot.phase = phase
	service.snapshot.world_uuid = world_uuid
	service.snapshot.camera.entity_uuid = camera_uuid
	service.snapshot.camera.debug_view = debug_view
	service.snapshot.renderer.backend = backend
	replace_owned_string(&service.snapshot.phase, snapshot.phase)
	replace_owned_string(&service.snapshot.world_uuid, snapshot.world_uuid)
	replace_owned_string(&service.snapshot.camera.entity_uuid, snapshot.camera.entity_uuid)
	replace_owned_string(&service.snapshot.camera.debug_view, snapshot.camera.debug_view)
	replace_owned_string(&service.snapshot.renderer.backend, snapshot.renderer.backend)
	service.snapshot.schema_version = SCHEMA_VERSION
	service.snapshot.process_id = service.process_id
}

capture_published_snapshot :: proc(service: ^Service) -> string {
	if service == nil {
		return ""
	}
	_ = begin_capture_frame(service)
	sync.mutex_lock(&service.mutex)
	if service.capture_status != .Capturing {
		sync.mutex_unlock(&service.mutex)
		return ""
	}
	if card(service.capture_artifacts) > 0 && !service.capture_artifacts_ready {
		sync.mutex_unlock(&service.mutex)
		return ""
	}
	if service.capture.frames_captured == 0 {
		service.capture_first_frame_index = service.snapshot.frame_index
	}
	capture_id := service.capture.id
	frame_number := service.capture.frames_captured
	directory := strings.clone(service.capture.directory)
	snapshot_data, marshal_err := json.marshal(service.snapshot)
	sync.mutex_unlock(&service.mutex)
	defer delete(directory)
	if marshal_err != nil {
		message := fmt.tprintf("failed to encode captured snapshot: %v", marshal_err)
		capture_fail(service, message)
		return message
	}
	defer delete(snapshot_data)
	if frame_number == 0 {
		make_err := ensure_directory(directory)
		if make_err != nil {
			message := fmt.tprintf("failed to create live debug capture directory: %v", make_err)
			capture_fail(service, message)
			return message
		}
	}
	file_name := fmt.aprintf("frame-%04d.json", frame_number)
	defer delete(file_name)
	path, path_err := filepath.join({directory, file_name})
	if path_err != nil {
		message := "failed to allocate captured snapshot path"
		capture_fail(service, message)
		return message
	}
	defer delete(path)
	if write_err := write_private_file(path, snapshot_data); write_err != nil {
		message := fmt.tprintf("failed to write captured snapshot: %v", write_err)
		capture_fail(service, message)
		return message
	}
	sync.mutex_lock(&service.mutex)
	if service.capture.id != capture_id || service.capture_status != .Capturing {
		sync.mutex_unlock(&service.mutex)
		return ""
	}
	service.capture.frames_captured += 1
	service.capture_artifacts_ready = false
	complete := service.capture.frames_captured >= service.capture.frames_requested
	manifest := Capture_Manifest {
		schema_version = SCHEMA_VERSION,
		id = capture_id,
		frames = service.capture.frames_captured,
		first_frame_index = service.capture_first_frame_index,
		last_frame_index = service.snapshot.frame_index,
		snapshot_pattern = "frame-%04d.json",
		artifacts = capture_artifact_manifest(service.capture_artifacts),
	}
	sync.mutex_unlock(&service.mutex)
	defer delete(manifest.artifacts)
	if !complete {
		return ""
	}
	manifest_data, manifest_err := json.marshal(manifest)
	if manifest_err != nil {
		message := fmt.tprintf("failed to encode capture manifest: %v", manifest_err)
		capture_fail(service, message)
		return message
	}
	defer delete(manifest_data)
	manifest_path, manifest_path_err := filepath.join({directory, "manifest.json"})
	if manifest_path_err != nil {
		message := "failed to allocate capture manifest path"
		capture_fail(service, message)
		return message
	}
	defer delete(manifest_path)
	if write_err := write_private_file(manifest_path, manifest_data); write_err != nil {
		message := fmt.tprintf("failed to write capture manifest: %v", write_err)
		capture_fail(service, message)
		return message
	}
	capture_complete(service, manifest_path)
	return ""
}

ensure_directory :: proc(path: string) -> os.Error {
	if os.exists(path) {
		return nil
	}
	return os.make_directory_all(path)
}

write_private_file :: proc(path: string, data: []byte) -> os.Error {
	if write_err := os.write_entire_file(path, data); write_err != nil {
		return write_err
	}
	if mode_err := os.chmod(path, {.Read_User, .Write_User}); mode_err != nil {
		_ = os.remove(path)
		return mode_err
	}
	return nil
}

update_phase :: proc(service: ^Service, phase: string) {
	if service == nil {
		return
	}
	sync.mutex_lock(&service.mutex)
	defer sync.mutex_unlock(&service.mutex)
	delete(service.snapshot.phase)
	service.snapshot.phase = strings.clone(phase)
}

replace_owned_string :: proc(destination: ^string, value: string) {
	if destination^ == value {
		return
	}
	delete(destination^)
	destination^ = strings.clone(value)
}

destroy_snapshot_strings :: proc(snapshot: ^Snapshot) {
	if snapshot == nil {
		return
	}
	delete(snapshot.renderer.backend)
	delete(snapshot.camera.debug_view)
	delete(snapshot.camera.entity_uuid)
	delete(snapshot.world_uuid)
	delete(snapshot.phase)
	delete(snapshot.project_root)
	snapshot^ = {}
}

encode_snapshot :: proc(service: ^Service, codec: Codec) -> ([]byte, string) {
	if service == nil {
		return nil, "live debug service is unavailable"
	}
	sync.mutex_lock(&service.mutex)
	defer sync.mutex_unlock(&service.mutex)
	switch codec {
		case .JSON:
			data, err := json.marshal(service.snapshot)
			if err != nil {
				return nil, fmt.tprintf("failed to encode live debug JSON: %v", err)
			}
			return data, ""
		case .CBOR:
			data, err := cbor.marshal(service.snapshot, cbor.ENCODE_FULLY_DETERMINISTIC)
			if err != nil {
				return nil, fmt.tprintf("failed to encode live debug CBOR: %v", err)
			}
			return data, ""
	}
	return nil, "unsupported live debug codec"
}

enqueue_capture :: proc(
	service: ^Service,
	requested_frames: u32,
	artifacts: Capture_Artifacts = {},
) -> (
	Capture_Job,
	string,
) {
	if service == nil {
		return {}, "live debug service is unavailable"
	}
	frames := clamp(requested_frames, u32(1), u32(MAX_CAPTURE_FRAMES))
	sync.mutex_lock(&service.mutex)
	defer sync.mutex_unlock(&service.mutex)
	if service.capture_status == .Pending || service.capture_status == .Capturing {
		return service.capture, "a live debug capture is already active"
	}
	delete(service.capture.error)
	delete(service.capture.manifest)
	delete(service.capture.directory)
	delete(service.capture.artifacts)
	id := service.next_capture_id
	service.next_capture_id += 1
	directory_name := fmt.aprintf("capture-%06d", id)
	defer delete(directory_name)
	directory, path_err := filepath.join({service.capture_root, directory_name})
	if path_err != nil {
		return {}, "failed to allocate capture directory"
	}
	service.capture = {
		schema_version = SCHEMA_VERSION,
		id = id,
		status = capture_status_name(.Pending),
		frames_requested = frames,
		directory = directory,
		artifacts = capture_artifact_names(artifacts),
	}
	service.capture_artifacts = artifacts
	service.capture_artifacts_ready = false
	service.capture_status = .Pending
	return service.capture, ""
}

begin_capture_frame :: proc(service: ^Service) -> Capture_Frame_Plan {
	if service == nil {
		return {}
	}
	sync.mutex_lock(&service.mutex)
	defer sync.mutex_unlock(&service.mutex)
	if service.capture_status == .Pending {
		set_capture_status(service, .Capturing)
	}
	if service.capture_status != .Capturing {
		return {}
	}
	return {
		active = true,
		id = service.capture.id,
		frame_number = service.capture.frames_captured,
		directory = service.capture.directory,
		artifacts = service.capture_artifacts,
	}
}

capture_artifact_requested :: proc "contextless" (
	plan: Capture_Frame_Plan,
	artifact: Capture_Artifact,
) -> bool {
	return plan.active && artifact in plan.artifacts
}

capture_frame_artifacts_ready :: proc(service: ^Service, plan: Capture_Frame_Plan) {
	if service == nil || !plan.active {
		return
	}
	sync.mutex_lock(&service.mutex)
	defer sync.mutex_unlock(&service.mutex)
	if service.capture_status != .Capturing ||
	   service.capture.id != plan.id ||
	   service.capture.frames_captured != plan.frame_number {
		return
	}
	service.capture_artifacts_ready = true
}

capture_artifact_path :: proc(
	plan: Capture_Frame_Plan,
	artifact: Capture_Artifact,
) -> (
	string,
	string,
) {
	if !capture_artifact_requested(plan, artifact) {
		return "", "capture artifact was not requested"
	}
	if make_err := ensure_directory(plan.directory); make_err != nil {
		return "", fmt.tprintf("failed to create live debug capture directory: %v", make_err)
	}
	name := fmt.aprintf(
		"%s-%04d%s",
		capture_artifact_name(artifact),
		plan.frame_number,
		capture_artifact_extension(artifact),
	)
	defer delete(name)
	path, path_err := filepath.join({plan.directory, name})
	if path_err != nil {
		return "", "failed to allocate capture artifact path"
	}
	return path, ""
}

capture_complete :: proc(service: ^Service, manifest: string) {
	if service == nil {
		return
	}
	sync.mutex_lock(&service.mutex)
	defer sync.mutex_unlock(&service.mutex)
	if service.capture_status != .Capturing {
		return
	}
	service.capture.manifest = strings.clone(manifest)
	set_capture_status(service, .Complete)
}

capture_fail :: proc(service: ^Service, message: string) {
	if service == nil {
		return
	}
	sync.mutex_lock(&service.mutex)
	defer sync.mutex_unlock(&service.mutex)
	delete(service.capture.error)
	service.capture.error = strings.clone(message)
	set_capture_status(service, .Failed)
}

set_capture_status :: proc(service: ^Service, status: Capture_Status) {
	service.capture_status = status
	service.capture.status = capture_status_name(status)
}

capture_status_name :: proc "contextless" (status: Capture_Status) -> string {
	switch status {
		case .None:
			return "none"
		case .Pending:
			return "pending"
		case .Capturing:
			return "capturing"
		case .Complete:
			return "complete"
		case .Failed:
			return "failed"
	}
	return "unknown"
}

encode_capture :: proc(service: ^Service, codec: Codec) -> ([]byte, string) {
	if service == nil {
		return nil, "live debug service is unavailable"
	}
	sync.mutex_lock(&service.mutex)
	defer sync.mutex_unlock(&service.mutex)
	switch codec {
		case .JSON:
			data, err := json.marshal(service.capture)
			if err != nil {
				return nil, fmt.tprintf("failed to encode capture JSON: %v", err)
			}
			return data, ""
		case .CBOR:
			data, err := cbor.marshal(service.capture, cbor.ENCODE_FULLY_DETERMINISTIC)
			if err != nil {
				return nil, fmt.tprintf("failed to encode capture CBOR: %v", err)
			}
			return data, ""
	}
	return nil, "unsupported live debug codec"
}

decode_capture_request :: proc(data: []byte, codec: Codec) -> (Capture_Request, string) {
	request := Capture_Request {
		frames = 5,
	}
	if len(data) == 0 {
		return request, ""
	}
	switch codec {
		case .JSON:
			if err := json.unmarshal(data, &request); err != nil {
				return {}, fmt.tprintf("invalid capture JSON: %v", err)
			}
		case .CBOR:
			if err := cbor.unmarshal(data, &request); err != nil {
				return {}, fmt.tprintf("invalid capture CBOR: %v", err)
			}
	}
	if request.frames == 0 || request.frames > MAX_CAPTURE_FRAMES {
		destroy_capture_request(&request)
		return {}, fmt.tprintf("capture frames must be between 1 and %d", MAX_CAPTURE_FRAMES)
	}
	if _, artifact_err := parse_capture_artifacts(request.artifacts); artifact_err != "" {
		destroy_capture_request(&request)
		return {}, artifact_err
	}
	return request, ""
}

destroy_capture_request :: proc(request: ^Capture_Request) {
	if request == nil {
		return
	}
	for artifact in request.artifacts {
		delete(artifact)
	}
	delete(request.artifacts)
	request^ = {}
}

parse_capture_artifacts :: proc(values: []string) -> (Capture_Artifacts, string) {
	result: Capture_Artifacts
	for value in values {
		switch value {
			case "color":
				result |= {.Color}
			case "depth":
				result |= {.Depth}
			case "visibility":
				result |= {.Visibility}
			case:
				return {}, fmt.tprintf("unsupported capture artifact %q", value)
		}
	}
	return result, ""
}

capture_artifact_name :: proc "contextless" (artifact: Capture_Artifact) -> string {
	switch artifact {
		case .Color:
			return "color"
		case .Depth:
			return "depth"
		case .Visibility:
			return "visibility"
	}
	return "unknown"
}

capture_artifact_extension :: proc "contextless" (artifact: Capture_Artifact) -> string {
	switch artifact {
		case .Color:
			return ".png"
		case .Depth:
			return ".f32"
		case .Visibility:
			return ".cbor"
	}
	return ".bin"
}

capture_artifact_names :: proc(artifacts: Capture_Artifacts) -> []string {
	result := make([]string, card(artifacts))
	index := 0
	for artifact in artifacts {
		result[index] = capture_artifact_name(artifact)
		index += 1
	}
	return result
}

capture_artifact_manifest :: proc(artifacts: Capture_Artifacts) -> []Capture_Artifact_Manifest {
	manifest_count := card(artifacts)
	if .Depth in artifacts {
		manifest_count += 1
	}
	result := make([]Capture_Artifact_Manifest, manifest_count)
	index := 0
	for artifact in artifacts {
		switch artifact {
			case .Color:
				result[index] = {
					kind = "color",
					media_type = "image/png",
					pattern = "color-%04d.png",
				}
				index += 1
			case .Depth:
				result[index] = {
					kind = "depth",
					media_type = "application/octet-stream",
					pattern = "depth-%04d.f32",
				}
				index += 1
				result[index] = {
					kind = "depth_preview",
					media_type = "image/png",
					pattern = "depth-preview-%04d.png",
				}
				index += 1
			case .Visibility:
				result[index] = {
					kind = "visibility",
					media_type = "application/cbor",
					pattern = "visibility-%04d.cbor",
				}
				index += 1
		}
	}
	return result
}

capture_companion_path :: proc(
	plan: Capture_Frame_Plan,
	name, extension: string,
) -> (
	string,
	string,
) {
	if !plan.active {
		return "", "capture frame is not active"
	}
	if make_err := ensure_directory(plan.directory); make_err != nil {
		return "", fmt.tprintf("failed to create live debug capture directory: %v", make_err)
	}
	filename := fmt.aprintf("%s-%04d%s", name, plan.frame_number, extension)
	defer delete(filename)
	result, path_err := filepath.join({plan.directory, filename})
	if path_err != nil {
		return "", "failed to allocate capture companion path"
	}
	return result, ""
}

encode_error :: proc(code, message: string, codec: Codec) -> []byte {
	response := Error_Response {
		schema_version = SCHEMA_VERSION,
		code = code,
		message = message,
	}
	switch codec {
		case .JSON:
			data, _ := json.marshal(response)
			return data
		case .CBOR:
			data, _ := cbor.marshal(response, cbor.ENCODE_FULLY_DETERMINISTIC)
			return data
	}
	return nil
}
