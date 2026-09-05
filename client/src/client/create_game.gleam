import client/component
import gleam/dynamic/decode
import gleam/uri
import lustre/attribute
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import modem
import plinth/browser/location
import plinth/browser/window
import rsvp
import shared

// MODEL ----------------------------------------------------------------------

pub type Model {
  Model(
    is_public: Bool,
    board_variant: shared.BoardVariant,
    game_variant: shared.GameVariant,
  )
}

pub type Message {
  UserClickedCreateGame
  UserClickedBoardVariant(board_variant: shared.BoardVariant)
  UserClickedGameVariant(game_variant: shared.GameVariant)
  ServerCreatedGame(Result(String, rsvp.Error(String)))
}

pub fn init(is_public: Bool) -> Model {
  let model =
    Model(
      is_public:,
      board_variant: shared.TwinPasses,
      game_variant: shared.RiverSacrifice,
    )

  model
}

// UPDATE ---------------------------------------------------------------------
pub fn update(model: Model, message: Message) {
  case message {
    UserClickedCreateGame -> {
      let effect =
        create_game(model.is_public, model.board_variant, model.game_variant)

      #(model, effect)
    }
    UserClickedBoardVariant(board_variant:) -> #(
      Model(..model, board_variant:),
      effect.none(),
    )
    UserClickedGameVariant(game_variant:) -> #(
      Model(..model, game_variant:),
      effect.none(),
    )
    ServerCreatedGame(result) -> {
      let effect = case result {
        Ok(invite_code) -> {
          case model.is_public {
            True ->
              case uri.parse("/game/") {
                Ok(uri) -> modem.load(uri)
                Error(_) -> effect.none()
              }
            False ->
              case uri.parse("/game/" <> invite_code) {
                Ok(uri) -> modem.load(uri)
                Error(_) -> effect.none()
              }
          }
        }
        Error(_) -> {
          effect.none()
        }
      }
      #(model, effect)
    }
  }
}

// EFFECTS --------------------------------------------------------------------
fn create_game(
  is_public: Bool,
  board_variant: shared.BoardVariant,
  game_variant: shared.GameVariant,
) -> effect.Effect(Message) {
  let url = "/v1/game"
  let body =
    shared.CreateGame(is_public:, board_variant:, game_variant:)
    |> shared.create_game_to_json
  let decoder = {
    use invite_code <- decode.field("invite_code", decode.string)
    decode.success(invite_code)
  }
  let handler = rsvp.expect_json(decoder, ServerCreatedGame)

  rsvp.post(url, body, handler)
}

// EXTERNAL -------------------------------------------------------------------
@external(javascript, "../client.ffi.mjs", "protocol")
fn protocol(location: location.Location) -> String

// VIEW -----------------------------------------------------------------------
pub fn view(model: Model) -> Element(Message) {
  let location = window.self() |> window.location()
  let protocol = protocol(location)
  echo protocol
  let static_directory = case protocol {
    "https:" -> "/static/"
    _ -> "/"
  }

  let content =
    html.div([attribute.class("p-8 max-w-2xl mx-auto flex flex-col")], [
      html.p([attribute.class("text-lg")], [html.text("Board Variant")]),
      html.div([attribute.class("mt-2 flex gap-2")], [
        html.button(
          [
            attribute.class("p-2 w-fit rounded-md cursor-pointer border"),
            attribute.class("border-blue-500"),
            attribute.class(case model.board_variant {
              shared.TwinPasses -> "text-white bg-blue-500"
              shared.GreatCrossing -> "hover:bg-blue-500 hover:text-white"
            }),
            event.on_click(UserClickedBoardVariant(shared.TwinPasses)),
          ],
          [html.text("Twin Passes")],
        ),
        html.button(
          [
            attribute.class("p-2 w-fit rounded-md cursor-pointer border"),
            attribute.class("border-blue-500"),
            attribute.class(case model.board_variant {
              shared.TwinPasses -> "hover:bg-blue-500 hover:text-white"
              shared.GreatCrossing -> "text-white bg-blue-500"
            }),
            event.on_click(UserClickedBoardVariant(shared.GreatCrossing)),
          ],
          [html.text("Great Crossing")],
        ),
      ]),
      html.div([attribute.class("mt-2")], [
        html.img([
          attribute.src(static_directory <> "twin_passes.svg"),
          attribute.hidden(case model.board_variant {
            shared.TwinPasses -> False
            shared.GreatCrossing -> True
          }),
        ]),
        html.img([
          attribute.src(static_directory <> "great_crossing.svg"),
          attribute.hidden(case model.board_variant {
            shared.TwinPasses -> True
            shared.GreatCrossing -> False
          }),
        ]),
      ]),

      html.p([attribute.class("mt-3 text-lg")], [html.text("Rule Variant")]),
      html.button(
        [
          attribute.class("p-2 mt-2 w-fit rounded-md cursor-pointer border"),
          attribute.class("border-blue-500 text-white bg-blue-500"),
          event.on_click(UserClickedGameVariant(shared.RiverSacrifice)),
        ],
        [html.text("River Sacrifice")],
      ),

      html.button(
        [
          attribute.class("p-2 mt-16 w-fit rounded-md cursor-pointer border"),
          attribute.class("border-blue-500 text-white bg-blue-500"),
          attribute.class("hover:bg-blue-600"),
          event.on_click(UserClickedCreateGame),
        ],
        [html.text("Create Game")],
      ),
    ])

  layout(static_directory, content)
}

fn layout(
  static_directory: String,
  content: Element(Message),
) -> Element(Message) {
  element.fragment([
    component.navbar(static_directory),
    html.main([attribute.class("bg-blue-100 min-h-dvh")], [content]),
  ])
}
