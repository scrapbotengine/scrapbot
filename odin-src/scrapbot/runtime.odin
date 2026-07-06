package main

import "core:strings"

ENGINE_NAMESPACE :: "scrapbot"

TRANSFORM_COMPONENT_ID :: "scrapbot.transform"
CUBE_RENDERER_COMPONENT_ID :: "scrapbot.render.cube"
GEOMETRY_PRIMITIVE_COMPONENT_ID :: "scrapbot.geometry.primitive"
SURFACE_MATERIAL_COMPONENT_ID :: "scrapbot.material.surface"
RENDERER_COMPONENT_ID :: "scrapbot.renderer"
CAMERA_COMPONENT_ID :: "scrapbot.camera"
DIRECTIONAL_LIGHT_COMPONENT_ID :: "scrapbot.light.directional"
SHADOW_CASTER_COMPONENT_ID :: "scrapbot.shadow.caster"
SHADOW_RECEIVER_COMPONENT_ID :: "scrapbot.shadow.receiver"
UI_CANVAS_COMPONENT_ID :: "scrapbot.ui.canvas"
UI_RECT_COMPONENT_ID :: "scrapbot.ui.rect"
UI_BORDER_COMPONENT_ID :: "scrapbot.ui.border"
UI_TEXT_COMPONENT_ID :: "scrapbot.ui.text"
UI_BUTTON_COMPONENT_ID :: "scrapbot.ui.button"
UI_HIT_AREA_COMPONENT_ID :: "scrapbot.ui.hit_area"
UI_COMMAND_COMPONENT_ID :: "scrapbot.ui.command"
UI_COMMAND_EVENT_COMPONENT_ID :: "scrapbot.ui.command_event"
UI_SCROLL_VIEW_COMPONENT_ID :: "scrapbot.ui.scroll_view"
UI_VGROUP_COMPONENT_ID :: "scrapbot.ui.vgroup"
UI_HGROUP_COMPONENT_ID :: "scrapbot.ui.hgroup"
UI_TABLE_COMPONENT_ID :: "scrapbot.ui.table"
UI_STACK_COMPONENT_ID :: "scrapbot.ui.stack"
UI_LAYOUT_ITEM_COMPONENT_ID :: "scrapbot.ui.layout.item"
UI_SPACER_COMPONENT_ID :: "scrapbot.ui.spacer"
UI_TEXT_BLOCK_COMPONENT_ID :: "scrapbot.ui.text_block"
UI_TOGGLE_COMPONENT_ID :: "scrapbot.ui.toggle"
UI_PROGRESS_BAR_COMPONENT_ID :: "scrapbot.ui.progress_bar"
UI_SEPARATOR_COMPONENT_ID :: "scrapbot.ui.separator"
INPUT_POINTER_COMPONENT_ID :: "scrapbot.input.pointer"
INPUT_KEYBOARD_COMPONENT_ID :: "scrapbot.input.keyboard"
INPUT_FRAME_COMPONENT_ID :: "scrapbot.input.frame"

Runtime_Error :: enum {
	None,
	Out_Of_Memory,
	Invalid_Type_ID,
	Reserved_Type_ID,
	Invalid_Field_Name,
	Duplicate_Component_Field,
	Duplicate_Component_Type,
	Duplicate_System_Access,
	Duplicate_System_Type,
	Duplicate_Entity_ID,
	Invalid_Entity,
	Unknown_Component,
	Unknown_Component_Type,
	Unknown_Field,
	Invalid_Field_Type,
	Cyclic_System_Order,
	Access_Denied,
	Invalid_Structural_Command,
}

Runtime_Field_Type :: enum {
	Boolean,
	Int,
	Float,
	Vec3,
	String,
}

Runtime_Component_Field_Definition :: struct {
	name:       string,
	value_type: Runtime_Field_Type,
}

Runtime_Component_Definition :: struct {
	id:      string,
	version: int,
	fields:  []Runtime_Component_Field_Definition,
}

Runtime_Component_Value :: struct {
	value_type:   Runtime_Field_Type,
	boolean:      bool,
	int_value:    int,
	float:        f32,
	vec3:         [3]f32,
	string_value: string,
}

Runtime_Component_Field_Value :: struct {
	name:  string,
	value: Runtime_Component_Value,
}

Runtime_Component_Column :: struct {
	name:       string,
	value_type: Runtime_Field_Type,
	values:     [dynamic]Runtime_Component_Value,
}

Runtime_Component_Table :: struct {
	id:             string,
	entities:       [dynamic]Entity_Handle,
	rows_by_entity: [dynamic]int,
	columns:        []Runtime_Component_Column,
}

Runtime_Resolved_Component_Row :: struct {
	table_index: u32,
	row_index:   u32,
}

Runtime_System_Phase :: enum {
	Startup,
	Update,
	Fixed_Update,
	Render,
}

Runtime_System_Runner_Kind :: enum {
	None,
	Luau,
	Native,
}

Runtime_System_Runner :: struct {
	kind: Runtime_System_Runner_Kind,
	ref:  u32,
}

Runtime_System_Definition :: struct {
	id:     string,
	phase:  Runtime_System_Phase,
	reads:  []string,
	writes: []string,
	before: []string,
	after:  []string,
	runner: Runtime_System_Runner,
}

Runtime_Scheduled_System :: struct {
	registry_index: int,
	id:             string,
	runner:         Runtime_System_Runner,
}

Runtime_System_Batch :: struct {
	phase:   Runtime_System_Phase,
	systems: []Runtime_Scheduled_System,
}

Runtime_System_Schedule :: struct {
	batches: []Runtime_System_Batch,
}

Runtime_Component_Registry :: struct {
	components: [dynamic]Runtime_Component_Definition,
	systems:    [dynamic]Runtime_System_Definition,
}

Runtime_Registration_Context :: enum {
	Engine,
	Project,
	Package,
}

Entity_Provenance :: enum {
	Spawned,
	Authored,
}

Entity_Handle :: struct {
	index:      u32,
	generation: u32,
}

Runtime_Entity :: struct {
	id:         string,
	name:       string,
	generation: u32,
	provenance: Entity_Provenance,
}

Runtime_World :: struct {
	entities:               [dynamic]Runtime_Entity,
	component_tables:       [dynamic]Runtime_Component_Table,
	next_entity_generation: u32,
	query_plan_generation:  u64,
}

Runtime_Deferred_Command_Kind :: enum {
	Add_Component,
	Remove_Component,
	Despawn_Entity,
}

Runtime_Deferred_Command :: struct {
	kind:         Runtime_Deferred_Command_Kind,
	entity:       Entity_Handle,
	component_id: string,
	fields:       []Runtime_Component_Field_Value,
}

Runtime_Deferred_Command_Buffer :: struct {
	commands:         [dynamic]Runtime_Deferred_Command,
	immediate_spawns: [dynamic]Entity_Handle,
}

runtime_registry_free :: proc(registry: ^Runtime_Component_Registry) {
	for system in registry.systems {
		runtime_system_definition_free(system)
	}
	if registry.systems != nil {
		delete(registry.systems)
	}
	for component in registry.components {
		runtime_component_definition_free(component)
	}
	if registry.components != nil {
		delete(registry.components)
	}
	registry.systems = nil
	registry.components = nil
}

runtime_registry_component_count :: proc(registry: Runtime_Component_Registry) -> int {
	return len(registry.components)
}

runtime_registry_system_count :: proc(registry: Runtime_Component_Registry) -> int {
	return len(registry.systems)
}

runtime_register_project_component :: proc(registry: ^Runtime_Component_Registry, definition: Runtime_Component_Definition) -> Runtime_Error {
	return runtime_register_component_as(registry, .Project, definition)
}

runtime_register_package_component :: proc(registry: ^Runtime_Component_Registry, definition: Runtime_Component_Definition) -> Runtime_Error {
	return runtime_register_component_as(registry, .Package, definition)
}

runtime_register_engine_component :: proc(registry: ^Runtime_Component_Registry, definition: Runtime_Component_Definition) -> Runtime_Error {
	return runtime_register_component_as(registry, .Engine, definition)
}

runtime_register_project_system :: proc(registry: ^Runtime_Component_Registry, definition: Runtime_System_Definition) -> Runtime_Error {
	return runtime_register_system_as(registry, .Project, definition)
}

runtime_register_package_system :: proc(registry: ^Runtime_Component_Registry, definition: Runtime_System_Definition) -> Runtime_Error {
	return runtime_register_system_as(registry, .Package, definition)
}

runtime_register_engine_system :: proc(registry: ^Runtime_Component_Registry, definition: Runtime_System_Definition) -> Runtime_Error {
	return runtime_register_system_as(registry, .Engine, definition)
}

runtime_find_component :: proc(registry: Runtime_Component_Registry, id: string) -> (^Runtime_Component_Definition, bool) {
	for &component in registry.components {
		if component.id == id {
			return &component, true
		}
	}
	return nil, false
}

runtime_find_system :: proc(registry: Runtime_Component_Registry, id: string) -> (^Runtime_System_Definition, bool) {
	for &system in registry.systems {
		if system.id == id {
			return &system, true
		}
	}
	return nil, false
}

runtime_register_component_as :: proc(
	registry: ^Runtime_Component_Registry,
	registration_context: Runtime_Registration_Context,
	definition: Runtime_Component_Definition,
) -> Runtime_Error {
	id_err := runtime_validate_type_id_for_context(definition.id, registration_context)
	if id_err != .None {
		return id_err
	}

	for field, index in definition.fields {
		field_err := runtime_validate_field_name(field.name)
		if field_err != .None {
			return field_err
		}
		for prior_field in definition.fields[:index] {
			if prior_field.name == field.name {
				return .Duplicate_Component_Field
			}
		}
	}

	if existing, ok := runtime_find_component(registry^, definition.id); ok {
		if runtime_component_definitions_equal(existing^, definition) {
			return .None
		}
		return .Duplicate_Component_Type
	}

	owned, copy_err := runtime_component_definition_clone(definition)
	if copy_err != .None {
		return copy_err
	}
	append(&registry.components, owned)
	return .None
}

runtime_register_system_as :: proc(
	registry: ^Runtime_Component_Registry,
	registration_context: Runtime_Registration_Context,
	definition: Runtime_System_Definition,
) -> Runtime_Error {
	id_err := runtime_validate_type_id_for_context(definition.id, registration_context)
	if id_err != .None {
		return id_err
	}
	access_err := runtime_validate_system_access(registry^, definition, registration_context)
	if access_err != .None {
		return access_err
	}

	if existing, ok := runtime_find_system(registry^, definition.id); ok {
		if runtime_system_definitions_equal(existing^, definition) {
			return .None
		}
		return .Duplicate_System_Type
	}

	owned, copy_err := runtime_system_definition_clone(definition)
	if copy_err != .None {
		return copy_err
	}
	append(&registry.systems, owned)
	return .None
}

runtime_validate_system_access :: proc(
	registry: Runtime_Component_Registry,
	definition: Runtime_System_Definition,
	registration_context: Runtime_Registration_Context,
) -> Runtime_Error {
	for component_id in definition.reads {
		id_err := runtime_validate_reference_type_id_for_context(component_id, registration_context)
		if id_err != .None {
			return id_err
		}
		if _, found := runtime_find_component(registry, component_id); !found {
			return .Unknown_Component_Type
		}
		if runtime_count_string(definition.reads, component_id) > 1 || runtime_contains_string(definition.writes, component_id) {
			return .Duplicate_System_Access
		}
	}
	for component_id in definition.writes {
		id_err := runtime_validate_reference_type_id_for_context(component_id, registration_context)
		if id_err != .None {
			return id_err
		}
		if _, found := runtime_find_component(registry, component_id); !found {
			return .Unknown_Component_Type
		}
		if runtime_count_string(definition.writes, component_id) > 1 {
			return .Duplicate_System_Access
		}
	}
	for system_id in definition.before {
		id_err := runtime_validate_reference_type_id_for_context(system_id, registration_context)
		if id_err != .None {
			return id_err
		}
	}
	for system_id in definition.after {
		id_err := runtime_validate_reference_type_id_for_context(system_id, registration_context)
		if id_err != .None {
			return id_err
		}
	}
	return .None
}

runtime_build_system_schedule :: proc(registry: Runtime_Component_Registry, phase: Runtime_System_Phase) -> (Runtime_System_Schedule, Runtime_Error) {
	phase_indices := make([dynamic]int)
	defer delete(phase_indices)
	for system, index in registry.systems {
		if system.phase == phase {
			append(&phase_indices, index)
		}
	}

	system_count := len(phase_indices)
	remaining_dependencies := make([]int, system_count)
	if remaining_dependencies == nil && system_count > 0 {
		return Runtime_System_Schedule{}, .Out_Of_Memory
	}
	defer delete(remaining_dependencies)
	scheduled := make([]bool, system_count)
	if scheduled == nil && system_count > 0 {
		return Runtime_System_Schedule{}, .Out_Of_Memory
	}
	defer delete(scheduled)

	for target_local := 0; target_local < system_count; target_local += 1 {
		for source_local := 0; source_local < system_count; source_local += 1 {
			if source_local == target_local {
				continue
			}
			if runtime_system_must_run_before(registry, phase_indices[source_local], phase_indices[target_local]) {
				remaining_dependencies[target_local] += 1
			}
		}
	}

	batches := make([dynamic]Runtime_System_Batch)
	scheduled_count := 0
	for scheduled_count < system_count {
		batch_local_indices := make([dynamic]int)
		for local_index := 0; local_index < system_count; local_index += 1 {
			if scheduled[local_index] || remaining_dependencies[local_index] != 0 {
				continue
			}
			if runtime_system_conflicts_with_batch(registry, phase_indices[local_index], phase_indices[:], batch_local_indices[:]) {
				continue
			}
			append(&batch_local_indices, local_index)
			scheduled[local_index] = true
		}

			if len(batch_local_indices) == 0 {
				delete(batch_local_indices)
				runtime_system_batches_free(batches[:])
				delete(batches)
				return Runtime_System_Schedule{}, .Cyclic_System_Order
			}

		systems := make([]Runtime_Scheduled_System, len(batch_local_indices))
			if systems == nil && len(batch_local_indices) > 0 {
				delete(batch_local_indices)
				runtime_system_batches_free(batches[:])
				delete(batches)
				return Runtime_System_Schedule{}, .Out_Of_Memory
			}
		copied_system_count := 0
		for local_index, batch_index in batch_local_indices {
			registry_index := phase_indices[local_index]
			owned_id, id_err := strings.clone(registry.systems[registry_index].id)
			if id_err != nil {
				for system in systems[:copied_system_count] {
					delete(system.id)
				}
				delete(systems)
				delete(batch_local_indices)
				runtime_system_batches_free(batches[:])
				delete(batches)
				return Runtime_System_Schedule{}, .Out_Of_Memory
			}
			systems[batch_index] = Runtime_Scheduled_System{
				registry_index = registry_index,
				id = owned_id,
				runner = registry.systems[registry_index].runner,
			}
			copied_system_count += 1
		}

		append(&batches, Runtime_System_Batch{phase = phase, systems = systems})
		scheduled_count += len(batch_local_indices)
		for source_local in batch_local_indices {
			for target_local := 0; target_local < system_count; target_local += 1 {
				if scheduled[target_local] {
					continue
				}
				if runtime_system_must_run_before(registry, phase_indices[source_local], phase_indices[target_local]) {
					remaining_dependencies[target_local] -= 1
				}
			}
		}
		delete(batch_local_indices)
	}

	owned_batches := make([]Runtime_System_Batch, len(batches))
	if owned_batches == nil && len(batches) > 0 {
		runtime_system_batches_free(batches[:])
		delete(batches)
		return Runtime_System_Schedule{}, .Out_Of_Memory
	}
	for batch, index in batches {
		owned_batches[index] = batch
	}
	delete(batches)
	return Runtime_System_Schedule{batches = owned_batches}, .None
}

runtime_system_schedule_free :: proc(schedule: Runtime_System_Schedule) {
	runtime_system_batches_free(schedule.batches)
	if schedule.batches != nil {
		delete(schedule.batches)
	}
}

runtime_system_batches_free :: proc(batches: []Runtime_System_Batch) {
	for batch in batches {
		for system in batch.systems {
			delete(system.id)
		}
		if batch.systems != nil {
			delete(batch.systems)
		}
	}
}

runtime_system_schedule_batch_count :: proc(schedule: Runtime_System_Schedule) -> int {
	return len(schedule.batches)
}

runtime_system_schedule_system_count :: proc(schedule: Runtime_System_Schedule) -> int {
	count := 0
	for batch in schedule.batches {
		count += len(batch.systems)
	}
	return count
}

runtime_system_must_run_before :: proc(registry: Runtime_Component_Registry, source_index, target_index: int) -> bool {
	source := registry.systems[source_index]
	target := registry.systems[target_index]
	return runtime_contains_string(source.before, target.id) || runtime_contains_string(target.after, source.id)
}

runtime_system_conflicts_with_batch :: proc(
	registry: Runtime_Component_Registry,
	candidate_index: int,
	phase_indices: []int,
	batch_local_indices: []int,
) -> bool {
	candidate := registry.systems[candidate_index]
	for local_index in batch_local_indices {
		other := registry.systems[phase_indices[local_index]]
		if runtime_systems_conflict(candidate, other) {
			return true
		}
	}
	return false
}

runtime_component_definition_clone :: proc(definition: Runtime_Component_Definition) -> (Runtime_Component_Definition, Runtime_Error) {
	owned_id, id_err := strings.clone(definition.id)
	if id_err != nil {
		return Runtime_Component_Definition{}, .Out_Of_Memory
	}

	owned_fields := make([]Runtime_Component_Field_Definition, len(definition.fields))
	if owned_fields == nil && len(definition.fields) > 0 {
		delete(owned_id)
		return Runtime_Component_Definition{}, .Out_Of_Memory
	}

	copied_count := 0
	for field, index in definition.fields {
		owned_name, name_err := strings.clone(field.name)
		if name_err != nil {
			for copied in owned_fields[:copied_count] {
				delete(copied.name)
			}
			delete(owned_fields)
			delete(owned_id)
			return Runtime_Component_Definition{}, .Out_Of_Memory
		}
		owned_fields[index] = Runtime_Component_Field_Definition{
			name = owned_name,
			value_type = field.value_type,
		}
		copied_count += 1
	}

	return Runtime_Component_Definition{
		id = owned_id,
		version = definition.version,
		fields = owned_fields,
	}, .None
}

runtime_system_definition_clone :: proc(definition: Runtime_System_Definition) -> (Runtime_System_Definition, Runtime_Error) {
	owned_id, id_err := strings.clone(definition.id)
	if id_err != nil {
		return Runtime_System_Definition{}, .Out_Of_Memory
	}
	reads, reads_err := runtime_string_list_clone(definition.reads)
	if reads_err != .None {
		delete(owned_id)
		return Runtime_System_Definition{}, reads_err
	}
	writes, writes_err := runtime_string_list_clone(definition.writes)
	if writes_err != .None {
		runtime_string_list_free(reads)
		delete(owned_id)
		return Runtime_System_Definition{}, writes_err
	}
	before, before_err := runtime_string_list_clone(definition.before)
	if before_err != .None {
		runtime_string_list_free(writes)
		runtime_string_list_free(reads)
		delete(owned_id)
		return Runtime_System_Definition{}, before_err
	}
	after, after_err := runtime_string_list_clone(definition.after)
	if after_err != .None {
		runtime_string_list_free(before)
		runtime_string_list_free(writes)
		runtime_string_list_free(reads)
		delete(owned_id)
		return Runtime_System_Definition{}, after_err
	}
	return Runtime_System_Definition{
		id = owned_id,
		phase = definition.phase,
		reads = reads,
		writes = writes,
		before = before,
		after = after,
		runner = definition.runner,
	}, .None
}

runtime_component_definition_free :: proc(definition: Runtime_Component_Definition) {
	if definition.id != "" {
		delete(definition.id)
	}
	for field in definition.fields {
		delete(field.name)
	}
	if definition.fields != nil {
		delete(definition.fields)
	}
}

runtime_system_definition_free :: proc(definition: Runtime_System_Definition) {
	if definition.id != "" {
		delete(definition.id)
	}
	runtime_string_list_free(definition.reads)
	runtime_string_list_free(definition.writes)
	runtime_string_list_free(definition.before)
	runtime_string_list_free(definition.after)
}

runtime_string_list_clone :: proc(values: []string) -> ([]string, Runtime_Error) {
	copied := make([]string, len(values))
	if copied == nil && len(values) > 0 {
		return nil, .Out_Of_Memory
	}
	copied_count := 0
	for value, index in values {
		owned, err := strings.clone(value)
		if err != nil {
			for copied_value in copied[:copied_count] {
				delete(copied_value)
			}
			delete(copied)
			return nil, .Out_Of_Memory
		}
		copied[index] = owned
		copied_count += 1
	}
	return copied, .None
}

runtime_string_list_free :: proc(values: []string) {
	for value in values {
		delete(value)
	}
	if values != nil {
		delete(values)
	}
}

runtime_component_definitions_equal :: proc(left, right: Runtime_Component_Definition) -> bool {
	if left.id != right.id || left.version != right.version || len(left.fields) != len(right.fields) {
		return false
	}
	for field, index in left.fields {
		other := right.fields[index]
		if field.name != other.name || field.value_type != other.value_type {
			return false
		}
	}
	return true
}

runtime_system_definitions_equal :: proc(left, right: Runtime_System_Definition) -> bool {
	return left.id == right.id &&
		left.phase == right.phase &&
		runtime_system_runners_equal(left.runner, right.runner) &&
		runtime_string_lists_equal(left.reads, right.reads) &&
		runtime_string_lists_equal(left.writes, right.writes) &&
		runtime_string_lists_equal(left.before, right.before) &&
		runtime_string_lists_equal(left.after, right.after)
}

runtime_system_runners_equal :: proc(left, right: Runtime_System_Runner) -> bool {
	return left.kind == right.kind && left.ref == right.ref
}

runtime_string_lists_equal :: proc(left, right: []string) -> bool {
	if len(left) != len(right) {
		return false
	}
	for value, index in left {
		if value != right[index] {
			return false
		}
	}
	return true
}

runtime_contains_string :: proc(values: []string, needle: string) -> bool {
	return runtime_count_string(values, needle) > 0
}

runtime_count_string :: proc(values: []string, needle: string) -> int {
	count := 0
	for value in values {
		if value == needle {
			count += 1
		}
	}
	return count
}

runtime_systems_conflict :: proc(left, right: Runtime_System_Definition) -> bool {
	for component_id in left.writes {
		if runtime_contains_string(right.reads, component_id) || runtime_contains_string(right.writes, component_id) {
			return true
		}
	}
	for component_id in right.writes {
		if runtime_contains_string(left.reads, component_id) || runtime_contains_string(left.writes, component_id) {
			return true
		}
	}
	return false
}

runtime_component_value_boolean :: proc(value: bool) -> Runtime_Component_Value {
	return Runtime_Component_Value{value_type = .Boolean, boolean = value}
}

runtime_component_value_int :: proc(value: int) -> Runtime_Component_Value {
	return Runtime_Component_Value{value_type = .Int, int_value = value}
}

runtime_component_value_float :: proc(value: f32) -> Runtime_Component_Value {
	return Runtime_Component_Value{value_type = .Float, float = value}
}

runtime_component_value_vec3 :: proc(value: [3]f32) -> Runtime_Component_Value {
	return Runtime_Component_Value{value_type = .Vec3, vec3 = value}
}

runtime_component_value_string :: proc(value: string) -> Runtime_Component_Value {
	return Runtime_Component_Value{value_type = .String, string_value = value}
}

runtime_component_value_clone :: proc(value: Runtime_Component_Value) -> (Runtime_Component_Value, Runtime_Error) {
	if value.value_type != .String {
		return value, .None
	}
	owned, err := strings.clone(value.string_value)
	if err != nil {
		return Runtime_Component_Value{}, .Out_Of_Memory
	}
	cloned := value
	cloned.string_value = owned
	return cloned, .None
}

runtime_component_value_free :: proc(value: Runtime_Component_Value) {
	if value.value_type == .String {
		delete(value.string_value)
	}
}

runtime_component_table_free :: proc(table: Runtime_Component_Table) {
	if table.id != "" {
		delete(table.id)
	}
	if table.entities != nil {
		delete(table.entities)
	}
	if table.rows_by_entity != nil {
		delete(table.rows_by_entity)
	}
	for column in table.columns {
		delete(column.name)
		for value in column.values {
			runtime_component_value_free(value)
		}
		if column.values != nil {
			delete(column.values)
		}
	}
	if table.columns != nil {
		delete(table.columns)
	}
}

runtime_component_table_field_index :: proc(table: Runtime_Component_Table, field_name: string) -> (int, bool) {
	for column, index in table.columns {
		if column.name == field_name {
			return index, true
		}
	}
	return -1, false
}

runtime_find_field_value :: proc(fields: []Runtime_Component_Field_Value, field_name: string) -> (Runtime_Component_Field_Value, bool) {
	for field in fields {
		if field.name == field_name {
			return field, true
		}
	}
	return Runtime_Component_Field_Value{}, false
}

runtime_component_table_validate_fields :: proc(table: Runtime_Component_Table, fields: []Runtime_Component_Field_Value) -> Runtime_Error {
	if len(fields) != len(table.columns) {
		return .Unknown_Field
	}
	for column in table.columns {
		field, found := runtime_find_field_value(fields, column.name)
		if !found {
			return .Unknown_Field
		}
		if field.value.value_type != column.value_type {
			return .Invalid_Field_Type
		}
	}
	for field, index in fields {
		if _, found := runtime_component_table_field_index(table, field.name); !found {
			return .Unknown_Field
		}
		for prior in fields[:index] {
			if prior.name == field.name {
				return .Unknown_Field
			}
		}
	}
	return .None
}

runtime_component_table_row_for_entity :: proc(table: Runtime_Component_Table, handle: Entity_Handle) -> (int, bool) {
	entity_index := int(handle.index)
	if entity_index < 0 || entity_index >= len(table.rows_by_entity) {
		return -1, false
	}
	row := table.rows_by_entity[entity_index]
	if row < 0 || row >= len(table.entities) {
		return -1, false
	}
	stored := table.entities[row]
	if stored.index != handle.index || (handle.generation != 0 && stored.generation != handle.generation) {
		return -1, false
	}
	return row, true
}

runtime_register_engine_components :: proc(registry: ^Runtime_Component_Registry) -> Runtime_Error {
	err := runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = TRANSFORM_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "position", value_type = .Vec3},
			{name = "rotation", value_type = .Vec3},
			{name = "scale", value_type = .Vec3},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = CUBE_RENDERER_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{{name = "color", value_type = .Vec3}},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = GEOMETRY_PRIMITIVE_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "primitive", value_type = .String},
			{name = "segments", value_type = .Int},
			{name = "rings", value_type = .Int},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = SURFACE_MATERIAL_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{{name = "base_color", value_type = .Vec3}},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = RENDERER_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "hdr", value_type = .Boolean},
			{name = "tone_mapping", value_type = .String},
			{name = "exposure", value_type = .Float},
			{name = "postprocess_enabled", value_type = .Boolean},
			{name = "antialiasing", value_type = .String},
			{name = "bloom_enabled", value_type = .Boolean},
			{name = "bloom_threshold", value_type = .Float},
			{name = "bloom_intensity", value_type = .Float},
			{name = "bloom_radius", value_type = .Float},
			{name = "vignette_enabled", value_type = .Boolean},
			{name = "vignette_strength", value_type = .Float},
			{name = "vignette_radius", value_type = .Float},
			{name = "chromatic_aberration_enabled", value_type = .Boolean},
			{name = "chromatic_aberration_strength", value_type = .Float},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = CAMERA_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "fov_y_degrees", value_type = .Float},
			{name = "near", value_type = .Float},
			{name = "far", value_type = .Float},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = DIRECTIONAL_LIGHT_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "direction", value_type = .Vec3},
			{name = "color", value_type = .Vec3},
			{name = "intensity", value_type = .Float},
			{name = "ambient", value_type = .Float},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{id = SHADOW_CASTER_COMPONENT_ID, version = 1})
	if err != .None do return err
	err = runtime_register_engine_component(registry, Runtime_Component_Definition{id = SHADOW_RECEIVER_COMPONENT_ID, version = 1})
	if err != .None do return err
	err = runtime_register_engine_component(registry, Runtime_Component_Definition{id = UI_BUTTON_COMPONENT_ID, version = 1})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_CANVAS_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "design_size", value_type = .Vec3},
			{name = "scale_mode", value_type = .String},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_RECT_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "position", value_type = .Vec3},
			{name = "size", value_type = .Vec3},
			{name = "color", value_type = .Vec3},
			{name = "corner_radius", value_type = .Float},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_BORDER_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "color", value_type = .Vec3},
			{name = "thickness", value_type = .Float},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_TEXT_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "position", value_type = .Vec3},
			{name = "size", value_type = .Float},
			{name = "color", value_type = .Vec3},
			{name = "value", value_type = .String},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_HIT_AREA_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "position", value_type = .Vec3},
			{name = "size", value_type = .Vec3},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_COMMAND_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{{name = "command", value_type = .String}},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_COMMAND_EVENT_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "command", value_type = .String},
			{name = "source", value_type = .String},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_SCROLL_VIEW_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "position", value_type = .Vec3},
			{name = "size", value_type = .Vec3},
			{name = "content_offset", value_type = .Vec3},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_VGROUP_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "position", value_type = .Vec3},
			{name = "size", value_type = .Vec3},
			{name = "spacing", value_type = .Float},
			{name = "padding", value_type = .Vec3},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_HGROUP_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "position", value_type = .Vec3},
			{name = "size", value_type = .Vec3},
			{name = "spacing", value_type = .Float},
			{name = "padding", value_type = .Vec3},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_TABLE_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "position", value_type = .Vec3},
			{name = "size", value_type = .Vec3},
			{name = "columns", value_type = .Int},
			{name = "row_height", value_type = .Float},
			{name = "column_gap", value_type = .Float},
			{name = "row_gap", value_type = .Float},
			{name = "padding", value_type = .Vec3},
			{name = "first_column_ratio", value_type = .Float},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_STACK_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "position", value_type = .Vec3},
			{name = "spacing", value_type = .Float},
			{name = "direction", value_type = .String},
			{name = "padding", value_type = .Vec3},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_LAYOUT_ITEM_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "parent", value_type = .String},
			{name = "order", value_type = .Int},
			{name = "min_size", value_type = .Vec3},
			{name = "preferred_size", value_type = .Vec3},
			{name = "max_size", value_type = .Vec3},
			{name = "grow", value_type = .Float},
			{name = "shrink", value_type = .Float},
			{name = "align", value_type = .String},
			{name = "margin", value_type = .Vec3},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_SPACER_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{{name = "size", value_type = .Vec3}},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_TEXT_BLOCK_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "size", value_type = .Vec3},
			{name = "horizontal_align", value_type = .String},
			{name = "vertical_align", value_type = .String},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_TOGGLE_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{{name = "checked", value_type = .Boolean}},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_PROGRESS_BAR_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "value", value_type = .Float},
			{name = "max", value_type = .Float},
			{name = "fill_color", value_type = .Vec3},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_SEPARATOR_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "position", value_type = .Vec3},
			{name = "size", value_type = .Vec3},
			{name = "color", value_type = .Vec3},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = INPUT_POINTER_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "position", value_type = .Vec3},
			{name = "delta", value_type = .Vec3},
			{name = "has_position", value_type = .Boolean},
			{name = "primary_down", value_type = .Boolean},
			{name = "primary_pressed", value_type = .Boolean},
			{name = "primary_released", value_type = .Boolean},
			{name = "secondary_down", value_type = .Boolean},
			{name = "secondary_pressed", value_type = .Boolean},
			{name = "secondary_released", value_type = .Boolean},
			{name = "wheel_delta", value_type = .Vec3},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = INPUT_KEYBOARD_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "ctrl_down", value_type = .Boolean},
			{name = "shift_down", value_type = .Boolean},
			{name = "alt_down", value_type = .Boolean},
			{name = "super_down", value_type = .Boolean},
			{name = "move_forward", value_type = .Boolean},
			{name = "move_back", value_type = .Boolean},
			{name = "move_left", value_type = .Boolean},
			{name = "move_right", value_type = .Boolean},
			{name = "move_up", value_type = .Boolean},
			{name = "move_down", value_type = .Boolean},
			{name = "editor_toggle_pressed", value_type = .Boolean},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = INPUT_FRAME_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "ui_visible", value_type = .Boolean},
			{name = "debug_overlay_visible", value_type = .Boolean},
			{name = "viewport", value_type = .Vec3},
			{name = "pixel_scale", value_type = .Float},
		},
	})
	if err != .None do return err

	return .None
}

runtime_validate_type_id :: proc(id: string) -> Runtime_Error {
	_, err := runtime_validate_type_id_shape(id)
	return err
}

runtime_validate_project_type_id :: proc(id: string) -> Runtime_Error {
	err := runtime_validate_type_id(id)
	if err != .None {
		return err
	}
	if runtime_is_engine_type_id(id) {
		return .Reserved_Type_ID
	}
	return .None
}

runtime_validate_package_type_id :: proc(id: string) -> Runtime_Error {
	segment_count, err := runtime_validate_type_id_shape(id)
	if err != .None {
		return err
	}
	if segment_count < 2 {
		return .Invalid_Type_ID
	}
	if runtime_is_engine_type_id(id) {
		return .Reserved_Type_ID
	}
	return .None
}

runtime_validate_engine_type_id :: proc(id: string) -> Runtime_Error {
	err := runtime_validate_type_id(id)
	if err != .None {
		return err
	}
	if !strings.has_prefix(id, ENGINE_NAMESPACE + ".") {
		return .Reserved_Type_ID
	}
	return .None
}

runtime_validate_type_id_for_context :: proc(id: string, registration_context: Runtime_Registration_Context) -> Runtime_Error {
	switch registration_context {
	case .Engine:
		return runtime_validate_engine_type_id(id)
	case .Project:
		return runtime_validate_project_type_id(id)
	case .Package:
		return runtime_validate_package_type_id(id)
	}
	return .Invalid_Type_ID
}

runtime_validate_reference_type_id_for_context :: proc(id: string, registration_context: Runtime_Registration_Context) -> Runtime_Error {
	switch registration_context {
	case .Engine, .Project:
		return runtime_validate_type_id(id)
	case .Package:
		segment_count, err := runtime_validate_type_id_shape(id)
		if err != .None {
			return err
		}
		if segment_count < 2 {
			return .Invalid_Type_ID
		}
		return .None
	}
	return .Invalid_Type_ID
}

runtime_validate_field_name :: proc(name: string) -> Runtime_Error {
	err := runtime_validate_identifier_segment(name)
	if err != .None {
		return .Invalid_Field_Name
	}
	return .None
}

runtime_validate_type_id_shape :: proc(id: string) -> (int, Runtime_Error) {
	segment_count := 0
	remaining := id
	for segment in strings.split_iterator(&remaining, ".") {
		err := runtime_validate_identifier_segment(segment)
		if err != .None {
			return 0, err
		}
		segment_count += 1
	}
	if segment_count == 0 {
		return 0, .Invalid_Type_ID
	}
	return segment_count, .None
}

runtime_validate_identifier_segment :: proc(segment: string) -> Runtime_Error {
	if segment == "" || !runtime_is_lower_alpha(segment[0]) {
		return .Invalid_Type_ID
	}
	for index := 1; index < len(segment); index += 1 {
		byte := segment[index]
		if !runtime_is_lower_alpha(byte) && !(byte >= '0' && byte <= '9') && byte != '_' {
			return .Invalid_Type_ID
		}
	}
	return .None
}

runtime_is_engine_type_id :: proc(id: string) -> bool {
	return id == ENGINE_NAMESPACE || strings.has_prefix(id, ENGINE_NAMESPACE + ".")
}

runtime_is_lower_alpha :: proc(byte: u8) -> bool {
	return byte >= 'a' && byte <= 'z'
}

runtime_world_init :: proc() -> Runtime_World {
	return Runtime_World{next_entity_generation = 1}
}

runtime_world_free :: proc(world: ^Runtime_World) {
	for table in world.component_tables {
		runtime_component_table_free(table)
	}
	if world.component_tables != nil {
		delete(world.component_tables)
	}
	for entity in world.entities {
		delete(entity.id)
		delete(entity.name)
	}
	if world.entities != nil {
		delete(world.entities)
	}
	world.component_tables = nil
	world.entities = nil
	world.next_entity_generation = 1
	world.query_plan_generation = 1
}

runtime_world_entity_count :: proc(world: Runtime_World) -> int {
	return len(world.entities)
}

runtime_world_component_instance_count :: proc(world: Runtime_World) -> int {
	count := 0
	for table in world.component_tables {
		count += len(table.entities)
	}
	return count
}

runtime_world_create_entity :: proc(world: ^Runtime_World, id, name: string) -> (Entity_Handle, Runtime_Error) {
	return runtime_world_create_entity_with_provenance(world, id, name, .Spawned)
}

runtime_world_create_authored_entity :: proc(world: ^Runtime_World, id, name: string) -> (Entity_Handle, Runtime_Error) {
	return runtime_world_create_entity_with_provenance(world, id, name, .Authored)
}

runtime_world_create_entity_with_provenance :: proc(
	world: ^Runtime_World,
	id, name: string,
	provenance: Entity_Provenance,
) -> (Entity_Handle, Runtime_Error) {
	if _, ok := runtime_world_find_entity_by_id(world^, id); ok {
		return Entity_Handle{}, .Duplicate_Entity_ID
	}

	owned_id, id_err := strings.clone(id)
	if id_err != nil {
		return Entity_Handle{}, .Out_Of_Memory
	}
	owned_name, name_err := strings.clone(name)
	if name_err != nil {
		delete(owned_id)
		return Entity_Handle{}, .Out_Of_Memory
	}

	generation := runtime_world_next_entity_generation(world)
	handle := Entity_Handle{index = u32(len(world.entities)), generation = generation}
	append(&world.entities, Runtime_Entity{
		id = owned_id,
		name = owned_name,
		generation = generation,
		provenance = provenance,
	})
	for &table in world.component_tables {
		append(&table.rows_by_entity, -1)
	}
	runtime_world_bump_query_plan_generation(world)
	return handle, .None
}

runtime_world_entity :: proc(world: Runtime_World, handle: Entity_Handle) -> (Runtime_Entity, Runtime_Error) {
	index := int(handle.index)
	if index < 0 || index >= len(world.entities) {
		return Runtime_Entity{}, .Invalid_Entity
	}
	entity := world.entities[index]
	if handle.generation != 0 && entity.generation != handle.generation {
		return Runtime_Entity{}, .Invalid_Entity
	}
	return entity, .None
}

runtime_world_find_entity_by_id :: proc(world: Runtime_World, id: string) -> (Entity_Handle, bool) {
	for entity, index in world.entities {
		if entity.id == id {
			return Entity_Handle{index = u32(index), generation = entity.generation}, true
		}
	}
	return Entity_Handle{}, false
}

runtime_world_find_component_table :: proc(world: Runtime_World, component_id: string) -> (^Runtime_Component_Table, bool) {
	for &table in world.component_tables {
		if table.id == component_id {
			return &table, true
		}
	}
	return nil, false
}

runtime_world_ensure_component_table :: proc(
	world: ^Runtime_World,
	component_id: string,
	fields: []Runtime_Component_Field_Value,
) -> (int, Runtime_Error) {
	for table, index in world.component_tables {
		if table.id == component_id {
			validate_err := runtime_component_table_validate_fields(table, fields)
			if validate_err != .None {
				return -1, validate_err
			}
			return index, .None
		}
	}

	owned_id, id_err := strings.clone(component_id)
	if id_err != nil {
		return -1, .Out_Of_Memory
	}
	columns := make([]Runtime_Component_Column, len(fields))
	if columns == nil && len(fields) > 0 {
		delete(owned_id)
		return -1, .Out_Of_Memory
	}
	initialized_columns := 0
	for field, index in fields {
		for prior in fields[:index] {
			if prior.name == field.name {
				for column in columns[:initialized_columns] {
					delete(column.name)
				}
				delete(columns)
				delete(owned_id)
				return -1, .Unknown_Field
			}
		}
		owned_name, name_err := strings.clone(field.name)
		if name_err != nil {
			for column in columns[:initialized_columns] {
				delete(column.name)
			}
			delete(columns)
			delete(owned_id)
			return -1, .Out_Of_Memory
		}
		columns[index] = Runtime_Component_Column{
			name = owned_name,
			value_type = field.value.value_type,
		}
		initialized_columns += 1
	}

	rows_by_entity := make([dynamic]int)
	for _ in world.entities {
		append(&rows_by_entity, -1)
	}

	append(&world.component_tables, Runtime_Component_Table{
		id = owned_id,
		rows_by_entity = rows_by_entity,
		columns = columns,
	})
	return len(world.component_tables) - 1, .None
}

runtime_world_set_component :: proc(
	world: ^Runtime_World,
	handle: Entity_Handle,
	component_id: string,
	fields: []Runtime_Component_Field_Value,
) -> Runtime_Error {
	entity_index, index_err := runtime_world_entity_index(world^, handle)
	if index_err != .None {
		return index_err
	}
	table_index, table_err := runtime_world_ensure_component_table(world, component_id, fields)
	if table_err != .None {
		return table_err
	}
	table := &world.component_tables[table_index]
	if table.rows_by_entity[entity_index] >= 0 {
		return runtime_world_update_component_row(table, table.rows_by_entity[entity_index], fields)
	}
	err := runtime_world_append_component_row(table, handle, entity_index, fields)
	if err == .None {
		runtime_world_bump_query_plan_generation(world)
	}
	return err
}

runtime_world_append_component_row :: proc(
	table: ^Runtime_Component_Table,
	handle: Entity_Handle,
	entity_index: int,
	fields: []Runtime_Component_Field_Value,
) -> Runtime_Error {
	validate_err := runtime_component_table_validate_fields(table^, fields)
	if validate_err != .None {
		return validate_err
	}
	row := len(table.entities)
	append(&table.entities, handle)
	table.rows_by_entity[entity_index] = row
	appended_columns := 0
	for &column in table.columns {
		field, found := runtime_find_field_value(fields, column.name)
		if !found {
			for &rollback_column in table.columns[:appended_columns] {
				runtime_component_value_free(pop(&rollback_column.values))
			}
			table.rows_by_entity[entity_index] = -1
			pop(&table.entities)
			return .Unknown_Field
		}
		cloned, clone_err := runtime_component_value_clone(field.value)
		if clone_err != .None {
			for &rollback_column in table.columns[:appended_columns] {
				runtime_component_value_free(pop(&rollback_column.values))
			}
			table.rows_by_entity[entity_index] = -1
			pop(&table.entities)
			return clone_err
		}
		append(&column.values, cloned)
		appended_columns += 1
	}
	return .None
}

runtime_world_update_component_row :: proc(
	table: ^Runtime_Component_Table,
	row: int,
	fields: []Runtime_Component_Field_Value,
) -> Runtime_Error {
	validate_err := runtime_component_table_validate_fields(table^, fields)
	if validate_err != .None {
		return validate_err
	}
	for &column in table.columns {
		field, found := runtime_find_field_value(fields, column.name)
		if !found {
			return .Unknown_Field
		}
		if field.value.value_type != column.value_type {
			return .Invalid_Field_Type
		}
		cloned, clone_err := runtime_component_value_clone(field.value)
		if clone_err != .None {
			return clone_err
		}
		runtime_component_value_free(column.values[row])
		column.values[row] = cloned
	}
	return .None
}

runtime_world_remove_component :: proc(world: ^Runtime_World, handle: Entity_Handle, component_id: string) -> (bool, Runtime_Error) {
	entity_index, index_err := runtime_world_entity_index(world^, handle)
	if index_err != .None {
		return false, index_err
	}
	table, found := runtime_world_find_component_table(world^, component_id)
	if !found || entity_index >= len(table.rows_by_entity) {
		return false, .None
	}
	row := table.rows_by_entity[entity_index]
	if row < 0 {
		return false, .None
	}
	last_row := len(table.entities) - 1
	removed_entity := table.entities[row]
	moved_entity := table.entities[last_row]

	table.entities[row] = moved_entity
	pop(&table.entities)
	table.rows_by_entity[int(removed_entity.index)] = -1
	if row != last_row {
		table.rows_by_entity[int(moved_entity.index)] = row
	}

	for &column in table.columns {
		runtime_component_column_swap_remove(&column, row)
	}
	runtime_world_bump_query_plan_generation(world)
	return true, .None
}

runtime_component_column_swap_remove :: proc(column: ^Runtime_Component_Column, row: int) {
	last_index := len(column.values) - 1
	if row == last_index {
		runtime_component_value_free(pop(&column.values))
		return
	}
	runtime_component_value_free(column.values[row])
	column.values[row] = column.values[last_index]
	pop(&column.values)
}

runtime_world_has_component :: proc(world: Runtime_World, handle: Entity_Handle, component_id: string) -> (bool, Runtime_Error) {
	entity_index, index_err := runtime_world_entity_index(world, handle)
	if index_err != .None {
		return false, index_err
	}
	table, found := runtime_world_find_component_table(world, component_id)
	if !found || entity_index >= len(table.rows_by_entity) {
		return false, .None
	}
	return table.rows_by_entity[entity_index] >= 0, .None
}

runtime_world_has_components :: proc(world: Runtime_World, handle: Entity_Handle, component_ids: []string) -> (bool, Runtime_Error) {
	for component_id in component_ids {
		has_component, err := runtime_world_has_component(world, handle, component_id)
		if err != .None || !has_component {
			return false, err
		}
	}
	return true, .None
}

runtime_world_get_component_field_value :: proc(
	world: Runtime_World,
	handle: Entity_Handle,
	component_id, field_name: string,
) -> (Runtime_Component_Value, Runtime_Error) {
	_, index_err := runtime_world_entity_index(world, handle)
	if index_err != .None {
		return Runtime_Component_Value{}, index_err
	}
	table, found := runtime_world_find_component_table(world, component_id)
	if !found {
		return Runtime_Component_Value{}, .Unknown_Component
	}
	row, row_found := runtime_component_table_row_for_entity(table^, handle)
	if !row_found {
		return Runtime_Component_Value{}, .Unknown_Component
	}
	column_index, column_found := runtime_component_table_field_index(table^, field_name)
	if !column_found {
		return Runtime_Component_Value{}, .Unknown_Field
	}
	return table.columns[column_index].values[row], .None
}

runtime_world_set_component_field_value :: proc(
	world: ^Runtime_World,
	handle: Entity_Handle,
	component_id, field_name: string,
	value: Runtime_Component_Value,
) -> Runtime_Error {
	_, index_err := runtime_world_entity_index(world^, handle)
	if index_err != .None {
		return index_err
	}
	table, found := runtime_world_find_component_table(world^, component_id)
	if !found {
		return .Unknown_Component
	}
	row, row_found := runtime_component_table_row_for_entity(table^, handle)
	if !row_found {
		return .Unknown_Component
	}
	column_index, column_found := runtime_component_table_field_index(table^, field_name)
	if !column_found {
		return .Unknown_Field
	}
	column := &table.columns[column_index]
	if value.value_type != column.value_type {
		return .Invalid_Field_Type
	}
	cloned, clone_err := runtime_component_value_clone(value)
	if clone_err != .None {
		return clone_err
	}
	runtime_component_value_free(column.values[row])
	column.values[row] = cloned
	return .None
}

runtime_world_prepare_query :: proc(
	world: Runtime_World,
	component_ids: []string,
	out_component_table_indices: []u32,
) -> (u32, bool, Runtime_Error) {
	if len(component_ids) == 0 || len(out_component_table_indices) < len(component_ids) {
		return 0, false, .Unknown_Component
	}
	driver_table_index := u32(0)
	driver_len := 0
	for component_id, index in component_ids {
		table_index, found := runtime_world_component_table_index(world, component_id)
		if !found {
			return 0, false, .None
		}
		out_component_table_indices[index] = u32(table_index)
		table := world.component_tables[table_index]
		if index == 0 || len(table.entities) < driver_len {
			driver_table_index = u32(table_index)
			driver_len = len(table.entities)
		}
	}
	return driver_table_index, true, .None
}

runtime_world_query_next_prepared :: proc(
	world: Runtime_World,
	component_table_indices: []u32,
	driver_table_index: u32,
	cursor: ^int,
	out_component_rows: []u32,
) -> (Entity_Handle, bool, Runtime_Error) {
	if len(component_table_indices) == 0 || len(out_component_rows) < len(component_table_indices) {
		return Entity_Handle{}, false, .Unknown_Component
	}
	driver, driver_ok := runtime_world_component_table_at(world, driver_table_index)
	if !driver_ok {
		return Entity_Handle{}, false, .Unknown_Component
	}
	for cursor^ < len(driver.entities) {
		handle := driver.entities[cursor^]
		cursor^ += 1
		matches := true
		for table_index, index in component_table_indices {
			table, table_ok := runtime_world_component_table_at(world, table_index)
			if !table_ok {
				return Entity_Handle{}, false, .Unknown_Component
			}
			row, row_found := runtime_component_table_row_for_entity(table^, handle)
			if !row_found {
				matches = false
				break
			}
			out_component_rows[index] = u32(row)
		}
		if matches {
			return handle, true, .None
		}
	}
	return Entity_Handle{}, false, .None
}

runtime_world_get_component_field_value_resolved :: proc(
	world: Runtime_World,
	handle: Entity_Handle,
	resolved: Runtime_Resolved_Component_Row,
	field_name: string,
) -> (Runtime_Component_Value, Runtime_Error) {
	_, index_err := runtime_world_entity_index(world, handle)
	if index_err != .None {
		return Runtime_Component_Value{}, index_err
	}
	table, table_ok := runtime_world_component_table_at(world, resolved.table_index)
	if !table_ok {
		return Runtime_Component_Value{}, .Unknown_Component
	}
	row, row_found := runtime_component_table_resolved_row_for_entity(table^, handle, int(resolved.row_index))
	if !row_found {
		return Runtime_Component_Value{}, .Unknown_Component
	}
	column_index, column_found := runtime_component_table_field_index(table^, field_name)
	if !column_found {
		return Runtime_Component_Value{}, .Unknown_Field
	}
	return table.columns[column_index].values[row], .None
}

runtime_world_set_component_field_value_resolved :: proc(
	world: ^Runtime_World,
	handle: Entity_Handle,
	resolved: Runtime_Resolved_Component_Row,
	field_name: string,
	value: Runtime_Component_Value,
) -> Runtime_Error {
	_, index_err := runtime_world_entity_index(world^, handle)
	if index_err != .None {
		return index_err
	}
	table, table_ok := runtime_world_component_table_at_mut(world, resolved.table_index)
	if !table_ok {
		return .Unknown_Component
	}
	row, row_found := runtime_component_table_resolved_row_for_entity(table^, handle, int(resolved.row_index))
	if !row_found {
		return .Unknown_Component
	}
	column_index, column_found := runtime_component_table_field_index(table^, field_name)
	if !column_found {
		return .Unknown_Field
	}
	column := &table.columns[column_index]
	if value.value_type != column.value_type {
		return .Invalid_Field_Type
	}
	cloned, clone_err := runtime_component_value_clone(value)
	if clone_err != .None {
		return clone_err
	}
	runtime_component_value_free(column.values[row])
	column.values[row] = cloned
	return .None
}

runtime_world_query_next :: proc(world: Runtime_World, component_ids: []string, cursor: ^int) -> (Entity_Handle, bool) {
	driver, driver_found := runtime_world_query_driver_table(world, component_ids)
	if !driver_found {
		return Entity_Handle{}, false
	}
	for cursor^ < len(driver.entities) {
		handle := driver.entities[cursor^]
		cursor^ += 1
		matches, err := runtime_world_has_components(world, handle, component_ids)
		if err == .None && matches {
			return handle, true
		}
	}
	return Entity_Handle{}, false
}

runtime_component_table_resolved_row_for_entity :: proc(table: Runtime_Component_Table, handle: Entity_Handle, resolved_row: int) -> (int, bool) {
	if resolved_row >= 0 && resolved_row < len(table.entities) {
		candidate := table.entities[resolved_row]
		if candidate.index == handle.index && candidate.generation == handle.generation {
			return resolved_row, true
		}
	}
	entity_index := int(handle.index)
	if entity_index < 0 || entity_index >= len(table.rows_by_entity) {
		return -1, false
	}
	row := table.rows_by_entity[entity_index]
	if row < 0 || row >= len(table.entities) {
		return -1, false
	}
	candidate := table.entities[row]
	if candidate.index != handle.index || candidate.generation != handle.generation {
		return -1, false
	}
	return row, true
}

runtime_world_component_table_index :: proc(world: Runtime_World, component_id: string) -> (int, bool) {
	for table, index in world.component_tables {
		if table.id == component_id {
			return index, true
		}
	}
	return -1, false
}

runtime_world_component_table_at :: proc(world: Runtime_World, table_index: u32) -> (^Runtime_Component_Table, bool) {
	index := int(table_index)
	if index < 0 || index >= len(world.component_tables) {
		return nil, false
	}
	return &world.component_tables[index], true
}

runtime_world_component_table_at_mut :: proc(world: ^Runtime_World, table_index: u32) -> (^Runtime_Component_Table, bool) {
	index := int(table_index)
	if index < 0 || index >= len(world.component_tables) {
		return nil, false
	}
	return &world.component_tables[index], true
}

runtime_world_query_driver_table :: proc(world: Runtime_World, component_ids: []string) -> (table: ^Runtime_Component_Table, ok: bool) {
	if len(component_ids) == 0 {
		return nil, false
	}
	best_len := 0
	for component_id in component_ids {
		candidate, found := runtime_world_find_component_table(world, component_id)
		if !found {
			return nil, false
		}
		if table == nil || len(candidate.entities) < best_len {
			table = candidate
			best_len = len(candidate.entities)
		}
	}
	return table, true
}

runtime_deferred_command_buffer_free :: proc(buffer: ^Runtime_Deferred_Command_Buffer) {
	runtime_deferred_clear_commands(buffer)
	if buffer.commands != nil {
		delete(buffer.commands)
	}
	if buffer.immediate_spawns != nil {
		delete(buffer.immediate_spawns)
	}
	buffer.commands = nil
	buffer.immediate_spawns = nil
}

runtime_deferred_clear_commands :: proc(buffer: ^Runtime_Deferred_Command_Buffer) {
	for command in buffer.commands {
		runtime_deferred_command_free(command)
	}
	clear(&buffer.commands)
	clear(&buffer.immediate_spawns)
}

runtime_deferred_command_free :: proc(command: Runtime_Deferred_Command) {
	if command.component_id != "" {
		delete(command.component_id)
	}
	for field in command.fields {
		if field.name != "" {
			delete(field.name)
		}
		runtime_component_value_free(field.value)
	}
	if command.fields != nil {
		delete(command.fields)
	}
}

runtime_deferred_record_immediate_spawn :: proc(buffer: ^Runtime_Deferred_Command_Buffer, handle: Entity_Handle) -> Runtime_Error {
	append(&buffer.immediate_spawns, handle)
	return .None
}

runtime_deferred_discard :: proc(buffer: ^Runtime_Deferred_Command_Buffer, world: ^Runtime_World) {
	runtime_deferred_rollback_immediate_spawns(buffer^, world)
	runtime_deferred_clear_commands(buffer)
}

runtime_deferred_queue_add_component :: proc(
	buffer: ^Runtime_Deferred_Command_Buffer,
	system: Runtime_System_Definition,
	entity: Entity_Handle,
	component_id: string,
	fields: []Runtime_Component_Field_Value,
) -> Runtime_Error {
	if !runtime_system_has_write_access(system, component_id) {
		return .Access_Denied
	}
	owned_id, id_err := strings.clone(component_id)
	if id_err != nil {
		return .Out_Of_Memory
	}
	owned_fields, fields_err := runtime_component_field_values_clone(fields)
	if fields_err != .None {
		delete(owned_id)
		return fields_err
	}
	append(&buffer.commands, Runtime_Deferred_Command{
		kind = .Add_Component,
		entity = entity,
		component_id = owned_id,
		fields = owned_fields,
	})
	return .None
}

runtime_deferred_queue_remove_component :: proc(
	buffer: ^Runtime_Deferred_Command_Buffer,
	system: Runtime_System_Definition,
	entity: Entity_Handle,
	component_id: string,
) -> Runtime_Error {
	if !runtime_system_has_write_access(system, component_id) {
		return .Access_Denied
	}
	owned_id, id_err := strings.clone(component_id)
	if id_err != nil {
		return .Out_Of_Memory
	}
	append(&buffer.commands, Runtime_Deferred_Command{
		kind = .Remove_Component,
		entity = entity,
		component_id = owned_id,
	})
	return .None
}

runtime_deferred_queue_despawn_entity :: proc(
	buffer: ^Runtime_Deferred_Command_Buffer,
	world: Runtime_World,
	system: Runtime_System_Definition,
	entity: Entity_Handle,
) -> Runtime_Error {
	if _, entity_err := runtime_world_entity(world, entity); entity_err != .None {
		return entity_err
	}
	for table in world.component_tables {
		if _, found := runtime_component_table_row_for_entity(table, entity); found {
			if !runtime_system_has_write_access(system, table.id) {
				return .Access_Denied
			}
		}
	}
	append(&buffer.commands, Runtime_Deferred_Command{kind = .Despawn_Entity, entity = entity})
	return .None
}

runtime_deferred_flush :: proc(buffer: ^Runtime_Deferred_Command_Buffer, world: ^Runtime_World, registry: Runtime_Component_Registry) -> Runtime_Error {
	preflight_err := runtime_deferred_preflight(buffer^, world^, registry)
	if preflight_err != .None {
		runtime_deferred_rollback_immediate_spawns(buffer^, world)
		runtime_deferred_clear_commands(buffer)
		return preflight_err
	}

	for command in buffer.commands {
		switch command.kind {
		case .Add_Component:
			err := runtime_world_set_component(world, command.entity, command.component_id, command.fields)
			if err != .None {
				runtime_deferred_rollback_immediate_spawns(buffer^, world)
				runtime_deferred_clear_commands(buffer)
				return err
			}
		case .Remove_Component:
			_, err := runtime_world_remove_component(world, command.entity, command.component_id)
			if err != .None {
				runtime_deferred_rollback_immediate_spawns(buffer^, world)
				runtime_deferred_clear_commands(buffer)
				return err
			}
		case .Despawn_Entity:
		}
	}

	for command in buffer.commands {
		switch command.kind {
		case .Add_Component, .Remove_Component:
		case .Despawn_Entity:
			err := runtime_world_remove_entity(world, command.entity)
			if err != .None {
				runtime_deferred_rollback_immediate_spawns(buffer^, world)
				runtime_deferred_clear_commands(buffer)
				return err
			}
		}
	}

	runtime_deferred_clear_commands(buffer)
	return .None
}

runtime_deferred_preflight :: proc(buffer: Runtime_Deferred_Command_Buffer, world: Runtime_World, registry: Runtime_Component_Registry) -> Runtime_Error {
	despawned_entities := make([dynamic]Entity_Handle)
	defer delete(despawned_entities)
	for command in buffer.commands {
		switch command.kind {
		case .Add_Component:
			if runtime_contains_entity_handle(despawned_entities[:], command.entity) {
				return .Invalid_Structural_Command
			}
			if _, entity_err := runtime_world_entity(world, command.entity); entity_err != .None {
				return entity_err
			}
			validate_err := runtime_deferred_validate_add_component(registry, command.component_id, command.fields)
			if validate_err != .None {
				return validate_err
			}
		case .Remove_Component:
			if runtime_contains_entity_handle(despawned_entities[:], command.entity) {
				return .Invalid_Structural_Command
			}
			if _, entity_err := runtime_world_entity(world, command.entity); entity_err != .None {
				return entity_err
			}
		case .Despawn_Entity:
			if runtime_contains_entity_handle(despawned_entities[:], command.entity) {
				return .Invalid_Structural_Command
			}
			if _, entity_err := runtime_world_entity(world, command.entity); entity_err != .None {
				return entity_err
			}
			append(&despawned_entities, command.entity)
		}
	}
	return .None
}

runtime_deferred_validate_add_component :: proc(
	registry: Runtime_Component_Registry,
	component_id: string,
	fields: []Runtime_Component_Field_Value,
) -> Runtime_Error {
	definition, found := runtime_find_component(registry, component_id)
	if !found {
		return .Unknown_Component_Type
	}
	if len(fields) != len(definition.fields) {
		return .Unknown_Field
	}
	for field_definition in definition.fields {
		matches := 0
		for field in fields {
			if field.name != field_definition.name {
				continue
			}
			matches += 1
			if field.value.value_type != field_definition.value_type {
				return .Invalid_Field_Type
			}
		}
		if matches == 0 {
			return .Unknown_Field
		}
		if matches > 1 {
			return .Invalid_Structural_Command
		}
	}
	return .None
}

runtime_deferred_rollback_immediate_spawns :: proc(buffer: Runtime_Deferred_Command_Buffer, world: ^Runtime_World) {
	index := len(buffer.immediate_spawns)
	for index > 0 {
		index -= 1
		_ = runtime_world_remove_entity(world, buffer.immediate_spawns[index])
	}
}

runtime_component_field_values_clone :: proc(fields: []Runtime_Component_Field_Value) -> ([]Runtime_Component_Field_Value, Runtime_Error) {
	owned_fields := make([]Runtime_Component_Field_Value, len(fields))
	if owned_fields == nil && len(fields) > 0 {
		return nil, .Out_Of_Memory
	}
	copied_count := 0
	for field, index in fields {
		owned_name, name_err := strings.clone(field.name)
		if name_err != nil {
			runtime_component_field_values_free(owned_fields[:copied_count])
			delete(owned_fields)
			return nil, .Out_Of_Memory
		}
		owned_value, value_err := runtime_component_value_clone(field.value)
		if value_err != .None {
			delete(owned_name)
			runtime_component_field_values_free(owned_fields[:copied_count])
			delete(owned_fields)
			return nil, value_err
		}
		owned_fields[index] = Runtime_Component_Field_Value{name = owned_name, value = owned_value}
		copied_count += 1
	}
	return owned_fields, .None
}

runtime_component_field_values_free :: proc(fields: []Runtime_Component_Field_Value) {
	for field in fields {
		if field.name != "" {
			delete(field.name)
		}
		runtime_component_value_free(field.value)
	}
}

runtime_system_has_write_access :: proc(system: Runtime_System_Definition, component_id: string) -> bool {
	return runtime_contains_string(system.writes, component_id)
}

runtime_contains_entity_handle :: proc(handles: []Entity_Handle, handle: Entity_Handle) -> bool {
	for candidate in handles {
		if candidate.index == handle.index && candidate.generation == handle.generation {
			return true
		}
	}
	return false
}

runtime_world_remove_entity :: proc(world: ^Runtime_World, handle: Entity_Handle) -> Runtime_Error {
	index := int(handle.index)
	if _, err := runtime_world_entity(world^, handle); err != .None {
		return err
	}

	last_index := len(world.entities) - 1
	for {
		removed_component := false
		for table in world.component_tables {
			if index < len(table.rows_by_entity) && table.rows_by_entity[index] >= 0 {
				_, remove_err := runtime_world_remove_component(world, handle, table.id)
				if remove_err != .None {
					return remove_err
				}
				removed_component = true
				break
			}
		}
		if !removed_component {
			break
		}
	}

	delete(world.entities[index].id)
	delete(world.entities[index].name)
	if index != last_index {
		world.entities[index] = world.entities[last_index]
	}
	pop(&world.entities)
	for &table in world.component_tables {
		moved_row := -1
		if index != last_index && last_index < len(table.rows_by_entity) {
			moved_row = table.rows_by_entity[last_index]
		}
		if index < len(table.rows_by_entity) {
			table.rows_by_entity[index] = moved_row
		}
		if moved_row >= 0 {
			table.entities[moved_row] = Entity_Handle{
				index = u32(index),
				generation = world.entities[index].generation,
			}
		}
		if len(table.rows_by_entity) > 0 {
			pop(&table.rows_by_entity)
		}
	}
	runtime_world_bump_query_plan_generation(world)
	return .None
}

runtime_world_query_plan_generation :: proc(world: Runtime_World) -> u64 {
	if world.query_plan_generation == 0 {
		return 1
	}
	return world.query_plan_generation
}

runtime_world_bump_query_plan_generation :: proc(world: ^Runtime_World) {
	if world.query_plan_generation == 0 {
		world.query_plan_generation = 1
	}
	world.query_plan_generation += 1
	if world.query_plan_generation == 0 {
		world.query_plan_generation = 1
	}
}

runtime_world_entity_index :: proc(world: Runtime_World, handle: Entity_Handle) -> (int, Runtime_Error) {
	index := int(handle.index)
	if index < 0 || index >= len(world.entities) {
		return -1, .Invalid_Entity
	}
	if handle.generation != 0 && world.entities[index].generation != handle.generation {
		return -1, .Invalid_Entity
	}
	return index, .None
}

runtime_world_next_entity_generation :: proc(world: ^Runtime_World) -> u32 {
	generation := world.next_entity_generation
	world.next_entity_generation += 1
	if world.next_entity_generation == 0 {
		world.next_entity_generation = 1
	}
	return generation
}
