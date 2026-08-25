import cheg
import client/accordion
import client/component
import gleam/dynamic/decode
import gleam/http/response
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/uri
import icon
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import modem
import plinth/browser/clipboard
import rsvp
import shared

// TODO:
// - Create interactive tutorial

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

// MODEL ----------------------------------------------------------------------

pub type Model {
  Model(
    game: cheg.Game,
    time: shared.Time,
    route: Route,
    lobby_code: String,
    error: Option(String),
    current_piece: Option(#(Int, Option(#(cheg.PieceType, cheg.Color)))),
    current_piece_moves: List(cheg.Move),
    websocket: Option(Websocket),
    role: Option(cheg.Role),
    player_color: Option(cheg.Color),
    guest_joined: Bool,
    offset: Int,
    link_copied: Bool,
    faq: accordion.Model,
    uri: option.Option(uri.Uri),
    game_state: cheg.GameState,
  )
}

pub type Message {
  ComponentProducedMessage(component.Message)
  AccordionProducedMessage(accordion.Message)

  UserNavigatedTo(Route)
  UserClickedNewGame
  UserClickedCopyLink(lobby_url: String)

  ServerCreatedGame(Result(String, rsvp.Error(String)))
  ServerCreatedSession(Result(response.Response(String), rsvp.Error(String)))
  ServerReturnedRole(cheg.Role)
  ServerUpdatedGame(body: String)

  ClockTickedForward
  ClockStoppedTicking
  TimerExpired
}

pub type Route {
  Home
  Game(id: String)
  NotFound
}

fn init(_) -> #(Model, Effect(Message)) {
  let #(route, uri) = case modem.initial_uri() {
    Ok(uri) -> {
      #(
        case uri.path_segments(uri.path) {
          [] -> Home
          ["game", id] -> Game(id)
          _ -> NotFound
        },
        Some(uri),
      )
    }
    Error(_) -> #(NotFound, None)
  }
  let ws_url = websocket_url("/ws/")
  let game = cheg.new()

  let #(init_msg, websocket) = case route {
    Game(id:) -> {
      let ws = create_websocket(ws_url <> id)
      let msg = receive_message(ws)

      #(Some(msg), Some(ws))
    }
    _ -> #(None, None)
  }
  let time = shared.new_time(monotonic_time())
  let accordion_items = [
    accordion.Item(id: 1, title: "What is Chesshire?", body: element.none()),
  ]

  let model =
    Model(
      route:,
      error: None,
      game:,
      current_piece: None,
      current_piece_moves: [],
      websocket:,
      time:,
      lobby_code: "",
      role: None,
      guest_joined: False,
      // in the future calculate based on latency
      offset: 0,
      link_copied: False,
      faq: accordion.init(accordion_items),
      uri:,
      game_state: cheg.Continue,
      player_color: None,
    )
  let effect =
    effect.batch([
      modem.init(on_url_change),
      create_session(),
      get_game_view(init_msg),
      tick(),
    ])

  #(model, effect)
}

fn on_url_change(uri: uri.Uri) -> Message {
  case uri.path_segments(uri.path) {
    [] -> UserNavigatedTo(Home)
    _ -> UserNavigatedTo(NotFound)
  }
}

// UPDATE ---------------------------------------------------------------------

fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case message {
    AccordionProducedMessage(message) -> {
      let model = Model(..model, faq: accordion.update(model.faq, message))
      let effect = effect.none()

      #(model, effect)
    }
    ComponentProducedMessage(component.UserClickedSquare(piece, pos)) -> {
      let current_piece_moves = case model.player_color {
        Some(player_color) -> {
          let to_move = cheg.to_move(model.game)

          case piece {
            Some(#(_, piece_color))
              if player_color == to_move
              && player_color == piece_color
              && model.game_state == cheg.Continue
            -> cheg.legal_moves_for_piece(model.game, pos)
            _ -> []
          }
        }
        None -> []
      }

      let model = Model(..model, current_piece_moves:)
      let effect = effect.none()

      #(model, effect)
    }
    ComponentProducedMessage(component.UserClickedTargetSquare(move)) -> {
      let message = cheg.move_to_json(move) |> json.to_string
      let game = cheg.apply_move(model.game, move)

      case model.websocket {
        Some(ws) -> send_message(ws, message)
        None -> Nil
      }

      let model =
        Model(..model, game:, current_piece: None, current_piece_moves: [])
      let effect = effect.none()

      #(model, effect)
    }
    ComponentProducedMessage(component.UserClickedNewGame) -> {
      let effect = create_game()

      #(model, effect)
    }
    UserClickedNewGame -> {
      let effect = create_game()

      #(model, effect)
    }
    ServerCreatedGame(result) -> {
      let model = case result {
        Ok(lobby_code) -> Model(..model, lobby_code:)
        Error(_) -> model
      }

      let effect = case result {
        Ok(lobby_code) -> {
          case uri.parse("/game/" <> lobby_code) {
            Ok(uri) -> modem.load(uri)
            Error(_) -> effect.none()
          }
        }
        Error(_) -> effect.none()
      }

      #(model, effect)
    }
    ServerReturnedRole(role) -> {
      let model = Model(..model, role: Some(role))
      let effect = listen(model.websocket)

      #(model, effect)
    }
    ServerUpdatedGame(body:) -> {
      case json.parse(body, cheg.game_view_decoder()) {
        Ok(game_view) -> {
          let black_tick = case cheg.to_move(game_view.game) {
            cheg.Black -> monotonic_time()
            cheg.White -> model.time.black_tick
          }
          let white_tick = case cheg.to_move(game_view.game) {
            cheg.Black -> model.time.white_tick
            cheg.White -> monotonic_time()
          }

          let effect = case game_view.game_state != cheg.Continue {
            True -> stop_clock()
            False -> listen(model.websocket)
          }
          let model =
            Model(
              ..model,
              game: game_view.game,
              time: shared.Time(..game_view.time, black_tick:, white_tick:),
              guest_joined: game_view.guest_joined,
              role: Some(game_view.role),
              game_state: game_view.game_state,
              player_color: game_view.player_color,
            )

          #(model, effect)
        }
        Error(_) -> #(model, effect.none())
      }
    }

    ClockTickedForward -> {
      let offset = model.offset

      let #(time, effect) = case cheg.to_move(model.game), model.time.started {
        cheg.Black, True -> {
          let black_tick = monotonic_time()
          let black_time =
            current_time(model.time.black_time, model.time.black_tick, offset)

          let effect = case black_time <= 0 {
            True -> stop_clock()
            False -> tick()
          }
          #(shared.Time(..model.time, black_time:, black_tick:), effect)
        }
        cheg.White, True -> {
          let white_tick = monotonic_time()
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
    UserNavigatedTo(route) -> {
      let model = Model(..model, route:)
      let effect = effect.none()

      #(model, effect)
    }
    ServerCreatedSession(_) -> {
      let effect = effect.none()

      #(model, effect)
    }
    UserClickedCopyLink(lobby_url:) -> {
      let model = Model(..model, link_copied: True)
      let effect = effect.batch([copy_link(lobby_url), reset_timer(1000)])

      #(model, effect)
    }
    TimerExpired -> #(Model(..model, link_copied: False), effect.none())
    ClockStoppedTicking -> {
      let black_time =
        int.clamp(model.time.black_time, shared.min_time, shared.max_time)
      let white_time =
        int.clamp(model.time.white_time, shared.min_time, shared.max_time)
      let game_state = case black_time <= 0 {
        True -> cheg.WhiteWin
        False -> cheg.BlackWin
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
  let elapsed = monotonic_time() + offset - tick
  remaining - elapsed
}

// EFFECTS --------------------------------------------------------------------

fn create_game() -> Effect(Message) {
  let url = "/v1/game"
  let body = json.null()
  let decoder = {
    use invite_code <- decode.field("invite_code", decode.string)
    decode.success(invite_code)
  }
  let handler = rsvp.expect_json(decoder, ServerCreatedGame)

  rsvp.post(url, body, handler)
}

fn create_session() -> Effect(Message) {
  let url = "/v1/session"
  let body = json.null()
  let handler = rsvp.expect_ok_response(ServerCreatedSession)

  rsvp.post(url, body, handler)
}

fn listen(ws: Option(Websocket)) -> Effect(Message) {
  case ws {
    Some(ws) ->
      effect.from(fn(dispatch) {
        promise.tap(receive_message(ws), fn(msg) {
          dispatch(ServerUpdatedGame(body: msg))
        })

        Nil
      })
    None -> effect.none()
  }
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

fn tick() -> Effect(Message) {
  use dispatch <- effect.from
  use <- set_timeout(1000)

  dispatch(ClockTickedForward)
}

fn stop_clock() -> Effect(Message) {
  use dispatch <- effect.from

  dispatch(ClockStoppedTicking)
}

fn copy_link(lobby_url: String) -> Effect(a) {
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

// EXTERNALS ------------------------------------------------------------------
pub type Websocket

@external(javascript, "./client.ffi.mjs", "create_websocket")
fn create_websocket(uri: String) -> Websocket

@external(javascript, "./client.ffi.mjs", "send_message")
fn send_message(ws: Websocket, message: String) -> Nil

@external(javascript, "./client.ffi.mjs", "receive_message")
fn receive_message(ws: Websocket) -> Promise(String)

@external(javascript, "./client.ffi.mjs", "monotonic_time")
fn monotonic_time() -> Int

@external(javascript, "./client.ffi.mjs", "set_timeout")
fn set_timeout(delay: Int, cb: fn() -> a) -> Nil

@external(javascript, "./client.ffi.mjs", "websocket_url")
fn websocket_url(path: String) -> String

// VIEW -----------------------------------------------------------------------

fn view(model: Model) -> Element(Message) {
  let lobby_url = case model.uri {
    Some(uri) -> uri.to_string(uri)
    None -> ""
  }

  case model.route {
    Home -> {
      let content =
        html.div([attribute.class("p-8 mx-auto max-w-4xl flex flex-col")], [
          html.div([attribute.class("flex gap-8")], [
            html.button(
              [
                attribute.class("p-2 bg-blue-500 text-white rounded-md h-fit"),
                attribute.class(" hover:bg-blue-600 hover:cursor-pointer"),
                event.on_click(UserClickedNewGame),
              ],
              [html.text("Create Lobby")],
            ),
            html.div([attribute.class("")], [
              html.button(
                [
                  attribute.class("bg-gray-600 px-4 py-2 rounded-md w-fit"),
                  attribute.class(" opacity-50 text-white cursor-not-allowed"),
                ],
                [html.text("Find Game")],
              ),
              html.p([attribute.class("mt-2")], [
                html.text("⚠️ Coming soon!"),
              ]),
            ]),
          ]),
          // accordion.view(model.faq) |> element.map(AccordionProducedMessage),
          html.p([attribute.class("mt-8 text-xl font-bold text-blue-500")], [
            html.text("What is Chesshire?"),
          ]),
          html.div([attribute.class("text-justify")], [
            html.p([attribute.class("mt-2")], [
              html.text(
                "Chesshire is a new chess variant with river and bridges!",
              ),
            ]),
            html.img([
              attribute.class("w-lg mt-2"),
              attribute.src("/static/chesshire_screenshot.webp"),
            ]),
            html.p([attribute.class("mt-2")], [
              html.text("Normal chess rule applies but with these additions:"),
            ]),
            html.ul([attribute.class("list-disc list-inside")], [
              html.li([], [html.text("Piece cannot move onto river tiles.")]),
              html.li([], [
                html.text(
                  "Knight can jump across the river but cannot land on it.",
                ),
              ]),
              html.img([
                attribute.class("w-64"),
                attribute.src("/static/knight_rule.png"),
              ]),
              html.li([], [
                html.text(
                  "Pieces cannot attack opponent piece across the river.",
                ),
              ]),
              html.img([
                attribute.class("w-64"),
                attribute.src("/static/attack_rule.png"),
              ]),
              html.li([], [
                html.text(
                  "Pieces can only cross using bridges."
                  <> " They can also attack opponent piece across the bridge.",
                ),
              ]),
            ]),
          ]),
        ])

      layout(content)
    }
    NotFound -> element.none()
    Game(id: _) -> {
      case model.guest_joined {
        False -> {
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
        True -> {
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
                  role: model.role,
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
  }
}

fn layout(content: Element(Message)) -> Element(Message) {
  element.fragment([
    component.navbar() |> element.map(ComponentProducedMessage),
    html.main([attribute.class("bg-blue-100 min-h-dvh")], [content]),
  ])
}
