const std = @import("std");

pub const DefaultSpeed = 5;

pub fn create_game_state(mode: GameMode, speed: u32, seed: u64, user_settings: UserSettings) GameState {
    var game = GameState{
        .rng = std.Random.Xoroshiro128.init(seed),
        .mode = mode,
        .speed = speed,
        .settings = user_settings,
        ._status = .Dropping,
        ._nextPiece = undefined,
        ._lcol = GridHeight - 1,
        ._wt = 0,
    };

    game._nextPiece = @enumFromInt(game.rng.random().uintLessThan(u32, 7)); // FIXME

    for (0..GridWidth) |i| {
        for (0..GridHeight) |j| {
            game._board[i][j] = null;
        }
    }

    switch (game.mode) {
        .garbage => |garbage| {
            game.fill_garbage(garbage.level);
            game._lines = GarbageModeLinesTarget;
        },
        .classic => {
            // Nothing ATM
        },
    }

    game.popPiece();

    return game;
}

const GameButtons = struct {
    d_up: bool,
    d_down: bool,
    d_left: bool,
    d_right: bool,
    rotate_cw: bool,
    rotate_ccw: bool,
    confirm: bool,
    pause: bool,
};

const Self = GameState;

const GameState = struct {
    rng: std.Random.Xoroshiro128,
    settings: UserSettings,
    mode: GameMode,
    speed: u32,
    _score: u32 = 0,
    _lines: u32 = 0,
    _tick: u32 = 0,
    _nextPiece: PieceType,
    _currentPiece: Piece = undefined,
    _status: GameStatus,
    _gameEnd: bool = false,
    _paused: bool = false,
    _shadow: Piece = undefined,
    _lcol: u32, // Used for lose event
    _wt: u32, // Used for win event
    lines_cleared_array: [4]u32 = undefined,
    lines_cleared_count: u32 = 0,
    _board: [GridWidth][GridHeight]?PieceType = undefined,

    fn fill_garbage(self: *Self, lines: u32) void {
        for (GridHeight - lines - GarbageModeMinHeight + 1..GridHeight) |j| {
            for (0..GridWidth) |i| {
                self._board[i][j] = @enumFromInt(self.getRand(7));
            }
            self._board[self.getRand(GridWidth)][j] = null;
        }
        for (0..lines * GarbageModePorosity) |_| {
            self._board[self.getRand(GridWidth)][GridHeight - self.getRand(lines + GarbageModeMinHeight) - 1] = null;
        }
    }

    fn getRand(self: *Self, upper_bound: u32) u32 {
        return self.rng.random().uintLessThan(u32, upper_bound);
    }

    fn getPushDownTickRate(self: *const Self) u32 {
        const tick_rate = std.math.divTrunc(u32, 60, self.speed) catch unreachable; // FIXME
        return tick_rate + FrameOffset;
    }

    // void Game::drawPieces(self: *const Self) {
    //   for (int j = 0; j < GridHeight; ++j) {
    //     bool clear = false;
    //     if (_status == WaitForClear) {
    //       for (std::list<int>::iterator it = _linesCleared.begin();
    //            it != _linesCleared.end(); ++it) {
    //         if (*it == j) {
    //           clear = true;
    //         }
    //       }
    //     }
    //     for (int i = 0; i < GridWidth; ++i) {
    //       if (_board[i][j] != 0) {
    //         if (clear) {
    //           if ((_tick % 20) < 10) {
    //             // Draw nothing
    //           } else {
    //             drawImageFrameXY(_tile, _board[i][j] - 1,
    //                              i * (BrickSize - 1) + GridOffsetX,
    //                              j * (BrickSize - 1) + GridOffsetY);
    //           }
    //         } else {
    //           drawImageFrameXY(_tile, _board[i][j] - 1,
    //                            i * (BrickSize - 1) + GridOffsetX,
    //                            j * (BrickSize - 1) + GridOffsetY);
    //         }
    //       }
    //     }
    //   }
    //   if (_status == Dropping) {
    //     if (settings.flags & show_piece_shadow) {
    //       // Draw shadow
    //       oslSetAlpha(OSL_FX_ALPHA, PieceShadowAlpha);
    //       for (int j = 0; j < 4; ++j) {
    //         for (int i = 0; i < 4; ++i) {
    //           if (_shadow.array[i][j] != 0) {
    //             drawImageFrameXY(
    //                 _tile, _shadow.array[i][j] - 1,
    //                 (i + _shadow.pos.x) * (BrickSize - 1) + GridOffsetX,
    //                 (j + _shadow.pos.y) * (BrickSize - 1) + GridOffsetY);
    //           }
    //         }
    //       }
    //       oslSetAlpha(OSL_FX_RGBA, PieceShadowAlpha);
    //     }
    //     // Draw falling piece
    //     for (int j = 0; j < 4; ++j) {
    //       for (int i = 0; i < 4; ++i) {
    //         if (_currentPiece.array[i][j] != 0) {
    //           drawImageFrameXY(
    //               _tile, _currentPiece.array[i][j] - 1,
    //               (i + _currentPiece.pos.x) * (BrickSize - 1) + GridOffsetX,
    //               (j + _currentPiece.pos.y) * (BrickSize - 1) + GridOffsetY);
    //         }
    //       }
    //     }
    //   }
    // }

    fn checkCollision(self: Self, p: *const Piece) bool {
        for (0..4) |j| {
            for (0..4) |i| {
                const x_offset: i32 = @intCast(i);
                const y_offset: i32 = @intCast(j);

                if (p.array[i][j]) {
                    if (x_offset + p.pos.x >= GridWidth) {
                        return false;
                    }
                    if (x_offset + p.pos.x < 0) {
                        return false;
                    }
                    if (y_offset + p.pos.y >= GridHeight) {
                        return false;
                    }
                    if (y_offset + p.pos.y < 0) {
                        return false;
                    }
                    if (self._board[@intCast(x_offset + p.pos.x)][@intCast(y_offset + p.pos.y)] != null) {
                        return false;
                    }
                }
            }
        }

        return true;
    }

    fn checkForLines(self: *Self) void {
        self.lines_cleared_count = 0;

        for (0..GridHeight) |j| {
            var lineFull = true;

            for (0..GridWidth) |i| {
                if (self._board[i][j] == null) {
                    lineFull = false; // Contradiction found
                }
            }

            if (lineFull) {
                self.lines_cleared_array[self.lines_cleared_count] = @intCast(j);
                self.lines_cleared_count += 1;
            }
        }
    }

    fn removeLines(self: *Self) void {
        const lines_to_clear = self.lines_cleared_array[0..self.lines_cleared_count];

        for (lines_to_clear) |line_to_clear| {
            for (0..GridWidth) |i| {
                self._board[i][line_to_clear] = null;
            }
        }

        var n: u32 = 0;

        for (lines_to_clear) |line_to_clear| {
            const offset = line_to_clear + n;
            var j = offset - 1;

            while (j >= 0) : (j -= 1) {
                for (0..GridWidth) |i| {
                    self._board[i][j + 1] = self._board[i][j];
                }
            }

            for (0..GridWidth) |i| {
                self._board[i][0] = null;
            }

            n += 1;
        }

        switch (self.mode) {
            .garbage => {
                if (self._lines == 0) {
                    self._status = .Win;
                    self._tick = 0;
                }
            },
            .classic => {
                // Nothing ATM
            },
        }

        unreachable;
    }

    fn scoreLines(self: *Self, lines: u32) void {
        // playSound(LineClearEnd); FIXME
        switch (self.mode) {
            .classic => {
                self._lines += lines;
                if (self._lines >= (self.speed * LinesBetweenLevels)) {
                    self.speed += 1;
                    //playSound(LevelUp); FIXME
                }
            },
            .garbage => {
                self._lines -= lines;
                if (self._lines < 0) {
                    self._lines = 0;
                }
            },
        }
        const t: u32 = switch (lines) {
            1 => 1,
            2 => 4,
            3 => 8,
            4 => 16,
            else => @panic("Invalid lines scored!"),
        };

        const tmpScore = self.speed * 100 * t;
        self._score += tmpScore;
        self.pushScoreNotification(tmpScore);
    }

    fn scoreDownBonus(self: *Self, iter: u32) void {
        const tmpScore = self.speed * PushDownBonus * iter;
        self._score += tmpScore;
        self.pushScoreNotification(tmpScore);
    }

    fn pushScoreNotification(self: *Self, points: u32) void {
        _ = self;
        _ = points;
        // FIXME
        // ScoreText tmp;
        // sprintf(tmp.text, "+%i", points);
        // tmp.alpha = 0xff;
        // tmp.frame = 0;
        // tmp.pos.x = ScoreTextOffsetX;
        // tmp.pos.y = ScoreTextOffsetY;
        // _scoreText.push_back(tmp);
    }

    fn requestTurnClockwise(self: *Self) void {
        var orientation = @intFromEnum(self._currentPiece.orientation);
        orientation +%= 1;

        var tmp: Piece = undefined;
        setPiece(&tmp, self._currentPiece.type, @enumFromInt(orientation), self._currentPiece.pos.x, self._currentPiece.pos.y, true);
        if (self.checkCollision(&tmp)) {
            copyPiece(tmp, &self._currentPiece);
            // playSound(RotatePiece); FIXME
        }
    }

    fn requestTurnCounterClockwise(self: *Self) void {
        var orientation = @intFromEnum(self._currentPiece.orientation);
        orientation -%= 1;

        var tmp: Piece = undefined;
        setPiece(&tmp, self._currentPiece.type, @enumFromInt(orientation), self._currentPiece.pos.x, self._currentPiece.pos.y, true);
        if (self.checkCollision(&tmp)) {
            copyPiece(tmp, &self._currentPiece);
            // playSound(RotatePiece); FIXME
        }
    }

    fn requestLeft(self: *Self) void {
        var tmp: Piece = undefined;
        setPiece(&tmp, self._currentPiece.type, self._currentPiece.orientation, self._currentPiece.pos.x - 1, self._currentPiece.pos.y, false);
        if (self.checkCollision(&tmp)) {
            copyPiece(tmp, &self._currentPiece);
            // playSound(MovePiece); FIXME
        }
    }

    fn requestRight(self: *Self) void {
        var tmp: Piece = undefined;
        setPiece(&tmp, self._currentPiece.type, self._currentPiece.orientation, self._currentPiece.pos.x + 1, self._currentPiece.pos.y, false);
        if (self.checkCollision(&tmp)) {
            copyPiece(tmp, &self._currentPiece);
            // playSound(MovePiece); FIXME
        }
    }

    fn requestDown(self: *Self, user: bool) void {
        var tmp: Piece = undefined;
        setPiece(&tmp, self._currentPiece.type, self._currentPiece.orientation, self._currentPiece.pos.x, self._currentPiece.pos.y + 1, false);
        if (self.checkCollision(&tmp)) {
            copyPiece(tmp, &self._currentPiece);
            if (user) {
                // playSound(MovePiece); FIXME
                self.scoreDownBonus(1);
            }
        } else {
            self.placePiece();
            if ((self._currentPiece.pos.x == BrickStartingPosX) and
                (self._currentPiece.pos.y == BrickStartingPosY))
            {
                self._status = .Lost;
                self._tick = 0;
            } else {
                self.onReachBottom();
            }
        }
    }

    fn requestUp(self: *Self) void {
        var tmp: Piece = undefined;
        var match = true;
        var n: u32 = 0;
        while (match) {
            setPiece(&tmp, self._currentPiece.type, self._currentPiece.orientation, self._currentPiece.pos.x, self._currentPiece.pos.y + 1, false);
            match = self.checkCollision(&tmp);
            if (match) {
                copyPiece(tmp, &self._currentPiece);
                n += 1;
            }
        }

        if (n > 0) {
            self.scoreDownBonus(n);
        }

        if (self.settings.enable_soft_drop) {
            self._tick = 0;
        } else {
            self.onReachBottom();
        }
    }

    fn onReachBottom(self: *Self) void {
        self.placePiece();
        self.checkForLines();
        if (self.lines_cleared_count != 0) {
            self._tick = 0;
            self._status = .WaitForClear;

            if (self.lines_cleared_count == 4) {
                // playSound(LineClearTetris); FIXME
            } else {
                // playSound(LineClearBegin); FIXME
            }
        } else {
            self.popPiece();
        }
    }

    fn updateShadow(self: *Self) void {
        var tmp: Piece = undefined;
        var match = true;
        copyPiece(self._currentPiece, &self._shadow);
        while (match) {
            setPiece(&tmp, self._shadow.type, self._shadow.orientation, self._shadow.pos.x, self._shadow.pos.y + 1, false);
            match = self.checkCollision(&tmp);
            if (match) {
                copyPiece(tmp, &self._shadow);
            }
        }
    }

    fn placePiece(self: *Self) void {
        for (0..4) |j| {
            for (0..4) |i| {
                if (self._currentPiece.array[i][j]) {
                    self._board[i + @as(usize, @intCast(self._currentPiece.pos.x))][j + @as(usize, @intCast(self._currentPiece.pos.y))] =
                        if (self._currentPiece.array[i][j]) self._currentPiece.type else null;
                }
            }
        }
        // playSound(PlacePiece); FIXME
    }

    fn popPiece(self: *Self) void {
        setPiece(&self._currentPiece, self._nextPiece, .North, BrickStartingPosX, BrickStartingPosY, false);
        self._nextPiece = @enumFromInt(self.getRand(7));
        self.updateShadow();
    }

    fn copyPiece(source: Piece, dest: *Piece) void {
        dest.type = source.type;
        dest.orientation = source.orientation;
        dest.pos.x = source.pos.x;
        dest.pos.y = source.pos.y;
        for (0..4) |i| {
            for (0..4) |j| {
                dest.array[i][j] = source.array[i][j];
            }
        }
    }

    fn setPiece(dest: *Piece, piece_type: PieceType, orientation: Orientation, x: i32, y: i32, applyRotFix: bool) void {
        dest.type = piece_type;
        dest.orientation = orientation;
        dest.pos.x = x;
        dest.pos.y = y;

        for (0..4) |i| {
            for (0..4) |j| {
                dest.array[i][j] = false;
            }
        }

        if (piece_type == .Bar) {
            switch (dest.orientation) {
                .West, .East => {
                    for (0..4) |i| {
                        dest.array[i][1] = true;
                    }
                },
                .South, .North => {
                    for (0..4) |j| {
                        dest.array[1][j] = true;
                    }
                },
            }
        }
        if (piece_type == .Quad) {
            for (0..2) |i| {
                for (0..2) |j| {
                    dest.array[i + 1][j + 1] = true;
                }
            }
        }
        if (piece_type == .SReverse) {
            switch (dest.orientation) {
                .West, .East => {
                    dest.array[2][0] = true;
                    dest.array[2][1] = true;
                    dest.array[1][1] = true;
                    dest.array[1][2] = true;
                },
                .South, .North => {
                    dest.array[1][1] = true;
                    dest.array[2][1] = true;
                    dest.array[2][2] = true;
                    dest.array[3][2] = true;
                },
            }
        }
        if (piece_type == .SNormal) {
            switch (dest.orientation) {
                .West, .East => {
                    dest.array[1][0] = false;
                    dest.array[1][1] = false;
                    dest.array[2][1] = false;
                    dest.array[2][2] = false;
                },
                .South, .North => {
                    dest.array[0][2] = false;
                    dest.array[1][2] = false;
                    dest.array[1][1] = false;
                    dest.array[2][1] = false;
                },
            }
        }
        if (piece_type == .LNormal) {
            dest.array[1][1] = true;
            if (dest.orientation == .West) {
                dest.array[0][1] = true;
                dest.array[2][1] = true;
                dest.array[2][0] = true;
            }
            if (dest.orientation == .South) {
                dest.array[1][0] = true;
                dest.array[1][2] = true;
                dest.array[0][0] = true;
            }
            if (dest.orientation == .East) {
                dest.array[0][1] = true;
                dest.array[2][1] = true;
                dest.array[0][2] = true;
            }
            if (dest.orientation == .North) {
                dest.array[1][0] = true;
                dest.array[1][2] = true;
                dest.array[2][2] = true;
            }
        }
        if (piece_type == .LReverse) {
            dest.array[2][1] = true;
            if (dest.orientation == .West) {
                dest.array[1][1] = true;
                dest.array[3][1] = true;
                dest.array[3][2] = true;
            }
            if (dest.orientation == .South) {
                dest.array[2][0] = true;
                dest.array[2][2] = true;
                dest.array[3][0] = true;
            }
            if (dest.orientation == .East) {
                dest.array[1][1] = true;
                dest.array[3][1] = true;
                dest.array[1][0] = true;
            }
            if (dest.orientation == .North) {
                dest.array[2][0] = true;
                dest.array[2][2] = true;
                dest.array[1][2] = true;
            }
        }
        if (piece_type == .Pyramid) {
            dest.array[1][1] = true;
            dest.array[1][0] = true;
            dest.array[0][1] = true;
            dest.array[2][1] = true;
            dest.array[1][2] = true;

            switch (dest.orientation) {
                .West => {
                    dest.array[0][1] = false;
                },
                .South => {
                    dest.array[1][2] = false;
                },
                .East => {
                    dest.array[2][1] = false;
                },
                .North => {
                    dest.array[1][0] = false;
                },
            }
        }
        // Apply fix when a piece is next to the side of the board and has to rotate
        if (applyRotFix) {
            if (dest.type == .Bar) {
                if ((dest.orientation == .East) and (dest.pos.x == -1)) {
                    dest.pos.x = 0;
                }
                if ((dest.orientation == .East) and (dest.pos.x >= GridWidth - 3)) {
                    dest.pos.x = GridWidth - 4;
                }
            }
        }
    }
};

pub fn update(self: *Self, pressed_buttons: GameButtons) void {
    if (self._status == .Dropping or self._status == .WaitForClear) {
        if (pressed_buttons.pause) {
            self._paused = !self._paused;
            // playSound(Pause); FIXME
        }
    }
    if (self._status == .Dropping) {
        if (!self._paused) {
            // Manually increase/decrease speed
            //       if (pressed_buttons.r_trigger == 1) {
            //         ++speed;
            //       }

            //         if (speed > 1) {
            //           --speed;
            //         }
            //       }
            //
            if (pressed_buttons.d_left) {
                self.requestLeft();
            } else if (pressed_buttons.d_right) {
                self.requestRight();
            }
            if (pressed_buttons.rotate_cw) {
                self.requestTurnClockwise();
            } else if (pressed_buttons.rotate_ccw) {
                self.requestTurnCounterClockwise();
            }
            if (pressed_buttons.d_down) {
                self.requestDown(true);
            } else if (pressed_buttons.d_up) {
                self.requestUp();
            }
        }
    }
    if (self._status == .Dropping) {
        if (!self._paused) {
            self._tick += 1;
            if (self._tick > self.getPushDownTickRate()) {
                self._tick = 0;
                self.requestDown(false);
            }
            self.updateShadow();
        }
    } else if (self._status == .WaitForClear) {
        if (!self._paused) {
            self._tick += 1;
            if (self._tick > ClearTickCount) {
                self._tick = 0;
                self._status = .Dropping;
                const lines = self.lines_cleared_count;
                if (lines > 0) {
                    self.scoreLines(lines);
                }
                self.removeLines();
                self.popPiece();
            }
        }
    } else if (self._status == .Lost) {
        if (pressed_buttons.confirm) {
            self._gameEnd = true;
        } else {
            self._tick += 1;
            if (self._tick > 0) {
                self._tick = 0;
                if (self._lcol >= 0) {
                    for (0..GridWidth) |i| {
                        self._board[i][self._lcol] = self._currentPiece.type;
                    }
                    self._lcol -= 1;
                }
            }
        }
    } else if (self._status == .Win) {
        if (pressed_buttons.confirm) {
            self._gameEnd = true;
        } else {
            // Win animation
            if (self._wt % 60 == 0) {
                self._wt = 0;
                for (0..GridWidth) |i| {
                    for (0..GridHeight / 2 - 2) |j| {
                        self._board[i][j] = @enumFromInt(self.getRand(7));
                    }
                    for (GridHeight / 2 - 2..GridHeight / 2 + 2) |j| {
                        self._board[i][j] = null;
                    }
                    for (GridHeight / 2 + 2..GridHeight) |j| {
                        self._board[i][j] = @enumFromInt(self.getRand(7));
                    }
                }
            }
            self._wt += 1;
        }
    }
    if (!self._paused) {
        // Manage score text list FIXME
        //std::list<ScoreText>::iterator it = _scoreText.begin();
        //while (it != _scoreText.end()) {
        //  if ((*it).frame > ScoreMaxLife) {
        //    it = _scoreText.erase(it);
        //  } else {
        //    ++it;
        //  }
        //}
        //// Update every notification
        //for (it = _scoreText.begin(); it != _scoreText.end(); ++it) {
        //  (*it).alpha = 240 - (*it).frame * 2;
        //  (*it).pos.y = ScoreTextOffsetY - (*it).frame / 6;
        //  ++(*it).frame;
        //}
    }
}

// void Game::loadSound(const char *filename, int index, int channel) {
//   Sound tmp;
//   tmp.soundData = oslLoadSoundFile(filename, OSL_FMT_NONE);
//   tmp.channel = channel;
//   _sounds[index] = tmp;
// }
//
// void Game::playSound(int index) {
//   oslPlaySound(_sounds[index].soundData, _sounds[index].channel);
// }
//
// void Game::playSound(int index, int channel) {
//   oslPlaySound(_sounds[index].soundData, channel);
// }
//
//

const BatteryIconX: u32 = 456;
const BatteryIconY: u32 = 4;
const BrickSize: u32 = 14;
const BrickStartingPosX: u32 = 3;
const BrickStartingPosY: u32 = 0;
const BoardBackgroundColor: u32 = 0xb0000000;
const BoardOutlineColor: u32 = 0x40aaaaaa;
const GridColor: u32 = 0x09FFFFFF;
const NextPieceBackgroundColor: u32 = 0x50000000;
const GridOffsetX = 150;
const GridOffsetY = 5;
const NextOffsetX = 295;
const NextOffsetY = 100;
const TextOffsetX = 295;
const TextOffsetY = 50;
const TextSpacingY = 15;
const ScoreTextOffsetX = 340;
const ScoreTextOffsetY = 40;
const ScoreMaxLife = 120;
const ClearTickCount = 60;
const ClearBlurFrameCount = 1;
const PushDownBonus = 1;
const FrameOffset = 2;
const LinesBetweenLevels = 10;
const GameModes = 2;
const GarbageModeLinesTarget = 25;
const GarbageModeMinHeight = 2;
const GarbageModePorosity = 6;
const PieceShadowAlpha = 0x4f;

const GameMode = union(enum) {
    classic,
    garbage: struct {
        level: u32,
    },
};

const ScoreType = enum {
    Single,
    Double,
    Triple,
    Tetris,
};

const Orientation = enum(u2) {
    North,
    East,
    South,
    West,
};

const BrickColor = enum {
    Empty,
    Yellow,
    Black,
    Green,
    Red,
    Orange,
    Blue,
    Purple,
};

const PieceType = enum {
    Bar,
    Quad,
    SReverse,
    SNormal,
    LNormal,
    LReverse,
    Pyramid,
};

const GameStatus = enum {
    Dropping,
    WaitForClear,
    Lost,
    Win,
};

const Sounds = enum {
    LineClearBegin,
    LineClearEnd,
    LineClearTetris,
    LevelUp,
    MovePiece,
    RotatePiece,
    PlacePiece,
    Pause,
};

const Piece = struct {
    type: PieceType,
    orientation: Orientation,
    pos: struct {
        x: i32,
        y: i32,
    },
    array: [4][4]bool,
};

fn render(state: *const GameState) void { // FIXME
    _ = state;
    // char temp[40];
    // oslStartDrawing();
    // oslDrawImage(_background);
    // // Draw board outline
    // oslDrawRect(GridOffsetX - 1, GridOffsetY - 1,
    //             GridOffsetX + GridWidth * (BrickSize - 1) + 2,
    //             GridOffsetY + GridHeight * (BrickSize - 1) + 2,
    //             BoardOutlineColor);
    // // Draw board background
    // oslDrawFillRect(
    //     GridOffsetX, GridOffsetY, GridOffsetX + GridWidth * (BrickSize - 1) + 1,
    //     GridOffsetY + GridHeight * (BrickSize - 1) + 1, BoardBackgroundColor);
    // if (settings.flags & show_grid) {
    //   // Draw vertical helpers
    //   for (int i = 1; i < GridWidth; ++i) {
    //     oslDrawLine(GridOffsetX + i * (BrickSize - 1), GridOffsetY,
    //                 GridOffsetX + i * (BrickSize - 1),
    //                 GridOffsetY + GridHeight * (BrickSize - 1) + 1, GridColor);
    //   }
    //   // Draw horizontal helpers
    //   for (int j = 1; j < GridHeight; ++j) {
    //     oslDrawLine(GridOffsetX, GridOffsetY + j * (BrickSize - 1),
    //                 GridOffsetX + GridWidth * (BrickSize - 1) + 1,
    //                 GridOffsetY + j * (BrickSize - 1), GridColor);
    //   }
    // }
    // if (!_paused)
    //   drawPieces();
    // else {
    //   intraFontSetStyle(_ltn, 0.7f, 0xFFFFFFFF, 0xFF000000, 0.f, 0);
    //   intraFontPrint(_ltn, GridOffsetX + 45, 140, "Pause");
    // }
    // if (_status == Win) {
    //   if ((_wt % 60) < 40) {
    //     intraFontSetStyle(_ltn, 0.7f, 0xFFFFFFFF, 0xFF000000, 0.f, 0);
    //     intraFontPrint(_ltn, 135, 140, "You Win !");
    //   }
    // }
    // if (settings.flags & show_score_animations) {
    //   // Draw score messages
    //   for (std::list<ScoreText>::iterator it = _scoreText.begin();
    //        it != _scoreText.end(); ++it) {
    //     intraFontSetStyle(_ltn, 0.6f, RGBA(0, 255, 0, (*it).alpha), 0xff000000,
    //                       0.f, 0);
    //     intraFontPrint(_ltn, (*it).pos.x, (*it).pos.y, (*it).text);
    //   }
    // }
    // if (settings.flags & show_upcoming_piece) {
    //   // Draw next piece
    //   oslDrawRect(NextOffsetX - 1, NextOffsetY - 1,
    //               NextOffsetX + 4 * (BrickSize - 1) + 2,
    //               NextOffsetY + 4 * (BrickSize - 1) + 2, BoardOutlineColor);
    //   oslDrawFillRect(
    //       NextOffsetX, NextOffsetY, NextOffsetX + 4 * (BrickSize - 1) + 1,
    //       NextOffsetY + 4 * (BrickSize - 1) + 1, NextPieceBackgroundColor);
    //   Piece tmp;
    //   setPiece(tmp, _nextPiece, North, 0, 0, 0);
    //   for (int j = 0; j < 4; ++j) {
    //     for (int i = 0; i < 4; ++i) {
    //       if (tmp.array[i][j] != 0) {
    //         drawImageFrameXY(_tile, tmp.array[i][j] - 1,
    //                          i * (BrickSize - 1) + NextOffsetX,
    //                          j * (BrickSize - 1) + NextOffsetY);
    //       }
    //     }
    //   }
    // }
    // // Print scores
    // intraFontSetStyle(_ltn, 0.6f, 0xFFFFFFFF, 0xFF000000, 0.f, 0);
    // sprintf(temp, "Score: %i", _score);
    // // oslDrawString(TextOffsetX, TextOffsetY, temp);
    // intraFontPrint(_ltn, TextOffsetX, TextOffsetY, temp);
    // sprintf(temp, "Lines: %i", _lines);
    // // oslDrawString(TextOffsetX, TextOffsetY + TextSpacingY, temp);
    // intraFontPrint(_ltn, TextOffsetX, TextOffsetY + TextSpacingY, temp);
    // sprintf(temp, "Speed: %i", settings.speed);
    // // oslDrawString(TextOffsetX, TextOffsetY + TextSpacingY * 2, temp);
    // intraFontPrint(_ltn, TextOffsetX, TextOffsetY + TextSpacingY * 2, temp);
    // // oslSyncDrawing();
    // if ((_status == WaitForClear) &&
    //     (_tick > ClearTickCount - ClearBlurFrameCount) && !_paused) {
    //   if (settings.flags & enable_clear_blur) {
    //     // blurDrawBufferHorizontally(24, _blurBuffer);
    //   }
    // }
    // oslEndDrawing();
}

// const int sampleRate = 44100;
// float frequency = 440.0f;
// float currentTime = 0;
// int function = 0;
//
// typedef struct {
//   short l, r;
// } sample_t;
//
// float currentFunction(const float time) {
//   double x;
//   float t = modf(time / (2 * PI), &x);
//
//   switch (function) {
//   case 0: // SINE
//     return sinf(time);
//   case 1: // SQUARE
//     if (t < 0.5f) {
//       return -0.2f;
//     } else {
//       return 0.2f;
//     }
//   case 2: // TRIANGLE
//     if (t < 0.5f) {
//       return t * 2.0f - 0.5f;
//     } else {
//       return 0.5f - (t - 0.5f) * 2.0f;
//     }
//   default:
//     return 0.0f;
//   }
// }
//
// // This function gets called by pspaudiolib every time the
// // audio buffer needs to be filled. The sample format is
// // 16-bit, stereo.
// void audioCallback(void *buf, unsigned int length, void *userdata) {
//   const float sampleLength = 1.0f / sampleRate;
//   const float scaleFactor = SHRT_MAX - 1.0f;
//   static float freq0 = 440.0f;
//   sample_t *ubuf = (sample_t *)buf;
//   int i;
//
//   if (frequency != freq0) {
//     currentTime *= (freq0 / frequency);
//   }
//   for (i = 0; i < length; i++) {
//     short s = (short)(scaleFactor *
//                       currentFunction(2.0f * PI * frequency * currentTime));
//     ubuf[i].l = s;
//     ubuf[i].r = s;
//     currentTime += sampleLength;
//   }
//   if (currentTime * frequency > 1.0f) {
//     double d;
//     currentTime = modf(currentTime * frequency, &d) / frequency;
//   }
//   freq0 = frequency;
// }
//
// /* Read the analog stick and adjust the frequency */
// void controlFrequency() {
//   static int oldButtons = 0;
//   const int zones[6] = {30, 70, 100, 112, 125, 130};
//   const float response[6] = {0.0f, 0.1f, 0.5f, 1.0f, 4.0f, 8.0f};
//   const float minFreq = 32.0f;
//   const float maxFreq = 7040.0f;
//   SceCtrlData pad;
//   float direction;
//   int changedButtons;
//   int i, v;
//
//   sceCtrlReadBufferPositive(&pad, 1);
//
//   v = pad.Ly - 128;
//   if (v < 0) {
//     direction = 1.0f;
//     v = -v;
//   } else {
//     direction = -1.0f;
//   }
//
//   for (i = 0; i < 6; i++) {
//     if (v < zones[i]) {
//       frequency += response[i] * direction;
//       break;
//     }
//   }
//
//   if (frequency < minFreq) {
//     frequency = minFreq;
//   } else if (frequency > maxFreq) {
//     frequency = maxFreq;
//   }
//
//   changedButtons = pad.Buttons & (~oldButtons);
//   if (changedButtons & PSP_CTRL_CROSS) {
//     function++;
//     if (function > 2) {
//       function = 0;
//     }
//   }
//   oldButtons = pad.Buttons;
// }
//
// int main(void) {
//   pspDebugScreenInit();
//   setupCallbacks();
//
//   pspAudioInit();
//   pspAudioSetChannelCallback(0, audioCallback, NULL);
//
//   while (1) {
//     sceDisplayWaitVblankStart();
//     pspDebugScreenSetXY(0, 2);
//     printf("freq = %.2f   \n", frequency);
//     controlFrequency();
//   }
//   return 0;
// }
