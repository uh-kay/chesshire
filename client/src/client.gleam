import cheg
import client/accordion
import client/component
import client/create_game
import client/home
import client/icon
import gleam/http/response.{type Response}
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/uri
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import modem
import plinth/browser/clipboard
import plinth/browser/location
import plinth/browser/window
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

type Model {
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
    page_model: PageModel,
  )
}

type PageModel {
  CreateModel(create_game.Model)
  HomeModel(home.Model)
  GameModel
  WaitingRoomModel(
    board_variant: shared.BoardVariant,
    game_variant: shared.GameVariant,
  )
  LearnModel
  NotFoundModel
}

pub type Message {
  ComponentProducedMessage(component.Message)
  AccordionProducedMessage(accordion.Message)

  CreatePageMessage(create_game.Message)
  HomePageMessage(home.Message)

  UserNavigatedTo(Route)
  // UserClickedCreatePublicGame
  // UserClickedFindGame
  // UserClickedCreatePrivateGame
  UserClickedCopyLink(lobby_url: String)

  ServerCreatedSession(Result(Response(String), rsvp.Error(String)))
  ServerReturnedRole(cheg.Role)
  ServerUpdatedGame(body: String)

  ClockTickedForward
  ClockStoppedTicking
  TimerExpired
  ClientPingedServer
}

pub type Route {
  Home
  Game(id: String)
  WaitingRoom
  Create(is_public: Bool)
  Learn
  NotFound
}

fn init(_) -> #(Model, Effect(Message)) {
  let #(route, uri) = case modem.initial_uri() {
    Ok(uri) -> {
      #(
        case uri.path_segments(uri.path) {
          [] -> Home
          ["game"] -> WaitingRoom
          ["game", id] -> Game(id)
          ["learn"] -> Learn
          ["create"] -> Create(is_public: True)
          ["create", "private"] -> Create(is_public: False)
          _ -> NotFound
        },
        Some(uri),
      )
    }
    Error(_) -> #(NotFound, None)
  }
  let ws_url = websocket_url("/ws/")
  let game = cheg.new(shared.TwinPasses, shared.RiverSacrifice)

  let #(init_msg, websocket) = case route {
    Game(id:) -> {
      let ws = create_websocket(ws_url <> id)
      let msg = receive_message(ws)

      #(Some(msg), Some(ws))
    }
    WaitingRoom -> {
      let ws = create_websocket(ws_url <> "")
      let msg = receive_message(ws)

      #(Some(msg), Some(ws))
    }
    _ -> {
      #(None, None)
    }
  }

  let time = shared.new_time(shared.monotonic_time())
  let accordion_items = [
    accordion.Item(id: 1, title: "What is Chesshire?", body: element.none()),
  ]

  let page_model = init_page_model(route)

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
      page_model:,
    )
  let effect =
    effect.batch([
      modem.init(on_url_change),
      create_session(),
      get_game_view(init_msg),
      tick(),
      ping_server(60_000, model.websocket),
    ])

  #(model, effect)
}

fn init_page_model(route: Route) {
  case route {
    Create(is_public) -> CreateModel(create_game.init(is_public))
    Home -> HomeModel(home.init())
    Game(id: _) -> GameModel
    WaitingRoom ->
      WaitingRoomModel(
        board_variant: shared.TwinPasses,
        game_variant: shared.RiverSacrifice,
      )
    Learn -> LearnModel
    NotFound -> NotFoundModel
  }
}

fn on_url_change(uri: uri.Uri) -> Message {
  case uri.path_segments(uri.path) {
    [] -> UserNavigatedTo(Home)
    ["game", id] -> UserNavigatedTo(Game(id))
    ["learn"] -> UserNavigatedTo(Learn)
    ["create"] -> UserNavigatedTo(Create(is_public: True))
    ["create", "private"] -> UserNavigatedTo(Create(is_public: False))
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

    ServerReturnedRole(role) -> {
      let model = Model(..model, role: Some(role))
      let effect = listen(model.websocket)

      #(model, effect)
    }

    ServerUpdatedGame(body:) -> {
      case json.parse(body, cheg.game_view_decoder()) {
        Ok(game_view) -> {
          let black_tick = case cheg.to_move(game_view.game) {
            cheg.Black -> shared.monotonic_time()
            cheg.White -> model.time.black_tick
          }
          let white_tick = case cheg.to_move(game_view.game) {
            cheg.Black -> model.time.white_tick
            cheg.White -> shared.monotonic_time()
          }

          let effect =
            effect.batch([
              case game_view.game_state != cheg.Continue {
                True -> stop_clock()
                False -> listen(model.websocket)
              },
              case model.route, game_view.guest_joined {
                WaitingRoom, True -> {
                  modem.push("/game/" <> game_view.lobby_id, None, None)
                }
                _, _ -> effect.none()
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
          let black_tick = shared.monotonic_time()
          let black_time =
            current_time(model.time.black_time, model.time.black_tick, offset)

          let effect = case black_time <= 0 {
            True -> stop_clock()
            False -> tick()
          }
          #(shared.Time(..model.time, black_time:, black_tick:), effect)
        }
        cheg.White, True -> {
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

    UserNavigatedTo(route) -> {
      let model = Model(..model, route:, page_model: init_page_model(route))
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

    ClientPingedServer -> #(model, ping_server(60_000, model.websocket))

    CreatePageMessage(message) -> {
      case model.page_model {
        CreateModel(create_model) -> {
          let #(create_model, effect) =
            create_game.update(create_model, message)

          let model = case message {
            create_game.ServerCreatedGame(result) ->
              case result {
                Ok(_) ->
                  Model(
                    ..model,
                    page_model: WaitingRoomModel(
                      board_variant: create_model.board_variant,
                      game_variant: create_model.game_variant,
                    ),
                  )
                Error(_) -> model
              }
            _ -> Model(..model, page_model: CreateModel(create_model))
          }
          let effect = effect.map(effect, CreatePageMessage)

          #(model, effect)
        }
        _ -> #(model, effect.none())
      }
    }

    HomePageMessage(message) ->
      case model.page_model {
        HomeModel(home_model) -> {
          let #(home_model, effect) = home.update(home_model, message)

          let model = Model(..model, page_model: HomeModel(home_model))
          let effect = effect.map(effect, HomePageMessage)

          #(model, effect)
        }
        _ -> #(model, effect.none())
      }
  }
}

fn current_time(remaining: Int, tick: Int, offset: Int) -> Int {
  let elapsed = shared.monotonic_time() + offset - tick
  remaining - elapsed
}

// EFFECTS --------------------------------------------------------------------

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

fn ping_server(duration: Int, websocket: Option(Websocket)) {
  use dispatch <- effect.from
  use <- set_timeout(duration)

  case websocket {
    Some(websocket) -> send_message(websocket, "ping")
    None -> Nil
  }

  dispatch(ClientPingedServer)
}

// EXTERNALS ------------------------------------------------------------------
pub type Websocket

@external(javascript, "./client.ffi.mjs", "create_websocket")
fn create_websocket(uri: String) -> Websocket

@external(javascript, "./client.ffi.mjs", "send_message")
fn send_message(ws: Websocket, message: String) -> Nil

@external(javascript, "./client.ffi.mjs", "receive_message")
fn receive_message(ws: Websocket) -> Promise(String)

@external(javascript, "./client.ffi.mjs", "set_timeout")
fn set_timeout(delay: Int, cb: fn() -> a) -> Nil

@external(javascript, "./client.ffi.mjs", "websocket_url")
fn websocket_url(path: String) -> String

@external(javascript, "./client.ffi.mjs", "protocol")
fn protocol(location: location.Location) -> String

// VIEW -----------------------------------------------------------------------

fn view(model: Model) -> Element(Message) {
  let lobby_url = case model.uri {
    Some(uri) -> uri.to_string(uri)
    None -> ""
  }

  let location = window.self() |> window.location()
  let protocol = protocol(location)
  let static_directory = case protocol {
    "https:" -> "/static/"
    _ -> ""
  }

  case model.route {
    NotFound -> element.none()

    Home ->
      case model.page_model {
        HomeModel(model) -> home.view(model) |> element.map(HomePageMessage)
        _ -> element.none()
      }

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

    WaitingRoom ->
      case model.guest_joined {
        False -> {
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

    Learn -> {
      let content =
        html.main([attribute.class("max-w-fit mx-auto")], [
          html.p([attribute.class("pt-8 text-xl font-bold text-blue-500")], [
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
              attribute.src(static_directory <> "chesshire_screenshot.webp"),
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
                attribute.src(static_directory <> "knight_rule.png"),
              ]),
              html.li([], [
                html.text(
                  "Pieces cannot attack opponent piece across the river.",
                ),
              ]),
              html.img([
                attribute.class("w-64"),
                attribute.src(static_directory <> "attack_rule.png"),
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

    Create(_) ->
      case model.page_model {
        CreateModel(model) ->
          create_game.view(model) |> element.map(CreatePageMessage)
        _ -> element.none()
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
    component.navbar(static_directory) |> element.map(ComponentProducedMessage),
    html.main([attribute.class("bg-blue-100 min-h-dvh")], [content]),
  ])
}
