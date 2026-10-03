import client/create_game
import client/game
import client/home
import client/learn
import gleam/http/response.{type Response}
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/uri.{type Uri}
import lustre
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import modem
import off_topic.{type Subscription}
import rsvp

pub fn main() -> Nil {
  let app = off_topic.application(init, update, subscriptions, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

fn subscriptions(model: Model) -> Subscription(Message) {
  case model.route, model.page_model {
    Game(_), GameModel(model) ->
      game.subscriptions(model) |> off_topic.map(GamePageMessage)
    _, _ -> off_topic.none()
  }
}

// MODEL ----------------------------------------------------------------------

type Model {
  Model(
    route: Route,
    error: Option(String),
    uri: option.Option(Uri),
    page_model: PageModel,
    websocket_url: Option(String),
  )
}

type PageModel {
  CreateModel(create_game.Model)
  HomeModel(home.Model)
  GameModel(game.Model)
  LearnModel(learn.Model)
  NotFoundModel
}

pub type Message {
  HomePageMessage(home.Message)
  LearnPageMessage(learn.Message)
  CreatePageMessage(create_game.Message)
  GamePageMessage(game.Message)

  UserNavigatedTo(Route)

  ServerCreatedSession(Result(Response(String), rsvp.Error(String)))
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
    Ok(uri) -> #(
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

    Error(_) -> #(NotFound, None)
  }
  let websocket_url = case route {
    Game(id:) -> Some(websocket_url("/ws/" <> id))
    _ -> None
  }
  let #(page_model, page_effect) = init_page(route, uri, websocket_url)

  let model = Model(route:, error: None, uri:, page_model:, websocket_url:)
  let effect =
    effect.batch([
      modem.init(on_url_change),
      create_session(),
      page_effect,
    ])

  #(model, effect)
}

fn init_page(
  route: Route,
  uri: Option(Uri),
  websocket_url: Option(String),
) -> #(PageModel, Effect(Message)) {
  case route {
    Create(is_public) -> {
      let model = CreateModel(create_game.init(is_public))

      #(model, effect.none())
    }
    Home -> {
      let model = HomeModel(home.init())

      #(model, effect.none())
    }
    Game(id:) -> {
      let #(model, effect) = game.init(uri, websocket_url, id)

      #(GameModel(model), effect.map(effect, GamePageMessage))
    }
    Learn -> {
      let model = LearnModel(learn.init())

      #(model, effect.none())
    }
    NotFound -> #(NotFoundModel, effect.none())
  }
}

fn on_url_change(uri: Uri) -> Message {
  case uri.path_segments(uri.path) {
    [] -> UserNavigatedTo(Home)
    ["game"] -> UserNavigatedTo(Game(""))
    ["game", id] -> UserNavigatedTo(Game(id:))
    ["learn"] -> UserNavigatedTo(Learn)
    ["create"] -> UserNavigatedTo(Create(is_public: True))
    ["create", "private"] -> UserNavigatedTo(Create(is_public: False))
    _ -> UserNavigatedTo(NotFound)
  }
}

// UPDATE ---------------------------------------------------------------------

fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case message {
    UserNavigatedTo(route) -> {
      let #(page_model, page_effect) = case route {
        Game(id:) ->
          case model.page_model {
            GameModel(game_model) -> {
              case id == game_model.lobby_id {
                True -> #(GameModel(game_model), effect.none())
                False -> init_page(route, model.uri, model.websocket_url)
              }
            }
            _ -> init_page(route, model.uri, model.websocket_url)
          }
        _ -> init_page(route, model.uri, model.websocket_url)
      }

      let model = Model(..model, route:, page_model:)
      let effect = page_effect

      #(model, effect)
    }

    ServerCreatedSession(_) -> #(model, effect.none())

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
                    game.init(model.uri, model.websocket_url, id)
                  let model =
                    Model(..model, page_model: GameModel({ game_model }))
                  let effect = game_effect |> effect.map(GamePageMessage)

                  #(model, effect)
                }
                Error(_) -> {
                  let model =
                    Model(..model, page_model: CreateModel(create_model))

                  #(model, effect.none())
                }
              }
            _ -> {
              let model = Model(..model, page_model: CreateModel(create_model))

              #(model, effect.none())
            }
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

    LearnPageMessage(message) ->
      case model.page_model {
        LearnModel(learn_model) -> {
          let #(learn_model, effect) = learn.update(learn_model, message)
          let model = Model(..model, page_model: LearnModel(learn_model))
          let effect = effect.map(effect, LearnPageMessage)

          #(model, effect)
        }
        _ -> #(model, effect.none())
      }
  }
}

// EXTERNAL -------------------------------------------------------------------

@external(javascript, "./client.ffi.mjs", "websocket_url")
pub fn websocket_url(path: String) -> String

// EFFECTS --------------------------------------------------------------------

fn create_session() -> Effect(Message) {
  let url = "/v1/session"
  let body = json.null()
  let handler = rsvp.expect_ok_response(ServerCreatedSession)

  rsvp.post(url, body, handler)
}

// VIEW -----------------------------------------------------------------------

fn view(model: Model) -> Element(Message) {
  case model.route {
    NotFound -> element.none()

    Home ->
      case model.page_model {
        HomeModel(model) -> home.view(model) |> element.map(HomePageMessage)
        _ -> element.none()
      }

    Learn -> {
      case model.page_model {
        LearnModel(model) -> learn.view(model) |> element.map(LearnPageMessage)
        _ -> element.none()
      }
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
