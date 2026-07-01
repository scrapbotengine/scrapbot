const _chained_struct = @import("chained_struct.zig");
const ChainedStructOut = _chained_struct.ChainedStructOut;
const ChainedStruct = _chained_struct.ChainedStruct;
const SType = _chained_struct.SType;

const _misc = @import("misc.zig");
const U32_MAX = _misc.U32_MAX;
const U64_MAX = _misc.U64_MAX;

pub const WGPU_LIMIT_U32_UNDEFINED = U32_MAX;
pub const WGPU_LIMIT_U64_UNDEFINED = U64_MAX;

pub const Limits = extern struct {
    // This struct chain is used as mutable in some places and immutable in others.
    next_in_chain: ?*ChainedStructOut = null,

    max_texture_dimension_1d: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_texture_dimension_2d: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_texture_dimension_3d: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_texture_array_layers: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_bind_groups: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_bind_groups_plus_vertex_buffers: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_bindings_per_bind_group: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_dynamic_uniform_buffers_per_pipeline_layout: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_dynamic_storage_buffers_per_pipeline_layout: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_sampled_textures_per_shader_stage: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_samplers_per_shader_stage: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_storage_buffers_per_shader_stage: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_storage_textures_per_shader_stage: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_uniform_buffers_per_shader_stage: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_uniform_buffer_binding_size: u64 = WGPU_LIMIT_U64_UNDEFINED,
    max_storage_buffer_binding_size: u64 = WGPU_LIMIT_U64_UNDEFINED,
    min_uniform_buffer_offset_alignment: u32 = WGPU_LIMIT_U32_UNDEFINED,
    min_storage_buffer_offset_alignment: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_vertex_buffers: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_buffer_size: u64 = WGPU_LIMIT_U64_UNDEFINED,
    max_vertex_attributes: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_vertex_buffer_array_stride: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_inter_stage_shader_variables: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_color_attachments: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_color_attachment_bytes_per_sample: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_compute_workgroup_storage_size: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_compute_invocations_per_workgroup: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_compute_workgroup_size_x: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_compute_workgroup_size_y: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_compute_workgroup_size_z: u32 = WGPU_LIMIT_U32_UNDEFINED,
    max_compute_workgroups_per_dimension: u32 = WGPU_LIMIT_U32_UNDEFINED,
};

pub const WGPUNativeLimits = extern struct {
    chain: ChainedStructOut = ChainedStructOut {
        .s_type = SType.native_limits,
    },
    max_push_constant_size: u32,
    max_non_sampler_bindings: u32,
};
