#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct scrapbot_luau scrapbot_luau;

typedef int (*scrapbot_luau_query_next_fn)(
    void* context,
    void* world,
    const char* const* component_ids,
    size_t component_count,
    uint32_t* cursor,
    uint32_t* out_entity,
    uint32_t* out_entity_generation
);

typedef int (*scrapbot_luau_prepare_query_fn)(
    void* context,
    void* world,
    const char* const* component_ids,
    size_t component_count,
    uint32_t* out_component_table_indices,
    uint32_t* out_driver_table_index
);

typedef int (*scrapbot_luau_query_next_prepared_fn)(
    void* context,
    void* world,
    const uint32_t* component_table_indices,
    size_t component_count,
    uint32_t driver_table_index,
    uint32_t* cursor,
    uint32_t* out_entity,
    uint32_t* out_entity_generation,
    uint32_t* out_component_rows
);

typedef uint64_t (*scrapbot_luau_query_plan_generation_fn)(
    void* context,
    void* world
);

typedef int (*scrapbot_luau_read_f32_view_fn)(
    void* context,
    void* world,
    const char* component_id,
    uint32_t component_table_index,
    const uint32_t* entities,
    const uint32_t* entity_generations,
    const uint32_t* component_rows,
    size_t entity_count,
    const char* field_name,
    float* out_values
);

typedef int (*scrapbot_luau_write_f32_view_fn)(
    void* context,
    void* world,
    const char* component_id,
    uint32_t component_table_index,
    const uint32_t* entities,
    const uint32_t* entity_generations,
    const uint32_t* component_rows,
    size_t entity_count,
    const char* field_name,
    const float* values
);

typedef int (*scrapbot_luau_read_vec3_view_fn)(
    void* context,
    void* world,
    const char* component_id,
    uint32_t component_table_index,
    const uint32_t* entities,
    const uint32_t* entity_generations,
    const uint32_t* component_rows,
    size_t entity_count,
    const char* field_name,
    float* out_values
);

typedef int (*scrapbot_luau_write_vec3_view_fn)(
    void* context,
    void* world,
    const char* component_id,
    uint32_t component_table_index,
    const uint32_t* entities,
    const uint32_t* entity_generations,
    const uint32_t* component_rows,
    size_t entity_count,
    const char* field_name,
    const float* values
);

typedef int (*scrapbot_luau_get_vec3_fn)(
    void* context,
    void* world,
    uint32_t entity,
    uint32_t entity_generation,
    const char* component_id,
    const char* field_name,
    float out_value[3]
);

typedef int (*scrapbot_luau_set_vec3_fn)(
    void* context,
    void* world,
    uint32_t entity,
    uint32_t entity_generation,
    const char* component_id,
    const char* field_name,
    const float value[3]
);

enum
{
    SCRAPBOT_LUAU_FIELD_BOOLEAN = 1,
    SCRAPBOT_LUAU_FIELD_INT = 2,
    SCRAPBOT_LUAU_FIELD_FLOAT = 3,
    SCRAPBOT_LUAU_FIELD_VEC3 = 4,
    SCRAPBOT_LUAU_FIELD_STRING = 5,
    SCRAPBOT_LUAU_FIELD_NUMBER = 6,
};

typedef struct scrapbot_luau_field_value
{
    int tag;
    int boolean_value;
    int32_t int_value;
    double number_value;
    const char* string_data;
    size_t string_len;
    float vec3_value[3];
} scrapbot_luau_field_value;

typedef int (*scrapbot_luau_get_field_fn)(
    void* context,
    void* world,
    uint32_t entity,
    uint32_t entity_generation,
    const char* component_id,
    const char* field_name,
    scrapbot_luau_field_value* out_value
);

typedef int (*scrapbot_luau_get_field_resolved_fn)(
    void* context,
    void* world,
    uint32_t entity,
    uint32_t entity_generation,
    const char* component_id,
    uint32_t component_table_index,
    uint32_t component_row_index,
    const char* field_name,
    scrapbot_luau_field_value* out_value
);

typedef int (*scrapbot_luau_set_field_fn)(
    void* context,
    void* world,
    uint32_t entity,
    uint32_t entity_generation,
    const char* component_id,
    const char* field_name,
    const scrapbot_luau_field_value* value
);

typedef int (*scrapbot_luau_set_field_resolved_fn)(
    void* context,
    void* world,
    uint32_t entity,
    uint32_t entity_generation,
    const char* component_id,
    uint32_t component_table_index,
    uint32_t component_row_index,
    const char* field_name,
    const scrapbot_luau_field_value* value
);

typedef struct scrapbot_luau_component_field_value
{
    const char* name;
    size_t name_len;
    scrapbot_luau_field_value value;
} scrapbot_luau_component_field_value;

typedef int (*scrapbot_luau_spawn_entity_fn)(
    void* context,
    void* world,
    const char* id,
    const char* name,
    uint32_t* out_entity,
    uint32_t* out_entity_generation
);

typedef int (*scrapbot_luau_despawn_entity_fn)(
    void* context,
    void* world,
    uint32_t entity,
    uint32_t entity_generation
);

typedef int (*scrapbot_luau_add_component_fn)(
    void* context,
    void* world,
    uint32_t entity,
    uint32_t entity_generation,
    const char* component_id,
    const scrapbot_luau_component_field_value* fields,
    size_t field_count
);

typedef int (*scrapbot_luau_remove_component_fn)(
    void* context,
    void* world,
    uint32_t entity,
    uint32_t entity_generation,
    const char* component_id
);

typedef const char* (*scrapbot_luau_host_error_fn)(void* context);

typedef struct scrapbot_luau_callbacks
{
    scrapbot_luau_query_next_fn query_next;
    scrapbot_luau_prepare_query_fn prepare_query;
    scrapbot_luau_query_next_prepared_fn query_next_prepared;
    scrapbot_luau_query_plan_generation_fn query_plan_generation;
    scrapbot_luau_read_f32_view_fn read_f32_view;
    scrapbot_luau_write_f32_view_fn write_f32_view;
    scrapbot_luau_read_vec3_view_fn read_vec3_view;
    scrapbot_luau_write_vec3_view_fn write_vec3_view;
    scrapbot_luau_get_vec3_fn get_vec3;
    scrapbot_luau_set_vec3_fn set_vec3;
    scrapbot_luau_get_field_fn get_field;
    scrapbot_luau_get_field_resolved_fn get_field_resolved;
    scrapbot_luau_set_field_fn set_field;
    scrapbot_luau_set_field_resolved_fn set_field_resolved;
    scrapbot_luau_spawn_entity_fn spawn_entity;
    scrapbot_luau_despawn_entity_fn despawn_entity;
    scrapbot_luau_add_component_fn add_component;
    scrapbot_luau_remove_component_fn remove_component;
    scrapbot_luau_host_error_fn host_error;
} scrapbot_luau_callbacks;

scrapbot_luau* scrapbot_luau_create(scrapbot_luau_callbacks callbacks);
void scrapbot_luau_destroy(scrapbot_luau* vm);
void scrapbot_luau_set_callback_context(scrapbot_luau* vm, void* context);

int scrapbot_luau_load(scrapbot_luau* vm, const char* chunk_name, const char* source, size_t source_len);
const char* scrapbot_luau_last_error(const scrapbot_luau* vm);

size_t scrapbot_luau_component_count(const scrapbot_luau* vm);
const char* scrapbot_luau_component_id(const scrapbot_luau* vm, size_t component_index);
uint32_t scrapbot_luau_component_version(const scrapbot_luau* vm, size_t component_index);
int scrapbot_luau_component_line(const scrapbot_luau* vm, size_t component_index);
size_t scrapbot_luau_component_field_count(const scrapbot_luau* vm, size_t component_index);
const char* scrapbot_luau_component_field_name(const scrapbot_luau* vm, size_t component_index, size_t field_index);
const char* scrapbot_luau_component_field_type(const scrapbot_luau* vm, size_t component_index, size_t field_index);

size_t scrapbot_luau_system_count(const scrapbot_luau* vm);
const char* scrapbot_luau_system_id(const scrapbot_luau* vm, size_t system_index);
const char* scrapbot_luau_system_phase(const scrapbot_luau* vm, size_t system_index);
uint32_t scrapbot_luau_system_runner_ref(const scrapbot_luau* vm, size_t system_index);
int scrapbot_luau_system_line(const scrapbot_luau* vm, size_t system_index);

size_t scrapbot_luau_system_reads_count(const scrapbot_luau* vm, size_t system_index);
const char* scrapbot_luau_system_reads_item(const scrapbot_luau* vm, size_t system_index, size_t item_index);
size_t scrapbot_luau_system_writes_count(const scrapbot_luau* vm, size_t system_index);
const char* scrapbot_luau_system_writes_item(const scrapbot_luau* vm, size_t system_index, size_t item_index);
size_t scrapbot_luau_system_before_count(const scrapbot_luau* vm, size_t system_index);
const char* scrapbot_luau_system_before_item(const scrapbot_luau* vm, size_t system_index, size_t item_index);
size_t scrapbot_luau_system_after_count(const scrapbot_luau* vm, size_t system_index);
const char* scrapbot_luau_system_after_item(const scrapbot_luau* vm, size_t system_index, size_t item_index);

int scrapbot_luau_call_system(scrapbot_luau* vm, uint32_t runner_ref, void* world, double delta_seconds);

#ifdef __cplusplus
}
#endif
