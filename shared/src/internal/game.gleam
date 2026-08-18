import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/option.{type Option, None}
import internal/board
import internal/hash
import internal/move/attack

pub type Game {
  Game(
    board: board.Board,
    board_variant: board.Variant,
    bridge_squares: List(Int),
    river_squares: List(Int),
    to_move: board.Color,
    castling: Castling,
    en_passant_square: Option(Int),
    half_moves: Int,
    full_moves: Int,
    zobrist_hash: Int,
    previous_positions: List(Int),
    attack_information: attack.AttackInformation,
    black_pieces: PieceInfo,
    white_pieces: PieceInfo,
    current_piece: Option(#(Int, Option(#(board.Piece, board.Color)))),
    current_piece_moves: List(Int),
    last_move: #(Int, Int),
  )
}

pub fn board_to_json(board: board.Board) {
  json.dict(board, int.to_string, fn(value) {
    let #(piece, color) = value
    json.preprocessed_array([
      board.piece_to_json(piece),
      board.color_to_json(color),
    ])
  })
}

pub fn board_decoder() -> decode.Decoder(board.Board) {
  let decoder = {
    use piece <- decode.field(1, board.piece_decoder())
    use color <- decode.field(0, board.color_decoder())
    decode.success(#(piece, color))
  }

  decode.dict(decode.int, decoder)
}

pub type Castling {
  Castling(
    white_kingside: Bool,
    white_queenside: Bool,
    black_kingside: Bool,
    black_queenside: Bool,
  )
}

pub fn castling_decoder() -> decode.Decoder(Castling) {
  use white_kingside <- decode.field("white_kingside", decode.bool)
  use white_queenside <- decode.field("white_queenside", decode.bool)
  use black_kingside <- decode.field("black_kingside", decode.bool)
  use black_queenside <- decode.field("black_queenside", decode.bool)
  decode.success(Castling(
    white_kingside:,
    white_queenside:,
    black_kingside:,
    black_queenside:,
  ))
}

pub fn castling_to_json(castling: Castling) -> json.Json {
  let Castling(
    white_kingside:,
    white_queenside:,
    black_kingside:,
    black_queenside:,
  ) = castling
  json.object([
    #("white_kingside", json.bool(white_kingside)),
    #("white_queenside", json.bool(white_queenside)),
    #("black_kingside", json.bool(black_kingside)),
    #("black_queenside", json.bool(black_queenside)),
  ])
}

pub type PieceInfo {
  PieceInfo(king_position: Int, non_pawn_material: Int, pawn_material: Int)
}

pub fn piece_info_to_json(piece_info: PieceInfo) -> json.Json {
  let PieceInfo(king_position:, non_pawn_material:, pawn_material:) = piece_info
  json.object([
    #("king_position", json.int(king_position)),
    #("non_pawn_material", json.int(non_pawn_material)),
    #("pawn_material", json.int(pawn_material)),
  ])
}

pub fn piece_info_decoder() -> decode.Decoder(PieceInfo) {
  use king_position <- decode.field("king_position", decode.int)
  use non_pawn_material <- decode.field("non_pawn_material", decode.int)
  use pawn_material <- decode.field("pawn_material", decode.int)
  decode.success(PieceInfo(king_position:, non_pawn_material:, pawn_material:))
}

pub const all_castling = Castling(True, True, True, True)

pub fn new() {
  let board = board.initial_position()
  // let board = board.testing_board()
  let white_king_position = 4
  let black_king_position = 68
  let attack_information =
    attack.calculate(board, white_king_position, board.White)
  let pawn_material = board.pawn_value * 8
  let non_pawn_material =
    board.bishop_value * 4 + board.rook_value * 2 + board.queen_value
  let zobrist_hash = hash.hash(board, board.White)

  Game(
    board:,
    to_move: board.White,
    castling: all_castling,
    current_piece_moves: [],
    current_piece: None,
    en_passant_square: None,
    attack_information:,
    half_moves: 0,
    full_moves: 1,
    black_pieces: PieceInfo(
      king_position: black_king_position,
      non_pawn_material:,
      pawn_material:,
    ),
    white_pieces: PieceInfo(
      king_position: white_king_position,
      non_pawn_material:,
      pawn_material:,
    ),
    zobrist_hash:,
    previous_positions: [],
    last_move: #(-1, -1),
    board_variant: board.TwoBridge,
    river_squares: board.river_square(board.TwoBridge),
    bridge_squares: board.bridge_square(board.TwoBridge),
  )
}

pub fn is_insufficient_material(game: Game) -> Bool {
  game.black_pieces.pawn_material == 0
  && game.white_pieces.pawn_material == 0
  && game.black_pieces.non_pawn_material <= board.bishop_value
  && game.white_pieces.non_pawn_material <= board.bishop_value
}

pub fn is_threefold_repetition(game: Game) -> Bool {
  is_threefold_repetition_loop(
    game.previous_positions,
    game.zobrist_hash,
    False,
  )
}

fn is_threefold_repetition_loop(
  positions: List(Int),
  position: Int,
  found: Bool,
) -> Bool {
  case positions {
    [] -> False
    [first, ..rest] if first == position ->
      case found {
        False -> is_threefold_repetition_loop(rest, position, True)
        True -> True
      }
    [_, ..rest] -> is_threefold_repetition_loop(rest, position, found)
  }
}
