#ifndef MACHINA_SDL_BRIDGE_H
#define MACHINA_SDL_BRIDGE_H

#include <stdint.h>

typedef enum MachinaSdlEventKind {
    MACHINA_SDL_EVENT_NONE = 0,
    MACHINA_SDL_EVENT_QUIT = 1,
    MACHINA_SDL_EVENT_KEY_DOWN = 2,
    MACHINA_SDL_EVENT_KEY_UP = 3,
    MACHINA_SDL_EVENT_MOUSE_MOTION = 4,
    MACHINA_SDL_EVENT_MOUSE_BUTTON_DOWN = 5,
    MACHINA_SDL_EVENT_MOUSE_BUTTON_UP = 6,
    MACHINA_SDL_EVENT_MOUSE_WHEEL = 7,
    MACHINA_SDL_EVENT_WINDOW_RESIZED = 8,
    MACHINA_SDL_EVENT_TEXT_INPUT = 9,
} MachinaSdlEventKind;

typedef enum MachinaSdlKey {
    MACHINA_SDL_KEY_UNKNOWN = 0,
    MACHINA_SDL_KEY_TAB = 1,
    MACHINA_SDL_KEY_W = 2,
    MACHINA_SDL_KEY_A = 3,
    MACHINA_SDL_KEY_S = 4,
    MACHINA_SDL_KEY_D = 5,
    MACHINA_SDL_KEY_SPACE = 6,
    MACHINA_SDL_KEY_LCTRL = 7,
    MACHINA_SDL_KEY_RCTRL = 8,
    MACHINA_SDL_KEY_F1 = 9,
    MACHINA_SDL_KEY_Z = 10,
    MACHINA_SDL_KEY_Y = 11,
    MACHINA_SDL_KEY_EQUALS = 12,
    MACHINA_SDL_KEY_MINUS = 13,
    MACHINA_SDL_KEY_LEFT = 14,
    MACHINA_SDL_KEY_RIGHT = 15,
    MACHINA_SDL_KEY_HOME = 16,
    MACHINA_SDL_KEY_END = 17,
    MACHINA_SDL_KEY_BACKSPACE = 18,
    MACHINA_SDL_KEY_DELETE = 19,
    MACHINA_SDL_KEY_RETURN = 20,
} MachinaSdlKey;

typedef struct MachinaSdlEvent {
    MachinaSdlEventKind kind;
    MachinaSdlKey key;
    int repeat;
    int ctrl_down;
    int shift_down;
    int alt_down;
    int super_down;
    float x;
    float y;
    float xrel;
    float yrel;
    float wheel_x;
    float wheel_y;
    int button;
    char text[64];
} MachinaSdlEvent;

int machina_sdl_init_video(void);
void machina_sdl_quit(void);
void *machina_sdl_create_window(const char *title, int width, int height, int hidden);
void machina_sdl_destroy_window(void *window);

void *machina_sdl_create_metal_view(void *window);
void machina_sdl_destroy_metal_view(void *view);
void *machina_sdl_get_metal_layer(void *view);

int machina_sdl_get_wayland_handles(void *window, void **display, void **surface);
int machina_sdl_get_x11_handles(void *window, void **display, uint64_t *xwindow);
int machina_sdl_get_win32_handles(void *window, void **hinstance, void **hwnd);

void *machina_sdl_create_resize_ew_cursor(void);
void machina_sdl_destroy_cursor(void *cursor);
void machina_sdl_set_default_cursor(void);
void machina_sdl_set_cursor(void *cursor);

uint64_t machina_sdl_get_ticks_ns(void);
int machina_sdl_poll_event(MachinaSdlEvent *out_event);
int machina_sdl_get_window_size(void *window, int *width, int *height);
int machina_sdl_get_window_size_in_pixels(void *window, int *width, int *height);
int machina_sdl_set_window_relative_mouse_mode(void *window, int enabled);
int machina_sdl_start_text_input(void *window);
void machina_sdl_delay_ms(uint32_t ms);

int machina_sdl_button_left(void);
int machina_sdl_button_right(void);

#endif
