package script

import shared "../shared"
import c "core:c"

scrapbot_ui_theme_resolve :: proc "c" (L: Lua_State) -> c.int {
	if lua_type(L, 1) != LUA_TSTRING {
		return luau_push_error(L, "scrapbot.ui.resolve expects a built-in theme name")
	}
	name_length: c.size_t
	name_data := lua_tolstring(L, 1, &name_length)
	if name_data == nil {
		return luau_push_error(L, "scrapbot.ui.resolve expects a built-in theme name")
	}
	theme_name, theme_ok := shared.ui_theme_name_parse(luau_string(name_data, name_length))
	if !theme_ok {
		return luau_push_error(L, "scrapbot.ui.resolve references an unsupported theme")
	}
	if lua_type(L, 2) != LUA_TTABLE {
		return luau_push_error(L, "scrapbot.ui.resolve expects a non-empty recipe array")
	}

	recipes: [shared.UI_THEME_RECIPE_CAPACITY]shared.UI_Theme_Recipe
	recipe_count := 0
	for index := 1; index <= len(recipes); index += 1 {
		lua_rawgeti(L, 2, c.int(index))
		if lua_type(L, -1) == LUA_TNIL {
			lua_settop(L, -2)
			break
		}
		if lua_type(L, -1) != LUA_TSTRING {
			lua_settop(L, -2)
			return luau_push_error(L, "scrapbot.ui.resolve recipe names must be strings")
		}
		recipe_length: c.size_t
		recipe_data := lua_tolstring(L, -1, &recipe_length)
		if recipe_data == nil {
			lua_settop(L, -2)
			return luau_push_error(L, "scrapbot.ui.resolve recipe names must be strings")
		}
		recipe, recipe_ok := shared.ui_theme_recipe_parse(luau_string(recipe_data, recipe_length))
		lua_settop(L, -2)
		if !recipe_ok {
			return luau_push_error(L, "scrapbot.ui.resolve references an unsupported recipe")
		}
		recipes[recipe_count] = recipe
		recipe_count += 1
	}
	if recipe_count == 0 {
		return luau_push_error(L, "scrapbot.ui.resolve expects a non-empty recipe array")
	}
	lua_rawgeti(L, 2, c.int(recipe_count + 1))
	has_extra_recipe := lua_type(L, -1) != LUA_TNIL
	lua_settop(L, -2)
	if has_extra_recipe {
		return luau_push_error(L, "scrapbot.ui.resolve accepts at most sixteen recipes")
	}

	resolved := shared.ui_theme_resolve(theme_name, recipes[:recipe_count])
	lua_createtable(L, 0, 9)
	if resolved.has_layout {
		push_ui_layout_table(L, resolved.layout)
		lua_setfield(L, -2, "scrapbot.ui_layout")
	}
	if resolved.has_scroll_area {
		push_ui_scroll_area_table(L, resolved.scroll_area)
		lua_setfield(L, -2, "scrapbot.ui_scroll_area")
	}
	if resolved.has_panel {
		push_ui_panel_table(L, resolved.panel)
		lua_setfield(L, -2, "scrapbot.ui_panel")
	}
	if resolved.has_list {
		push_ui_list_table(L, resolved.list)
		lua_setfield(L, -2, "scrapbot.ui_list")
	}
	if resolved.has_text {
		push_ui_text_table(L, resolved.text)
		lua_setfield(L, -2, "scrapbot.ui_text")
	}
	if resolved.has_button {
		push_ui_button_table(L, resolved.button)
		lua_setfield(L, -2, "scrapbot.ui_button")
	}
	if resolved.has_input {
		push_ui_input_table(L, resolved.input)
		lua_setfield(L, -2, "scrapbot.ui_input")
	}
	if resolved.has_checkbox {
		push_ui_checkbox_table(L, resolved.checkbox)
		lua_setfield(L, -2, "scrapbot.ui_checkbox")
	}
	if resolved.has_color_picker {
		push_ui_color_picker_table(L, resolved.color_picker)
		lua_setfield(L, -2, "scrapbot.ui_color_picker")
	}
	return 1
}
