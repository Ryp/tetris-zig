const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const native_endian = builtin.cpu.arch.endian();

const tetris = @import("tetris/game.zig");
const backend = @import("sdl_backend.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Parse arguments
    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    const DefaultSpeed: u32 = 5;
    const speed = if (args.len > 1) try std.fmt.parseUnsigned(u32, args[1], 0) else DefaultSpeed;

    // Using the method from the docs to get a reasonably random seed
    var buf: [8]u8 = undefined;
    std.crypto.random.bytes(buf[0..]);
    const seed = std.mem.readInt(u64, buf[0..8], native_endian);

    const user_settings = tetris.UserSettings{};

    var game_state = tetris.create_game_state(speed, seed, user_settings);

    try backend.execute_main_loop(gpa.allocator(), &game_state);
}
