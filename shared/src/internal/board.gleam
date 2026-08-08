import gleam/bool
import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/option.{Some}
import gleam/result

pub type Board =
  Dict(Int, #(Piece, Color))

pub type Piece {
  Pawn
  Knight
  Bishop
  Rook
  Queen
  King
}

pub fn piece_decoder() -> Decoder(Piece) {
  use variant <- decode.then(decode.string)
  case variant {
    "pawn" -> decode.success(Pawn)
    "knight" -> decode.success(Knight)
    "bishop" -> decode.success(Bishop)
    "rook" -> decode.success(Rook)
    "queen" -> decode.success(Queen)
    "king" -> decode.success(King)
    _ -> decode.failure(Pawn, "Piece")
  }
}

pub fn piece_to_json(piece: Piece) -> Json {
  case piece {
    Pawn -> json.string("pawn")
    Knight -> json.string("knight")
    Bishop -> json.string("bishop")
    Rook -> json.string("rook")
    Queen -> json.string("queen")
    King -> json.string("king")
  }
}

pub type Color {
  White
  Black
}

pub fn color_decoder() -> Decoder(Color) {
  use variant <- decode.then(decode.string)
  case variant {
    "white" -> decode.success(White)
    "black" -> decode.success(Black)
    _ -> decode.failure(White, "Color")
  }
}

pub fn color_to_json(color: Color) -> Json {
  case color {
    White -> json.string("white")
    Black -> json.string("black")
  }
}

pub type Square {
  Empty
  OffBoard
  Occupied(piece: Piece, color: Color)
}

pub const size = 72

pub fn get(board: Board, position: Int) {
  use <- bool.guard(position == -1, OffBoard)

  case dict.get(board, position) {
    Ok(#(piece, color)) -> Occupied(piece:, color:)
    Error(_) -> Empty
  }
}

pub fn initial_position() {
  dict.from_list(initial_squares)
}

pub fn position(file file: Int, rank rank: Int) {
  rank * 9 + file
}

pub fn file(position: Int) {
  position % 8
}

pub fn rank(position: Int) {
  position / 8
}

pub const pawn_promotions = [Queen, Knight, Bishop, Rook]

pub const river_square = [32, 34, 35, 36, 37, 39]

pub const bridge_square = [33, 38]

pub const pawn_value = 1

pub const knight_value = 3

pub const bishop_value = 3

pub const rook_value = 5

pub const queen_value = 9

pub const king_value = 9001

pub fn piece_value(piece: Piece) {
  case piece {
    Pawn -> pawn_value
    Knight -> knight_value
    Bishop -> bishop_value
    Rook -> rook_value
    Queen -> queen_value
    King -> king_value
  }
}

const initial_squares = [
  #(0, #(Rook, White)),
  #(1, #(Knight, White)),
  #(2, #(Bishop, White)),
  #(3, #(Queen, White)),
  #(4, #(King, White)),
  #(5, #(Bishop, White)),
  #(6, #(Knight, White)),
  #(7, #(Rook, White)),
  #(8, #(Pawn, White)),
  #(9, #(Pawn, White)),
  #(10, #(Pawn, White)),
  #(11, #(Pawn, White)),
  #(12, #(Pawn, White)),
  #(13, #(Pawn, White)),
  #(14, #(Pawn, White)),
  #(15, #(Pawn, White)),

  #(56, #(Pawn, Black)),
  #(57, #(Pawn, Black)),
  #(58, #(Pawn, Black)),
  #(59, #(Pawn, Black)),
  #(60, #(Pawn, Black)),
  #(61, #(Pawn, Black)),
  #(62, #(Pawn, Black)),
  #(63, #(Pawn, Black)),
  #(64, #(Rook, Black)),
  #(65, #(Knight, Black)),
  #(66, #(Bishop, Black)),
  #(67, #(Queen, Black)),
  #(68, #(King, Black)),
  #(69, #(Bishop, Black)),
  #(70, #(Knight, Black)),
  #(71, #(Rook, Black)),
]

pub fn position_to_string(position: Int) {
  let rank = int.to_string(rank(position) + 1)
  let file = case file(position) {
    0 -> "a"
    1 -> "b"
    2 -> "c"
    3 -> "d"
    4 -> "e"
    5 -> "f"
    6 -> "g"
    _ -> "h"
  }

  file <> rank
}

pub fn parse_position(fen: String) -> Result(#(Int, String), Nil) {
  use #(file, fen) <- result.try(case fen {
    "a" <> fen | "A" <> fen -> Ok(#(0, fen))
    "b" <> fen | "B" <> fen -> Ok(#(1, fen))
    "c" <> fen | "C" <> fen -> Ok(#(2, fen))
    "d" <> fen | "D" <> fen -> Ok(#(3, fen))
    "e" <> fen | "E" <> fen -> Ok(#(4, fen))
    "f" <> fen | "F" <> fen -> Ok(#(5, fen))
    "g" <> fen | "G" <> fen -> Ok(#(6, fen))
    "h" <> fen | "H" <> fen -> Ok(#(7, fen))
    _ -> Error(Nil)
  })

  use #(rank, fen) <- result.try(case fen {
    "1" <> fen -> Ok(#(0, fen))
    "2" <> fen -> Ok(#(1, fen))
    "3" <> fen -> Ok(#(2, fen))
    "4" <> fen -> Ok(#(3, fen))
    "5" <> fen -> Ok(#(4, fen))
    "6" <> fen -> Ok(#(5, fen))
    "7" <> fen -> Ok(#(6, fen))
    "8" <> fen -> Ok(#(7, fen))
    "9" <> fen -> Ok(#(8, fen))
    _ -> Error(Nil)
  })

  Ok(#(position(file, rank), fen))
}

pub type FenParseResult {
  FenParseResult(
    board: Board,
    remaining: String,
    board_is_complete: Bool,
    white_king_position: option.Option(Int),
    black_king_position: option.Option(Int),
    white_pawn_material: Int,
    black_pawn_material: Int,
    white_non_pawn_material: Int,
    black_non_pawn_material: Int,
  )
}

pub fn from_fen(fen: String) -> FenParseResult {
  from_fen_loop(fen, 0, 9, dict.new(), option.None, option.None, 0, 0, 0, 0)
}

fn from_fen_loop(
  fen: String,
  file: Int,
  rank: Int,
  board: Board,
  white_king_position: option.Option(Int),
  black_king_position: option.Option(Int),
  white_pawn_material: Int,
  black_pawn_material: Int,
  white_non_pawn_material: Int,
  black_non_pawn_material: Int,
) -> FenParseResult {
  let position = position(file, rank)

  case fen {
    "/" <> fen ->
      from_fen_loop(
        fen,
        0,
        rank - 1,
        board,
        white_king_position,
        black_king_position,
        white_pawn_material,
        black_pawn_material,
        white_non_pawn_material,
        black_non_pawn_material,
      )
    "0" <> fen ->
      from_fen_loop(
        fen,
        file,
        rank,
        board,
        white_king_position,
        black_king_position,
        white_pawn_material,
        black_pawn_material,
        white_non_pawn_material,
        black_non_pawn_material,
      )
    "1" <> fen ->
      from_fen_loop(
        fen,
        file + 1,
        rank,
        board,
        white_king_position,
        black_king_position,
        white_pawn_material,
        black_pawn_material,
        white_non_pawn_material,
        black_non_pawn_material,
      )
    "2" <> fen ->
      from_fen_loop(
        fen,
        file + 2,
        rank,
        board,
        white_king_position,
        black_king_position,
        white_pawn_material,
        black_pawn_material,
        white_non_pawn_material,
        black_non_pawn_material,
      )
    "3" <> fen ->
      from_fen_loop(
        fen,
        file + 3,
        rank,
        board,
        white_king_position,
        black_king_position,
        white_pawn_material,
        black_pawn_material,
        white_non_pawn_material,
        black_non_pawn_material,
      )
    "4" <> fen ->
      from_fen_loop(
        fen,
        file + 4,
        rank,
        board,
        white_king_position,
        black_king_position,
        white_pawn_material,
        black_pawn_material,
        white_non_pawn_material,
        black_non_pawn_material,
      )
    "5" <> fen ->
      from_fen_loop(
        fen,
        file + 5,
        rank,
        board,
        white_king_position,
        black_king_position,
        white_pawn_material,
        black_pawn_material,
        white_non_pawn_material,
        black_non_pawn_material,
      )
    "6" <> fen ->
      from_fen_loop(
        fen,
        file + 6,
        rank,
        board,
        white_king_position,
        black_king_position,
        white_pawn_material,
        black_pawn_material,
        white_non_pawn_material,
        black_non_pawn_material,
      )
    "7" <> fen ->
      from_fen_loop(
        fen,
        file + 7,
        rank,
        board,
        white_king_position,
        black_king_position,
        white_pawn_material,
        black_pawn_material,
        white_non_pawn_material,
        black_non_pawn_material,
      )
    "8" <> fen ->
      from_fen_loop(
        fen,
        file + 8,
        rank,
        board,
        white_king_position,
        black_king_position,
        white_pawn_material,
        black_pawn_material,
        white_non_pawn_material,
        black_non_pawn_material,
      )
    "9" <> fen ->
      from_fen_loop(
        fen,
        file + 9,
        rank,
        board,
        white_king_position,
        black_king_position,
        white_pawn_material,
        black_pawn_material,
        white_non_pawn_material,
        black_non_pawn_material,
      )
    "K" <> fen ->
      from_fen_loop(
        fen,
        file + 1,
        rank,
        dict.insert(board, position, #(King, White)),
        Some(position),
        black_king_position,
        white_pawn_material,
        black_pawn_material,
        white_non_pawn_material,
        black_non_pawn_material,
      )
    "Q" <> fen ->
      from_fen_loop(
        fen,
        file + 1,
        rank,
        dict.insert(board, position, #(Queen, White)),
        white_king_position,
        black_king_position,
        white_pawn_material,
        black_pawn_material,
        white_non_pawn_material + queen_value,
        black_non_pawn_material,
      )
    "B" <> fen ->
      from_fen_loop(
        fen,
        file + 1,
        rank,
        dict.insert(board, position, #(Bishop, White)),
        white_king_position,
        black_king_position,
        white_pawn_material,
        black_pawn_material,
        white_non_pawn_material + bishop_value,
        black_non_pawn_material,
      )
    "N" <> fen ->
      from_fen_loop(
        fen,
        file + 1,
        rank,
        dict.insert(board, position, #(Knight, White)),
        white_king_position,
        black_king_position,
        white_pawn_material,
        black_pawn_material,
        white_non_pawn_material + knight_value,
        black_non_pawn_material,
      )
    "R" <> fen ->
      from_fen_loop(
        fen,
        file + 1,
        rank,
        dict.insert(board, position, #(Rook, White)),
        white_king_position,
        black_king_position,
        white_pawn_material,
        black_pawn_material,
        white_non_pawn_material + rook_value,
        black_non_pawn_material,
      )
    "P" <> fen ->
      from_fen_loop(
        fen,
        file + 1,
        rank,
        dict.insert(board, position, #(Pawn, White)),
        white_king_position,
        black_king_position,
        white_pawn_material + pawn_value,
        black_pawn_material,
        white_non_pawn_material,
        black_non_pawn_material,
      )
    "k" <> fen ->
      from_fen_loop(
        fen,
        file + 1,
        rank,
        dict.insert(board, position, #(King, Black)),
        white_king_position,
        Some(position),
        white_pawn_material,
        black_pawn_material,
        white_non_pawn_material,
        black_non_pawn_material,
      )
    "q" <> fen ->
      from_fen_loop(
        fen,
        file + 1,
        rank,
        dict.insert(board, position, #(Queen, Black)),
        white_king_position,
        black_king_position,
        white_pawn_material,
        black_pawn_material,
        white_non_pawn_material,
        black_non_pawn_material + queen_value,
      )
    "b" ->
      from_fen_loop(
        fen,
        file + 1,
        rank,
        dict.insert(board, position, #(Bishop, Black)),
        white_king_position,
        black_king_position,
        white_pawn_material,
        black_pawn_material,
        white_non_pawn_material,
        black_non_pawn_material + bishop_value,
      )
    "n" ->
      from_fen_loop(
        fen,
        file + 1,
        rank,
        dict.insert(board, position, #(Knight, Black)),
        white_king_position,
        black_king_position,
        white_pawn_material,
        black_pawn_material,
        white_non_pawn_material,
        black_non_pawn_material + knight_value,
      )
    "r" ->
      from_fen_loop(
        fen,
        file + 1,
        rank,
        dict.insert(board, position, #(Rook, Black)),
        white_king_position,
        black_king_position,
        white_pawn_material,
        black_pawn_material,
        white_non_pawn_material,
        black_non_pawn_material + rook_value,
      )
    "p" ->
      from_fen_loop(
        fen,
        file + 1,
        rank,
        dict.insert(board, position, #(Pawn, Black)),
        white_king_position,
        black_king_position,
        white_pawn_material,
        black_pawn_material + pawn_value,
        white_non_pawn_material,
        black_non_pawn_material,
      )
    _ ->
      FenParseResult(
        board:,
        remaining: fen,
        board_is_complete: position == 9,
        white_king_position:,
        black_king_position:,
        white_pawn_material:,
        black_pawn_material:,
        white_non_pawn_material:,
        black_non_pawn_material:,
      )
  }
}

pub fn to_fen(board: Board) -> String {
  do_to_fen(board, 0, 9 - 1, 0, "")
}

fn do_to_fen(board: Board, file: Int, rank: Int, empty: Int, fen: String) {
  use <- bool.lazy_guard(file >= 9, fn() {
    case rank == 0 {
      True -> maybe_add_empty(fen, empty)
      False ->
        do_to_fen(board, 0, rank - 1, 0, maybe_add_empty(fen, empty) <> "/")
    }
  })

  let position = position(file:, rank:)

  case get(board, position) {
    Empty -> do_to_fen(board, file + 1, rank, empty + 1, fen)
    Occupied(piece:, color:) -> {
      let fen = maybe_add_empty(fen, empty)

      let fen = case piece, color {
        Pawn, White -> fen <> "P"
        Knight, White -> fen <> "N"
        Bishop, White -> fen <> "B"
        Rook, White -> fen <> "R"
        Queen, White -> fen <> "Q"
        King, White -> fen <> "K"
        Pawn, Black -> fen <> "p"
        Knight, Black -> fen <> "n"
        Bishop, Black -> fen <> "b"
        Rook, Black -> fen <> "r"
        Queen, Black -> fen <> "q"
        King, Black -> fen <> "k"
      }

      do_to_fen(board, file + 1, rank, 0, fen)
    }
    OffBoard -> maybe_add_empty(fen, empty)
  }
}

fn maybe_add_empty(fen: String, empty: Int) {
  case empty {
    0 -> fen
    _ -> fen <> int.to_string(empty)
  }
}
