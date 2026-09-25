import cheg
import client/component
import client/icon
import gleam/option.{type Option, None, Some}
import gleam/uri
import lustre/attribute
import lustre/effect
import lustre/element
import lustre/element/html
import lustre/event
import modem
import shared.{GreatCrossing, TwinPasses}

pub type Model {
  Model(
    game: cheg.Game,
    board_variant: shared.BoardVariant,
    rule_variant: shared.GameVariant,
    current_piece_moves: List(cheg.Move),
    dragged_over_square: Option(Int),
    dragged_piece: Option(component.DraggedPiece),
    current_move: Option(cheg.Move),
  )
}

pub type Message {
  ComponentProducedMessage(component.Message)
  UserClickedCreatePublicGame
  UserClickedFindGame
  UserClickedCreatePrivateGame
  UserClickedReset
  UserClickedChangeBoardVariant(board_variant: shared.BoardVariant)
  UserClickedChangeRuleVariant(rule_variant: shared.GameVariant)
}

pub fn init() -> Model {
  Model(
    game: cheg.new(TwinPasses, shared.FlemishGiant),
    board_variant: TwinPasses,
    rule_variant: shared.FlemishGiant,
    current_piece_moves: [],
    dragged_over_square: None,
    dragged_piece: None,
    current_move: None,
  )
}

pub fn update(model: Model, message: Message) {
  case message {
    ComponentProducedMessage(component.UserDraggedPiece(
      from:,
      pointer_x:,
      pointer_y:,
      offset_x:,
      offset_y:,
      width:,
      height:,
    )) -> {
      let moves = cheg.legal_moves_for_piece(model.game, from)
      let model =
        Model(
          ..model,
          current_piece_moves: moves,
          dragged_piece: Some(component.DraggedPiece(
            width:,
            height:,
            from:,
            pointer_x:,
            pointer_y:,
            offset_x:,
            offset_y:,
          )),
        )

      #(model, effect.none())
    }

    ComponentProducedMessage(component.UserDraggedToTargetSquare(
      move:,
      position:,
    )) -> {
      let model =
        Model(
          ..model,
          current_move: Some(move),
          dragged_over_square: Some(position),
        )

      #(model, effect.none())
    }

    ComponentProducedMessage(component.UserDraggedOutOfTargetSquare) -> {
      let model = Model(..model, dragged_over_square: None, current_move: None)

      #(model, effect.none())
    }

    ComponentProducedMessage(component.UserMovedPiece(pointer_x:, pointer_y:)) -> {
      let model = case model.dragged_piece {
        Some(dragged_piece) -> {
          Model(
            ..model,
            dragged_piece: Some(
              component.DraggedPiece(..dragged_piece, pointer_x:, pointer_y:),
            ),
          )
        }
        None -> model
      }

      #(model, effect.none())
    }

    ComponentProducedMessage(component.UserDroppedPiece) -> {
      let game = case model.current_move {
        Some(move) -> cheg.apply_move(model.game, move)
        None -> model.game
      }

      let model =
        Model(
          ..model,
          game:,
          current_piece_moves: [],
          dragged_over_square: None,
          dragged_piece: None,
          current_move: None,
        )

      #(model, effect.none())
    }

    ComponentProducedMessage(component.UserCancelledDrag) -> {
      let model = Model(..model, dragged_piece: None)
      #(model, effect.none())
    }

    ComponentProducedMessage(component.UserClickedPiece(piece: _, position:)) -> {
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
          game: cheg.new(model.board_variant, model.rule_variant),
          current_piece_moves: [],
        )

      #(model, effect.none())
    }

    UserClickedChangeBoardVariant(board_variant:) -> {
      let model =
        Model(
          ..model,
          game: cheg.new(board_variant, model.rule_variant),
          board_variant:,
        )

      #(model, effect.none())
    }
    UserClickedChangeRuleVariant(rule_variant:) -> {
      let model =
        Model(
          ..model,
          game: cheg.new(model.board_variant, rule_variant),
          rule_variant:,
        )

      #(model, effect.none())
    }
  }
}

pub fn view(model: Model) {
  let button_style = fn(attributes: List(attribute.Attribute(a))) {
    [
      attribute.class("px-2 py-3 bg-blue-500 text-white rounded-md flex"),
      attribute.class("hover:cursor-pointer transition-all gap-1 border-2"),
      attribute.class("border-black font-comic drop-shadow-[4px_4px_0_#000]"),
      attribute.class("hover:translate-x-[4px] hover:translate-y-[4px] "),
      attribute.class("hover:drop-shadow-none"),
      ..attributes
    ]
  }

  html.div(
    [
      attribute.class("pt-4 md:p-8 px-3 max-w-fit mx-auto"),
      attribute.class("flex flex-col"),
    ],
    [
      html.p([attribute.class("text-3xl font-josefin font-bold")], [
        html.text("Create"),
      ]),

      // Big screen layout
      html.div([attribute.class("mt-2 flex gap-4 pb-8 hidden md:flex")], [
        html.a(
          [event.on_click(UserClickedCreatePublicGame), ..button_style([])],
          [
            icon.plus(),
            html.text("Public Match"),
          ],
        ),
        html.button([event.on_click(UserClickedFindGame), ..button_style([])], [
          icon.search(),
          html.text("Find Match"),
        ]),
        html.button(
          [event.on_click(UserClickedCreatePrivateGame), ..button_style([])],
          [icon.globe_lock(), html.text("Private Match")],
        ),
      ]),

      // Small screen layout
      html.div([attribute.class("mt-2 gap-4 pb-8 flex flex-col md:hidden")], [
        html.div([attribute.class("flex gap-3")], [
          html.a(
            [
              event.on_click(UserClickedCreatePublicGame),
              attribute.class("w-full justify-center"),
              ..button_style([])
            ],
            [icon.plus(), html.text("Public Match")],
          ),

          html.button(
            [
              event.on_click(UserClickedCreatePrivateGame),
              attribute.class("w-full justify-center"),
              ..button_style([])
            ],
            [icon.globe_lock(), html.text("Private Match")],
          ),
        ]),

        html.button(
          [
            event.on_click(UserClickedFindGame),
            attribute.class("w-full justify-center"),
            ..button_style([])
          ],
          [
            icon.search(),
            html.text("Find Match"),
          ],
        ),
      ]),

      html.div(
        [
          attribute.class("p-6 border-2 rounded-xl bg-blue-200 mt-2 flex"),
          attribute.class("flex-col-reverse md:flex-row gap-6"),
        ],
        [
          html.div([], [
            html.p([attribute.class("text-3xl font-josefin font-bold mb-4")], [
              html.text("Sandbox"),
            ]),
            html.div([attribute.class("flex flex-col gap-4")], [
              html.button(
                [
                  event.on_click(UserClickedReset),
                  ..button_style([
                    attribute.class("w-32 justify-center"),
                  ])
                ],
                [html.text("Reset")],
              ),
              html.div([], [
                html.label([attribute.class("font-comic text-xl")], [
                  html.text("Board Variant"),
                ]),
                html.div(
                  [
                    attribute.class("flex flex-row md:flex-col mt-2 border-2"),
                    attribute.class("border-black rounded-xl truncate "),
                    attribute.class("font-comic"),
                  ],
                  [
                    html.button(
                      [
                        attribute.class("px-2 py-3 w-fit md:w-full md:h-fit"),
                        attribute.class("text-nowrap rounded-b-none border-b-2"),
                        attribute.class("border-black"),
                        attribute.class(case model.board_variant {
                          TwinPasses -> "bg-blue-500 text-white"
                          GreatCrossing -> "hover:bg-blue-300"
                        }),
                        event.on_click(UserClickedChangeBoardVariant(TwinPasses)),
                      ],
                      [html.text("Twin Passes")],
                    ),
                    html.button(
                      [
                        attribute.class("px-2 py-3 w-fit md:w-full md:h-fit"),
                        attribute.class("text-nowrap"),
                        attribute.class(case model.board_variant {
                          GreatCrossing -> "bg-blue-500 text-white"
                          TwinPasses -> "hover:bg-blue-300"
                        }),
                        event.on_click(UserClickedChangeBoardVariant(
                          GreatCrossing,
                        )),
                      ],
                      [html.text("Great Crossing")],
                    ),
                  ],
                ),
              ]),
              html.div([], [
                html.label([attribute.class("font-comic text-xl")], [
                  html.text("Rule Variant"),
                ]),
                html.div(
                  [
                    attribute.class("flex flex-row md:flex-col mt-2 border-2"),
                    attribute.class("border-black rounded-xl truncate"),
                    attribute.class("font-comic"),
                  ],
                  [
                    html.button(
                      [
                        attribute.class("px-2 py-3 w-fit md:w-full md:h-fit"),
                        attribute.class("text-nowrap rounded-b-none border-b-2"),
                        attribute.class("border-black"),
                        attribute.class(case model.rule_variant {
                          shared.RiverSacrifice -> "bg-blue-500 text-white"
                          shared.FlemishGiant -> "hover:bg-blue-300"
                        }),
                        event.on_click(UserClickedChangeRuleVariant(
                          shared.RiverSacrifice,
                        )),
                      ],
                      [html.text("Classic")],
                    ),
                    html.button(
                      [
                        attribute.class("px-2 py-3 w-fit md:w-full md:h-fit"),
                        attribute.class("text-nowrap"),
                        attribute.class(case model.rule_variant {
                          shared.FlemishGiant -> "bg-blue-500 text-white"
                          shared.RiverSacrifice -> "hover:bg-blue-300"
                        }),
                        event.on_click(UserClickedChangeRuleVariant(
                          shared.FlemishGiant,
                        )),
                      ],
                      [html.text("Flemish Giant")],
                    ),
                  ],
                ),
              ]),
            ]),
          ]),
          component.game_view(component.Model(
            game: model.game,
            moves: model.current_piece_moves,
            player_color: Some(shared.White),
            premove: None,
            dragged_over_square: model.dragged_over_square,
            dragged_piece: model.dragged_piece,
          ))
            |> element.map(ComponentProducedMessage),
        ],
      ),

      component.dragged_piece_view(model.game, model.dragged_piece)
        |> element.map(ComponentProducedMessage),
    ],
  )
  |> component.game_layout(model.dragged_piece, ComponentProducedMessage)
}
