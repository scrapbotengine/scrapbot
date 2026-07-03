export type MachinaComponentId = string
export type MachinaSystemId = string

export type MachinaFieldType =
    "boolean"
    | "bool"
    | "int"
    | "i32"
    | "float"
    | "f32"
    | "vec3"
    | "string"

export type MachinaComponentDefinition = {
    version: number?,
    fields: { [string]: MachinaFieldType }?,
}

export type MachinaSystemPhase = "startup" | "update" | "fixed_update" | "render"

export type MachinaVec3 = { number }

type function MachinaPayloadFromComponentType(component)
    if not component:is("table") then
        return component
    end

    local payload = types.newtable()
    local vec3Type = types.newtable(nil, {
        index = types.number,
        readresult = types.number,
        writeresult = types.number,
    })

    local didMap = false
    for key, property in pairs(component:properties() :: any) do
        local fieldType = (property :: any).read or (property :: any).write
        if fieldType == nil or not fieldType:is("singleton") then
            return component
        end

        local value = fieldType:value()
        if type(value) ~= "string" then
            return component
        end

        if value == "vec3" then
            payload:setproperty(key :: any, vec3Type :: any)
        elseif value == "string" then
            payload:setproperty(key :: any, types.string :: any)
        elseif value == "boolean" or value == "bool" then
            payload:setproperty(key :: any, types.boolean :: any)
        elseif value == "float" or value == "f32" or value == "int" or value == "i32" then
            payload:setproperty(key :: any, types.number :: any)
        else
            error("unsupported component field type '" .. value .. "'")
        end

        didMap = true
    end

    if not didMap then
        return component
    end

    return payload
end

type function MachinaValidatedFields(fields)
    if not fields:is("table") then
        error("component fields must be a table type")
    end

    for _, property in pairs(fields:properties() :: any) do
        local fieldType = (property :: any).read or (property :: any).write
        if fieldType == nil or not fieldType:is("singleton") then
            error("component field declarations must be literal field type strings")
        end

        local value = fieldType:value()
        if type(value) ~= "string" then
            error("component field declarations must be literal field type strings")
        end

        if value ~= "vec3"
            and value ~= "string"
            and value ~= "boolean"
            and value ~= "bool"
            and value ~= "float"
            and value ~= "f32"
            and value ~= "int"
            and value ~= "i32"
        then
            error("unsupported component field type '" .. value .. "'")
        end
    end

    return fields
end

type function MachinaNonNil(value)
    local ty = value :: any
    if ty:is("union") then
        local components = {}
        for _, component in ipairs(ty:components() :: any) do
            if not component:is("nil") then
                table.insert(components, component)
            end
        end

        if #components == 0 then
            return types.never
        elseif #components == 1 then
            return components[1] :: any
        else
            return types.unionof(table.unpack(components) :: any)
        end
    elseif ty:is("nil") then
        return types.never
    else
        return value
    end
end

export type MachinaSchemaValue = MachinaVec3

export type MachinaSchemaComponentDefinition<T> = {
    version: number?,
    fields: T,
}

export type MachinaInferredComponentDefinition<T> =
    { fields: T }
    | { version: number, fields: T }

export type MachinaComponent<T> = {
    id: MachinaComponentId,

    --- Runtime-guarded type brand used by Luau to preserve component payload types through handles.
    __machina_component_type: () -> T,

    --- Analysis-only payload slot used by typed query inference.
    __machina_component_payload: T?,
}

export type MachinaTypedComponent<T> = {
    id: MachinaComponentId,
    __machina_component_payload: T?,
}

export type MachinaComponentHandle = {
    id: MachinaComponentId,
}

export type MachinaComponentRef = MachinaComponentId | MachinaComponentHandle
export type MachinaComponentRefs = { MachinaComponentId }
export type MachinaQueryRef = {
    refs: MachinaComponentRefs,
}

export type MachinaTransform = {
    position: MachinaVec3,
    rotation: MachinaVec3,
    scale: MachinaVec3,
}

export type MachinaRenderCube = {
    color: MachinaVec3,
}

export type MachinaGeometryPrimitive = {
    primitive: string,
    segments: number,
    rings: number,
}

export type MachinaSurfaceMaterial = {
    base_color: MachinaVec3,
}

export type MachinaCamera = {
    fov_y_degrees: number,
    near: number,
    far: number,
}

export type MachinaDirectionalLight = {
    direction: MachinaVec3,
    color: MachinaVec3,
    intensity: number,
    ambient: number,
}

export type MachinaShadowCaster = {}
export type MachinaShadowReceiver = {}

export type MachinaUiCanvas = {}

export type MachinaUiRect = {
    position: MachinaVec3,
    size: MachinaVec3,
    color: MachinaVec3,
}

export type MachinaUiText = {
    position: MachinaVec3,
    size: number,
    color: MachinaVec3,
    value: string,
}

export type MachinaUiButton = {}

export type MachinaUiCommand = {
    command: string,
}

export type MachinaUiCommandEvent = {
    command: string,
    source: string,
}

export type MachinaInputPointer = {
    position: MachinaVec3,
    has_position: boolean,
    primary_down: boolean,
    primary_pressed: boolean,
    primary_released: boolean,
    wheel_delta: MachinaVec3,
}

export type MachinaInputKeyboard = {
    ctrl_down: boolean,
    shift_down: boolean,
    alt_down: boolean,
    super_down: boolean,
    editor_toggle_pressed: boolean,
}

export type MachinaInputFrame = {
    ui_visible: boolean,
    debug_overlay_visible: boolean,
    viewport: MachinaVec3,
}

export type MachinaEntity = {
    add: <T>(
        self: MachinaEntity,
        component: MachinaTypedComponent<T>,
        fields: T?
    ) -> (),

    remove: (
        self: MachinaEntity,
        component: MachinaComponentRef
    ) -> (),

    despawn: (
        self: MachinaEntity
    ) -> (),

    get_vec3: (
        component: MachinaComponentId,
        field: string
    ) -> MachinaVec3,

    set_vec3: (
        component: MachinaComponentId,
        field: string,
        value: MachinaVec3
    ) -> (),
}

export type MachinaWorldQueryFunction =
    (<A>(MachinaTypedComponent<A>) -> (() -> (MachinaEntity, MachinaNonNil<A>)))
    & (<A, B>(MachinaTypedComponent<A>, MachinaTypedComponent<B>) -> (() -> (MachinaEntity, MachinaNonNil<A>, MachinaNonNil<B>)))
    & (<A, B, C>(MachinaTypedComponent<A>, MachinaTypedComponent<B>, MachinaTypedComponent<C>) -> (() -> (MachinaEntity, MachinaNonNil<A>, MachinaNonNil<B>, MachinaNonNil<C>)))
    & (<A, B, C, D>(MachinaTypedComponent<A>, MachinaTypedComponent<B>, MachinaTypedComponent<C>, MachinaTypedComponent<D>) -> (() -> (MachinaEntity, MachinaNonNil<A>, MachinaNonNil<B>, MachinaNonNil<C>, MachinaNonNil<D>)))
    & (<A, B, C, D, E>(MachinaTypedComponent<A>, MachinaTypedComponent<B>, MachinaTypedComponent<C>, MachinaTypedComponent<D>, MachinaTypedComponent<E>) -> (() -> (MachinaEntity, MachinaNonNil<A>, MachinaNonNil<B>, MachinaNonNil<C>, MachinaNonNil<D>, MachinaNonNil<E>)))
    & (<A, B, C, D, E, F>(MachinaTypedComponent<A>, MachinaTypedComponent<B>, MachinaTypedComponent<C>, MachinaTypedComponent<D>, MachinaTypedComponent<E>, MachinaTypedComponent<F>) -> (() -> (MachinaEntity, MachinaNonNil<A>, MachinaNonNil<B>, MachinaNonNil<C>, MachinaNonNil<D>, MachinaNonNil<E>, MachinaNonNil<F>)))
    & ((...MachinaComponentId) -> (() -> MachinaEntity))

export type MachinaWorld = {
    --- Iterates entities that have all requested components.
    query: MachinaWorldQueryFunction,

    --- Spawns an empty entity. Add components before expecting it in queries.
    spawn: (id: string, name: string?) -> MachinaEntity,
}

export type MachinaQueryView = {
    --- Returns the number of entities captured by this frame-local view.
    count: (self: MachinaQueryView) -> number,

    --- Bulk reads one f32 field into a packed Luau buffer.
    read_f32: (self: MachinaQueryView, component: MachinaComponentRef, field: string) -> buffer,

    --- Bulk writes one f32 field from a packed Luau buffer.
    write_f32: (self: MachinaQueryView, component: MachinaComponentRef, field: string, values: buffer) -> (),

    --- Bulk reads one vec3 field into a packed xyz xyz Luau buffer.
    read_vec3: (self: MachinaQueryView, component: MachinaComponentRef, field: string) -> buffer,

    --- Bulk writes one vec3 field from a packed xyz xyz Luau buffer.
    write_vec3: (self: MachinaQueryView, component: MachinaComponentRef, field: string, values: buffer) -> (),
}

export type MachinaQueryObject1<A> = {
    refs: MachinaComponentRefs,
    iter: (self: MachinaQueryObject1<A>, world: MachinaWorld) -> (() -> (MachinaEntity, A)),
    view: (self: MachinaQueryObject1<A>, world: MachinaWorld) -> MachinaQueryView,
}

export type MachinaQueryObject2<A, B> = {
    refs: MachinaComponentRefs,
    iter: (self: MachinaQueryObject2<A, B>, world: MachinaWorld) -> (() -> (MachinaEntity, A, B)),
    view: (self: MachinaQueryObject2<A, B>, world: MachinaWorld) -> MachinaQueryView,
}

export type MachinaQueryObject3<A, B, C> = {
    refs: MachinaComponentRefs,
    iter: (self: MachinaQueryObject3<A, B, C>, world: MachinaWorld) -> (() -> (MachinaEntity, A, B, C)),
    view: (self: MachinaQueryObject3<A, B, C>, world: MachinaWorld) -> MachinaQueryView,
}

export type MachinaQueryObject4<A, B, C, D> = {
    refs: MachinaComponentRefs,
    iter: (self: MachinaQueryObject4<A, B, C, D>, world: MachinaWorld) -> (() -> (MachinaEntity, A, B, C, D)),
    view: (self: MachinaQueryObject4<A, B, C, D>, world: MachinaWorld) -> MachinaQueryView,
}

export type MachinaQueryObject5<A, B, C, D, E> = {
    refs: MachinaComponentRefs,
    iter: (self: MachinaQueryObject5<A, B, C, D, E>, world: MachinaWorld) -> (() -> (MachinaEntity, A, B, C, D, E)),
    view: (self: MachinaQueryObject5<A, B, C, D, E>, world: MachinaWorld) -> MachinaQueryView,
}

export type MachinaQueryObject6<A, B, C, D, E, F> = {
    refs: MachinaComponentRefs,
    iter: (self: MachinaQueryObject6<A, B, C, D, E, F>, world: MachinaWorld) -> (() -> (MachinaEntity, A, B, C, D, E, F)),
    view: (self: MachinaQueryObject6<A, B, C, D, E, F>, world: MachinaWorld) -> MachinaQueryView,
}

export type MachinaSystemDefinition = {
    phase: MachinaSystemPhase?,
    query: MachinaQueryRef?,
    reads: MachinaComponentRefs?,
    writes: MachinaComponentRefs?,
    before: { MachinaSystemId }?,
    after: { MachinaSystemId }?,
    run: ((world: MachinaWorld, delta_seconds: number) -> ())?,
}

export type MachinaComponentFunction = <T>(
    id: MachinaComponentId,
    definition: (MachinaComponentDefinition | MachinaInferredComponentDefinition<T>)?
) -> MachinaComponent<MachinaPayloadFromComponentType<T>>

export type MachinaFieldsFunction = <T>(
    fields: T & { [string]: MachinaFieldType }
) -> MachinaValidatedFields<T>

export type MachinaSchemaFunction = <T>(
    fields: T & { [string]: MachinaSchemaValue }
) -> T

export type MachinaQueryFunction =
    (<A>(MachinaTypedComponent<A>) -> MachinaQueryObject1<MachinaNonNil<A>>)
    & (<A, B>(MachinaTypedComponent<A>, MachinaTypedComponent<B>) -> MachinaQueryObject2<MachinaNonNil<A>, MachinaNonNil<B>>)
    & (<A, B, C>(MachinaTypedComponent<A>, MachinaTypedComponent<B>, MachinaTypedComponent<C>) -> MachinaQueryObject3<MachinaNonNil<A>, MachinaNonNil<B>, MachinaNonNil<C>>)
    & (<A, B, C, D>(MachinaTypedComponent<A>, MachinaTypedComponent<B>, MachinaTypedComponent<C>, MachinaTypedComponent<D>) -> MachinaQueryObject4<MachinaNonNil<A>, MachinaNonNil<B>, MachinaNonNil<C>, MachinaNonNil<D>>)
    & (<A, B, C, D, E>(MachinaTypedComponent<A>, MachinaTypedComponent<B>, MachinaTypedComponent<C>, MachinaTypedComponent<D>, MachinaTypedComponent<E>) -> MachinaQueryObject5<MachinaNonNil<A>, MachinaNonNil<B>, MachinaNonNil<C>, MachinaNonNil<D>, MachinaNonNil<E>>)
    & (<A, B, C, D, E, F>(MachinaTypedComponent<A>, MachinaTypedComponent<B>, MachinaTypedComponent<C>, MachinaTypedComponent<D>, MachinaTypedComponent<E>, MachinaTypedComponent<F>) -> MachinaQueryObject6<MachinaNonNil<A>, MachinaNonNil<B>, MachinaNonNil<C>, MachinaNonNil<D>, MachinaNonNil<E>, MachinaNonNil<F>>)
    & ((...MachinaComponentId) -> MachinaQueryRef)

export type MachinaEcs = {
    --- Registers a project-local component type or returns a typed handle for an existing component.
    component: MachinaComponentFunction,

    --- Creates a reusable query object over typed component handles.
    query: MachinaQueryFunction,

    --- Validates field declaration maps and preserves their literal shape for payload inference.
    fields: MachinaFieldsFunction,

    --- Infers component payload types from schema marker fields. Prefer ecs.fields for new code.
    schema: MachinaSchemaFunction,

    --- Declares a vec3 field in a marker schema. Prefer the "vec3" field string for new code.
    vec3: () -> MachinaVec3,

    --- Erases typed component handles into component id refs for system read/write declarations.
    refs: (...MachinaComponentRef) -> MachinaComponentRefs,

    --- Registers a project-local system type.
    system: (id: MachinaSystemId, definition: MachinaSystemDefinition) -> (),
}

declare ecs: MachinaEcs
