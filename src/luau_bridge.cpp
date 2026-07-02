#include "luau_bridge.h"

#include <cstdlib>
#include <cstring>
#include <new>
#include <string>
#include <vector>

#include "lua.h"
#include "lualib.h"
#include "luacode.h"

struct ComponentField
{
    std::string name;
    std::string type;
};

struct ComponentDecl
{
    std::string id;
    uint32_t version = 1;
    int line = 0;
    std::vector<ComponentField> fields;
};

struct SystemDecl
{
    std::string id;
    std::string phase = "update";
    std::vector<std::string> reads;
    std::vector<std::string> writes;
    std::vector<std::string> before;
    std::vector<std::string> after;
    uint32_t runner_ref = 0;
    int line = 0;
};

struct machina_luau
{
    lua_State* state = nullptr;
    machina_luau_callbacks callbacks = {};
    void* callback_context = nullptr;
    void* active_world = nullptr;
    std::vector<ComponentDecl> components;
    std::vector<SystemDecl> systems;
    std::string last_error;
};

struct QueryState
{
    machina_luau* vm = nullptr;
    std::vector<std::string> component_ids;
    uint32_t cursor = 0;
};

static machina_luau* vm_from_upvalue(lua_State* state)
{
    return static_cast<machina_luau*>(lua_tolightuserdata(state, lua_upvalueindex(1)));
}

static void set_error(machina_luau* vm, const char* message)
{
    vm->last_error = message ? message : "unknown Luau error";
}

static const char* host_error_message(machina_luau* vm, const char* fallback)
{
    if (vm && vm->callbacks.host_error)
    {
        const char* message = vm->callbacks.host_error(vm->callback_context);
        if (message && message[0] != '\0')
            return message;
    }
    return fallback;
}

static void raise_host_error(lua_State* state, machina_luau* vm, const char* fallback)
{
    luaL_error(state, "%s", host_error_message(vm, fallback));
}

static std::string check_string(lua_State* state, int index)
{
    size_t len = 0;
    const char* value = luaL_checklstring(state, index, &len);
    return std::string(value, len);
}

static int component_type_brand(lua_State* state)
{
    luaL_error(state, "component type brand is for Luau analysis only");
    return 0;
}

static void push_schema_marker(lua_State* state, const char* field_type)
{
    lua_newtable(state);
    lua_pushstring(state, field_type);
    lua_setfield(state, -2, "__machina_schema_field_type");
    lua_setreadonly(state, -1, 1);
}

static void push_component_handle(lua_State* state, const std::string& id)
{
    lua_newtable(state);
    lua_pushlstring(state, id.c_str(), id.size());
    lua_setfield(state, -2, "id");
    lua_pushcclosure(state, component_type_brand, "component.__machina_component_type", 0);
    lua_setfield(state, -2, "__machina_component_type");
    lua_setreadonly(state, -1, 1);
}

static std::string check_component_id(lua_State* state, int index)
{
    if (lua_isstring(state, index))
        return check_string(state, index);

    luaL_checktype(state, index, LUA_TTABLE);
    lua_getfield(state, index, "id");
    size_t len = 0;
    const char* value = luaL_checklstring(state, -1, &len);
    std::string id(value, len);
    lua_pop(state, 1);
    return id;
}

static QueryState* query_state_from_upvalue(lua_State* state)
{
    return static_cast<QueryState*>(lua_touserdata(state, lua_upvalueindex(1)));
}

static void query_state_dtor(void* userdata)
{
    static_cast<QueryState*>(userdata)->~QueryState();
}

static bool read_optional_string_field(lua_State* state, int table_index, const char* key, std::string* out)
{
    lua_getfield(state, table_index, key);
    if (lua_isnil(state, -1))
    {
        lua_pop(state, 1);
        return false;
    }

    size_t len = 0;
    const char* value = luaL_checklstring(state, -1, &len);
    out->assign(value, len);
    lua_pop(state, 1);
    return true;
}

static int caller_line(lua_State* state)
{
    lua_Debug ar;
    if (lua_getinfo(state, 1, "l", &ar) && ar.currentline > 0)
        return ar.currentline;
    return 0;
}

static uint32_t read_optional_u32_field(lua_State* state, int table_index, const char* key, uint32_t fallback)
{
    lua_getfield(state, table_index, key);
    if (lua_isnil(state, -1))
    {
        lua_pop(state, 1);
        return fallback;
    }

    const int value = luaL_checkinteger(state, -1);
    lua_pop(state, 1);
    return value < 0 ? fallback : static_cast<uint32_t>(value);
}

static std::vector<std::string> read_string_array(lua_State* state, int table_index)
{
    std::vector<std::string> values;
    const int count = lua_objlen(state, table_index);
    values.reserve(count);

    for (int i = 1; i <= count; ++i)
    {
        lua_rawgeti(state, table_index, i);
        values.push_back(check_component_id(state, -1));
        lua_pop(state, 1);
    }

    return values;
}

static std::vector<std::string> read_refs_array_field(lua_State* state, int table_index, const char* key)
{
    lua_getfield(state, table_index, key);
    luaL_checktype(state, -1, LUA_TTABLE);
    const int refs_index = lua_absindex(state, -1);
    std::vector<std::string> values = read_string_array(state, refs_index);
    lua_pop(state, 1);
    return values;
}

static std::vector<std::string> read_optional_string_array_field(lua_State* state, int table_index, const char* key)
{
    lua_getfield(state, table_index, key);
    if (lua_isnil(state, -1))
    {
        lua_pop(state, 1);
        return {};
    }

    luaL_checktype(state, -1, LUA_TTABLE);
    const int array_index = lua_absindex(state, -1);
    std::vector<std::string> values = read_string_array(state, array_index);
    lua_pop(state, 1);
    return values;
}

static void check_query_refs(lua_State* state, const std::vector<std::string>& values);

static std::vector<std::string> read_optional_query_refs_field(lua_State* state, int table_index, const char* key)
{
    lua_getfield(state, table_index, key);
    if (lua_isnil(state, -1))
    {
        lua_pop(state, 1);
        return {};
    }

    luaL_checktype(state, -1, LUA_TTABLE);
    const int query_index = lua_absindex(state, -1);
    std::vector<std::string> values = read_refs_array_field(state, query_index, "refs");
    check_query_refs(state, values);
    lua_pop(state, 1);
    return values;
}

static bool string_list_contains(const std::vector<std::string>& values, const std::string& needle)
{
    for (const std::string& value : values)
    {
        if (value == needle)
            return true;
    }
    return false;
}

static void check_query_refs(lua_State* state, const std::vector<std::string>& values)
{
    if (values.empty())
        luaL_error(state, "query expects at least one component id");

    for (size_t index = 0; index < values.size(); ++index)
    {
        for (size_t prior = 0; prior < index; ++prior)
        {
            if (values[prior] == values[index])
                luaL_error(state, "query contains duplicate component id '%s'", values[index].c_str());
        }
    }
}

static void append_query_reads(SystemDecl& system, const std::vector<std::string>& query_refs)
{
    for (const std::string& id : query_refs)
    {
        if (string_list_contains(system.writes, id) || string_list_contains(system.reads, id))
            continue;
        system.reads.push_back(id);
    }
}

static int ecs_component(lua_State* state)
{
    machina_luau* vm = vm_from_upvalue(state);
    const std::string id = check_string(state, 1);

    if (!lua_isnoneornil(state, 2))
    {
        ComponentDecl component;
        component.id = id;
        component.line = caller_line(state);

        luaL_checktype(state, 2, LUA_TTABLE);
        const int definition_index = lua_absindex(state, 2);
        component.version = read_optional_u32_field(state, definition_index, "version", 1);

        lua_getfield(state, definition_index, "fields");
        if (!lua_isnil(state, -1))
        {
            luaL_checktype(state, -1, LUA_TTABLE);
            const int fields_index = lua_absindex(state, -1);
            lua_pushnil(state);
            while (lua_next(state, fields_index) != 0)
            {
                size_t name_len = 0;
                size_t type_len = 0;
                const char* name = luaL_checklstring(state, -2, &name_len);
                const char* type = luaL_checklstring(state, -1, &type_len);
                component.fields.push_back({
                    std::string(name, name_len),
                    std::string(type, type_len),
                });
                lua_pop(state, 1);
            }
        }
        lua_pop(state, 1);

        vm->components.push_back(std::move(component));
    }

    push_component_handle(state, id);
    return 1;
}

static int ecs_refs(lua_State* state)
{
    const int count = lua_gettop(state);
    lua_createtable(state, count, 0);

    for (int index = 1; index <= count; ++index)
    {
        const std::string id = check_component_id(state, index);
        lua_pushlstring(state, id.c_str(), id.size());
        lua_rawseti(state, -2, index);
    }

    lua_setreadonly(state, -1, 1);
    return 1;
}

static int ecs_fields(lua_State* state)
{
    luaL_checktype(state, 1, LUA_TTABLE);
    const int source_index = lua_absindex(state, 1);

    lua_newtable(state);
    lua_pushnil(state);
    while (lua_next(state, source_index) != 0)
    {
        size_t name_len = 0;
        size_t type_len = 0;
        const char* name = luaL_checklstring(state, -2, &name_len);
        const char* type = luaL_checklstring(state, -1, &type_len);

        lua_pushlstring(state, name, name_len);
        lua_pushlstring(state, type, type_len);
        lua_settable(state, -5);
        lua_pop(state, 1);
    }

    lua_setreadonly(state, -1, 1);
    return 1;
}

static std::string check_schema_marker_type(lua_State* state, int index)
{
    luaL_checktype(state, index, LUA_TTABLE);
    lua_getfield(state, index, "__machina_schema_field_type");
    size_t len = 0;
    const char* value = luaL_checklstring(state, -1, &len);
    std::string field_type(value, len);
    lua_pop(state, 1);
    return field_type;
}

static int ecs_schema(lua_State* state)
{
    luaL_checktype(state, 1, LUA_TTABLE);
    const int source_index = lua_absindex(state, 1);

    lua_newtable(state);
    lua_pushnil(state);
    while (lua_next(state, source_index) != 0)
    {
        size_t name_len = 0;
        const char* name = luaL_checklstring(state, -2, &name_len);
        const std::string field_type = check_schema_marker_type(state, -1);

        lua_pushlstring(state, name, name_len);
        lua_pushlstring(state, field_type.c_str(), field_type.size());
        lua_settable(state, -5);
        lua_pop(state, 1);
    }

    lua_setreadonly(state, -1, 1);
    return 1;
}

static int ecs_vec3(lua_State* state)
{
    push_schema_marker(state, "vec3");
    return 1;
}

static int query_iterator(lua_State* state);
static int query_object_iter(lua_State* state);

static void push_query_object(lua_State* state, machina_luau* vm, const std::vector<std::string>& component_ids)
{
    lua_newtable(state);

    lua_createtable(state, static_cast<int>(component_ids.size()), 0);
    for (size_t index = 0; index < component_ids.size(); ++index)
    {
        const std::string& id = component_ids[index];
        lua_pushlstring(state, id.c_str(), id.size());
        lua_rawseti(state, -2, static_cast<int>(index + 1));
    }
    lua_setreadonly(state, -1, 1);
    lua_setfield(state, -2, "refs");

    lua_pushlightuserdata(state, vm);
    lua_pushcclosure(state, query_object_iter, "ecs.query.iter", 1);
    lua_setfield(state, -2, "iter");

    lua_setreadonly(state, -1, 1);
}

static int ecs_query(lua_State* state)
{
    machina_luau* vm = vm_from_upvalue(state);
    const int component_count = lua_gettop(state);
    if (component_count <= 0)
        luaL_error(state, "ecs.query expects at least one component id");

    std::vector<std::string> component_ids;
    component_ids.reserve(component_count);
    for (int index = 1; index <= component_count; ++index)
        component_ids.push_back(check_component_id(state, index));
    check_query_refs(state, component_ids);

    push_query_object(state, vm, component_ids);
    return 1;
}

static int ecs_system(lua_State* state)
{
    machina_luau* vm = vm_from_upvalue(state);
    SystemDecl system;
    system.id = check_string(state, 1);
    system.line = caller_line(state);

    if (!lua_isnoneornil(state, 2))
    {
        luaL_checktype(state, 2, LUA_TTABLE);
        const int definition_index = lua_absindex(state, 2);
        read_optional_string_field(state, definition_index, "phase", &system.phase);
        system.reads = read_optional_string_array_field(state, definition_index, "reads");
        system.writes = read_optional_string_array_field(state, definition_index, "writes");
        append_query_reads(system, read_optional_query_refs_field(state, definition_index, "query"));
        system.before = read_optional_string_array_field(state, definition_index, "before");
        system.after = read_optional_string_array_field(state, definition_index, "after");

        lua_getfield(state, definition_index, "run");
        if (!lua_isnil(state, -1))
        {
            luaL_checktype(state, -1, LUA_TFUNCTION);
            system.runner_ref = static_cast<uint32_t>(lua_ref(state, -1));
        }
        lua_pop(state, 1);
    }

    vm->systems.push_back(std::move(system));
    return 0;
}

static void push_vec3(lua_State* state, const float value[3])
{
    lua_newtable(state);
    for (int i = 0; i < 3; ++i)
    {
        lua_pushnumber(state, value[i]);
        lua_rawseti(state, -2, i + 1);
    }
}

static bool read_vec3(lua_State* state, int index, float value[3])
{
    luaL_checktype(state, index, LUA_TTABLE);
    const int table_index = lua_absindex(state, index);
    for (int i = 0; i < 3; ++i)
    {
        lua_rawgeti(state, table_index, i + 1);
        value[i] = static_cast<float>(luaL_checknumber(state, -1));
        lua_pop(state, 1);
    }
    return true;
}

static void push_field_value(lua_State* state, const machina_luau_field_value& value)
{
    switch (value.tag)
    {
    case MACHINA_LUAU_FIELD_BOOLEAN:
        lua_pushboolean(state, value.boolean_value != 0);
        return;
    case MACHINA_LUAU_FIELD_INT:
        lua_pushinteger(state, value.int_value);
        return;
    case MACHINA_LUAU_FIELD_FLOAT:
    case MACHINA_LUAU_FIELD_NUMBER:
        lua_pushnumber(state, value.number_value);
        return;
    case MACHINA_LUAU_FIELD_VEC3:
        push_vec3(state, value.vec3_value);
        return;
    case MACHINA_LUAU_FIELD_STRING:
        lua_pushlstring(state, value.string_data ? value.string_data : "", value.string_len);
        return;
    default:
        luaL_error(state, "component field read returned unsupported field type");
        return;
    }
}

static void read_field_value(lua_State* state, int index, machina_luau_field_value* value)
{
    std::memset(value, 0, sizeof(*value));

    if (lua_isboolean(state, index))
    {
        value->tag = MACHINA_LUAU_FIELD_BOOLEAN;
        value->boolean_value = lua_toboolean(state, index);
        return;
    }

    if (lua_isnumber(state, index))
    {
        value->tag = MACHINA_LUAU_FIELD_NUMBER;
        value->number_value = lua_tonumber(state, index);
        return;
    }

    if (lua_isstring(state, index))
    {
        value->tag = MACHINA_LUAU_FIELD_STRING;
        size_t len = 0;
        value->string_data = luaL_checklstring(state, index, &len);
        value->string_len = len;
        return;
    }

    if (lua_istable(state, index))
    {
        value->tag = MACHINA_LUAU_FIELD_VEC3;
        read_vec3(state, index, value->vec3_value);
        return;
    }

    luaL_error(state, "component field write received unsupported value type");
}

static std::vector<machina_luau_component_field_value> read_component_field_values(lua_State* state, int index)
{
    std::vector<machina_luau_component_field_value> fields;
    if (lua_isnoneornil(state, index))
        return fields;

    luaL_checktype(state, index, LUA_TTABLE);
    const int table_index = lua_absindex(state, index);
    lua_pushnil(state);
    while (lua_next(state, table_index) != 0)
    {
        size_t name_len = 0;
        const char* name = luaL_checklstring(state, -2, &name_len);
        machina_luau_component_field_value field = {};
        field.name = name;
        field.name_len = name_len;
        read_field_value(state, -1, &field.value);
        fields.push_back(field);
        lua_pop(state, 1);
    }
    return fields;
}

static void push_entity(lua_State* state, machina_luau* vm, uint32_t entity)
{
    lua_newtable(state);

    lua_pushlightuserdata(state, vm);
    lua_pushinteger(state, entity);
    lua_pushcclosure(state, [](lua_State* state) -> int {
        machina_luau* vm = static_cast<machina_luau*>(lua_tolightuserdata(state, lua_upvalueindex(1)));
        const uint32_t entity = static_cast<uint32_t>(lua_tointeger(state, lua_upvalueindex(2)));
        const char* component_id = luaL_checkstring(state, 1);
        const char* field_name = luaL_checkstring(state, 2);
        float value[3] = {};
        if (!vm->callbacks.get_vec3 || !vm->callbacks.get_vec3(vm->callback_context, vm->active_world, entity, component_id, field_name, value))
            raise_host_error(state, vm, "world query get_vec3 access denied or failed");
        push_vec3(state, value);
        return 1;
    }, "entity.get_vec3", 2);
    lua_setfield(state, -2, "get_vec3");

    lua_pushlightuserdata(state, vm);
    lua_pushinteger(state, entity);
    lua_pushcclosure(state, [](lua_State* state) -> int {
        machina_luau* vm = static_cast<machina_luau*>(lua_tolightuserdata(state, lua_upvalueindex(1)));
        const uint32_t entity = static_cast<uint32_t>(lua_tointeger(state, lua_upvalueindex(2)));
        const char* component_id = luaL_checkstring(state, 1);
        const char* field_name = luaL_checkstring(state, 2);
        float value[3] = {};
        read_vec3(state, 3, value);
        if (!vm->callbacks.set_vec3 || !vm->callbacks.set_vec3(vm->callback_context, vm->active_world, entity, component_id, field_name, value))
            raise_host_error(state, vm, "world query set_vec3 access denied or failed");
        return 0;
    }, "entity.set_vec3", 2);
    lua_setfield(state, -2, "set_vec3");

    lua_pushlightuserdata(state, vm);
    lua_pushinteger(state, entity);
    lua_pushcclosure(state, [](lua_State* state) -> int {
        machina_luau* vm = static_cast<machina_luau*>(lua_tolightuserdata(state, lua_upvalueindex(1)));
        const uint32_t entity = static_cast<uint32_t>(lua_tointeger(state, lua_upvalueindex(2)));
        const int first_arg = lua_istable(state, 1) ? 2 : 1;
        const std::string component_id = check_component_id(state, first_arg);
        const std::vector<machina_luau_component_field_value> fields = read_component_field_values(state, first_arg + 1);
        if (!vm->callbacks.add_component || !vm->callbacks.add_component(vm->callback_context, vm->active_world, entity, component_id.c_str(), fields.data(), fields.size()))
            raise_host_error(state, vm, "entity.add access denied or failed");
        return 0;
    }, "entity.add", 2);
    lua_setfield(state, -2, "add");

    lua_pushlightuserdata(state, vm);
    lua_pushinteger(state, entity);
    lua_pushcclosure(state, [](lua_State* state) -> int {
        machina_luau* vm = static_cast<machina_luau*>(lua_tolightuserdata(state, lua_upvalueindex(1)));
        const uint32_t entity = static_cast<uint32_t>(lua_tointeger(state, lua_upvalueindex(2)));
        const int first_arg = lua_istable(state, 1) ? 2 : 1;
        const std::string component_id = check_component_id(state, first_arg);
        if (!vm->callbacks.remove_component || !vm->callbacks.remove_component(vm->callback_context, vm->active_world, entity, component_id.c_str()))
            raise_host_error(state, vm, "entity.remove access denied or failed");
        return 0;
    }, "entity.remove", 2);
    lua_setfield(state, -2, "remove");

    lua_pushlightuserdata(state, vm);
    lua_pushinteger(state, entity);
    lua_pushcclosure(state, [](lua_State* state) -> int {
        machina_luau* vm = static_cast<machina_luau*>(lua_tolightuserdata(state, lua_upvalueindex(1)));
        const uint32_t entity = static_cast<uint32_t>(lua_tointeger(state, lua_upvalueindex(2)));
        if (!vm->callbacks.despawn_entity || !vm->callbacks.despawn_entity(vm->callback_context, vm->active_world, entity))
            raise_host_error(state, vm, "entity.despawn access denied or failed");
        return 0;
    }, "entity.despawn", 2);
    lua_setfield(state, -2, "despawn");

    lua_setreadonly(state, -1, 1);
}

static int component_proxy_index(lua_State* state)
{
    machina_luau* vm = static_cast<machina_luau*>(lua_tolightuserdata(state, lua_upvalueindex(1)));
    const uint32_t entity = static_cast<uint32_t>(lua_tointeger(state, lua_upvalueindex(2)));
    const char* component_id = lua_tostring(state, lua_upvalueindex(3));
    const char* field_name = luaL_checkstring(state, 2);

    if (std::strcmp(field_name, "id") == 0)
    {
        lua_pushstring(state, component_id);
        return 1;
    }

    machina_luau_field_value value = {};
    if (!vm->callbacks.get_field || !vm->callbacks.get_field(vm->callback_context, vm->active_world, entity, component_id, field_name, &value))
        raise_host_error(state, vm, "component field read access denied or failed");
    push_field_value(state, value);
    return 1;
}

static int component_proxy_newindex(lua_State* state)
{
    machina_luau* vm = static_cast<machina_luau*>(lua_tolightuserdata(state, lua_upvalueindex(1)));
    const uint32_t entity = static_cast<uint32_t>(lua_tointeger(state, lua_upvalueindex(2)));
    const char* component_id = lua_tostring(state, lua_upvalueindex(3));
    const char* field_name = luaL_checkstring(state, 2);
    machina_luau_field_value value = {};
    read_field_value(state, 3, &value);
    if (!vm->callbacks.set_field || !vm->callbacks.set_field(vm->callback_context, vm->active_world, entity, component_id, field_name, &value))
        raise_host_error(state, vm, "component field write access denied or failed");
    return 0;
}

static void push_component_proxy(lua_State* state, machina_luau* vm, uint32_t entity, const std::string& component_id)
{
    lua_newtable(state);

    lua_newtable(state);
    lua_pushlightuserdata(state, vm);
    lua_pushinteger(state, entity);
    lua_pushlstring(state, component_id.c_str(), component_id.size());
    lua_pushcclosure(state, component_proxy_index, "component.__index", 3);
    lua_setfield(state, -2, "__index");

    lua_pushlightuserdata(state, vm);
    lua_pushinteger(state, entity);
    lua_pushlstring(state, component_id.c_str(), component_id.size());
    lua_pushcclosure(state, component_proxy_newindex, "component.__newindex", 3);
    lua_setfield(state, -2, "__newindex");

    lua_setmetatable(state, -2);
}

static void push_query_iterator(lua_State* state, machina_luau* vm, const std::vector<std::string>& component_ids)
{
    void* storage = lua_newuserdatadtor(state, sizeof(QueryState), query_state_dtor);
    QueryState* query = new (storage) QueryState();
    query->vm = vm;
    query->component_ids = component_ids;

    lua_pushcclosure(state, query_iterator, "query.iterator", 1);
}

static int query_iterator(lua_State* state)
{
    QueryState* query = query_state_from_upvalue(state);
    if (!query || !query->vm || !query->vm->callbacks.query_next)
        return 0;

    std::vector<const char*> component_ids;
    component_ids.reserve(query->component_ids.size());
    for (const std::string& id : query->component_ids)
        component_ids.push_back(id.c_str());

    uint32_t entity = 0;
    const int status = query->vm->callbacks.query_next(
        query->vm->callback_context,
        query->vm->active_world,
        component_ids.data(),
        component_ids.size(),
        &query->cursor,
        &entity);
    if (status < 0)
        raise_host_error(state, query->vm, "world.query access denied or failed");
    if (status == 0)
    {
        return 0;
    }

    push_entity(state, query->vm, entity);
    for (const std::string& id : query->component_ids)
        push_component_proxy(state, query->vm, entity, id);
    return static_cast<int>(1 + query->component_ids.size());
}

static int query_object_iter(lua_State* state)
{
    machina_luau* vm = vm_from_upvalue(state);
    luaL_checktype(state, 1, LUA_TTABLE);
    if (lua_isnoneornil(state, 2))
        luaL_error(state, "query:iter expects a world");

    const int query_index = lua_absindex(state, 1);
    std::vector<std::string> component_ids = read_refs_array_field(state, query_index, "refs");
    if (component_ids.empty())
        luaL_error(state, "query:iter expects at least one component id");

    push_query_iterator(state, vm, component_ids);
    return 1;
}

static int world_query(lua_State* state)
{
    machina_luau* vm = vm_from_upvalue(state);
    const int component_count = lua_gettop(state);
    if (component_count <= 0)
        luaL_error(state, "world.query expects at least one component id");

    void* storage = lua_newuserdatadtor(state, sizeof(QueryState), query_state_dtor);
    QueryState* query = new (storage) QueryState();
    query->vm = vm;
    query->component_ids.reserve(component_count);
    for (int index = 1; index <= component_count; ++index)
        query->component_ids.push_back(check_component_id(state, index));

    lua_pushcclosure(state, query_iterator, "world.query.iterator", 1);
    return 1;
}

static void install_ecs(lua_State* state, machina_luau* vm)
{
    lua_newtable(state);

    lua_pushlightuserdata(state, vm);
    lua_pushcclosure(state, ecs_component, "ecs.component", 1);
    lua_setfield(state, -2, "component");

    lua_pushlightuserdata(state, vm);
    lua_pushcclosure(state, ecs_query, "ecs.query", 1);
    lua_setfield(state, -2, "query");

    lua_pushcclosure(state, ecs_refs, "ecs.refs", 0);
    lua_setfield(state, -2, "refs");

    lua_pushcclosure(state, ecs_fields, "ecs.fields", 0);
    lua_setfield(state, -2, "fields");

    lua_pushcclosure(state, ecs_schema, "ecs.schema", 0);
    lua_setfield(state, -2, "schema");

    lua_pushcclosure(state, ecs_vec3, "ecs.vec3", 0);
    lua_setfield(state, -2, "vec3");

    lua_pushlightuserdata(state, vm);
    lua_pushcclosure(state, ecs_system, "ecs.system", 1);
    lua_setfield(state, -2, "system");

    lua_setreadonly(state, -1, 1);
    lua_setglobal(state, "ecs");
}

static void push_world(lua_State* state, machina_luau* vm)
{
    lua_newtable(state);
    lua_pushlightuserdata(state, vm);
    lua_pushcclosure(state, world_query, "world.query", 1);
    lua_setfield(state, -2, "query");

    lua_pushlightuserdata(state, vm);
    lua_pushcclosure(state, [](lua_State* state) -> int {
        machina_luau* vm = vm_from_upvalue(state);
        const char* id = luaL_checkstring(state, 1);
        const char* name = luaL_optstring(state, 2, id);
        uint32_t entity = 0;
        if (!vm->callbacks.spawn_entity || !vm->callbacks.spawn_entity(vm->callback_context, vm->active_world, id, name, &entity))
            raise_host_error(state, vm, "world.spawn access denied or failed");
        push_entity(state, vm, entity);
        return 1;
    }, "world.spawn", 1);
    lua_setfield(state, -2, "spawn");

    lua_setreadonly(state, -1, 1);
}

machina_luau* machina_luau_create(machina_luau_callbacks callbacks)
{
    machina_luau* vm = new machina_luau();
    vm->callbacks = callbacks;
    vm->state = luaL_newstate();
    if (!vm->state)
    {
        set_error(vm, "failed to create Luau state");
        return vm;
    }

    luaL_openlibs(vm->state);
    install_ecs(vm->state, vm);
    luaL_sandbox(vm->state);
    return vm;
}

void machina_luau_destroy(machina_luau* vm)
{
    if (!vm)
        return;

    if (vm->state)
        lua_close(vm->state);
    delete vm;
}

void machina_luau_set_callback_context(machina_luau* vm, void* context)
{
    if (vm)
        vm->callback_context = context;
}

int machina_luau_load(machina_luau* vm, const char* chunk_name, const char* source, size_t source_len)
{
    if (!vm || !vm->state)
        return 0;

    vm->last_error.clear();

    size_t bytecode_size = 0;
    char* bytecode = luau_compile(source, source_len, nullptr, &bytecode_size);
    if (!bytecode)
    {
        set_error(vm, "failed to compile Luau source");
        return 0;
    }

    lua_State* thread = lua_newthread(vm->state);
    luaL_sandboxthread(thread);

    int status = luau_load(thread, chunk_name, bytecode, bytecode_size, 0);
    std::free(bytecode);
    if (status == LUA_OK)
        status = lua_resume(thread, nullptr, 0);

    if (status != LUA_OK)
    {
        set_error(vm, lua_tostring(thread, -1));
        lua_pop(vm->state, 1);
        return 0;
    }

    lua_pop(vm->state, 1);
    return 1;
}

const char* machina_luau_last_error(const machina_luau* vm)
{
    return vm ? vm->last_error.c_str() : "missing Luau VM";
}

size_t machina_luau_component_count(const machina_luau* vm)
{
    return vm ? vm->components.size() : 0;
}

const char* machina_luau_component_id(const machina_luau* vm, size_t component_index)
{
    return vm && component_index < vm->components.size() ? vm->components[component_index].id.c_str() : nullptr;
}

uint32_t machina_luau_component_version(const machina_luau* vm, size_t component_index)
{
    return vm && component_index < vm->components.size() ? vm->components[component_index].version : 1;
}

int machina_luau_component_line(const machina_luau* vm, size_t component_index)
{
    return vm && component_index < vm->components.size() ? vm->components[component_index].line : 0;
}

size_t machina_luau_component_field_count(const machina_luau* vm, size_t component_index)
{
    return vm && component_index < vm->components.size() ? vm->components[component_index].fields.size() : 0;
}

const char* machina_luau_component_field_name(const machina_luau* vm, size_t component_index, size_t field_index)
{
    if (!vm || component_index >= vm->components.size() || field_index >= vm->components[component_index].fields.size())
        return nullptr;
    return vm->components[component_index].fields[field_index].name.c_str();
}

const char* machina_luau_component_field_type(const machina_luau* vm, size_t component_index, size_t field_index)
{
    if (!vm || component_index >= vm->components.size() || field_index >= vm->components[component_index].fields.size())
        return nullptr;
    return vm->components[component_index].fields[field_index].type.c_str();
}

size_t machina_luau_system_count(const machina_luau* vm)
{
    return vm ? vm->systems.size() : 0;
}

const char* machina_luau_system_id(const machina_luau* vm, size_t system_index)
{
    return vm && system_index < vm->systems.size() ? vm->systems[system_index].id.c_str() : nullptr;
}

const char* machina_luau_system_phase(const machina_luau* vm, size_t system_index)
{
    return vm && system_index < vm->systems.size() ? vm->systems[system_index].phase.c_str() : nullptr;
}

uint32_t machina_luau_system_runner_ref(const machina_luau* vm, size_t system_index)
{
    return vm && system_index < vm->systems.size() ? vm->systems[system_index].runner_ref : 0;
}

int machina_luau_system_line(const machina_luau* vm, size_t system_index)
{
    return vm && system_index < vm->systems.size() ? vm->systems[system_index].line : 0;
}

static size_t string_list_count(const std::vector<std::string>* values)
{
    return values ? values->size() : 0;
}

static const char* string_list_item(const std::vector<std::string>* values, size_t item_index)
{
    return values && item_index < values->size() ? (*values)[item_index].c_str() : nullptr;
}

static const std::vector<std::string>* system_reads(const machina_luau* vm, size_t system_index)
{
    return vm && system_index < vm->systems.size() ? &vm->systems[system_index].reads : nullptr;
}

static const std::vector<std::string>* system_writes(const machina_luau* vm, size_t system_index)
{
    return vm && system_index < vm->systems.size() ? &vm->systems[system_index].writes : nullptr;
}

static const std::vector<std::string>* system_before(const machina_luau* vm, size_t system_index)
{
    return vm && system_index < vm->systems.size() ? &vm->systems[system_index].before : nullptr;
}

static const std::vector<std::string>* system_after(const machina_luau* vm, size_t system_index)
{
    return vm && system_index < vm->systems.size() ? &vm->systems[system_index].after : nullptr;
}

size_t machina_luau_system_reads_count(const machina_luau* vm, size_t system_index)
{
    return string_list_count(system_reads(vm, system_index));
}

const char* machina_luau_system_reads_item(const machina_luau* vm, size_t system_index, size_t item_index)
{
    return string_list_item(system_reads(vm, system_index), item_index);
}

size_t machina_luau_system_writes_count(const machina_luau* vm, size_t system_index)
{
    return string_list_count(system_writes(vm, system_index));
}

const char* machina_luau_system_writes_item(const machina_luau* vm, size_t system_index, size_t item_index)
{
    return string_list_item(system_writes(vm, system_index), item_index);
}

size_t machina_luau_system_before_count(const machina_luau* vm, size_t system_index)
{
    return string_list_count(system_before(vm, system_index));
}

const char* machina_luau_system_before_item(const machina_luau* vm, size_t system_index, size_t item_index)
{
    return string_list_item(system_before(vm, system_index), item_index);
}

size_t machina_luau_system_after_count(const machina_luau* vm, size_t system_index)
{
    return string_list_count(system_after(vm, system_index));
}

const char* machina_luau_system_after_item(const machina_luau* vm, size_t system_index, size_t item_index)
{
    return string_list_item(system_after(vm, system_index), item_index);
}

int machina_luau_call_system(machina_luau* vm, uint32_t runner_ref, void* world, double delta_seconds)
{
    if (!vm || !vm->state || runner_ref == 0)
        return 1;

    vm->last_error.clear();
    vm->active_world = world;
    lua_getref(vm->state, static_cast<int>(runner_ref));
    if (!lua_isfunction(vm->state, -1))
    {
        lua_pop(vm->state, 1);
        vm->active_world = nullptr;
        set_error(vm, "system runner reference is not a function");
        return 0;
    }

    push_world(vm->state, vm);
    lua_pushnumber(vm->state, delta_seconds);
    const int status = lua_pcall(vm->state, 2, 0, 0);
    vm->active_world = nullptr;

    if (status != LUA_OK)
    {
        set_error(vm, lua_tostring(vm->state, -1));
        lua_pop(vm->state, 1);
        return 0;
    }

    return 1;
}
