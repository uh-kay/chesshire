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
      game_variant: shared.FlemishGiant,
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

// VIEW -----------------------------------------------------------------------
pub fn view(model: Model) -> Element(Message) {
  let variant_box_style = [
    attribute.class("flex flex-row md:flex-col mt-2 border-2"),
    attribute.class("border-black rounded-xl truncate"),
    attribute.class("font-comic w-full divide-x-2"),
    attribute.class("md:divide-x-0 md:divide-y-2 divide-black"),
    attribute.class("dark:border-dark dark:divide-dark mb-4"),
  ]
  let variant_label_style =
    attribute.class("font-comic text-xl flex md:justify-center")
  let content =
    html.div([attribute.class("p-8 max-w-2xl mx-auto flex flex-col")], [
      html.h1([attribute.class("font-josefin text-3xl font-bold mb-4")], [
        html.text(case model.is_public {
          True -> "Create Game"
          False -> "Create Private Game"
        }),
      ]),

      html.div([attribute.class("flex flex-col items-center")], [
        html.div(
          [attribute.class("flex flex-col-reverse md:flex-row gap-4 md:gap-8")],
          [
            html.div([], [
              html.label([variant_label_style], [html.text("Board Variant")]),
              html.div(variant_box_style, [
                component.variant_button_view(
                  model.board_variant,
                  shared.TwinPasses,
                  UserClickedBoardVariant(shared.TwinPasses),
                  "Twin Passes",
                ),
                component.variant_button_view(
                  model.board_variant,
                  shared.GreatCrossing,
                  UserClickedBoardVariant(shared.GreatCrossing),
                  "Great Crossing",
                ),
              ]),

              html.label([variant_label_style], [html.text("Rule Variant")]),
              html.div(variant_box_style, [
                component.variant_button_view(
                  model.game_variant,
                  shared.RiverSacrifice,
                  UserClickedGameVariant(shared.RiverSacrifice),
                  "Classic",
                ),
                component.variant_button_view(
                  model.game_variant,
                  shared.FlemishGiant,
                  UserClickedGameVariant(shared.FlemishGiant),
                  "Default",
                ),
              ]),

              html.label([variant_label_style], [html.text("Side")]),
              html.div(variant_box_style, [
                component.variant_button_view(
                  model.host_side,
                  Black,
                  UserClickedPlayingSide(Black),
                  "Black",
                ),
                component.variant_button_view(
                  model.host_side,
                  Random,
                  UserClickedPlayingSide(Random),
                  "Random",
                ),
                component.variant_button_view(
                  model.host_side,
                  White,
                  UserClickedPlayingSide(White),
                  "White",
                ),
              ]),
            ]),

            html.div(
              [
                attribute.class("md:mt-2 grid grid-cols-8 grid-rows-9"),
                attribute.class("outline-2 bg-current"),
                attribute.class("w-xs min-h-fit min-w-fit h-full md:w-fit"),
                attribute.class(case model.host_side {
                  Black -> "scale-x-[-1]"
                  Random -> "scale-y-[-1]"
                  White -> "scale-y-[-1]"
                }),
              ],
              board_view(model),
            ),
          ],
        ),

        html.button(
          component.button_style([
            attribute.class("mt-8"),
            event.on_click(UserClickedCreateGame),
          ]),
          [
            html.text(case model.is_public {
              True -> "Create Game"
              False -> "Create Private Game"
            }),
          ],
        ),
      ]),
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
      html.div([attribute.class("hidden md:block")], [
        component.special_square_marker(square_color, case model.host_side {
          Black -> Some(shared.Black)
          Random -> None
          White -> Some(shared.White)
        }),
      ]),
    ])
  })
}
