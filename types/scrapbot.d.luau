export type ScrapbotComponentId = string
export type ScrapbotSystemId = string

export type ScrapbotFieldType =
    "boolean"
    | "bool"
    | "int"
    | "i32"
    | "float"
    | "f32"
    | "vec3"
    | "string"

export type ScrapbotComponentDefinition = {
    version: number?,
    fields: { [string]: ScrapbotFieldType }?,
}

export type ScrapbotSystemPhase = "startup" | "update" | "fixed_update" | "render"

export type ScrapbotVec3 = { number }

type function ScrapbotPayloadFromComponentType(component)
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

type function ScrapbotValidatedFields(fields)
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

type function ScrapbotNonNil(value)
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

export type ScrapbotSchemaValue = ScrapbotVec3

export type ScrapbotSchemaComponentDefinition<T> = {
    version: number?,
    fields: T,
}

export type ScrapbotInferredComponentDefinition<T> =
    { fields: T }
    | { version: number, fields: T }

export type ScrapbotComponent<T> = {
    id: ScrapbotComponentId,

    --- Runtime-guarded type brand used by Luau to preserve component payload types through handles.
    __scrapbot_component_type: () -> T,

    --- Analysis-only payload slot used by typed query inference.
    __scrapbot_component_payload: T?,
}

export type ScrapbotTypedComponent<T> = {
    id: ScrapbotComponentId,
    __scrapbot_component_payload: T?,
}

export type ScrapbotComponentHandle = {
    id: ScrapbotComponentId,
}

export type ScrapbotComponentRef = ScrapbotComponentId | ScrapbotComponentHandle
export type ScrapbotComponentRefs = { ScrapbotComponentId }
export type ScrapbotQueryRef = {
    refs: ScrapbotComponentRefs,
}

export type ScrapbotTransform = {
    position: ScrapbotVec3,
    rotation: ScrapbotVec3,
    scale: ScrapbotVec3,
}

export type ScrapbotRenderCube = {
    color: ScrapbotVec3,
}

export type ScrapbotGeometryPrimitive = {
    primitive: string,
    segments: number,
    rings: number,
}

export type ScrapbotSurfaceMaterial = {
    base_color: ScrapbotVec3,
}

export type ScrapbotRenderer = {
    hdr: boolean,
    tone_mapping: string,
    exposure: number,
    postprocess_enabled: boolean,
    antialiasing: string,
    bloom_enabled: boolean,
    bloom_threshold: number,
    bloom_intensity: number,
    bloom_radius: number,
    vignette_enabled: boolean,
    vignette_strength: number,
    vignette_radius: number,
    chromatic_aberration_enabled: boolean,
    chromatic_aberration_strength: number,
}

export type ScrapbotCamera = {
    fov_y_degrees: number,
    near: number,
    far: number,
}

export type ScrapbotDirectionalLight = {
    direction: ScrapbotVec3,
    color: ScrapbotVec3,
    intensity: number,
    ambient: number,
}

export type ScrapbotShadowCaster = {}
export type ScrapbotShadowReceiver = {}

export type ScrapbotUiCanvas = {
    design_size: ScrapbotVec3,
    scale_mode: string,
}

export type ScrapbotUiRect = {
    position: ScrapbotVec3,
    size: ScrapbotVec3,
    color: ScrapbotVec3,
    corner_radius: number,
}

export type ScrapbotUiBorder = {
    color: ScrapbotVec3,
    thickness: number,
}

export type ScrapbotUiText = {
    position: ScrapbotVec3,
    size: number,
    color: ScrapbotVec3,
    value: string,
}

export type ScrapbotUiButton = {}

export type ScrapbotUiHitArea = {
    position: ScrapbotVec3,
    size: ScrapbotVec3,
}

export type ScrapbotUiCommand = {
    command: string,
}

export type ScrapbotUiScrollView = {
    position: ScrapbotVec3,
    size: ScrapbotVec3,
    content_offset: ScrapbotVec3,
}

export type ScrapbotUiVBox = {
    position: ScrapbotVec3,
    spacing: number,
}

export type ScrapbotUiStack = {
    position: ScrapbotVec3,
    spacing: number,
    direction: string,
    padding: ScrapbotVec3,
}

export type ScrapbotUiLayoutItem = {
    parent: string,
    order: number,
    min_size: ScrapbotVec3,
    grow: number,
    align: string,
    margin: ScrapbotVec3,
}

export type ScrapbotUiSpacer = {
    size: ScrapbotVec3,
}

export type ScrapbotUiTextBlock = {
    size: ScrapbotVec3,
    horizontal_align: string,
    vertical_align: string,
}

export type ScrapbotUiToggle = {
    checked: boolean,
}

export type ScrapbotUiProgressBar = {
    value: number,
    max: number,
    fill_color: ScrapbotVec3,
}

export type ScrapbotUiSeparator = {
    position: ScrapbotVec3,
    size: ScrapbotVec3,
    color: ScrapbotVec3,
}

export type ScrapbotUiCommandEvent = {
    command: string,
    source: string,
}

export type ScrapbotInputPointer = {
    position: ScrapbotVec3,
    delta: ScrapbotVec3,
    has_position: boolean,
    primary_down: boolean,
    primary_pressed: boolean,
    primary_released: boolean,
    secondary_down: boolean,
    secondary_pressed: boolean,
    secondary_released: boolean,
    wheel_delta: ScrapbotVec3,
}

export type ScrapbotInputKeyboard = {
    ctrl_down: boolean,
    shift_down: boolean,
    alt_down: boolean,
    super_down: boolean,
    move_forward: boolean,
    move_back: boolean,
    move_left: boolean,
    move_right: boolean,
    move_up: boolean,
    move_down: boolean,
    editor_toggle_pressed: boolean,
}

export type ScrapbotInputFrame = {
    ui_visible: boolean,
    debug_overlay_visible: boolean,
    viewport: ScrapbotVec3,
}

export type ScrapbotEntity = {
    add: <T>(
        self: ScrapbotEntity,
        component: ScrapbotTypedComponent<T>,
        fields: T?
    ) -> (),

    remove: (
        self: ScrapbotEntity,
        component: ScrapbotComponentRef
    ) -> (),

    despawn: (
        self: ScrapbotEntity
    ) -> (),

    get_vec3: (
        component: ScrapbotComponentId,
        field: string
    ) -> ScrapbotVec3,

    set_vec3: (
        component: ScrapbotComponentId,
        field: string,
        value: ScrapbotVec3
    ) -> (),
}

export type ScrapbotWorldQueryFunction =
    (<A>(ScrapbotTypedComponent<A>) -> (() -> (ScrapbotEntity, ScrapbotNonNil<A>)))
    & (<A, B>(ScrapbotTypedComponent<A>, ScrapbotTypedComponent<B>) -> (() -> (ScrapbotEntity, ScrapbotNonNil<A>, ScrapbotNonNil<B>)))
    & (<A, B, C>(ScrapbotTypedComponent<A>, ScrapbotTypedComponent<B>, ScrapbotTypedComponent<C>) -> (() -> (ScrapbotEntity, ScrapbotNonNil<A>, ScrapbotNonNil<B>, ScrapbotNonNil<C>)))
    & (<A, B, C, D>(ScrapbotTypedComponent<A>, ScrapbotTypedComponent<B>, ScrapbotTypedComponent<C>, ScrapbotTypedComponent<D>) -> (() -> (ScrapbotEntity, ScrapbotNonNil<A>, ScrapbotNonNil<B>, ScrapbotNonNil<C>, ScrapbotNonNil<D>)))
    & (<A, B, C, D, E>(ScrapbotTypedComponent<A>, ScrapbotTypedComponent<B>, ScrapbotTypedComponent<C>, ScrapbotTypedComponent<D>, ScrapbotTypedComponent<E>) -> (() -> (ScrapbotEntity, ScrapbotNonNil<A>, ScrapbotNonNil<B>, ScrapbotNonNil<C>, ScrapbotNonNil<D>, ScrapbotNonNil<E>)))
    & (<A, B, C, D, E, F>(ScrapbotTypedComponent<A>, ScrapbotTypedComponent<B>, ScrapbotTypedComponent<C>, ScrapbotTypedComponent<D>, ScrapbotTypedComponent<E>, ScrapbotTypedComponent<F>) -> (() -> (ScrapbotEntity, ScrapbotNonNil<A>, ScrapbotNonNil<B>, ScrapbotNonNil<C>, ScrapbotNonNil<D>, ScrapbotNonNil<E>, ScrapbotNonNil<F>)))
    & ((...ScrapbotComponentId) -> (() -> ScrapbotEntity))

export type ScrapbotWorld = {
    --- Iterates entities that have all requested components.
    query: ScrapbotWorldQueryFunction,

    --- Spawns an empty entity. Add components before expecting it in queries.
    spawn: (id: string, name: string?) -> ScrapbotEntity,
}

export type ScrapbotQueryView = {
    --- Returns the number of entities captured by this frame-local view.
    count: (self: ScrapbotQueryView) -> number,

    --- Bulk reads one f32 field into a packed Luau buffer.
    read_f32: (self: ScrapbotQueryView, component: ScrapbotComponentRef, field: string) -> buffer,

    --- Bulk writes one f32 field from a packed Luau buffer.
    write_f32: (self: ScrapbotQueryView, component: ScrapbotComponentRef, field: string, values: buffer) -> (),

    --- Bulk reads one vec3 field into a packed xyz xyz Luau buffer.
    read_vec3: (self: ScrapbotQueryView, component: ScrapbotComponentRef, field: string) -> buffer,

    --- Bulk writes one vec3 field from a packed xyz xyz Luau buffer.
    write_vec3: (self: ScrapbotQueryView, component: ScrapbotComponentRef, field: string, values: buffer) -> (),
}

export type ScrapbotQueryObject1<A> = {
    refs: ScrapbotComponentRefs,
    iter: (self: ScrapbotQueryObject1<A>, world: ScrapbotWorld) -> (() -> (ScrapbotEntity, A)),
    view: (self: ScrapbotQueryObject1<A>, world: ScrapbotWorld) -> ScrapbotQueryView,
}

export type ScrapbotQueryObject2<A, B> = {
    refs: ScrapbotComponentRefs,
    iter: (self: ScrapbotQueryObject2<A, B>, world: ScrapbotWorld) -> (() -> (ScrapbotEntity, A, B)),
    view: (self: ScrapbotQueryObject2<A, B>, world: ScrapbotWorld) -> ScrapbotQueryView,
}

export type ScrapbotQueryObject3<A, B, C> = {
    refs: ScrapbotComponentRefs,
    iter: (self: ScrapbotQueryObject3<A, B, C>, world: ScrapbotWorld) -> (() -> (ScrapbotEntity, A, B, C)),
    view: (self: ScrapbotQueryObject3<A, B, C>, world: ScrapbotWorld) -> ScrapbotQueryView,
}

export type ScrapbotQueryObject4<A, B, C, D> = {
    refs: ScrapbotComponentRefs,
    iter: (self: ScrapbotQueryObject4<A, B, C, D>, world: ScrapbotWorld) -> (() -> (ScrapbotEntity, A, B, C, D)),
    view: (self: ScrapbotQueryObject4<A, B, C, D>, world: ScrapbotWorld) -> ScrapbotQueryView,
}

export type ScrapbotQueryObject5<A, B, C, D, E> = {
    refs: ScrapbotComponentRefs,
    iter: (self: ScrapbotQueryObject5<A, B, C, D, E>, world: ScrapbotWorld) -> (() -> (ScrapbotEntity, A, B, C, D, E)),
    view: (self: ScrapbotQueryObject5<A, B, C, D, E>, world: ScrapbotWorld) -> ScrapbotQueryView,
}

export type ScrapbotQueryObject6<A, B, C, D, E, F> = {
    refs: ScrapbotComponentRefs,
    iter: (self: ScrapbotQueryObject6<A, B, C, D, E, F>, world: ScrapbotWorld) -> (() -> (ScrapbotEntity, A, B, C, D, E, F)),
    view: (self: ScrapbotQueryObject6<A, B, C, D, E, F>, world: ScrapbotWorld) -> ScrapbotQueryView,
}

export type ScrapbotSystemDefinition = {
    phase: ScrapbotSystemPhase?,
    query: ScrapbotQueryRef?,
    reads: ScrapbotComponentRefs?,
    writes: ScrapbotComponentRefs?,
    before: { ScrapbotSystemId }?,
    after: { ScrapbotSystemId }?,
    run: ((world: ScrapbotWorld, delta_seconds: number) -> ())?,
}

export type ScrapbotComponentFunction = <T>(
    id: ScrapbotComponentId,
    definition: (ScrapbotComponentDefinition | ScrapbotInferredComponentDefinition<T>)?
) -> ScrapbotComponent<ScrapbotPayloadFromComponentType<T>>

export type ScrapbotFieldsFunction = <T>(
    fields: T & { [string]: ScrapbotFieldType }
) -> ScrapbotValidatedFields<T>

export type ScrapbotSchemaFunction = <T>(
    fields: T & { [string]: ScrapbotSchemaValue }
) -> T

export type ScrapbotQueryFunction =
    (<A>(ScrapbotTypedComponent<A>) -> ScrapbotQueryObject1<ScrapbotNonNil<A>>)
    & (<A, B>(ScrapbotTypedComponent<A>, ScrapbotTypedComponent<B>) -> ScrapbotQueryObject2<ScrapbotNonNil<A>, ScrapbotNonNil<B>>)
    & (<A, B, C>(ScrapbotTypedComponent<A>, ScrapbotTypedComponent<B>, ScrapbotTypedComponent<C>) -> ScrapbotQueryObject3<ScrapbotNonNil<A>, ScrapbotNonNil<B>, ScrapbotNonNil<C>>)
    & (<A, B, C, D>(ScrapbotTypedComponent<A>, ScrapbotTypedComponent<B>, ScrapbotTypedComponent<C>, ScrapbotTypedComponent<D>) -> ScrapbotQueryObject4<ScrapbotNonNil<A>, ScrapbotNonNil<B>, ScrapbotNonNil<C>, ScrapbotNonNil<D>>)
    & (<A, B, C, D, E>(ScrapbotTypedComponent<A>, ScrapbotTypedComponent<B>, ScrapbotTypedComponent<C>, ScrapbotTypedComponent<D>, ScrapbotTypedComponent<E>) -> ScrapbotQueryObject5<ScrapbotNonNil<A>, ScrapbotNonNil<B>, ScrapbotNonNil<C>, ScrapbotNonNil<D>, ScrapbotNonNil<E>>)
    & (<A, B, C, D, E, F>(ScrapbotTypedComponent<A>, ScrapbotTypedComponent<B>, ScrapbotTypedComponent<C>, ScrapbotTypedComponent<D>, ScrapbotTypedComponent<E>, ScrapbotTypedComponent<F>) -> ScrapbotQueryObject6<ScrapbotNonNil<A>, ScrapbotNonNil<B>, ScrapbotNonNil<C>, ScrapbotNonNil<D>, ScrapbotNonNil<E>, ScrapbotNonNil<F>>)
    & ((...ScrapbotComponentId) -> ScrapbotQueryRef)

export type ScrapbotEcs = {
    --- Registers a project-local component type or returns a typed handle for an existing component.
    component: ScrapbotComponentFunction,

    --- Creates a reusable query object over typed component handles.
    query: ScrapbotQueryFunction,

    --- Validates field declaration maps and preserves their literal shape for payload inference.
    fields: ScrapbotFieldsFunction,

    --- Infers component payload types from schema marker fields. Prefer ecs.fields for new code.
    schema: ScrapbotSchemaFunction,

    --- Declares a vec3 field in a marker schema. Prefer the "vec3" field string for new code.
    vec3: () -> ScrapbotVec3,

    --- Erases typed component handles into component id refs for system read/write declarations.
    refs: (...ScrapbotComponentRef) -> ScrapbotComponentRefs,

    --- Registers a project-local system type.
    system: (id: ScrapbotSystemId, definition: ScrapbotSystemDefinition) -> (),
}

declare ecs: ScrapbotEcs
