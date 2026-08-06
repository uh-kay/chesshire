import gleam/dynamic/decode
import gleam/json

pub type Time {
  Time(
    black_time: Int,
    white_time: Int,
    black_tick: Int,
    white_tick: Int,
    started: Bool,
  )
}

pub const min_time = 0

pub const max_time = 600_000

pub fn new_time(now: Int) {
  Time(
    black_time: max_time,
    white_time: max_time,
    black_tick: now,
    white_tick: now,
    started: False,
  )
}

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
