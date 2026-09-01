import gleam/bool
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import internal/board.{type Board, type Color}
import internal/move/direction.{type Direction}

pub type AttackInformation {
  AttackInformation(
    in_check: Bool,
    attacks: List(Int),
    check_attack_squares: List(Int),
    check_block_lines: List(Int),
    pin_lines: Dict(Int, List(Int)),
  )
}

pub fn calculate(
  board: Board,
  river_squares: List(Int),
  king_position: Int,
  to_move: Color,
) {
  let attacking = case to_move {
    board.White -> board.Black
    board.Black -> board.White
  }
  let attacks = get_attacks(board, river_squares, attacking)

  let in_check = list.contains(attacks, king_position)

  let #(check_attack_squares, check_block_lines) = case in_check {
    False -> #([], [])
    True -> #(
      get_check_attack_squares(board, river_squares, attacking, king_position),
      get_check_block_line(board, river_squares, attacking, king_position),
    )
  }
  let pin_lines = get_pin_lines(board, river_squares, attacking, king_position)

  AttackInformation(
    in_check:,
    attacks:,
    check_block_lines:,
    pin_lines:,
    check_attack_squares:,
  )
}

fn get_pin_lines(
  board: Board,
  river_squares,
  attacking: Color,
  king_position: Int,
) {
  use lines, position, #(piece, color) <- dict.fold(board, dict.new())
  use <- bool.guard(color != attacking, lines)

  case piece {
    board.Bishop ->
      get_sliding_pin_lines(
        board,
        river_squares,
        attacking,
        position,
        king_position,
        direction.bishop_directions,
        lines,
      )
    board.Rook ->
      get_sliding_pin_lines(
        board,
        river_squares,
        attacking,
        position,
        king_position,
        direction.rook_directions,
        lines,
      )
    board.Queen ->
      get_sliding_pin_lines(
        board,
        river_squares,
        attacking,
        position,
        king_position,
        direction.queen_directions,
        lines,
      )
    _ -> lines
  }
}

fn get_sliding_pin_lines(
  board: Board,
  river_squares,
  attacking: Color,
  position: Int,
  king_position: Int,
  directions: List(Direction),
  lines: Dict(Int, List(Int)),
) -> Dict(Int, List(Int)) {
  case directions {
    [] -> lines
    [direction, ..directions] ->
      get_sliding_pin_lines(
        board,
        river_squares,
        attacking,
        position,
        king_position,
        directions,
        get_sliding_pin_lines_loop(
          board,
          river_squares,
          attacking,
          position,
          king_position,
          direction,
          lines,
          [position],
          -1,
        ),
      )
  }
}

fn get_sliding_pin_lines_loop(
  board: Board,
  river_squares,
  attacking: Color,
  position: Int,
  king_position: Int,
  direction: Direction,
  lines: Dict(Int, List(Int)),
  line: List(Int),
  pinned_piece: Int,
) {
  let position = direction.in_direction(position, direction)

  use <- bool.lazy_guard(pinned_piece != -1 && position == king_position, fn() {
    dict.insert(lines, pinned_piece, line)
  })

  case board.get(board, river_squares, position) {
    board.Empty ->
      get_sliding_pin_lines_loop(
        board,
        river_squares,
        attacking,
        position,
        king_position,
        direction,
        lines,
        [position, ..line],
        pinned_piece,
      )
    board.Occupied(color:, ..) if color != attacking && pinned_piece == -1 ->
      get_sliding_pin_lines_loop(
        board,
        river_squares,
        attacking,
        position,
        king_position,
        direction,
        lines,
        line,
        position,
      )
    board.River ->
      get_sliding_pin_lines_loop(
        board,
        river_squares,
        attacking,
        position,
        king_position,
        direction,
        lines,
        [position, ..line],
        pinned_piece,
      )
    _ -> lines
  }
}

type Line {
  NoLine
  Single(List(Int))
  Multiple
}

// TODO: Maybe it's faster to check from the king instead?
// rook / bishop = 4 dir calculation
// queen = 8 dir calculation
// 2 rook + 2 bishop + 1 queen = worst case 160 calculation
// K = 8 dir = worst case 64 calculation
fn get_check_block_line(
  board: Board,
  river_squares,
  attacking: Color,
  king_position: Int,
) {
  // This cursed piece of code just lets us map the final value after all the
  // `use` statements. Because of function inlining, this is equivalent to using
  // a block, then mapping at the end.
  use <-
    fn(f) {
      let line = f()
      case line {
        Single(line) -> line
        NoLine | Multiple -> []
      }
    }

  use line, position, #(piece, color) <- dict.fold(board, NoLine)
  use <- bool.guard(line == Multiple, line)
  use <- bool.guard(color != attacking, line)

  case piece {
    board.Queen ->
      case
        sliding_check_block_line(
          board,
          river_squares,
          position,
          king_position,
          direction.queen_directions,
        ),
        line
      {
        [], _ -> line
        line, NoLine -> Single(line)
        _, _ -> Multiple
      }
    board.Bishop ->
      case
        sliding_check_block_line(
          board,
          river_squares,
          position,
          king_position,
          direction.bishop_directions,
        ),
        line
      {
        [], _ -> line
        line, NoLine -> Single(line)
        _, _ -> Multiple
      }
    board.Rook ->
      case
        sliding_check_block_line(
          board,
          river_squares,
          position,
          king_position,
          direction.rook_directions,
        ),
        line
      {
        [], _ -> line
        line, NoLine -> Single(line)
        _, _ -> Multiple
      }
    board.Knight ->
      case
        piece_attacks_square(
          position,
          king_position,
          direction.knight_directions,
        ),
        line
      {
        False, _ -> line
        True, NoLine -> Single([position])
        _, _ -> Multiple
      }
    board.King ->
      case
        piece_attacks_square(
          position,
          king_position,
          direction.queen_directions,
        ),
        line
      {
        False, _ -> line
        True, NoLine -> Single([position])
        _, _ -> Multiple
      }
    board.Pawn if attacking == board.Black ->
      case
        piece_attacks_square(
          position,
          king_position,
          direction.black_pawn_captures,
        ),
        line
      {
        False, _ -> line
        True, NoLine -> Single([position])
        _, _ -> Multiple
      }
    board.Pawn ->
      case
        piece_attacks_square(
          position,
          king_position,
          direction.white_pawn_captures,
        ),
        line
      {
        False, _ -> line
        True, NoLine -> Single([position])
        _, _ -> Multiple
      }
  }
}

fn piece_attacks_square(
  position: Int,
  target: Int,
  directions: List(Direction),
) {
  case directions {
    [] -> False
    [direction, ..directions] ->
      case direction.in_direction(position, direction) == target {
        True -> True
        False -> piece_attacks_square(position, target, directions)
      }
  }
}

fn sliding_check_block_line(
  board: Board,
  river_squares,
  position: Int,
  king_position: Int,
  directions: List(Direction),
) {
  case directions {
    [] -> []
    [direction, ..directions] ->
      case
        sliding_check_block_line_loop(
          board,
          river_squares,
          position,
          king_position,
          direction,
          [position],
        )
      {
        [] ->
          sliding_check_block_line(
            board,
            river_squares,
            position,
            king_position,
            directions,
          )
        line -> line
      }
  }
}

fn sliding_check_block_line_loop(
  board: Board,
  river_squares,
  position: Int,
  king_position: Int,
  direction: Direction,
  line: List(Int),
) -> List(Int) {
  let new_position = direction.in_direction(position, direction)
  use <- bool.guard(new_position == king_position, line)

  case board.get(board, river_squares, new_position) {
    board.Empty ->
      sliding_check_block_line_loop(
        board,
        river_squares,
        new_position,
        king_position,
        direction,
        [new_position, ..line],
      )
    _ -> []
  }
}

fn get_check_attack_squares(
  board: Board,
  river_squares,
  attacking: board.Color,
  king_position: Int,
) -> List(Int) {
  use squares, position, #(piece, colour) <- dict.fold(board, [])
  use <- bool.guard(colour != attacking, squares)

  case piece {
    board.Bishop ->
      get_sliding_check_attack_squares(
        board,
        river_squares,
        position,
        king_position,
        direction.bishop_directions,
        squares,
      )
    board.Queen ->
      get_sliding_check_attack_squares(
        board,
        river_squares,
        position,
        king_position,
        direction.queen_directions,
        squares,
      )
    board.Rook ->
      get_sliding_check_attack_squares(
        board,
        river_squares,
        position,
        king_position,
        direction.rook_directions,
        squares,
      )
    _ -> squares
  }
}

fn get_sliding_check_attack_squares(
  board: Board,
  river_squares,
  position: Int,
  king_position: Int,
  directions: List(Direction),
  squares: List(Int),
) -> List(Int) {
  case directions {
    [] -> squares
    [direction, ..directions] ->
      get_sliding_check_attack_squares(
        board,
        river_squares,
        position,
        king_position,
        directions,
        get_sliding_check_attack_squares_loop(
          board,
          river_squares,
          position,
          king_position,
          direction,
          squares,
        ),
      )
  }
}

fn get_sliding_check_attack_squares_loop(
  board: Board,
  river_squares,
  position: Int,
  king_position: Int,
  direction: Direction,
  squares: List(Int),
) -> List(Int) {
  let new_position = direction.in_direction(position, direction)

  case new_position == king_position {
    True ->
      case direction.in_direction(new_position, direction) {
        -1 -> squares
        position -> [position, ..squares]
      }
    False ->
      case board.get(board, river_squares, new_position) {
        board.Empty ->
          get_sliding_check_attack_squares_loop(
            board,
            river_squares,
            new_position,
            king_position,
            direction,
            squares,
          )

        _ -> squares
      }
  }
}

fn get_attacks(board: Board, river_squares: List(Int), attacking: Color) {
  use attacks, position, #(piece, color) <- dict.fold(board, [])
  case color == attacking {
    True ->
      get_attacks_for_piece(
        board,
        piece,
        position,
        attacking,
        attacks,
        river_squares,
      )
    False -> attacks
  }
}

fn get_attacks_for_piece(
  board: Board,
  piece: board.Piece,
  position: Int,
  color: Color,
  positions: List(Int),
  river_squares: List(Int),
) {
  case piece {
    board.Bishop ->
      get_sliding_attacks(
        board,
        river_squares,
        position,
        direction.bishop_directions,
        positions,
      )
    board.Rook ->
      get_sliding_attacks(
        board,
        river_squares,
        position,
        direction.rook_directions,
        positions,
      )
    board.Queen ->
      get_sliding_attacks(
        board,
        river_squares,
        position,
        direction.queen_directions,
        positions,
      )
    board.Pawn if color == board.Black ->
      get_single_move_attacks(
        position,
        positions,
        direction.black_pawn_captures,
      )
    board.Pawn ->
      get_single_move_attacks(
        position,
        positions,
        direction.white_pawn_captures,
      )
    board.Knight ->
      get_single_move_attacks(position, positions, direction.knight_directions)
    board.King ->
      get_single_move_attacks(position, positions, direction.queen_directions)
  }
}

fn get_sliding_attacks(
  board: Board,
  river_squares: List(Int),
  position: Int,
  directions: List(Direction),
  positions: List(Int),
) {
  case directions {
    [] -> positions
    [direction, ..directions] ->
      get_sliding_attacks(
        board,
        river_squares,
        position,
        directions,
        get_sliding_attacks_loop(
          board,
          river_squares,
          position,
          direction,
          positions,
        ),
      )
  }
}

fn get_sliding_attacks_loop(
  board: Board,
  river_squares: List(Int),
  position: Int,
  direction: Direction,
  positions: List(Int),
) -> List(Int) {
  let new_position = direction.in_direction(position, direction)

  case board.get(board, river_squares, new_position) {
    board.OffBoard -> positions
    board.Empty ->
      get_sliding_attacks_loop(board, river_squares, new_position, direction, [
        new_position,
        ..positions
      ])
    _ -> [new_position, ..positions]
  }
}

fn get_single_move_attacks(
  position: Int,
  positions: List(Int),
  directions: List(Direction),
) {
  case directions {
    [] -> positions
    [direction, ..directions] -> {
      let positions = case direction.in_direction(position, direction) {
        -1 -> positions
        position -> [position, ..positions]
      }
      get_single_move_attacks(position, positions, directions)
    }
  }
}

// (DE)SERIALIZATION ----------------------------------------------------------
pub fn attack_information_to_json(
  attack_information: AttackInformation,
) -> json.Json {
  let AttackInformation(
    in_check:,
    attacks:,
    check_attack_squares:,
    check_block_lines:,
    pin_lines:,
  ) = attack_information
  json.object([
    #("in_check", json.bool(in_check)),
    #("attacks", json.array(attacks, json.int)),
    #("check_attack_squares", json.array(check_attack_squares, json.int)),
    #("check_block_lines", json.array(check_block_lines, json.int)),
    #("pin_lines", json.dict(pin_lines, int.to_string, json.array(_, json.int))),
  ])
}

pub fn attack_information_decoder() -> decode.Decoder(AttackInformation) {
  use in_check <- decode.field("in_check", decode.bool)
  use attacks <- decode.field("attacks", decode.list(decode.int))
  use check_attack_squares <- decode.field(
    "check_attack_squares",
    decode.list(decode.int),
  )
  use check_block_lines <- decode.field(
    "check_block_lines",
    decode.list(decode.int),
  )
  use pin_lines <- decode.field(
    "pin_lines",
    decode.dict(decode.string, decode.list(decode.int)),
  )
  let pin_lines =
    dict.to_list(pin_lines)
    |> list.fold(dict.new(), fn(acc, v) {
      let #(pinned_piece, squares) = v

      case int.parse(pinned_piece) {
        Ok(pinned_piece) -> dict.insert(acc, pinned_piece, squares)
        Error(_) -> acc
      }
    })
  decode.success(AttackInformation(
    in_check:,
    attacks:,
    check_attack_squares:,
    check_block_lines:,
    pin_lines:,
  ))
}
