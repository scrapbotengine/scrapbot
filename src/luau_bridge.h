#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct machina_luau machina_luau;

typedef int (*machina_luau_query_next_fn)(
    void* context,
    void* world,
    const char* const* component_ids,
    size_t component_count,
    uint32_t* cursor,
    uint32_t* out_entity
);

typedef int (*machina_luau_get_vec3_fn)(
    void* context,
    void* world,
    uint32_t entity,
    const char* component_id,
    const char* field_name,
    float out_value[3]
);

typedef int (*machina_luau_set_vec3_fn)(
    void* context,
    void* world,
    uint32_t entity,
    const char* component_id,
    const char* field_name,
    const float value[3]
);

enum
{
    MACHINA_LUAU_FIELD_BOOLEAN = 1,
    MACHINA_LUAU_FIELD_INT = 2,
    MACHINA_LUAU_FIELD_FLOAT = 3,
    MACHINA_LUAU_FIELD_VEC3 = 4,
    MACHINA_LUAU_FIELD_STRING = 5,
    MACHINA_LUAU_FIELD_NUMBER = 6,
};

typedef struct machina_luau_field_value
{
    int tag;
    int boolean_value;
    int32_t int_value;
    double number_value;
    const char* string_data;
    size_t string_len;
    float vec3_value[3];
} machina_luau_field_value;

typedef int (*machina_luau_get_field_fn)(
    void* context,
    void* world,
    uint32_t entity,
    const char* component_id,
    const char* field_name,
    machina_luau_field_value* out_value
);

typedef int (*machina_luau_set_field_fn)(
    void* context,
    void* world,
    uint32_t entity,
    const char* component_id,
    const char* field_name,
    const machina_luau_field_value* value
);

typedef const char* (*machina_luau_host_error_fn)(void* context);

typedef struct machina_luau_callbacks
{
    machina_luau_query_next_fn query_next;
    machina_luau_get_vec3_fn get_vec3;
    machina_luau_set_vec3_fn set_vec3;
    machina_luau_get_field_fn get_field;
    machina_luau_set_field_fn set_field;
    machina_luau_host_error_fn host_error;
} machina_luau_callbacks;

machina_luau* machina_luau_create(machina_luau_callbacks callbacks);
void machina_luau_destroy(machina_luau* vm);
void machina_luau_set_callback_context(machina_luau* vm, void* context);

int machina_luau_load(machina_luau* vm, const char* chunk_name, const char* source, size_t source_len);
const char* machina_luau_last_error(const machina_luau* vm);

size_t machina_luau_component_count(const machina_luau* vm);
const char* machina_luau_component_id(const machina_luau* vm, size_t component_index);
uint32_t machina_luau_component_version(const machina_luau* vm, size_t component_index);
int machina_luau_component_line(const machina_luau* vm, size_t component_index);
size_t machina_luau_component_field_count(const machina_luau* vm, size_t component_index);
const char* machina_luau_component_field_name(const machina_luau* vm, size_t component_index, size_t field_index);
const char* machina_luau_component_field_type(const machina_luau* vm, size_t component_index, size_t field_index);

size_t machina_luau_system_count(const machina_luau* vm);
const char* machina_luau_system_id(const machina_luau* vm, size_t system_index);
const char* machina_luau_system_phase(const machina_luau* vm, size_t system_index);
uint32_t machina_luau_system_runner_ref(const machina_luau* vm, size_t system_index);
int machina_luau_system_line(const machina_luau* vm, size_t system_index);

size_t machina_luau_system_reads_count(const machina_luau* vm, size_t system_index);
const char* machina_luau_system_reads_item(const machina_luau* vm, size_t system_index, size_t item_index);
size_t machina_luau_system_writes_count(const machina_luau* vm, size_t system_index);
const char* machina_luau_system_writes_item(const machina_luau* vm, size_t system_index, size_t item_index);
size_t machina_luau_system_before_count(const machina_luau* vm, size_t system_index);
const char* machina_luau_system_before_item(const machina_luau* vm, size_t system_index, size_t item_index);
size_t machina_luau_system_after_count(const machina_luau* vm, size_t system_index);
const char* machina_luau_system_after_item(const machina_luau* vm, size_t system_index, size_t item_index);

int machina_luau_call_system(machina_luau* vm, uint32_t runner_ref, void* world, double delta_seconds);

#ifdef __cplusplus
}
#endif
