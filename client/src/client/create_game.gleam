import cheg
import client/component
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set
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
    host_side: HostSide,
    board_variant: shared.BoardVariant,
    game_variant: shared.GameVariant,
  )
}

pub type HostSide {
  Black
  Random
  White
}

pub type Message {
  UserClickedCreateGame
  UserClickedBoardVariant(board_variant: shared.BoardVariant)
  UserClickedGameVariant(game_variant: shared.GameVariant)
  UserClickedPlayingSide(playing_side: HostSide)
  ServerCreatedGame(Result(String, rsvp.Error(String)))
}

pub fn init(is_public: Bool) -> Model {
  let model =
    Model(
      is_public:,
      host_side: Random,
      board_variant: shared.TwinPasses,
      game_variant: shared.RiverSacrifice,
    )

  model
}

// UPDATE ---------------------------------------------------------------------
pub fn update(model: Model, message: Message) {
  case message {
    UserClickedCreateGame -> {
      let host_side = case model.host_side {
        Black -> shared.Black
        Random -> {
          case int.random(2) {
            1 -> shared.Black
            _ -> shared.White
          }
        }
        White -> shared.White
      }
      let effect =
        create_game(
          model.is_public,
          model.board_variant,
          model.game_variant,
          host_side,
        )

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
    UserClickedPlayingSide(playing_side:) -> {
      let model = Model(..model, host_side: playing_side)

      #(model, effect.none())
    }
  }
}

// EFFECTS --------------------------------------------------------------------
fn create_game(
  is_public: Bool,
  board_variant: shared.BoardVariant,
  game_variant: shared.GameVariant,
  host_side: shared.PlayerColor,
) -> effect.Effect(Message) {
  let url = "/v1/game"
  let body =
    shared.CreateGame(is_public:, board_variant:, game_variant:, host_side:)
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

  let static_directory = case protocol {
    "https:" -> "/static/"
    _ -> "/"
  }

  let button_style = fn(selected_variant: Bool) {
    [
      attribute.class("p-2 w-fit rounded-md cursor-pointer border-2"),
      attribute.class("border-blue-500"),
      attribute.class(case selected_variant {
        True -> "text-white bg-blue-500"
        False -> "hover:bg-blue-500 hover:text-white"
      }),
    ]
  }

  let content =
    html.div([attribute.class("p-8 max-w-2xl mx-auto flex flex-col")], [
      html.p([attribute.class("text-lg")], [html.text("Board Variant")]),
      html.div([attribute.class("mt-2 flex gap-2")], [
        html.button(
          [
            event.on_click(UserClickedBoardVariant(shared.TwinPasses)),
            ..button_style(model.board_variant == shared.TwinPasses)
          ],
          [html.text("Twin Passes")],
        ),
        html.button(
          [
            event.on_click(UserClickedBoardVariant(shared.GreatCrossing)),
            ..button_style(model.board_variant == shared.GreatCrossing)
          ],
          [html.text("Great Crossing")],
        ),
      ]),

      html.div(
        [
          attribute.class("mt-2 grid grid-cols-8 grid-rows-9 w-full min-h-fit"),
          attribute.class("outline-1 min-w-fit md:w-fit"),
          attribute.class(case model.host_side {
            Black -> "scale-x-[-1]"
            Random -> "scale-y-[-1]"
            White -> "scale-y-[-1]"
          }),
        ],
        board_view(model),
      ),

      html.p([attribute.class("mt-3 text-lg")], [html.text("Rule Variant")]),
      html.div([attribute.class("mt-2 flex gap-2")], [
        html.button(
          [
            event.on_click(UserClickedGameVariant(shared.RiverSacrifice)),
            ..button_style(model.game_variant == shared.RiverSacrifice)
          ],
          [html.text("River Sacrifice")],
        ),
        html.button(
          [
            event.on_click(UserClickedGameVariant(shared.FlemishGiant)),
            ..button_style(model.game_variant == shared.FlemishGiant)
          ],
          [html.text("Flemish Giant")],
        ),
      ]),

      html.p([attribute.class("mt-3 text-lg")], [html.text("Side")]),
      html.div([attribute.class("mt-2 flex gap-2")], [
        html.button(
          [
            event.on_click(UserClickedPlayingSide(Black)),
            ..button_style(model.host_side == Black)
          ],
          [html.text("Black")],
        ),
        html.button(
          [
            event.on_click(UserClickedPlayingSide(Random)),
            ..button_style(model.host_side == Random)
          ],
          [html.text("Random")],
        ),
        html.button(
          [
            event.on_click(UserClickedPlayingSide(White)),
            ..button_style(model.host_side == White)
          ],
          [html.text("White")],
        ),
      ]),

      html.button(
        [
          attribute.class("p-2 mt-8 w-fit rounded-md cursor-pointer border"),
          attribute.class("border-blue-500 text-white bg-blue-500"),
          attribute.class("hover:bg-blue-600"),
          event.on_click(UserClickedCreateGame),
        ],
        [
          html.text(case model.is_public {
            True -> "Create Game"
            False -> "Create Private Game"
          }),
        ],
      ),
    ])

  component.layout(content)
}

fn board_view(model: Model) {
  let game = cheg.new(model.board_variant, model.game_variant)
  let board = cheg.board(game)
  let bridge_squares = cheg.bridge_squares(game)
  let river_squares = cheg.river_squares(game)
  let new_board = dict.map_values(board, fn(_, v) { Some(v) })
  let current =
    board
    |> dict.to_list
    |> list.map(fn(square) { square.0 })
    |> set.from_list
  let new_board =
    int.range(0, 72, [], list.prepend)
    |> list.filter(fn(i) { !set.contains(current, i) })
    |> list.map(fn(pos) { #(pos, None) })
    |> dict.from_list
    |> dict.combine(new_board, fn(_, _) { None })
    |> dict.to_list
    |> list.sort(fn(a, b) {
      let #(pos_a, _) = a
      let #(pos_b, _) = b
      int.compare(pos_a, pos_b)
    })

  list.map(new_board, fn(value) {
    let #(pos, piece) = value
    let row = pos / 8
    let col = pos % 8

    let square_color = case { row + col } % 2 == 0 {
      True -> component.White
      False -> component.Black
    }
    let square_color = case list.contains(river_squares, pos) {
      True -> component.Blue
      False ->
        case list.contains(bridge_squares, pos) {
          True -> component.Brown
          False -> square_color
        }
    }
    let square_style = [
      attribute.class("flex justify-center aspect-square"),
      attribute.class("items-center relative touch-none w-full md:w-14"),
      component.square_color_style(square_color),
    ]

    html.div(square_style, [
      html.div(
        [
          attribute.class("p-1 w-full"),
          attribute.class(case model.host_side {
            Black -> "scale-x-[-1]"
            Random -> "scale-y-[-1]"
            White -> "scale-y-[-1]"
          }),
        ],
        [
          component.piece_view(piece),
        ],
      ),
    ])
  })
}
