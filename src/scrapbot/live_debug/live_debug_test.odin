package live_debug

import "core:encoding/cbor"
import "core:encoding/json"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

@(test)
test_live_debug_snapshot_supports_json_and_cbor :: proc(t: ^testing.T) {
	root, root_err := os.make_directory_temp("", "scrapbot-live-debug-*", context.allocator)
	testing.expect(t, root_err == nil)
	if root_err != nil {
		return
	}
	defer os.remove_all(root)
	defer delete(root)
	service: Service
	testing.expect_value(t, init_service(&service, root), "")
	defer destroy_service(&service)
	publish_snapshot(
		&service,
		Snapshot {
			phase = "running",
			frame_index = 42,
			camera = {available = true, debug_view = "meshlet-visibility"},
			renderer = {backend = "wgpu", visible_virtual_clusters = 73},
		},
	)
	json_data, json_err := encode_snapshot(&service, .JSON)
	defer delete(json_data)
	testing.expect_value(t, json_err, "")
	decoded_json: Snapshot
	defer destroy_snapshot_strings(&decoded_json)
	testing.expect(t, json.unmarshal(json_data, &decoded_json) == nil)
	testing.expect_value(t, decoded_json.frame_index, u64(42))
	testing.expect_value(t, decoded_json.renderer.visible_virtual_clusters, u32(73))
	cbor_data, cbor_err := encode_snapshot(&service, .CBOR)
	defer delete(cbor_data)
	testing.expect_value(t, cbor_err, "")
	decoded_cbor: Snapshot
	defer destroy_snapshot_strings(&decoded_cbor)
	testing.expect(t, cbor.unmarshal(cbor_data, &decoded_cbor) == nil)
	testing.expect_value(t, decoded_cbor.camera.debug_view, "meshlet-visibility")
}

@(test)
test_live_debug_capture_records_consecutive_snapshots :: proc(t: ^testing.T) {
	root, root_err := os.make_directory_temp("", "scrapbot-live-capture-*", context.allocator)
	testing.expect(t, root_err == nil)
	if root_err != nil {
		return
	}
	defer os.remove_all(root)
	defer delete(root)
	service: Service
	testing.expect_value(t, init_service(&service, root), "")
	defer destroy_service(&service)
	job, enqueue_err := enqueue_capture(&service, 3)
	testing.expect_value(t, enqueue_err, "")
	for frame_index in 10 ..< 13 {
		publish_snapshot(&service, Snapshot{phase = "running", frame_index = u64(frame_index)})
		testing.expect_value(t, capture_published_snapshot(&service), "")
	}
	testing.expect_value(t, service.capture.status, "complete")
	testing.expect_value(t, service.capture.frames_captured, u32(3))
	testing.expect(t, service.capture.manifest != "")
	manifest_data, read_err := os.read_entire_file(service.capture.manifest, context.allocator)
	defer delete(manifest_data)
	testing.expect(t, read_err == nil)
	manifest: Capture_Manifest
	defer delete(manifest.snapshot_pattern)
	testing.expect(t, json.unmarshal(manifest_data, &manifest) == nil)
	testing.expect_value(t, manifest.first_frame_index, u64(10))
	testing.expect_value(t, manifest.last_frame_index, u64(12))
	first_path, path_err := filepath.join({job.directory, "frame-0000.json"})
	defer delete(first_path)
	testing.expect(t, path_err == nil)
	first_data, first_err := os.read_entire_file(first_path, context.allocator)
	defer delete(first_data)
	testing.expect(t, first_err == nil)
	first: Snapshot
	defer destroy_snapshot_strings(&first)
	testing.expect(t, json.unmarshal(first_data, &first) == nil)
	testing.expect_value(t, first.frame_index, u64(10))
}

@(test)
test_live_debug_http_parser_and_authentication_are_bounded :: proc(t: ^testing.T) {
	request_text := "POST /v1/captures HTTP/1.1\r\nAuthorization: Bearer secret\r\nAccept: application/cbor\r\nContent-Type: application/json\r\nContent-Length: 12\r\n\r\n{\"frames\":5}"
	request, parse_err := parse_http_request(transmute([]byte)request_text)
	testing.expect_value(t, parse_err, "")
	testing.expect_value(t, request.method, "POST")
	testing.expect_value(t, request.path, "/v1/captures")
	testing.expect_value(t, request.accept, "application/cbor")
	testing.expect_value(t, http_content_length(request_text), 12)
	service := Service {
		token = strings.clone("secret"),
	}
	defer delete(service.token)
	testing.expect(t, authorized(&service, request.authorization))
	testing.expect(t, !authorized(&service, "Bearer wrong"))
	_, bad_request := parse_http_request(transmute([]byte)(string("GET / HTTP/2\r\n\r\n")))
	testing.expect(t, bad_request != "")
}

@(test)
test_live_debug_service_reuses_existing_engine_directories :: proc(t: ^testing.T) {
	root, root_err := os.make_directory_temp("", "scrapbot-live-restart-*", context.allocator)
	testing.expect(t, root_err == nil)
	if root_err != nil {
		return
	}
	defer os.remove_all(root)
	defer delete(root)
	first: Service
	testing.expect_value(t, init_service(&first, root), "")
	destroy_service(&first)
	second: Service
	testing.expect_value(t, init_service(&second, root), "")
	destroy_service(&second)
}

@(test)
test_live_debug_color_artifact_uses_the_same_capture_frame :: proc(t: ^testing.T) {
	root, root_err := os.make_directory_temp("", "scrapbot-live-artifact-*", context.allocator)
	testing.expect(t, root_err == nil)
	if root_err != nil {
		return
	}
	defer os.remove_all(root)
	defer delete(root)
	service: Service
	testing.expect_value(t, init_service(&service, root), "")
	defer destroy_service(&service)
	_, enqueue_err := enqueue_capture(&service, 1, {.Color})
	testing.expect_value(t, enqueue_err, "")
	plan := begin_capture_frame(&service)
	testing.expect(t, capture_artifact_requested(plan, .Color))
	artifact_path, path_err := capture_artifact_path(plan, .Color)
	defer delete(artifact_path)
	testing.expect_value(t, path_err, "")
	png_bytes := []byte{0x89, 'P', 'N', 'G'}
	testing.expect(t, write_private_file(artifact_path, png_bytes) == nil)
	publish_snapshot(&service, Snapshot{phase = "running", frame_index = 27})
	testing.expect_value(t, capture_published_snapshot(&service), "")
	testing.expect_value(t, service.capture.frames_captured, u32(0))
	capture_frame_artifacts_ready(&service, plan)
	testing.expect_value(t, capture_published_snapshot(&service), "")
	testing.expect_value(t, service.capture.status, "complete")

	manifest_data, manifest_err := os.read_entire_file(service.capture.manifest, context.allocator)
	defer delete(manifest_data)
	testing.expect(t, manifest_err == nil)
	manifest: Capture_Manifest
	defer {
		delete(manifest.snapshot_pattern)
		for &artifact in manifest.artifacts {
			delete(artifact.kind)
			delete(artifact.media_type)
			delete(artifact.pattern)
		}
		delete(manifest.artifacts)
	}
	testing.expect(t, json.unmarshal(manifest_data, &manifest) == nil)
	testing.expect_value(t, manifest.first_frame_index, u64(27))
	testing.expect_value(t, len(manifest.artifacts), 1)
	testing.expect_value(t, manifest.artifacts[0].kind, "color")
	testing.expect_value(t, manifest.artifacts[0].pattern, "color-%04d.png")

	artifact_data, media_type, read_artifact_err := read_current_capture_artifact(
		&service,
		"color-0000.png",
	)
	defer delete(artifact_data)
	testing.expect_value(t, read_artifact_err, "")
	testing.expect_value(t, media_type, "image/png")
	testing.expect_value(t, len(artifact_data), len(png_bytes))
	for value, index in artifact_data {
		testing.expect_value(t, value, png_bytes[index])
	}
}

@(test)
test_live_debug_capture_request_rejects_unknown_artifacts :: proc(t: ^testing.T) {
	request, request_err := decode_capture_request(
		transmute([]byte)(string(`{"frames":5,"artifacts":["color","depth","visibility"]}`)),
		.JSON,
	)
	defer destroy_capture_request(&request)
	testing.expect_value(t, request_err, "")
	artifacts, artifact_err := parse_capture_artifacts(request.artifacts)
	testing.expect_value(t, artifact_err, "")
	testing.expect(t, .Color in artifacts)
	testing.expect(t, .Depth in artifacts)
	testing.expect(t, .Visibility in artifacts)
	_, invalid_err := decode_capture_request(
		transmute([]byte)(string(`{"frames":5,"artifacts":["unknown"]}`)),
		.JSON,
	)
	testing.expect(t, invalid_err != "")
}

@(test)
test_live_debug_depth_and_visibility_artifact_manifest_is_self_describing :: proc(t: ^testing.T) {
	manifest := capture_artifact_manifest({.Depth, .Visibility})
	defer delete(manifest)
	testing.expect_value(t, len(manifest), 3)
	testing.expect_value(t, manifest[0].kind, "depth")
	testing.expect_value(t, manifest[0].pattern, "depth-%04d.f32")
	testing.expect_value(t, manifest[1].kind, "depth_preview")
	testing.expect_value(t, manifest[1].pattern, "depth-preview-%04d.png")
	testing.expect_value(t, manifest[2].kind, "visibility")
	testing.expect_value(t, manifest[2].media_type, "application/cbor")
}
