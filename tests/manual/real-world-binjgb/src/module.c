#include <stddef.h>

#include "common.h"
#include "emulator.h"

#include "cgb_acid2_data.h"

void shim_reset_heap(void);

typedef struct ProbeRun {
    int frame_count;
    int first_hash;
    int last_hash;
    int combined_hash;
    int width;
    int height;
    int success;
} ProbeRun;

typedef enum InputPreset {
    INPUT_PRESET_NONE = 0,
    INPUT_PRESET_ACID2_A_PRESS = 1,
    INPUT_PRESET_TETRIS_START = 2,
    INPUT_PRESET_TETRIS_START_THEN_A = 3,
} InputPreset;

typedef struct ButtonScriptEntry {
    int start_frame;
    int end_frame;
    u8 mask;
} ButtonScriptEntry;

static Emulator *g_host_emulator;
static unsigned char *g_host_rom_copy;
static size_t g_host_rom_size;
static unsigned char g_native_framebuffer[SCREEN_WIDTH * SCREEN_HEIGHT * 2];
static int g_host_last_frame;
static u8 g_manual_button_mask;
static InputPreset g_host_input_preset;
static ButtonScriptEntry g_button_script[32];
static int g_button_script_count;
static JoypadButtons g_live_buttons;

static void zero_buttons(JoypadButtons *buttons) {
    buttons->down = FALSE;
    buttons->up = FALSE;
    buttons->left = FALSE;
    buttons->right = FALSE;
    buttons->start = FALSE;
    buttons->select = FALSE;
    buttons->B = FALSE;
    buttons->A = FALSE;
}

static void apply_button_mask(JoypadButtons *buttons, u8 mask) {
    buttons->A = (mask & (1u << 0)) ? TRUE : buttons->A;
    buttons->B = (mask & (1u << 1)) ? TRUE : buttons->B;
    buttons->select = (mask & (1u << 2)) ? TRUE : buttons->select;
    buttons->start = (mask & (1u << 3)) ? TRUE : buttons->start;
    buttons->right = (mask & (1u << 4)) ? TRUE : buttons->right;
    buttons->left = (mask & (1u << 5)) ? TRUE : buttons->left;
    buttons->up = (mask & (1u << 6)) ? TRUE : buttons->up;
    buttons->down = (mask & (1u << 7)) ? TRUE : buttons->down;
}

static void set_scripted_buttons_for_preset(int frame_index,
                                            InputPreset preset,
                                            JoypadButtons *buttons) {
    zero_buttons(buttons);
    if (preset == INPUT_PRESET_ACID2_A_PRESS && (frame_index == 8 || frame_index == 9)) {
        buttons->A = TRUE;
    }

    if (preset == INPUT_PRESET_TETRIS_START || preset == INPUT_PRESET_TETRIS_START_THEN_A) {
        /* Practical timings for Tetris (World) (Rev 1):
         * 1) leave title -> 2) leave game-type/music menu -> 3) start playfield */
        if ((frame_index >= 520 && frame_index <= 620) ||
            (frame_index >= 700 && frame_index <= 710) ||
            (frame_index >= 920 && frame_index <= 930)) {
            buttons->start = TRUE;
        }
        if (preset == INPUT_PRESET_TETRIS_START_THEN_A && frame_index >= 960 &&
            frame_index <= 965) {
            buttons->A = TRUE;
        }
    }
}

static void set_scripted_buttons_host(int frame_index, JoypadButtons *buttons) {
    int index = 0;
    set_scripted_buttons_for_preset(frame_index, g_host_input_preset, buttons);
    for (index = 0; index < g_button_script_count; index++) {
        ButtonScriptEntry entry = g_button_script[index];
        if (frame_index >= entry.start_frame && frame_index <= entry.end_frame) {
            apply_button_mask(buttons, entry.mask);
        }
    }
    apply_button_mask(buttons, g_manual_button_mask);
}

static void live_joypad_callback(JoypadButtons *buttons, void *user_data) {
    (void)user_data;
    *buttons = g_live_buttons;
}

static unsigned short pack_rgba_to_rgb555(RGBA rgba) {
    const unsigned short r = (unsigned short)((rgba >> 0) & 0xffu) >> 3;
    const unsigned short g = (unsigned short)((rgba >> 8) & 0xffu) >> 3;
    const unsigned short b = (unsigned short)((rgba >> 16) & 0xffu) >> 3;
    return (unsigned short)((r << 10) | (g << 5) | b);
}

static void refresh_native_framebuffer(Emulator *emulator) {
    const RGBA *source = *emulator_get_frame_buffer(emulator);
    size_t index = 0;
    for (index = 0; index < (SCREEN_WIDTH * SCREEN_HEIGHT); index++) {
        const unsigned short pixel = pack_rgba_to_rgb555(source[index]);
        g_native_framebuffer[index * 2] = (unsigned char)(pixel & 0xffu);
        g_native_framebuffer[index * 2 + 1] = (unsigned char)(pixel >> 8);
    }
}

static int hash_bytes(const unsigned char *data, size_t size) {
    u32 hash = 2166136261u;
    size_t index = 0;
    for (index = 0; index < size; index++) {
        hash ^= data[index];
        hash *= 16777619u;
    }
    return (int)hash;
}

static int hash_current_frame(Emulator *emulator) {
    refresh_native_framebuffer(emulator);
    return hash_bytes(g_native_framebuffer, sizeof(g_native_framebuffer));
}

static int run_until_next_frame(Emulator *emulator) {
    Ticks until_ticks = emulator_get_ticks(emulator) + PPU_FRAME_TICKS;
    while (TRUE) {
        EmulatorEvent event = emulator_run_until(emulator, until_ticks);
        if (event & EMULATOR_EVENT_NEW_FRAME) {
            return 1;
        }
        if (event & EMULATOR_EVENT_INVALID_OPCODE) {
            return 0;
        }
        if (event & EMULATOR_EVENT_UNTIL_TICKS) {
            until_ticks += PPU_FRAME_TICKS;
        }
    }
}

static Emulator *create_emulator(const unsigned char *rom_data, size_t rom_size) {
    EmulatorInit init;
    ZERO_MEMORY(init);
    init.rom.data = (u8 *)rom_data;
    init.rom.size = rom_size;
    init.audio_frequency = 44100;
    init.audio_frames = 2048;
    init.random_seed = 0xcabba6e5u;
    init.builtin_palette = 0;
    init.force_dmg = FALSE;
    init.cgb_color_curve = CGB_COLOR_CURVE_NONE;
    return emulator_new(&init);
}

static ProbeRun run_probe_script(const unsigned char *rom_data, size_t rom_size, int frame_limit) {
    ProbeRun result;
    Emulator *emulator = 0;
    int frame_index = 0;

    ZERO_MEMORY(result);
    if (frame_limit <= 0) {
        return result;
    }

    shim_reset_heap();
    emulator = create_emulator(rom_data, rom_size);
    if (!emulator) {
        return result;
    }
    zero_buttons(&g_live_buttons);
    emulator_set_joypad_callback(emulator, live_joypad_callback, 0);

    for (frame_index = 0; frame_index < frame_limit; frame_index++) {
        JoypadButtons buttons;
        int frame_hash = 0;

        set_scripted_buttons_for_preset(frame_index, INPUT_PRESET_ACID2_A_PRESS, &buttons);
        g_live_buttons = buttons;
        if (!run_until_next_frame(emulator)) {
            emulator_delete(emulator);
            return result;
        }

        frame_hash = hash_current_frame(emulator);
        if (frame_index == 0) {
            result.first_hash = frame_hash;
            result.width = SCREEN_WIDTH;
            result.height = SCREEN_HEIGHT;
        }
        result.last_hash = frame_hash;
        result.combined_hash = (result.combined_hash * 33) ^ frame_hash;
        result.frame_count++;
    }

    result.success = 1;
    emulator_delete(emulator);
    return result;
}

static void clear_host_state(void) {
    g_host_emulator = 0;
    g_host_rom_copy = 0;
    g_host_rom_size = 0;
    g_host_last_frame = -1;
    g_manual_button_mask = 0;
    g_host_input_preset = INPUT_PRESET_NONE;
    g_button_script_count = 0;
}

static int host_prepare_emulator(void) {
    if (!g_host_rom_copy || g_host_rom_size == 0) {
        return 0;
    }
    g_host_emulator = create_emulator(g_host_rom_copy, g_host_rom_size);
    g_host_last_frame = -1;
    zero_buttons(&g_live_buttons);
    emulator_set_joypad_callback(g_host_emulator, live_joypad_callback, 0);
    return g_host_emulator != 0;
}

int binjgb_decode_hash(int frame_limit) {
    ProbeRun result = run_probe_script(cgb_acid2_data, cgb_acid2_data_size, frame_limit);
    return result.success ? result.combined_hash : -1;
}

int binjgb_probe_width(void) {
    return SCREEN_WIDTH;
}

int binjgb_probe_height(void) {
    return SCREEN_HEIGHT;
}

int binjgb_probe_frame_count(int frame_limit) {
    ProbeRun result = run_probe_script(cgb_acid2_data, cgb_acid2_data_size, frame_limit);
    return result.success ? result.frame_count : -1;
}

int binjgb_probe_first_frame_hash(void) {
    ProbeRun result = run_probe_script(cgb_acid2_data, cgb_acid2_data_size, 1);
    return result.success ? result.first_hash : -1;
}

int binjgb_probe_last_frame_hash(int frame_limit) {
    ProbeRun result = run_probe_script(cgb_acid2_data, cgb_acid2_data_size, frame_limit);
    return result.success ? result.last_hash : -1;
}

int binjgb_host_alloc(int size) {
    void *result = 0;
    if (size <= 0) {
        return 0;
    }
    result = malloc((size_t)size);
    return result ? (int)(size_t)result : 0;
}

int binjgb_host_reset(void) {
    if (g_host_emulator) {
        emulator_delete(g_host_emulator);
    }
    clear_host_state();
    shim_reset_heap();
    return 1;
}

int binjgb_host_load_rom(int bytes_ptr, int bytes_len) {
    const unsigned char *source = (const unsigned char *)(size_t)bytes_ptr;
    size_t rom_size = (size_t)bytes_len;
    size_t aligned_size = ALIGN_UP(rom_size, MINIMUM_ROM_SIZE);

    if (bytes_ptr == 0 || bytes_len <= 0) {
        return 0;
    }

    g_host_rom_copy = (unsigned char *)calloc(1, aligned_size);
    if (!g_host_rom_copy) {
        return 0;
    }

    memcpy(g_host_rom_copy, source, rom_size);
    g_host_rom_size = aligned_size;
    return 1;
}

int binjgb_host_set_buttons(int mask) {
    if ((mask & ~0xff) != 0) {
        const int preset_id = (mask >> 8) & 0xff;
        if (preset_id >= INPUT_PRESET_NONE && preset_id <= INPUT_PRESET_TETRIS_START_THEN_A) {
            g_host_input_preset = (InputPreset)preset_id;
        }
    }
    g_manual_button_mask = (u8)mask;
    return 1;
}

int binjgb_host_clear_button_script(void) {
    g_button_script_count = 0;
    return 1;
}

int binjgb_host_add_button_script(int start_frame, int end_frame, int mask) {
    if (start_frame < 0 || end_frame < start_frame) {
        return 0;
    }
    if (g_button_script_count >= (int)(sizeof(g_button_script) / sizeof(g_button_script[0]))) {
        return 0;
    }
    g_button_script[g_button_script_count].start_frame = start_frame;
    g_button_script[g_button_script_count].end_frame = end_frame;
    g_button_script[g_button_script_count].mask = (u8)mask;
    g_button_script_count++;
    return 1;
}

int binjgb_host_set_input_preset(int preset_id) {
    if (preset_id < INPUT_PRESET_NONE || preset_id > INPUT_PRESET_TETRIS_START_THEN_A) {
        return 0;
    }
    g_host_input_preset = (InputPreset)preset_id;
    return 1;
}

int binjgb_host_run_frame(int frame_index) {
    int current = 0;

    if (frame_index < 0) {
        return 0;
    }

    if (g_host_emulator) {
        emulator_delete(g_host_emulator);
        g_host_emulator = 0;
    }

    if (!host_prepare_emulator()) {
        return 0;
    }

    for (current = 0; current <= frame_index; current++) {
        JoypadButtons buttons;
        set_scripted_buttons_host(current, &buttons);
        g_live_buttons = buttons;
        if (!run_until_next_frame(g_host_emulator)) {
            emulator_delete(g_host_emulator);
            g_host_emulator = 0;
            return 0;
        }
    }

    refresh_native_framebuffer(g_host_emulator);
    g_host_last_frame = frame_index;
    return 1;
}

int binjgb_host_get_framebuffer_ptr(void) {
    return (int)(size_t)g_native_framebuffer;
}

int binjgb_host_get_framebuffer_size(void) {
    return (int)sizeof(g_native_framebuffer);
}

int binjgb_host_get_width(void) {
    return SCREEN_WIDTH;
}

int binjgb_host_get_height(void) {
    return SCREEN_HEIGHT;
}
