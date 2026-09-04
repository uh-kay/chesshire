import client/component
import gleam/dynamic/decode
import gleam/uri
import lustre/attribute
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import modem
import rsvp
import shared

// MODEL ----------------------------------------------------------------------

pub type Model {
  Model(board_variant: shared.BoardVariant, game_variant: shared.GameVariant)
}

pub type Message {
  UserClickedCreateGame
  UserClickedBoardVariant(board_variant: shared.BoardVariant)
  UserClickedGameVariant(game_variant: shared.GameVariant)
  ServerCreatedGame(Result(String, rsvp.Error(String)))
}

pub fn init() {
  let model =
    Model(board_variant: shared.TwoBridge, game_variant: shared.RiverSacrifice)

  model
}

// UPDATE ---------------------------------------------------------------------
pub fn update(model: Model, message: Message) {
  case message {
    UserClickedCreateGame -> {
      let effect = case uri.parse("/game/") {
        Ok(uri) ->
          effect.batch([
            modem.load(uri),
            create_game(model.board_variant, model.game_variant),
          ])
        Error(_) -> effect.none()
      }

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
        Ok(_) -> {
          case uri.parse("/game/") {
            Ok(uri) -> modem.load(uri)
            Error(_) -> effect.none()
          }
        }
        Error(_) -> effect.none()
      }
      #(model, effect)
    }
  }
}

// EFFECTS --------------------------------------------------------------------
fn create_game(board_variant, game_variant) -> effect.Effect(Message) {
  let url = "/v1/game"
  let body =
    shared.CreateGame(is_public: True, board_variant:, game_variant:)
    |> shared.create_game_to_json
  let decoder = {
    use invite_code <- decode.field("invite_code", decode.string)
    decode.success(invite_code)
  }
  let handler = rsvp.expect_json(decoder, ServerCreatedGame)

  rsvp.post(url, body, handler)
}

// VIEW -----------------------------------------------------------------------
pub fn view(model: Model) -> Element(Message) {
  let content =
    html.div([attribute.class("p-8 max-w-2xl mx-auto flex flex-col")], [
      html.p([attribute.class("text-lg")], [html.text("Board Variant")]),
      html.div([attribute.class("mt-2 flex gap-2")], [
        html.button(
          [
            attribute.class("p-2 w-fit rounded-md cursor-pointer border"),
            attribute.class("border-blue-500"),
            attribute.class(case model.board_variant {
              shared.TwoBridge -> "text-white bg-blue-500"
              shared.MiddleBridge -> "hover:bg-blue-500 hover:text-white"
            }),
            event.on_click(UserClickedBoardVariant(shared.TwoBridge)),
          ],
          [html.text("Two Bridge")],
        ),
        html.button(
          [
            attribute.class("p-2 w-fit rounded-md cursor-pointer border"),
            attribute.class("border-blue-500"),
            attribute.class(case model.board_variant {
              shared.TwoBridge -> "hover:bg-blue-500 hover:text-white"
              shared.MiddleBridge -> "text-white bg-blue-500"
            }),
            event.on_click(UserClickedBoardVariant(shared.MiddleBridge)),
          ],
          [html.text("Middle Bridge")],
        ),
      ]),
      html.div([attribute.class("mt-2")], [
        html.img([
          attribute.src("/static/two_bridge.png"),
          attribute.hidden(case model.board_variant {
            shared.TwoBridge -> False
            shared.MiddleBridge -> True
          }),
        ]),
        html.img([
          attribute.src("/static/middle_bridge.png"),
          attribute.hidden(case model.board_variant {
            shared.TwoBridge -> True
            shared.MiddleBridge -> False
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

  layout(content)
}

fn layout(content: Element(Message)) -> Element(Message) {
  element.fragment([
    component.navbar(),
    html.main([attribute.class("bg-blue-100 min-h-dvh")], [content]),
  ])
}
