import gleam/dynamic/decode
import gleam/json

pub const min_time = 0

pub const max_time = 600_000

pub type Time {
  Time(
    black_time: Int,
    white_time: Int,
    black_tick: Int,
    white_tick: Int,
    started: Bool,
  )
}

pub fn new_time(now: Int) {
  Time(
    black_time: max_time,
    white_time: max_time,
    black_tick: now,
    white_tick: now,
    started: False,
  )
}

pub type CreateGame {
  CreateGame(
    is_public: Bool,
    board_variant: BoardVariant,
    game_variant: GameVariant,
    host_side: PlayerColor,
  )
}

pub type BoardVariant {
  TwinPasses
  GreatCrossing
}

pub type GameVariant {
  RiverSacrifice
  FlemishGiant
}

pub type PlayerColor {
  Black
  White
}

@external(erlang, "shared_ffi", "monotonic_time")
@external(javascript, "./shared.ffi.mjs", "monotonic_time")
pub fn monotonic_time() -> Int

// (DE)SERIALIZATION ----------------------------------------------------------
pub fn time_to_json(time: Time) -> json.Json {
  let Time(black_time:, white_time:, black_tick:, white_tick:, started:) = time
  json.object([
    #("black_time", json.int(black_time)),
    #("white_time", json.int(white_time)),
    #("black_tick", json.int(black_tick)),
    #("white_tick", json.int(white_tick)),
    #("started", json.bool(started)),
  ])
}

pub fn time_decoder() -> decode.Decoder(Time) {
  use black_time <- decode.field("black_time", decode.int)
  use white_time <- decode.field("white_time", decode.int)
  use black_tick <- decode.field("black_tick", decode.int)
  use white_tick <- decode.field("white_tick", decode.int)
  use started <- decode.field("started", decode.bool)
  decode.success(Time(
    black_time:,
    white_time:,
    black_tick:,
    white_tick:,
    started:,
  ))
}

pub fn create_game_to_json(create_game: CreateGame) -> json.Json {
  let CreateGame(is_public:, board_variant:, game_variant:, host_side:) =
    create_game
  json.object([
    #("is_public", json.bool(is_public)),
    #("board_variant", board_variant_to_json(board_variant)),
    #("game_variant", game_variant_to_json(game_variant)),
    #("host_side", player_color_to_json(host_side)),
  ])
}

pub fn create_game_decoder() -> decode.Decoder(CreateGame) {
  use is_public <- decode.field("is_public", decode.bool)
  use board_variant <- decode.field("board_variant", board_variant_decoder())
  use game_variant <- decode.field("game_variant", game_variant_decoder())
  use host_side <- decode.field("host_side", player_color_decoder())
  decode.success(CreateGame(
    is_public,
    board_variant:,
    game_variant:,
    host_side:,
  ))
}

fn board_variant_to_json(board_variant: BoardVariant) -> json.Json {
  case board_variant {
    TwinPasses -> json.string("two_bridge")
    GreatCrossing -> json.string("middle_bridge")
  }
}

fn board_variant_decoder() -> decode.Decoder(BoardVariant) {
  use variant <- decode.then(decode.string)
  case variant {
    "two_bridge" -> decode.success(TwinPasses)
    "middle_bridge" -> decode.success(GreatCrossing)
    _ -> decode.failure(TwinPasses, "BoardVariant")
  }
}

fn game_variant_to_json(game_variant: GameVariant) -> json.Json {
  case game_variant {
    RiverSacrifice -> json.string("river_sacrifice")
    FlemishGiant -> json.string("flemish_giant")
  }
}

fn game_variant_decoder() -> decode.Decoder(GameVariant) {
  use variant <- decode.then(decode.string)
  case variant {
    "river_sacrifice" -> decode.success(RiverSacrifice)
    "flemish_giant" -> decode.success(FlemishGiant)
    _ -> decode.failure(RiverSacrifice, "GameVariant")
  }
}

fn player_color_to_json(player_color: PlayerColor) -> json.Json {
  case player_color {
    Black -> json.string("black")
    White -> json.string("white")
  }
}

fn player_color_decoder() -> decode.Decoder(PlayerColor) {
  use variant <- decode.then(decode.string)
  case variant {
    "black" -> decode.success(Black)
    "white" -> decode.success(White)
    _ -> decode.failure(Black, "PlayerColor")
  }
}
