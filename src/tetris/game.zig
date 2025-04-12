const std = @import("std");
const assert = std.debug.assert;

pub const u32_2 = @Vector(2, u32);
pub const i32_2 = @Vector(2, i32);

pub const BoardWidth: u32 = 10;
pub const BoardHeight: u32 = 20;
// const BoardHeight: u32 = 20;
const BoardExtent = u32_2{ BoardWidth, BoardHeight };

pub const GameState = struct {
    rng: std.Random.Xoroshiro128,
    settings: UserSettings,

    current_speed: u32,

    // Set by generate_next_piece
    current_piece: Piece = undefined,

    board: Board = undefined,

    next_piece_type: PieceType,

    lines_cleared_array: [4]u32 = undefined,
    lines_cleared_count: u32 = 0,

    const Board = [BoardWidth * BoardHeight]?PieceType;
};

pub fn create_game_state(speed: u32, seed: u64, user_settings: UserSettings) GameState {
    var rng = std.Random.Xoroshiro128.init(seed);

    const next_piece_type = generate_new_piece_type(&rng.random());

    var game = GameState{
        .rng = rng,
        .settings = user_settings,
        .current_speed = speed,
        .next_piece_type = next_piece_type,
    };

    generate_next_piece(&game);

    for (&game.board) |*cell| {
        cell.* = null;
    }

    return game;
}

pub fn press_direction_down(game: *GameState) void {
    const piece_one_step_down = Piece{
        .type = game.current_piece.type,
        .orientation = game.current_piece.orientation,
        .offset = game.current_piece.offset + i32_2{ 0, 1 },
        .local_positions = game.current_piece.local_positions,
    };

    const collides_with_board = check_piece_collision(game.board, piece_one_step_down);

    if (collides_with_board) {
        place_piece(game, game.current_piece);
        generate_next_piece(game);
    } else {
        game.current_piece.offset += .{ 0, 1 };
    }
}

pub fn press_direction_side(game: *GameState, right: bool) void {
    const piece_one_step_side = Piece{
        .type = game.current_piece.type,
        .orientation = game.current_piece.orientation,
        .offset = game.current_piece.offset + i32_2{ if (right) 1 else -1, 0 },
        .local_positions = game.current_piece.local_positions,
    };

    const collides_with_board = check_piece_collision(game.board, piece_one_step_side);

    if (collides_with_board) {
        // TODO feedback
    } else {
        game.current_piece.offset += .{ if (right) 1 else -1, 0 };
    }
}

pub fn update(game: *GameState) void {
    _ = game;
}

fn generate_next_piece(game: *GameState) void {
    game.current_piece = .{
        .type = game.next_piece_type,
        .orientation = .North,
        .offset = .{ 3, 0 },
        .local_positions = undefined, // Set right after
    };
    game.current_piece.local_positions = build_piece_positions(game.current_piece.type, game.current_piece.orientation);

    game.next_piece_type = generate_new_piece_type(&game.rng.random());
}

fn place_piece(game: *GameState, piece: Piece) void {
    for (game.current_piece.local_positions) |local_position| {
        const block_offset = piece.offset + local_position;
        const board_offset_flat = cell_index_from_coord(@intCast(block_offset));
        game.board[board_offset_flat] = game.current_piece.type;
    }
}

fn check_piece_collision(board: GameState.Board, piece: Piece) bool {
    const piece_offset: i32_2 = @intCast(piece.offset);

    for (piece.local_positions) |local_position| {
        const board_position = piece_offset + local_position;

        const piece_is_on_board = all(board_position >= i32_2{ 0, 0 }) and all(board_position < i32_2{ BoardExtent[0], BoardExtent[1] });

        if (!piece_is_on_board) {
            return true;
        }

        const board_position_flat = cell_index_from_coord(@intCast(board_position));

        if (board[board_position_flat] != null) {
            return true;
        }
    }

    return false;
}

// I borrowed this name from HLSL
fn all(vector: anytype) bool {
    const type_info = @typeInfo(@TypeOf(vector));
    assert(type_info.vector.child == bool);
    assert(type_info.vector.len > 1);

    return @reduce(.And, vector);
}

pub fn cell_coord_from_index(cell_index: usize) u32_2 {
    const x: u32 = @intCast(cell_index % BoardWidth);
    const y: u32 = @intCast(cell_index / BoardWidth);

    const position = u32_2{ x, y };
    assert(all(position < BoardExtent));

    return position;
}

pub fn cell_index_from_coord(position: u32_2) u32 {
    assert(all(position < BoardExtent));

    return position[0] + BoardWidth * position[1];
}

pub const UserSettings = packed struct {
    // enable_clear_blur: bool = true,
    // show_grid: bool = true,
    // show_piece_shadow: bool = true,
    // show_score_animations: bool = true,
    // show_upcoming_piece: bool = true,
    // enable_soft_drop: bool = false,
};

const Piece = struct {
    type: PieceType,
    orientation: Orientation,
    offset: i32_2,
    local_positions: [4]i32_2,
};

const PieceType = enum {
    const Count: u32 = 7;

    Bar,
    Quad,
    SNormal,
    SReverse,
    LNormal,
    LReverse,
    Tee,
};

const Orientation = enum(u2) {
    North,
    East,
    South,
    West,
};

fn build_piece_positions(piece_type: PieceType, orientation: Orientation) [4]i32_2 {
    return switch (piece_type) {
        .Bar => switch (orientation) {
            .West, .East => .{
                .{ 0, 1 },
                .{ 1, 1 },
                .{ 2, 1 },
                .{ 3, 1 },
            },
            .South, .North => .{
                .{ 1, 0 },
                .{ 1, 1 },
                .{ 1, 2 },
                .{ 1, 3 },
            },
        },
        .Quad => .{
            .{ 1, 1 },
            .{ 1, 2 },
            .{ 2, 1 },
            .{ 2, 2 },
        },
        .SNormal => switch (orientation) {
            .West, .East => .{
                .{ 1, 0 },
                .{ 1, 1 },
                .{ 2, 1 },
                .{ 2, 2 },
            },
            .South, .North => .{
                .{ 0, 2 },
                .{ 1, 2 },
                .{ 1, 1 },
                .{ 2, 1 },
            },
        },
        .SReverse => switch (orientation) {
            .West, .East => .{
                .{ 2, 0 },
                .{ 2, 1 },
                .{ 1, 1 },
                .{ 1, 2 },
            },
            .South, .North => .{
                .{ 1, 1 },
                .{ 2, 1 },
                .{ 2, 2 },
                .{ 3, 2 },
            },
        },
        .LNormal => switch (orientation) {
            .West => .{
                .{ 0, 1 },
                .{ 2, 1 },
                .{ 2, 0 },
                .{ 1, 1 },
            },
            .South => .{
                .{ 1, 0 },
                .{ 1, 2 },
                .{ 0, 0 },
                .{ 1, 1 },
            },
            .East => .{
                .{ 0, 1 },
                .{ 2, 1 },
                .{ 0, 2 },
                .{ 1, 1 },
            },
            .North => .{
                .{ 1, 0 },
                .{ 1, 2 },
                .{ 2, 2 },
                .{ 1, 1 },
            },
        },
        .LReverse => switch (orientation) {
            .West => .{
                .{ 1, 1 },
                .{ 3, 1 },
                .{ 3, 2 },
                .{ 2, 1 },
            },
            .South => .{
                .{ 2, 0 },
                .{ 2, 2 },
                .{ 3, 0 },
                .{ 2, 1 },
            },
            .East => .{
                .{ 1, 1 },
                .{ 3, 1 },
                .{ 1, 0 },
                .{ 2, 1 },
            },
            .North => .{
                .{ 2, 0 },
                .{ 2, 2 },
                .{ 1, 2 },
                .{ 2, 1 },
            },
        },
        .Tee => switch (orientation) {
            .West => .{
                .{ 1, 1 },
                .{ 1, 0 },
                .{ 2, 1 },
                .{ 1, 2 },
            },
            .South => .{
                .{ 1, 1 },
                .{ 1, 0 },
                .{ 0, 1 },
                .{ 2, 1 },
            },
            .East => .{
                .{ 1, 1 },
                .{ 1, 0 },
                .{ 0, 1 },
                .{ 1, 2 },
            },
            .North => .{
                .{ 1, 1 },
                .{ 0, 1 },
                .{ 2, 1 },
                .{ 1, 2 },
            },
        },
    };
}

// const GameButtons = struct {
//     d_up: bool,
//     d_down: bool,
//     d_left: bool,
//     d_right: bool,
//     rotate_cw: bool,
//     rotate_ccw: bool,
//     confirm: bool,
//     pause: bool,
// };

fn generate_new_piece_type(random: *const std.Random) PieceType {
    return @enumFromInt(random.uintLessThan(u32, PieceType.Count)); // FIXME
}
