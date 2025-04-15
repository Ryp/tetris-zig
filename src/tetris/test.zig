const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const game = @import("game.zig");

const test_seed: u64 = 0xC0FFEE42DEADBEEF;

test "Critical path" {
    var game_state = game.create_game_state(5, test_seed);

    game.update(&game_state, 1.0);
}
