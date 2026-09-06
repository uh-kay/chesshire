import cheg
import client/component
import gleam/option
import gleam/uri
import lustre/attribute
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import modem
import plinth/browser/location
import plinth/browser/window
import shared.{GreatCrossing, TwinPasses}

pub type Model {
  Model(
    game: cheg.Game,
    board_variant: shared.BoardVariant,
    game_variant: shared.GameVariant,
    current_piece_moves: List(cheg.Move),
  )
}

pub type Message {
  ComponentProducedMessage(component.Message)
  UserClickedCreatePublicGame
  UserClickedFindGame
  UserClickedCreatePrivateGame
  UserClickedReset
  UserClickedChangeBoardVariant(board_variant: shared.BoardVariant)
}

pub fn init() -> Model {
  Model(
    game: cheg.new(TwinPasses, shared.RiverSacrifice),
    board_variant: TwinPasses,
    game_variant: shared.RiverSacrifice,
    current_piece_moves: [],
  )
}

pub fn update(model: Model, message: Message) {
  case message {
    ComponentProducedMessage(component.UserClickedSquare(piece: _, position:)) -> {
      let moves = cheg.legal_moves_for_piece(model.game, position)
      let model = Model(..model, current_piece_moves: moves)

      #(model, effect.none())
    }
    ComponentProducedMessage(component.UserClickedTargetSquare(move:)) -> {
      let game = cheg.apply_move(model.game, move)
      let model = Model(..model, game:, current_piece_moves: [])

      #(model, effect.none())
    }
    UserClickedCreatePublicGame -> {
      let effect = case uri.parse("/create") {
        Ok(uri) -> modem.load(uri)
        Error(_) -> effect.none()
      }

      #(model, effect)
    }
    UserClickedFindGame -> {
      let effect = case uri.parse("/game/") {
        Ok(uri) -> modem.load(uri)
        Error(_) -> effect.none()
      }

      #(model, effect)
    }
    UserClickedCreatePrivateGame -> {
      let effect = case uri.parse("/create/private") {
        Ok(uri) -> modem.load(uri)
        Error(_) -> effect.none()
      }

      #(model, effect)
    }
    UserClickedReset -> {
      let model =
        Model(
          ..model,
          game: cheg.new(model.board_variant, model.game_variant),
          current_piece_moves: [],
        )

      #(model, effect.none())
    }
    UserClickedChangeBoardVariant(board_variant:) -> {
      let model =
        Model(
          ..model,
          game: cheg.new(board_variant, model.game_variant),
          board_variant:,
        )

      #(model, effect.none())
    }
  }
}

pub fn view(model: Model) {
  html.div(
    [
      attribute.class("pt-8 px-3 md:p-8 max-w-fit mx-auto"),
      attribute.class("flex flex-col"),
    ],
    [
      html.div([attribute.class("flex gap-4")], [
        html.a(
          [
            attribute.class("p-2 w-fit bg-blue-500 text-white rounded-md"),
            attribute.class("hover:bg-blue-600 hover:cursor-pointer"),
            event.on_click(UserClickedCreatePublicGame),
          ],
          [html.text("Create Game")],
        ),
        html.button(
          [
            attribute.class("bg-blue-500 p-2 rounded-md w-fit"),
            attribute.class("text-white hover:cursor-pointer"),
            attribute.class("hover:bg-blue-600"),
            event.on_click(UserClickedFindGame),
          ],
          [html.text("Join Game")],
        ),
        html.button(
          [
            attribute.class("p-2 bg-blue-500 text-white rounded-md w-fit"),
            attribute.class("hover:bg-blue-600 hover:cursor-pointer"),
            event.on_click(UserClickedCreatePrivateGame),
          ],
          [html.text("Create Private Game")],
        ),
      ]),
      html.p([attribute.class("text-2xl mt-8")], [html.text("Sandbox")]),
      html.div(
        [attribute.class("mt-2 flex flex-col-reverse md:flex-row gap-4")],
        [
          html.div([attribute.class("flex flex-col gap-4")], [
            html.button(
              [
                attribute.class(
                  "p-2 w-32 md:h-fit bg-blue-500 text-white rounded-md",
                ),
                event.on_click(UserClickedReset),
              ],
              [html.text("Reset")],
            ),
            html.label([], [html.text("Board Variant")]),
            html.div([attribute.class("flex flex-row md:flex-col gap-2")], [
              html.button(
                [
                  attribute.class("p-2 w-fit md:w-full md:h-fit rounded-md"),
                  attribute.class("text-nowrap border-2 border-blue-500"),
                  attribute.class(case model.board_variant {
                    TwinPasses -> "bg-blue-500 text-white"
                    GreatCrossing -> ""
                  }),
                  event.on_click(UserClickedChangeBoardVariant(TwinPasses)),
                ],
                [html.text("Twin Passes")],
              ),
              html.button(
                [
                  attribute.class("p-2 w-fit md:w-full md:h-fit rounded-md"),
                  attribute.class("text-nowrap border-2 border-blue-500"),
                  attribute.class(case model.board_variant {
                    GreatCrossing -> "bg-blue-500 text-white"
                    TwinPasses -> ""
                  }),
                  event.on_click(UserClickedChangeBoardVariant(GreatCrossing)),
                ],
                [html.text("Great Crossing")],
              ),
            ]),
          ]),

          component.game_view(component.Model(
            game: model.game,
            moves: model.current_piece_moves,
            player_color: option.Some(cheg.White),
          ))
            |> element.map(ComponentProducedMessage),
        ],
      ),
    ],
  )
  |> layout
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

@external(javascript, "../client.ffi.mjs", "protocol")
fn protocol(location: location.Location) -> String
