package scrapbot

import ecs "./ecs"
import project "./project"
import render "./render"
import script "./script"
import shared "./shared"

VERSION :: "0.1.0-dev"

PROJECT_FILE :: shared.PROJECT_FILE
DEFAULT_SCENE :: shared.DEFAULT_SCENE

Renderer_Backend :: shared.Renderer_Backend
Run_Config :: render.Run_Config
Project_Load_Result :: project.Project_Load_Result
Runtime_Result :: struct {
	frame: shared.Render_Frame,
	err:   string,
}

init_project :: project.init_project
load_project :: project.load_project
destroy_project_load_result :: project.destroy_project_load_result
check_project :: project.check_project

parse_renderer_backend :: render.parse_renderer_backend
renderer_backend_name :: render.renderer_backend_name

run_headless :: proc(root: string) -> Runtime_Result {
	return run_project(root, Run_Config{backend = .Null})
}

run_project :: proc(root: string, config: Run_Config) -> Runtime_Result {
	result: Runtime_Result
	run_config := config

	loaded := project.load_project(root)
	defer project.destroy_project_load_result(&loaded)
	if loaded.err != "" {
		result.err = loaded.err
		return result
	}

	world := ecs.build_world(&loaded.scene)
	defer ecs.destroy_world(&world)

	if run_config.hot_reload {
		hot_reload: Hot_Reload_State
		defer destroy_hot_reload_state(&hot_reload)
		if err := init_hot_reload_state(&hot_reload, root, &loaded, &world); err != "" {
			result.err = err
			return result
		}

		run_config.frame_system = hot_reload_frame_system
		run_config.frame_system_data = &hot_reload
		result.frame, result.err = render.run_renderer(run_config, &world)
		return result
	}

	script_runtime: script.Runtime
	defer script.destroy_runtime(&script_runtime)
	script_result := script.run_project_script(&script_runtime, root, &world)
	if script_result.err != "" {
		result.err = script_result.err
		return result
	}
	if script_result.ran {
		run_config.frame_system = script.step_frame_system
		run_config.frame_system_data = &script_runtime
	}

	result.frame, result.err = render.run_renderer(run_config, &world)
	return result
}
