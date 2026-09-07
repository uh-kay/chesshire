import cheg
import client/component
import client/icon
import client/websocket
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/uri
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import modem
import plinth/browser/clipboard
import plinth/browser/location
import plinth/browser/window
import shared

// MODEL ----------------------------------------------------------------------

pub type Model {
  Model(
    game: cheg.Game,
    guest_joined: Bool,
    link_copied: Bool,
    current_piece_moves: List(cheg.Move),
    player_color: Option(shared.PlayerColor),
    time: shared.Time,
    role: Option(cheg.Role),
    game_state: cheg.GameState,
    current_page_uri: Option(uri.Uri),
    websocket: Option(websocket.Websocket),
    current_piece: Option(#(Int, Option(#(cheg.PieceType, shared.PlayerColor)))),
    offset: Int,
    lobby_id: String,
    is_public: Bool,
  )
}

pub type Websocket

pub type Message {
  ComponentProducedMessage(component.Message)
  UserClickedCopyLink(lobby_url: String)
  TimerExpired
  ServerUpdatedGame(body: String)
  ClockTickedForward
  ClockStoppedTicking
}

pub fn init(
  current_page_uri: Option(uri.Uri),
  websocket: Option(websocket.Websocket),
  lobby_id: String,
) -> #(Model, Effect(Message)) {
  let game = cheg.new(shared.TwinPasses, shared.RiverSacrifice)
  let time = shared.new_time(shared.monotonic_time())

  let init_message = case websocket {
    Some(websocket) -> {
      let message = websocket.receive_message(websocket)
      Some(message)
    }
    None -> None
  }

  let model =
    Model(
      game:,
      guest_joined: False,
      link_copied: False,
      current_piece_moves: [],
      player_color: None,
      time:,
      role: None,
      game_state: cheg.Continue,
      current_page_uri:,
      websocket:,
      current_piece: None,
      // in the future calculate based on latency
      offset: 0,
      lobby_id:,
      is_public: False,
    )
  let effect = get_game_view(init_message)

  #(model, effect)
}

// UPDATE ---------------------------------------------------------------------

pub fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case message {
    ComponentProducedMessage(component.UserClickedSquare(piece:, position:)) -> {
      let current_piece_moves = case model.player_color {
        Some(player_color) -> {
          let to_move = cheg.to_move(model.game)

          case piece {
            Some(#(_, piece_color))
              if player_color == to_move
              && player_color == piece_color
              && model.game_state == cheg.Continue
            -> cheg.legal_moves_for_piece(model.game, position)
            _ -> []
          }
        }
        None -> []
      }

      let model = Model(..model, current_piece_moves:)
      let effect = effect.none()

      #(model, effect)
    }
    ComponentProducedMessage(component.UserClickedTargetSquare(move:)) -> {
      let message = cheg.move_to_json(move) |> json.to_string
      let game = cheg.apply_move(model.game, move)

      case model.websocket {
        Some(ws) -> websocket.send_message(ws, message)
        None -> Nil
      }

      let model =
        Model(..model, game:, current_piece: None, current_piece_moves: [])
      let effect = effect.none()

      #(model, effect)
    }
    UserClickedCopyLink(lobby_url:) -> {
      let model = Model(..model, link_copied: True)
      let effect = effect.batch([copy_link(lobby_url), reset_timer(1000)])

      #(model, effect)
    }
    TimerExpired -> #(Model(..model, link_copied: False), effect.none())
    ServerUpdatedGame(body:) -> {
      case json.parse(body, cheg.game_view_decoder()) {
        Ok(game_view) -> {
          let black_tick = case cheg.to_move(game_view.game) {
            shared.Black -> shared.monotonic_time()
            shared.White -> model.time.black_tick
          }
          let white_tick = case cheg.to_move(game_view.game) {
            shared.Black -> model.time.white_tick
            shared.White -> shared.monotonic_time()
          }

          let effect =
            effect.batch([
              case game_view.game_state != cheg.Continue {
                True -> stop_clock()
                False -> listen(model.websocket)
              },
              case game_view.guest_joined {
                False -> {
                  modem.push("/game/" <> game_view.lobby_id, None, None)
                }
                _ -> effect.none()
              },
            ])
          let model =
            Model(
              ..model,
              game: game_view.game,
              time: shared.Time(..game_view.time, black_tick:, white_tick:),
              guest_joined: game_view.guest_joined,
              role: Some(game_view.role),
              game_state: game_view.game_state,
              player_color: game_view.player_color,
              is_public: game_view.is_public,
            )

          #(model, effect)
        }
        Error(_) -> #(model, effect.none())
      }
    }
    ClockTickedForward -> {
      let offset = model.offset

      let #(time, effect) = case cheg.to_move(model.game), model.time.started {
        shared.Black, True -> {
          let black_tick = shared.monotonic_time()
          let black_time =
            current_time(model.time.black_time, model.time.black_tick, offset)

          let effect = case black_time <= 0 {
            True -> stop_clock()
            False -> tick()
          }
          #(shared.Time(..model.time, black_time:, black_tick:), effect)
        }
        shared.White, True -> {
          let white_tick = shared.monotonic_time()
          let white_time =
            current_time(model.time.white_time, model.time.white_tick, offset)
          let effect = case white_time <= 0 {
            True -> stop_clock()
            False -> tick()
          }

          #(shared.Time(..model.time, white_time:, white_tick:), effect)
        }
        _, _ -> #(model.time, tick())
      }
      let model = Model(..model, time:)

      #(model, effect)
    }
    ClockStoppedTicking -> {
      let black_time =
        int.clamp(model.time.black_time, shared.min_time, shared.max_time)
      let white_time =
        int.clamp(model.time.white_time, shared.min_time, shared.max_time)

      let game_state = case model.game_state == cheg.Continue, black_time <= 0 {
        True, True -> cheg.WhiteWin
        True, False -> cheg.BlackWin
        _, _ -> model.game_state
      }

      let model =
        Model(
          ..model,
          time: shared.Time(
            ..model.time,
            black_time:,
            white_time:,
            started: False,
          ),
          game_state:,
        )
      let effect = effect.none()

      #(model, effect)
    }
  }
}

fn current_time(remaining: Int, tick: Int, offset: Int) -> Int {
  let elapsed = shared.monotonic_time() + offset - tick
  remaining - elapsed
}

// EFFECTS --------------------------------------------------------------------

fn copy_link(lobby_url: String) -> Effect(Message) {
  effect.from(fn(_) {
    promise.tap(clipboard.write_text(lobby_url), fn(_) { Nil })
    Nil
  })
}

fn reset_timer(duration: Int) -> Effect(Message) {
  use dispatch <- effect.from
  use <- set_timeout(duration)

  dispatch(TimerExpired)
}

fn get_game_view(init_msg: Option(Promise(String))) -> Effect(Message) {
  effect.from(fn(dispatch) {
    case init_msg {
      Some(init_msg) -> {
        promise.tap(init_msg, fn(msg) {
          case json.parse(msg, cheg.game_view_decoder()) {
            Ok(_) -> dispatch(ServerUpdatedGame(msg))
            Error(_) -> Nil
          }
        })
      }
      None -> promise.resolve("")
    }

    Nil
  })
}

fn listen(ws: Option(websocket.Websocket)) -> Effect(Message) {
  case ws {
    Some(ws) ->
      effect.from(fn(dispatch) {
        promise.tap(websocket.receive_message(ws), fn(msg) {
          dispatch(ServerUpdatedGame(body: msg))
        })

        Nil
      })
    None -> effect.none()
  }
}

fn tick() -> Effect(Message) {
  use dispatch <- effect.from
  use <- set_timeout(1000)

  dispatch(ClockTickedForward)
}

fn stop_clock() -> Effect(Message) {
  use dispatch <- effect.from

  dispatch(ClockStoppedTicking)
}

// EXTERNALS ------------------------------------------------------------------

@external(javascript, "../client.ffi.mjs", "protocol")
fn protocol(location: location.Location) -> String

@external(javascript, "../client.ffi.mjs", "set_timeout")
fn set_timeout(delay: Int, cb: fn() -> a) -> Nil

// VIEW -----------------------------------------------------------------------

pub fn view(model: Model) -> Element(Message) {
  let lobby_url = case model.current_page_uri {
    Some(uri) -> uri.to_string(uri)
    None -> ""
  }

  case model.guest_joined, model.is_public {
    False, False -> {
      let content =
        html.div([attribute.class("mx-auto max-w-xl p-8")], [
          html.p([], [
            html.text("Send this link to invite someone to play:"),
          ]),
          html.div([attribute.class("mt-4 flex")], [
            html.p(
              [
                attribute.class("p-2 border-y-2 border-l-2 w-fit rounded-l"),
                attribute.class("border-blue-500"),
              ],
              [html.text(lobby_url)],
            ),
            html.button(
              [
                attribute.class("rounded-r-md p-2 cursor-pointer"),
                attribute.class("bg-blue-500 text-white"),
                attribute.class("hover:bg-blue-600"),
                event.on_click(UserClickedCopyLink(lobby_url)),
              ],
              [
                case model.link_copied {
                  True -> icon.check()
                  False -> icon.clipboard()
                },
              ],
            ),
          ]),
        ])

      layout(content)
    }
    False, True -> {
      let content =
        html.p(
          [
            attribute.class("pt-8 px-3 md:p-8 max-w-fit mx-auto"),
            attribute.class("flex flex-col md:flex-row text-xl"),
          ],
          [
            html.text("Waiting for someone to join"),
            html.span([attribute.class("ellipsis")], [
              html.text("..."),
            ]),
          ],
        )

      layout(content)
    }
    True, _ -> {
      let content =
        html.div(
          [
            attribute.class("pt-8 px-3 md:p-8 max-w-fit mx-auto"),
            attribute.class("flex flex-col md:flex-row"),
          ],
          [
            component.game_view(component.Model(
              game: model.game,
              moves: model.current_piece_moves,
              player_color: model.player_color,
            ))
              |> element.map(ComponentProducedMessage),
            component.clock_view(
              model.time.black_time,
              model.time.white_time,
              model.role,
              model.game_state,
            ),
          ],
        )

      layout(content)
    }
  }
}

fn layout(content: Element(Message)) -> Element(Message) {
  let location = window.self() |> window.location()
  let protocol = protocol(location)
  let static_directory = case protocol {
    "https:" -> "/static/"
    _ -> ""
  }

  element.fragment([
    component.navbar(static_directory),
    html.main([attribute.class("bg-blue-100 min-h-dvh")], [content]),
  ])
}
