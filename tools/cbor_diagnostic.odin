package main

import "core:encoding/cbor"
import "core:encoding/json"
import "core:fmt"
import "core:os"

Visibility_Record :: struct {
	classification: string,
}

Visibility_Artifact :: struct {
	frame_number: u32,
	record_count: u32,
	records_written: int,
	records_truncated: bool,
	visible_instances: u32,
	visible_meshlets: u32,
	visible_virtual_clusters: u32,
	virtual_rejected_clusters: u32,
	frustum_culled_instances: u32,
	occlusion_culled_instances: u32,
	frustum_culled_meshlets: u32,
	cone_culled_meshlets: u32,
	occlusion_culled_meshlets: u32,
	records: []Visibility_Record,
}

Visibility_Summary :: struct {
	frame_number: u32,
	record_count: u32,
	records_written: int,
	records_truncated: bool,
	visible_instances: u32,
	visible_meshlets: u32,
	visible_virtual_clusters: u32,
	virtual_rejected_clusters: u32,
	frustum_culled_instances: u32,
	occlusion_culled_instances: u32,
	frustum_culled_meshlets: u32,
	cone_culled_meshlets: u32,
	occlusion_culled_meshlets: u32,
	classifications: map[string]int,
}

main :: proc() {
	summary_only := len(os.args) == 3 && os.args[1] == "--summary"
	if len(os.args) != 2 && !summary_only {
		fmt.eprintln("usage: odin run tools/cbor_diagnostic.odin -file -- [--summary] <path>")
		os.exit(2)
	}
	path := os.args[len(os.args) - 1]
	data, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		fmt.eprintf("failed to read %s: %v\n", path, read_err)
		os.exit(1)
	}
	defer delete(data)
	if summary_only {
		write_visibility_summary(data, path)
		return
	}
	value, decode_err := cbor.decode(string(data))
	if decode_err != nil {
		fmt.eprintf("failed to decode %s: %v\n", path, decode_err)
		os.exit(1)
	}
	defer cbor.destroy(value)
	diagnostic, format_err := cbor.to_diagnostic_format(value)
	if format_err != nil {
		fmt.eprintf("failed to format %s: %v\n", os.args[1], format_err)
		os.exit(1)
	}
	defer delete(diagnostic)
	fmt.println(diagnostic)
}

write_visibility_summary :: proc(data: []byte, path: string) {
	artifact: Visibility_Artifact
	decode_err := cbor.unmarshal(data, &artifact)
	if decode_err != nil {
		fmt.eprintf("failed to decode %s as visibility evidence: %v\n", path, decode_err)
		os.exit(1)
	}
	defer {
		for record in artifact.records {
			delete(record.classification)
		}
		delete(artifact.records)
	}
	summary := Visibility_Summary {
		frame_number = artifact.frame_number,
		record_count = artifact.record_count,
		records_written = artifact.records_written,
		records_truncated = artifact.records_truncated,
		visible_instances = artifact.visible_instances,
		visible_meshlets = artifact.visible_meshlets,
		visible_virtual_clusters = artifact.visible_virtual_clusters,
		virtual_rejected_clusters = artifact.virtual_rejected_clusters,
		frustum_culled_instances = artifact.frustum_culled_instances,
		occlusion_culled_instances = artifact.occlusion_culled_instances,
		frustum_culled_meshlets = artifact.frustum_culled_meshlets,
		cone_culled_meshlets = artifact.cone_culled_meshlets,
		occlusion_culled_meshlets = artifact.occlusion_culled_meshlets,
		classifications = make(map[string]int),
	}
	defer delete(summary.classifications)
	for record in artifact.records {
		summary.classifications[record.classification] += 1
	}
	encoded, encode_err := json.marshal(summary)
	if encode_err != nil {
		fmt.eprintf("failed to encode visibility summary: %v\n", encode_err)
		os.exit(1)
	}
	defer delete(encoded)
	fmt.println(string(encoded))
}
