#include "sdl_bridge.h"

#include <SDL3/SDL.h>

#if defined(__APPLE__)
#include <SDL3/SDL_metal.h>
#endif

static SDL_Window *scrapbot_sdl_window(void *window) {
    return (SDL_Window *)window;
}

static SDL_Cursor *scrapbot_sdl_cursor(void *cursor) {
    return (SDL_Cursor *)cursor;
}

static ScrapbotSdlKey scrapbot_sdl_key(SDL_Keycode key) {
    switch (key) {
        case SDLK_TAB:
            return SCRAPBOT_SDL_KEY_TAB;
        case SDLK_W:
            return SCRAPBOT_SDL_KEY_W;
        case SDLK_A:
            return SCRAPBOT_SDL_KEY_A;
        case SDLK_S:
            return SCRAPBOT_SDL_KEY_S;
        case SDLK_D:
            return SCRAPBOT_SDL_KEY_D;
        case SDLK_SPACE:
            return SCRAPBOT_SDL_KEY_SPACE;
        case SDLK_LCTRL:
            return SCRAPBOT_SDL_KEY_LCTRL;
        case SDLK_RCTRL:
            return SCRAPBOT_SDL_KEY_RCTRL;
        case SDLK_F1:
            return SCRAPBOT_SDL_KEY_F1;
        case SDLK_Z:
            return SCRAPBOT_SDL_KEY_Z;
        case SDLK_Y:
            return SCRAPBOT_SDL_KEY_Y;
        case SDLK_EQUALS:
        case SDLK_KP_PLUS:
            return SCRAPBOT_SDL_KEY_EQUALS;
        case SDLK_MINUS:
        case SDLK_KP_MINUS:
            return SCRAPBOT_SDL_KEY_MINUS;
        case SDLK_LEFT:
            return SCRAPBOT_SDL_KEY_LEFT;
        case SDLK_RIGHT:
            return SCRAPBOT_SDL_KEY_RIGHT;
        case SDLK_HOME:
            return SCRAPBOT_SDL_KEY_HOME;
        case SDLK_END:
            return SCRAPBOT_SDL_KEY_END;
        case SDLK_BACKSPACE:
            return SCRAPBOT_SDL_KEY_BACKSPACE;
        case SDLK_DELETE:
            return SCRAPBOT_SDL_KEY_DELETE;
        case SDLK_RETURN:
        case SDLK_RETURN2:
        case SDLK_KP_ENTER:
            return SCRAPBOT_SDL_KEY_RETURN;
        default:
            return SCRAPBOT_SDL_KEY_UNKNOWN;
    }
}

static void scrapbot_sdl_fill_modifiers(ScrapbotSdlEvent *out_event, SDL_Keymod modifiers) {
    out_event->ctrl_down = (modifiers & SDL_KMOD_CTRL) != 0;
    out_event->shift_down = (modifiers & SDL_KMOD_SHIFT) != 0;
    out_event->alt_down = (modifiers & SDL_KMOD_ALT) != 0;
    out_event->super_down = (modifiers & SDL_KMOD_GUI) != 0;
}

int scrapbot_sdl_init_video(void) {
    return SDL_Init(SDL_INIT_VIDEO) ? 1 : 0;
}

void scrapbot_sdl_quit(void) {
    SDL_Quit();
}

void *scrapbot_sdl_create_window(const char *title, int width, int height, int hidden) {
    SDL_WindowFlags flags = SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY;
#if defined(__APPLE__)
    flags |= SDL_WINDOW_METAL;
#endif
    if (hidden) {
        flags |= SDL_WINDOW_HIDDEN;
    }
    return SDL_CreateWindow(title, width, height, flags);
}

void scrapbot_sdl_destroy_window(void *window) {
    SDL_DestroyWindow(scrapbot_sdl_window(window));
}

void *scrapbot_sdl_create_metal_view(void *window) {
#if defined(__APPLE__)
    return SDL_Metal_CreateView(scrapbot_sdl_window(window));
#else
    (void)window;
    return NULL;
#endif
}

void scrapbot_sdl_destroy_metal_view(void *view) {
#if defined(__APPLE__)
    SDL_Metal_DestroyView((SDL_MetalView)view);
#else
    (void)view;
#endif
}

void *scrapbot_sdl_get_metal_layer(void *view) {
#if defined(__APPLE__)
    return SDL_Metal_GetLayer((SDL_MetalView)view);
#else
    (void)view;
    return NULL;
#endif
}

int scrapbot_sdl_get_wayland_handles(void *window, void **display, void **surface) {
    SDL_PropertiesID props = SDL_GetWindowProperties(scrapbot_sdl_window(window));
    if (props == 0) {
        return 0;
    }
    *display = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WAYLAND_DISPLAY_POINTER, NULL);
    *surface = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER, NULL);
    return *display != NULL && *surface != NULL;
}

int scrapbot_sdl_get_x11_handles(void *window, void **display, uint64_t *xwindow) {
    SDL_PropertiesID props = SDL_GetWindowProperties(scrapbot_sdl_window(window));
    if (props == 0) {
        return 0;
    }
    *display = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_X11_DISPLAY_POINTER, NULL);
    *xwindow = SDL_GetNumberProperty(props, SDL_PROP_WINDOW_X11_WINDOW_NUMBER, 0);
    return *display != NULL && *xwindow != 0;
}

int scrapbot_sdl_get_win32_handles(void *window, void **hinstance, void **hwnd) {
    SDL_PropertiesID props = SDL_GetWindowProperties(scrapbot_sdl_window(window));
    if (props == 0) {
        return 0;
    }
    *hinstance = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WIN32_INSTANCE_POINTER, NULL);
    *hwnd = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WIN32_HWND_POINTER, NULL);
    return *hinstance != NULL && *hwnd != NULL;
}

void *scrapbot_sdl_create_resize_ew_cursor(void) {
    return SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_EW_RESIZE);
}

void scrapbot_sdl_destroy_cursor(void *cursor) {
    SDL_DestroyCursor(scrapbot_sdl_cursor(cursor));
}

void scrapbot_sdl_set_default_cursor(void) {
    SDL_SetCursor(SDL_GetDefaultCursor());
}

void scrapbot_sdl_set_cursor(void *cursor) {
    SDL_SetCursor(scrapbot_sdl_cursor(cursor));
}

uint64_t scrapbot_sdl_get_ticks_ns(void) {
    return SDL_GetTicksNS();
}

int scrapbot_sdl_poll_event(ScrapbotSdlEvent *out_event) {
    SDL_Event event;
    if (!SDL_PollEvent(&event)) {
        return 0;
    }

    *out_event = (ScrapbotSdlEvent){0};
    switch (event.type) {
        case SDL_EVENT_QUIT:
            out_event->kind = SCRAPBOT_SDL_EVENT_QUIT;
            break;
        case SDL_EVENT_KEY_DOWN:
            out_event->kind = SCRAPBOT_SDL_EVENT_KEY_DOWN;
            out_event->key = scrapbot_sdl_key(event.key.key);
            out_event->repeat = event.key.repeat ? 1 : 0;
            scrapbot_sdl_fill_modifiers(out_event, event.key.mod);
            break;
        case SDL_EVENT_KEY_UP:
            out_event->kind = SCRAPBOT_SDL_EVENT_KEY_UP;
            out_event->key = scrapbot_sdl_key(event.key.key);
            out_event->repeat = event.key.repeat ? 1 : 0;
            scrapbot_sdl_fill_modifiers(out_event, event.key.mod);
            break;
        case SDL_EVENT_MOUSE_MOTION:
            out_event->kind = SCRAPBOT_SDL_EVENT_MOUSE_MOTION;
            out_event->x = event.motion.x;
            out_event->y = event.motion.y;
            out_event->xrel = event.motion.xrel;
            out_event->yrel = event.motion.yrel;
            break;
        case SDL_EVENT_MOUSE_BUTTON_DOWN:
            out_event->kind = SCRAPBOT_SDL_EVENT_MOUSE_BUTTON_DOWN;
            out_event->x = event.button.x;
            out_event->y = event.button.y;
            out_event->button = event.button.button;
            break;
        case SDL_EVENT_MOUSE_BUTTON_UP:
            out_event->kind = SCRAPBOT_SDL_EVENT_MOUSE_BUTTON_UP;
            out_event->x = event.button.x;
            out_event->y = event.button.y;
            out_event->button = event.button.button;
            break;
        case SDL_EVENT_MOUSE_WHEEL:
            out_event->kind = SCRAPBOT_SDL_EVENT_MOUSE_WHEEL;
            out_event->wheel_x = event.wheel.x != 0.0f ? event.wheel.x : (float)event.wheel.integer_x;
            out_event->wheel_y = event.wheel.y != 0.0f ? event.wheel.y : (float)event.wheel.integer_y;
            if (event.wheel.direction == SDL_MOUSEWHEEL_FLIPPED) {
                out_event->wheel_x = -out_event->wheel_x;
                out_event->wheel_y = -out_event->wheel_y;
            }
            break;
        case SDL_EVENT_TEXT_INPUT:
            out_event->kind = SCRAPBOT_SDL_EVENT_TEXT_INPUT;
            if (event.text.text != NULL) {
                SDL_strlcpy(out_event->text, event.text.text, sizeof(out_event->text));
            }
            break;
        case SDL_EVENT_WINDOW_RESIZED:
        case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
        case SDL_EVENT_WINDOW_METAL_VIEW_RESIZED:
            out_event->kind = SCRAPBOT_SDL_EVENT_WINDOW_RESIZED;
            break;
        default:
            out_event->kind = SCRAPBOT_SDL_EVENT_NONE;
            break;
    }

    return 1;
}

int scrapbot_sdl_get_window_size(void *window, int *width, int *height) {
    return SDL_GetWindowSize(scrapbot_sdl_window(window), width, height) ? 1 : 0;
}

int scrapbot_sdl_get_window_size_in_pixels(void *window, int *width, int *height) {
    return SDL_GetWindowSizeInPixels(scrapbot_sdl_window(window), width, height) ? 1 : 0;
}

int scrapbot_sdl_set_window_relative_mouse_mode(void *window, int enabled) {
    return SDL_SetWindowRelativeMouseMode(scrapbot_sdl_window(window), enabled != 0) ? 1 : 0;
}

int scrapbot_sdl_start_text_input(void *window) {
    return SDL_StartTextInput(scrapbot_sdl_window(window)) ? 1 : 0;
}

void scrapbot_sdl_delay_ms(uint32_t ms) {
    SDL_Delay(ms);
}

int scrapbot_sdl_button_left(void) {
    return SDL_BUTTON_LEFT;
}

int scrapbot_sdl_button_right(void) {
    return SDL_BUTTON_RIGHT;
}
