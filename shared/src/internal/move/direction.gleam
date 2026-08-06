pub type Direction {
  Direction(file_change: Int, rank_change: Int)
}

pub fn in_direction(position: Int, direction: Direction) -> Int {
  let file = position % 8 + direction.file_change
  let rank = position / 8 + direction.rank_change

  case file >= 8 || rank >= 9 || file < 0 || rank < 0 {
    True -> -1
    False -> rank * 8 + file
  }
}

pub const left = Direction(-1, 0)

pub const right = Direction(1, 0)

pub const up = Direction(0, 1)

pub const down = Direction(0, -1)

pub const up_left = Direction(-1, 1)

pub const up_right = Direction(1, 1)

pub const down_left = Direction(-1, -1)

pub const down_right = Direction(1, -1)

pub const rook_directions = [left, right, up, down]

pub const bishop_directions = [up_left, up_right, down_left, down_right]

pub const queen_directions = [
  left,
  right,
  up,
  down,
  up_left,
  up_right,
  down_left,
  down_right,
]

pub const white_pawn_captures = [up_left, up_right]

pub const black_pawn_captures = [down_left, down_right]

pub const knight_directions = [
  Direction(-1, -2),
  Direction(1, -2),
  Direction(-1, 2),
  Direction(1, 2),
  Direction(2, -1),
  Direction(2, 1),
  Direction(-2, -1),
  Direction(-2, 1),
]
