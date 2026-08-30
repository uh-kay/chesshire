import gleam/bool
import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import internal/board.{type Piece}
import internal/game
import internal/move
import internal/move/attack
import shared

fn game_to_json(game: Game) -> json.Json {
  let game.Game(
    board:,
    to_move:,
    castling:,
    en_passant_square:,
    half_moves:,
    full_moves:,
    zobrist_hash:,
    previous_positions:,
    attack_information:,
    black_pieces:,
    white_pieces:,
    current_piece:,
    current_piece_moves:,
    last_move:,
    board_variant:,
    river_squares:,
    bridge_squares:,
    game_variant:,
  ) = game.game
  json.object([
    #(
      "board",
      json.dict(board, int.to_string, fn(value) {
        json.preprocessed_array([
          board.piece_to_json(value.0),
          board.color_to_json(value.1),
        ])
      }),
    ),
    #("to_move", board.color_to_json(to_move)),
    #("castling", game.castling_to_json(castling)),
    #("en_passant_square", case en_passant_square {
      None -> json.null()
      option.Some(value) -> json.int(value)
    }),
    #("half_moves", json.int(half_moves)),
    #("full_moves", json.int(full_moves)),
    #("zobrist_hash", json.int(zobrist_hash)),
    #("previous_positions", json.array(previous_positions, json.int)),
    #(
      "attack_information",
      attack.attack_information_to_json(attack_information),
    ),
    #("black_pieces", game.piece_info_to_json(black_pieces)),
    #("white_pieces", game.piece_info_to_json(white_pieces)),
    #("current_piece", case current_piece {
      None -> json.null()
      option.Some(value) ->
        json.preprocessed_array([
          json.int(value.0),
          case value.1 {
            None -> json.null()
            option.Some(value) ->
              json.preprocessed_array([
                board.piece_to_json(value.0),
                board.color_to_json(value.1),
              ])
          },
        ])
    }),
    #("current_piece_moves", json.array(current_piece_moves, json.int)),
    #(
      "last_move",
      json.preprocessed_array([json.int(last_move.0), json.int(last_move.1)]),
    ),
    #("board_variant", board.variant_to_json(board_variant)),
    #("river_squares", json.array(river_squares, json.int)),
    #("bridge_squares", json.array(bridge_squares, json.int)),
    #("game_variant", game.game_variant_to_json(game_variant)),
  ])
}

fn game_decoder() -> decode.Decoder(Game) {
  use board <- decode.field(
    "board",
    decode.dict(decode.string, {
      use a <- decode.field(0, board.piece_decoder())
      use b <- decode.field(1, board.color_decoder())

      decode.success(#(a, b))
    }),
  )
  let board =
    dict.to_list(board)
    |> list.fold(dict.new(), fn(acc, v) {
      let #(pos, piece) = v

      case int.parse(pos) {
        Ok(pos) -> dict.insert(acc, pos, piece)
        Error(_) -> acc
      }
    })
  use to_move <- decode.field("to_move", board.color_decoder())
  use castling <- decode.field("castling", game.castling_decoder())
  use en_passant_square <- decode.field(
    "en_passant_square",
    decode.optional(decode.int),
  )
  use half_moves <- decode.field("half_moves", decode.int)
  use full_moves <- decode.field("full_moves", decode.int)
  use zobrist_hash <- decode.field("zobrist_hash", decode.int)
  use previous_positions <- decode.field(
    "previous_positions",
    decode.list(decode.int),
  )
  use attack_information <- decode.field(
    "attack_information",
    attack.attack_information_decoder(),
  )
  use black_pieces <- decode.field("black_pieces", game.piece_info_decoder())
  use white_pieces <- decode.field("white_pieces", game.piece_info_decoder())
  use current_piece <- decode.field(
    "current_piece",
    decode.optional({
      use a <- decode.field(0, decode.int)
      use b <- decode.field(
        1,
        decode.optional({
          use a <- decode.field(0, board.piece_decoder())
          use b <- decode.field(1, board.color_decoder())

          decode.success(#(a, b))
        }),
      )

      decode.success(#(a, b))
    }),
  )
  use current_piece_moves <- decode.field(
    "current_piece_moves",
    decode.list(decode.int),
  )
  use last_move <- decode.field("last_move", {
    use from <- decode.field(0, decode.int)
    use to <- decode.field(1, decode.int)
    decode.success(#(from, to))
  })
  use board_variant <- decode.field("board_variant", board.variant_decoder())
  use river_squares <- decode.field("river_squares", decode.list(decode.int))
  use bridge_squares <- decode.field("bridge_squares", decode.list(decode.int))
  use game_variant <- decode.field("game_variant", game.game_variant_decoder())
  decode.success(
    Game(game.Game(
      board:,
      to_move:,
      castling:,
      en_passant_square:,
      half_moves:,
      full_moves:,
      zobrist_hash:,
      previous_positions:,
      attack_information:,
      black_pieces:,
      white_pieces:,
      current_piece:,
      current_piece_moves:,
      last_move:,
      board_variant:,
      river_squares:,
      bridge_squares:,
      game_variant:,
    )),
  )
}

pub opaque type Game {
  Game(game: game.Game)
}

pub opaque type Move {
  Move(move: move.Move)
}

@internal
pub fn get_move(move: Move) -> move.Move {
  move.move
}

pub type GameState {
  Continue
  Draw(reason: DrawReason)
  WhiteWin
  BlackWin
}

pub fn get_full_moves(game: Game) {
  game.game.full_moves
}

pub fn game_state_to_json(game_state: GameState) -> Json {
  case game_state {
    Continue ->
      json.object([
        #("type", json.string("continue")),
      ])
    Draw(reason:) ->
      json.object([
        #("type", json.string("draw")),
        #("reason", draw_reason_to_json(reason)),
      ])
    WhiteWin ->
      json.object([
        #("type", json.string("white_win")),
      ])
    BlackWin ->
      json.object([
        #("type", json.string("black_win")),
      ])
  }
}

pub fn game_state_decoder() -> Decoder(GameState) {
  use variant <- decode.field("type", decode.string)
  case variant {
    "continue" -> decode.success(Continue)
    "draw" -> {
      use reason <- decode.field("reason", draw_reason_decoder())
      decode.success(Draw(reason:))
    }
    "white_win" -> decode.success(WhiteWin)
    "black_win" -> decode.success(BlackWin)
    _ -> decode.failure(Continue, "GameState")
  }
}

pub type DrawReason {
  ThreefoldRepetition
  InsufficientMaterial
  Stalemate
  FiftyMoves
}

fn draw_reason_to_json(draw_reason: DrawReason) -> Json {
  case draw_reason {
    ThreefoldRepetition -> json.string("threefold_repetition")
    InsufficientMaterial -> json.string("insufficient_material")
    Stalemate -> json.string("stalemate")
    FiftyMoves -> json.string("fifty_moves")
  }
}

fn draw_reason_decoder() -> Decoder(DrawReason) {
  use variant <- decode.then(decode.string)
  case variant {
    "threefold_repetition" -> decode.success(ThreefoldRepetition)
    "insufficient_material" -> decode.success(InsufficientMaterial)
    "stalemate" -> decode.success(Stalemate)
    "fifty_moves" -> decode.success(FiftyMoves)
    _ -> decode.failure(ThreefoldRepetition, "DrawReason")
  }
}

pub fn state(game: Game) -> GameState {
  let game = game.game

  use <- bool.guard(game.half_moves >= 50, Draw(FiftyMoves))
  use <- bool.guard(
    game.is_insufficient_material(game),
    Draw(InsufficientMaterial),
  )
  use <- bool.guard(
    game.is_threefold_repetition(game),
    Draw(ThreefoldRepetition),
  )
  use <- bool.guard(move.any_legal(game), Continue)
  use <- bool.guard(!game.attack_information.in_check, Draw(Stalemate))
  case game.to_move {
    board.White -> BlackWin
    board.Black -> WhiteWin
  }
}

pub fn new() -> Game {
  Game(game.new())
}

pub fn apply_move(game: Game, move: Move) -> Game {
  Game(move.apply(game.game, move.move))
}

pub fn in_check(game: Game) {
  game.game.attack_information.in_check
}

pub type PieceType {
  Pawn
  Knight
  Bishop
  Rook
  Queen
  King
}

pub type Color {
  Black
  White
}

fn color_to_json(color: Color) -> Json {
  case color {
    Black -> json.string("black")
    White -> json.string("white")
  }
}

fn color_decoder() -> Decoder(Color) {
  use variant <- decode.then(decode.string)
  case variant {
    "black" -> decode.success(Black)
    "white" -> decode.success(White)
    _ -> decode.failure(Black, "Color")
  }
}

pub fn board(game: Game) -> Dict(Int, #(PieceType, Color)) {
  dict.map_values(game.game.board, fn(_, v) {
    let #(piece, color) = v
    let piece = piece_to_piece_type(piece)
    let color = color_to_piece_color(color)
    #(piece, color)
  })
}

pub fn piece_to_piece_type(piece: Piece) -> PieceType {
  case piece {
    board.Pawn -> Pawn
    board.Knight -> Knight
    board.Bishop -> Bishop
    board.Rook -> Rook
    board.Queen -> Queen
    board.King -> King
  }
}

pub fn color_to_piece_color(color: board.Color) -> Color {
  case color {
    board.White -> White
    board.Black -> Black
  }
}

pub fn move_to(move: Move) -> Int {
  move.move.to
}

pub type Role {
  Host
  Guest
  Spectator
}

pub fn role_decoder() -> Decoder(Role) {
  use variant <- decode.then(decode.string)
  case variant {
    "host" -> decode.success(Host)
    "guest" -> decode.success(Guest)
    "spectator" -> decode.success(Spectator)
    _ -> decode.failure(Host, "Role")
  }
}

pub fn role_to_json(role: Role) -> Json {
  case role {
    Host -> json.string("host")
    Guest -> json.string("guest")
    Spectator -> json.string("spectator")
  }
}

pub fn role(game: Game) -> Role {
  case game.game.to_move {
    board.White -> Host
    board.Black -> Guest
  }
}

pub fn to_move(game: Game) -> Color {
  case game.game.to_move {
    board.White -> White
    board.Black -> Black
  }
}

pub fn legal_moves(game: Game) -> List(Move) {
  list.map(move.legal(game.game), Move)
}

pub fn last_move(game: Game) -> #(Int, Int) {
  game.game.last_move
}

pub fn legal_moves_for_piece(game: Game, pos: Int) -> List(Move) {
  let board = game.game.board
  let to_move = game.game.to_move
  let king_position = case to_move {
    board.White -> game.game.white_pieces.king_position
    board.Black -> game.game.black_pieces.king_position
  }

  // Update attack information first before getting moves to make sure the moves
  // are correct.
  let game =
    Game(
      game: game.Game(
        ..game.game,
        attack_information: attack.calculate(
          board,
          king_position,
          to_move,
          game.game.river_squares,
        ),
      ),
    )

  list.filter(legal_moves(game), fn(move) { move.move.from == pos })
}

pub type JoinModel {
  JoinModel(board: Dict(Int, #(PieceType, Color)), role: Role)
}

pub type GameView {
  GameView(
    game: Game,
    role: Role,
    game_state: GameState,
    time: shared.Time,
    guest_joined: Bool,
    player_color: Option(Color),
    lobby_id: String,
  )
}

pub fn game_view_to_json(game_view: GameView) -> Json {
  let GameView(
    game:,
    role:,
    game_state:,
    time:,
    guest_joined:,
    player_color:,
    lobby_id:,
  ) = game_view
  json.object([
    #("game", game_to_json(game)),
    #("role", role_to_json(role)),
    #("game_state", game_state_to_json(game_state)),
    #("time", shared.time_to_json(time)),
    #("guest_joined", json.bool(guest_joined)),
    #("player_color", json.nullable(player_color, color_to_json)),
    #("lobby_id", json.string(lobby_id)),
  ])
}

pub fn game_view_decoder() -> Decoder(GameView) {
  use game <- decode.field("game", game_decoder())
  use role <- decode.field("role", role_decoder())
  use game_state <- decode.field("game_state", game_state_decoder())
  use time <- decode.field("time", shared.time_decoder())
  use guest_joined <- decode.field("guest_joined", decode.bool)
  use player_color <- decode.field(
    "player_color",
    decode.optional(color_decoder()),
  )
  use lobby_id <- decode.field("lobby_id", decode.string)
  decode.success(GameView(
    game:,
    role:,
    game_state:,
    time:,
    guest_joined:,
    player_color:,
    lobby_id:,
  ))
}

pub fn move_to_json(move: Move) -> Json {
  case move.move {
    move.Castle(from:, to:) ->
      json.object([
        #("type", json.string("castle")),
        #("from", json.int(from)),
        #("to", json.int(to)),
      ])
    move.Move(from:, to:, piece:) ->
      json.object([
        #("type", json.string("move")),
        #("from", json.int(from)),
        #("to", json.int(to)),
        #("piece", board.piece_to_json(piece)),
      ])
    move.Capture(from:, to:, piece:, captured_piece:) ->
      json.object([
        #("type", json.string("capture")),
        #("from", json.int(from)),
        #("to", json.int(to)),
        #("piece", board.piece_to_json(piece)),
        #("captured_piece", board.piece_to_json(captured_piece)),
      ])
    move.EnPassant(from:, to:) ->
      json.object([
        #("type", json.string("en_passant")),
        #("from", json.int(from)),
        #("to", json.int(to)),
      ])
    move.Promotion(from:, to:, piece:, captured_piece:) ->
      json.object([
        #("type", json.string("promotion")),
        #("from", json.int(from)),
        #("to", json.int(to)),
        #("piece", board.piece_to_json(piece)),
        #("captured_piece", case captured_piece {
          None -> json.null()
          Some(value) -> board.piece_to_json(value)
        }),
      ])
  }
}

pub fn move_decoder() -> decode.Decoder(Move) {
  use variant <- decode.field("type", decode.string)
  case variant {
    "castle" -> {
      use from <- decode.field("from", decode.int)
      use to <- decode.field("to", decode.int)
      decode.success(Move(move.Castle(from:, to:)))
    }
    "move" -> {
      use from <- decode.field("from", decode.int)
      use to <- decode.field("to", decode.int)
      use piece <- decode.field("piece", board.piece_decoder())
      decode.success(Move(move.Move(from:, to:, piece:)))
    }
    "capture" -> {
      use from <- decode.field("from", decode.int)
      use to <- decode.field("to", decode.int)
      use piece <- decode.field("piece", board.piece_decoder())
      use captured_piece <- decode.field(
        "captured_piece",
        board.piece_decoder(),
      )
      decode.success(Move(move.Capture(from:, to:, piece:, captured_piece:)))
    }
    "en_passant" -> {
      use from <- decode.field("from", decode.int)
      use to <- decode.field("to", decode.int)
      decode.success(Move(move.EnPassant(from:, to:)))
    }
    "promotion" -> {
      use from <- decode.field("from", decode.int)
      use to <- decode.field("to", decode.int)
      use piece <- decode.field("piece", board.piece_decoder())
      use captured_piece <- decode.field(
        "captured_piece",
        decode.optional(board.piece_decoder()),
      )
      decode.success(Move(move.Promotion(from:, to:, piece:, captured_piece:)))
    }
    _ -> decode.failure(Move(move.Castle(from: 0, to: 0)), "Move")
  }
}

pub fn river_squares(game: Game) {
  game.game.river_squares
}

pub fn bridge_squares(game: Game) {
  game.game.bridge_squares
}
