#ifndef SCRAPBOT_SDL_BRIDGE_H
#define SCRAPBOT_SDL_BRIDGE_H

#include <stdint.h>

typedef enum ScrapbotSdlEventKind {
    SCRAPBOT_SDL_EVENT_NONE = 0,
    SCRAPBOT_SDL_EVENT_QUIT = 1,
    SCRAPBOT_SDL_EVENT_KEY_DOWN = 2,
    SCRAPBOT_SDL_EVENT_KEY_UP = 3,
    SCRAPBOT_SDL_EVENT_MOUSE_MOTION = 4,
    SCRAPBOT_SDL_EVENT_MOUSE_BUTTON_DOWN = 5,
    SCRAPBOT_SDL_EVENT_MOUSE_BUTTON_UP = 6,
    SCRAPBOT_SDL_EVENT_MOUSE_WHEEL = 7,
    SCRAPBOT_SDL_EVENT_WINDOW_RESIZED = 8,
    SCRAPBOT_SDL_EVENT_TEXT_INPUT = 9,
} ScrapbotSdlEventKind;

typedef enum ScrapbotSdlKey {
    SCRAPBOT_SDL_KEY_UNKNOWN = 0,
    SCRAPBOT_SDL_KEY_TAB = 1,
    SCRAPBOT_SDL_KEY_W = 2,
    SCRAPBOT_SDL_KEY_A = 3,
    SCRAPBOT_SDL_KEY_S = 4,
    SCRAPBOT_SDL_KEY_D = 5,
    SCRAPBOT_SDL_KEY_SPACE = 6,
    SCRAPBOT_SDL_KEY_LCTRL = 7,
    SCRAPBOT_SDL_KEY_RCTRL = 8,
    SCRAPBOT_SDL_KEY_F1 = 9,
    SCRAPBOT_SDL_KEY_Z = 10,
    SCRAPBOT_SDL_KEY_Y = 11,
    SCRAPBOT_SDL_KEY_EQUALS = 12,
    SCRAPBOT_SDL_KEY_MINUS = 13,
    SCRAPBOT_SDL_KEY_LEFT = 14,
    SCRAPBOT_SDL_KEY_RIGHT = 15,
    SCRAPBOT_SDL_KEY_HOME = 16,
    SCRAPBOT_SDL_KEY_END = 17,
    SCRAPBOT_SDL_KEY_BACKSPACE = 18,
    SCRAPBOT_SDL_KEY_DELETE = 19,
    SCRAPBOT_SDL_KEY_RETURN = 20,
} ScrapbotSdlKey;

typedef struct ScrapbotSdlEvent {
    ScrapbotSdlEventKind kind;
    ScrapbotSdlKey key;
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
} ScrapbotSdlEvent;

int scrapbot_sdl_init_video(void);
void scrapbot_sdl_quit(void);
void *scrapbot_sdl_create_window(const char *title, int width, int height, int hidden);
void scrapbot_sdl_destroy_window(void *window);

void *scrapbot_sdl_create_metal_view(void *window);
void scrapbot_sdl_destroy_metal_view(void *view);
void *scrapbot_sdl_get_metal_layer(void *view);

int scrapbot_sdl_get_wayland_handles(void *window, void **display, void **surface);
int scrapbot_sdl_get_x11_handles(void *window, void **display, uint64_t *xwindow);
int scrapbot_sdl_get_win32_handles(void *window, void **hinstance, void **hwnd);

void *scrapbot_sdl_create_resize_ew_cursor(void);
void scrapbot_sdl_destroy_cursor(void *cursor);
void scrapbot_sdl_set_default_cursor(void);
void scrapbot_sdl_set_cursor(void *cursor);

uint64_t scrapbot_sdl_get_ticks_ns(void);
int scrapbot_sdl_poll_event(ScrapbotSdlEvent *out_event);
int scrapbot_sdl_get_window_size(void *window, int *width, int *height);
int scrapbot_sdl_get_window_size_in_pixels(void *window, int *width, int *height);
int scrapbot_sdl_set_window_relative_mouse_mode(void *window, int enabled);
int scrapbot_sdl_start_text_input(void *window);
void scrapbot_sdl_delay_ms(uint32_t ms);

int scrapbot_sdl_button_left(void);
int scrapbot_sdl_button_right(void);

#endif
