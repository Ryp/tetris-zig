const std = @import("std");
const assert = std.debug.assert;

const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

const game = @import("tetris/game.zig");

const SpriteSheetTileExtent = 14;
const SpriteScreenExtent = 38;

fn get_sprite_sheet_rect(position: [2]u8) c.SDL_FRect {
    return c.SDL_FRect{
        .x = @floatFromInt(position[0] * SpriteSheetTileExtent),
        .y = @floatFromInt(position[1] * SpriteSheetTileExtent),
        .w = @floatFromInt(SpriteSheetTileExtent),
        .h = @floatFromInt(SpriteSheetTileExtent),
    };
}

pub fn execute_main_loop(allocator: std.mem.Allocator, game_state: *game.GameState) !void {
    const width = game.BoardWidth * SpriteScreenExtent;
    const height = game.BoardHeight * SpriteScreenExtent;

    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS)) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("Tetris", @as(c_int, @intCast(width)), @as(c_int, @intCast(height)), 0) orelse {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(window);

    if (!c.SDL_SetHint(c.SDL_HINT_RENDER_VSYNC, "1")) {
        c.SDL_Log("Unable to set hint: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }

    const ren = c.SDL_CreateRenderer(window, null) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(ren);

    // Create sprite sheet texture
    const sprite_sheet_buffer = @embedFile("sprite_sheet");
    const sprite_sheet_io = c.SDL_IOFromConstMem(sprite_sheet_buffer, sprite_sheet_buffer.len);
    const sprite_sheet_surface = c.SDL_LoadBMP_IO(sprite_sheet_io, true) orelse {
        c.SDL_Log("Unable to create BMP surface from file: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroySurface(sprite_sheet_surface);

    const sprite_sheet_texture = c.SDL_CreateTextureFromSurface(ren, sprite_sheet_surface) orelse {
        c.SDL_Log("Unable to create texture from surface: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyTexture(sprite_sheet_texture);

    // FIXME Match SDL2 behavior
    _ = c.SDL_SetTextureScaleMode(sprite_sheet_texture, c.SDL_SCALEMODE_NEAREST);

    var shouldExit = false;

    var last_frame_time_ms: u64 = c.SDL_GetTicks();

    while (!shouldExit) {
        const current_frame_time_ms: u64 = c.SDL_GetTicks();
        const frame_delta_secs = @as(f32, @floatFromInt(current_frame_time_ms - last_frame_time_ms)) * 0.001;

        // Poll events
        var sdlEvent: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&sdlEvent)) {
            switch (sdlEvent.type) {
                c.SDL_EVENT_QUIT => {
                    shouldExit = true;
                },
                c.SDL_EVENT_KEY_DOWN => {
                    switch (sdlEvent.key.key) {
                        c.SDLK_ESCAPE => {
                            shouldExit = true;
                        },
                        c.SDLK_DOWN => {
                            game.press_direction_down(game_state);
                        },
                        c.SDLK_RIGHT => {
                            game.press_direction_side(game_state, true);
                        },
                        c.SDLK_LEFT => {
                            game.press_direction_side(game_state, false);
                        },
                        c.SDLK_E => {
                            game.press_rotate(game_state, true);
                        },
                        c.SDLK_W => {
                            game.press_rotate(game_state, false);
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        game.update(game_state, frame_delta_secs);

        const string = try std.fmt.allocPrintZ(allocator, "Tetris | speed {d} tick = {}", .{ game_state.current_speed, game_state.next_tick_time_secs });
        defer allocator.free(string);

        _ = c.SDL_SetWindowTitle(window, string.ptr);

        _ = c.SDL_RenderClear(ren);

        for (game_state.board, 0..) |piece_type_opt, flat_index| {
            if (piece_type_opt) |piece_type| {
                const cell_coords = game.cell_coord_from_index(@intCast(flat_index));

                const sprite_output_pos_rect = c.SDL_FRect{
                    .x = @floatFromInt(cell_coords[0] * SpriteScreenExtent),
                    .y = @floatFromInt(cell_coords[1] * SpriteScreenExtent),
                    .w = @floatFromInt(SpriteScreenExtent),
                    .h = @floatFromInt(SpriteScreenExtent),
                };

                const sprite_sheet_rect = get_sprite_sheet_rect(.{ @intFromEnum(piece_type), 0 });
                _ = c.SDL_RenderTexture(ren, sprite_sheet_texture, &sprite_sheet_rect, &sprite_output_pos_rect);
            }
        }

        for (game_state.current_piece.local_positions) |local_position| {
            const cell_coords = @as(game.i32_2, @intCast(local_position)) + game_state.current_piece.offset;

            const sprite_output_pos_rect = c.SDL_FRect{
                .x = @floatFromInt(cell_coords[0] * SpriteScreenExtent),
                .y = @floatFromInt(cell_coords[1] * SpriteScreenExtent),
                .w = @floatFromInt(SpriteScreenExtent),
                .h = @floatFromInt(SpriteScreenExtent),
            };

            const sprite_sheet_rect = get_sprite_sheet_rect(.{ @intFromEnum(game_state.current_piece.type), 0 });
            _ = c.SDL_RenderTexture(ren, sprite_sheet_texture, &sprite_sheet_rect, &sprite_output_pos_rect);
        }

        _ = c.SDL_RenderPresent(ren);

        last_frame_time_ms = current_frame_time_ms;
    }
}
