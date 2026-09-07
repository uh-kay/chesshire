import client/accordion
import client/component
import client/create_game
import client/game
import client/home
import client/websocket.{type Websocket}
import gleam/http/response.{type Response}
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/uri
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import modem
import plinth/browser/location
import plinth/browser/window
import rsvp

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

// MODEL ----------------------------------------------------------------------

type Model {
  Model(
    route: Route,
    error: Option(String),
    websocket: Option(Websocket),
    faq: accordion.Model,
    uri: option.Option(uri.Uri),
    page_model: PageModel,
  )
}

type PageModel {
  CreateModel(create_game.Model)
  HomeModel(home.Model)
  GameModel(game.Model)
  LearnModel
  NotFoundModel
}

pub type Message {
  AccordionProducedMessage(accordion.Message)

  CreatePageMessage(create_game.Message)
  HomePageMessage(home.Message)
  GamePageMessage(game.Message)

  UserNavigatedTo(Route)

  ServerCreatedSession(Result(Response(String), rsvp.Error(String)))

  ClientPingedServer
}

pub type Route {
  Home
  Game(id: String)
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
          ["game"] -> Game(id: "")
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

  let websocket = case route {
    Game(id:) -> {
      let websocket = websocket.create(ws_url <> id)

      Some(websocket)
    }
    _ -> None
  }

  let accordion_items = [
    accordion.Item(id: 1, title: "What is Chesshire?", body: element.none()),
  ]

  let #(page_model, page_effect) = init_page(route, websocket, uri)

  let model =
    Model(
      route:,
      error: None,
      websocket:,
      faq: accordion.init(accordion_items),
      uri:,
      page_model:,
    )
  let effect =
    effect.batch([
      modem.init(on_url_change),
      create_session(),
      page_effect,
      ping_server(60_000, model.websocket),
    ])

  #(model, effect)
}

fn init_page(route: Route, websocket: Option(Websocket), uri: Option(uri.Uri)) {
  case route {
    Create(is_public) -> #(
      CreateModel(create_game.init(is_public)),
      effect.none(),
    )
    Home -> #(HomeModel(home.init()), effect.none())
    Game(id:) -> {
      let #(model, effect) = game.init(uri, websocket, id)
      #(GameModel(model), effect.map(effect, GamePageMessage))
    }
    Learn -> #(LearnModel, effect.none())
    NotFound -> #(NotFoundModel, effect.none())
  }
}

fn on_url_change(uri: uri.Uri) -> Message {
  case uri.path_segments(uri.path) {
    [] -> UserNavigatedTo(Home)
    ["game"] -> UserNavigatedTo(Game(""))
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

    UserNavigatedTo(route) -> {
      let #(page_model, page_effect) = case route {
        Game(id:) ->
          case model.page_model {
            GameModel(game_model) -> {
              case id == game_model.lobby_id {
                True -> #(GameModel(game_model), effect.none())
                False -> init_page(route, model.websocket, model.uri)
              }
            }
            _ -> init_page(route, model.websocket, model.uri)
          }
        _ -> init_page(route, model.websocket, model.uri)
      }

      let model = Model(..model, route:, page_model:)
      let effect = page_effect

      #(model, effect)
    }

    ServerCreatedSession(_) -> {
      let effect = effect.none()

      #(model, effect)
    }

    ClientPingedServer -> #(model, ping_server(60_000, model.websocket))

    CreatePageMessage(message) -> {
      case model.page_model {
        CreateModel(create_model) -> {
          let #(create_model, create_effect) =
            create_game.update(create_model, message)

          let #(model, page_effect) = case message {
            create_game.ServerCreatedGame(result) ->
              case result {
                Ok(id) -> {
                  let #(game_model, game_effect) =
                    game.init(model.uri, model.websocket, id)
                  #(
                    Model(..model, page_model: GameModel({ game_model })),
                    game_effect |> effect.map(GamePageMessage),
                  )
                }
                Error(_) -> #(
                  Model(..model, page_model: CreateModel(create_model)),
                  effect.none(),
                )
              }
            _ -> #(
              Model(..model, page_model: CreateModel(create_model)),
              effect.none(),
            )
          }
          let effect =
            effect.batch([
              effect.map(create_effect, CreatePageMessage),
              page_effect,
            ])

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
    GamePageMessage(message) ->
      case model.page_model {
        GameModel(game_model) -> {
          let #(game_model, effect) = game.update(game_model, message)
          let model = Model(..model, page_model: GameModel(game_model))
          let effect = effect.map(effect, GamePageMessage)

          #(model, effect)
        }
        _ -> #(model, effect.none())
      }
  }
}

// EFFECTS --------------------------------------------------------------------

fn create_session() -> Effect(Message) {
  let url = "/v1/session"
  let body = json.null()
  let handler = rsvp.expect_ok_response(ServerCreatedSession)

  rsvp.post(url, body, handler)
}

fn ping_server(duration: Int, websocket: Option(Websocket)) {
  use dispatch <- effect.from
  use <- set_timeout(duration)

  case websocket {
    Some(websocket) -> websocket.send_message(websocket, "ping")
    None -> Nil
  }

  dispatch(ClientPingedServer)
}

// EXTERNALS ------------------------------------------------------------------

@external(javascript, "./client.ffi.mjs", "set_timeout")
fn set_timeout(delay: Int, callback: fn() -> a) -> Nil

@external(javascript, "./client.ffi.mjs", "websocket_url")
fn websocket_url(path: String) -> String

@external(javascript, "./client.ffi.mjs", "protocol")
fn protocol(location: location.Location) -> String

// VIEW -----------------------------------------------------------------------

fn view(model: Model) -> Element(Message) {
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
    Game(_) ->
      case model.page_model {
        GameModel(model) -> game.view(model) |> element.map(GamePageMessage)
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
    component.navbar(static_directory),
    html.main([attribute.class("bg-blue-100 min-h-dvh")], [content]),
  ])
}
