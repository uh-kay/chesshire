import cheg
import client/component
import client/icon
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import shared

pub type Model {
  Model(
    river_knight_model: RiverKnightModel,
    pawn_sacrifice_model: PawnSacrificeModel,
    bridge_movement_model: BridgeMovementModel,
  )
}

pub type Piece {
  Piece(color: shared.PlayerColor, type_: cheg.PieceType)
}

pub type BoardType {
  RiverKnight
  PawnSacrifice
  BridgeMovement
}

pub type RiverKnightModel {
  RiverKnightModel(
    board: dict.Dict(Int, Option(Piece)),
    moves: List(#(Int, Int)),
    can_move: Bool,
  )
}

pub type PawnSacrificeModel {
  PawnSacrificeModel(
    board: dict.Dict(Int, Option(Piece)),
    moves: List(#(Int, Int)),
    can_move: Bool,
    river_squares: List(Int),
    bridge_squares: List(Int),
  )
}

pub type BridgeMovementModel {
  BridgeMovementModel(
    board: dict.Dict(Int, Option(Piece)),
    moves: List(#(Int, Int)),
    can_move: Bool,
    river_squares: List(Int),
    bridge_squares: List(Int),
  )
}

pub type Message {
  UserClickedPiece(for: BoardType, from: Int)
  UserClickedTargetSquare(for: BoardType, move: #(Int, Int))
}

pub fn init() {
  let river_knight_model =
    RiverKnightModel(
      board: dict.from_list([
        #(1, None),
        #(2, Some(Piece(shared.White, cheg.Knight))),
        #(3, None),
        #(4, None),
        #(5, None),
        #(6, None),
        #(7, None),
        #(8, None),
        #(9, None),
      ]),
      moves: [],
      can_move: True,
    )
  let pawn_sacrifice_model =
    PawnSacrificeModel(
      board: dict.from_list([
        #(1, None),
        #(2, Some(Piece(shared.White, cheg.Pawn))),
        #(3, None),
        #(4, None),
        #(5, None),
        #(6, None),
        #(7, None),
        #(8, None),
        #(9, None),
      ]),
      moves: [],
      can_move: True,
      river_squares: [4, 5, 6],
      bridge_squares: [],
    )
  let bridge_movement_model =
    BridgeMovementModel(
      board: dict.from_list([
        #(1, Some(Piece(shared.White, cheg.Bishop))),
        #(2, None),
        #(3, None),
        #(4, None),
        #(5, None),
        #(6, None),
        #(7, None),
        #(8, None),
        #(9, Some(Piece(shared.Black, cheg.Pawn))),
      ]),
      moves: [],
      can_move: True,
      river_squares: [4, 6],
      bridge_squares: [5],
    )

  Model(river_knight_model:, pawn_sacrifice_model:, bridge_movement_model:)
}

pub fn update(model: Model, message: Message) {
  case message {
    UserClickedPiece(for:, from:) -> {
      let model = case for {
        RiverKnight -> {
          let moves = case model.river_knight_model.can_move {
            True -> [#(from, 7), #(from, 9)]
            False -> []
          }

          Model(
            ..model,
            river_knight_model: RiverKnightModel(
              ..model.river_knight_model,
              moves:,
            ),
          )
        }
        PawnSacrifice -> {
          let moves = case model.pawn_sacrifice_model.can_move {
            True -> [#(from, 5)]
            False -> []
          }

          Model(
            ..model,
            pawn_sacrifice_model: PawnSacrificeModel(
              ..model.pawn_sacrifice_model,
              moves:,
            ),
          )
        }
        BridgeMovement -> {
          let moves = case model.bridge_movement_model.can_move {
            True -> [#(from, 5), #(from, 9)]
            False -> []
          }

          Model(
            ..model,
            bridge_movement_model: BridgeMovementModel(
              ..model.bridge_movement_model,
              moves:,
            ),
          )
        }
      }

      #(model, effect.none())
    }

    UserClickedTargetSquare(move:, for:) -> {
      let model = case for {
        RiverKnight -> {
          let piece = case dict.get(model.river_knight_model.board, move.0) {
            Ok(piece) -> piece
            Error(_) -> None
          }
          let board =
            model.river_knight_model.board
            |> dict.insert(move.0, None)
            |> dict.insert(move.1, piece)
          let moves = []
          let can_move = False

          Model(
            ..model,
            river_knight_model: RiverKnightModel(board:, moves:, can_move:),
          )
        }
        PawnSacrifice -> {
          let board =
            model.pawn_sacrifice_model.board
            |> dict.insert(move.0, None)

          let moves = []
          let can_move = False
          let river_squares =
            list.filter(model.pawn_sacrifice_model.river_squares, fn(pos) {
              pos != move.1
            })
          let bridge_squares = [move.1]

          Model(
            ..model,
            pawn_sacrifice_model: PawnSacrificeModel(
              board:,
              moves:,
              can_move:,
              river_squares:,
              bridge_squares:,
            ),
          )
        }
        BridgeMovement -> {
          let piece = case dict.get(model.bridge_movement_model.board, move.0) {
            Ok(piece) -> piece
            Error(_) -> None
          }
          let board =
            model.bridge_movement_model.board
            |> dict.insert(move.0, None)
            |> dict.insert(move.1, piece)
          let moves = []
          let can_move = False

          Model(
            ..model,
            bridge_movement_model: BridgeMovementModel(
              ..model.bridge_movement_model,
              board:,
              moves:,
              can_move:,
            ),
          )
        }
      }

      #(model, effect.none())
    }
  }
}

// TODO: maybe also explain that pieces cannot attack across river?
pub fn view(model: Model) {
  let board_style =
    attribute.class("border grid grid-cols-3 grid-rows-3 scale-y-[-1] shrink-0")

  html.div([attribute.class("max-w-2xl mx-auto")], [
    html.h1([attribute.class("text-2xl pt-8 mb-8")], [
      html.text("Learn Chesshire"),
    ]),
    html.p([attribute.class("text-lg mb-8")], [
      html.text("Normal chess rule applies but with these additions:"),
    ]),
    html.h2([attribute.class("text-xl mb-4")], [html.text("River Square")]),
    html.div([attribute.class("flex justify-between gap-8 items-center mb-4")], [
      html.p([attribute.class("text-lg")], [
        html.text("Knight can jump over the river."),
      ]),
      html.div(
        [board_style],
        demo_view(
          RiverKnight,
          model.river_knight_model.board,
          [4, 5, 6],
          [],
          model.river_knight_model.moves,
        ),
      ),
    ]),
    html.div([attribute.class("flex gap-8 items-center justify-between mb-8")], [
      html.p([attribute.class("text-lg")], [
        html.text(
          "Any piece can be sacrificed at the river to create a bridge square.",
        ),
      ]),
      html.div(
        [board_style],
        demo_view(
          PawnSacrifice,
          model.pawn_sacrifice_model.board,
          model.pawn_sacrifice_model.river_squares,
          model.pawn_sacrifice_model.bridge_squares,
          model.pawn_sacrifice_model.moves,
        ),
      ),
    ]),
    html.h2([attribute.class("mb-4 text-xl")], [html.text("Bridge Square")]),
    html.div([attribute.class("flex justify-between gap-8 items-center mb-4")], [
      html.p([attribute.class("text-lg")], [
        html.text("Any piece can use the bridge to move to the other side "),
        html.text("and attack pieces on the other side."),
      ]),
      html.div(
        [board_style],
        demo_view(
          BridgeMovement,
          model.bridge_movement_model.board,
          model.bridge_movement_model.river_squares,
          model.bridge_movement_model.bridge_squares,
          model.bridge_movement_model.moves,
        ),
      ),
    ]),
  ])
  |> component.layout
}

fn demo_view(for, board, river_squares, bridge_squares, moves) {
  let board =
    dict.to_list(board)
    |> list.sort(fn(a, b) {
      let #(pos_a, _) = a
      let #(pos_b, _) = b
      int.compare(pos_a, pos_b)
    })

  list.map(board, fn(value) {
    let #(pos, piece) = value

    let river_squares = river_squares
    let square_color = case pos % 2 == 0 {
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
      attribute.class("items-center relative"),
      component.square_color_style(square_color),
      case piece {
        Some(_) -> event.on_click(UserClickedPiece(for:, from: pos))
        None -> attribute.none()
      },
    ]

    let square_view =
      html.div(square_style, [
        html.div([attribute.class("w-18 scale-y-[-1]")], [piece_view(piece)]),
        special_square_marker(square_color, Some(shared.White)),
      ])

    let has_piece = option.is_some(piece)
    let target_square_view = fn(move) {
      html.div(
        [
          attribute.class(case list.contains(river_squares, pos) || has_piece {
            True -> "inset-ring-2 inset-ring-red-500"
            False -> ""
          }),
          event.on_click(UserClickedTargetSquare(for, move)),
          ..square_style
        ],
        [
          html.div(
            [
              attribute.class(case piece {
                Some(_) -> "w-18 z-40 flex justify-center"
                None -> "w-3 h-3 rounded-full bg-black/30"
              }),
              attribute.class("scale-y-[-1]"),
            ],
            [piece_view(piece)],
          ),
          special_square_marker(square_color, Some(shared.White)),
        ],
      )
    }
    let moves = moves
    let to_moves =
      list.map(moves, fn(value) {
        let #(_, to) = value
        to
      })

    case list.contains(to_moves, pos) {
      True ->
        target_square_view(case list.find(moves, fn(move) { move.1 == pos }) {
          Ok(move) -> move
          Error(_) -> #(-1, -1)
        })
      False -> square_view
    }
  })
}

fn piece_view(piece: Option(Piece)) -> Element(Message) {
  case piece {
    Some(Piece(shared.White, cheg.Pawn)) -> icon.white_pawn()
    Some(Piece(shared.White, cheg.Knight)) -> icon.white_knight()
    Some(Piece(shared.White, cheg.Bishop)) -> icon.white_bishop()
    Some(Piece(shared.White, cheg.Rook)) -> icon.white_rook()
    Some(Piece(shared.White, cheg.Queen)) -> icon.white_queen()
    Some(Piece(shared.White, cheg.King)) -> icon.white_king()
    Some(Piece(shared.Black, cheg.Pawn)) -> icon.black_pawn()
    Some(Piece(shared.Black, cheg.Knight)) -> icon.black_knight()
    Some(Piece(shared.Black, cheg.Bishop)) -> icon.black_bishop()
    Some(Piece(shared.Black, cheg.Rook)) -> icon.black_rook()
    Some(Piece(shared.Black, cheg.Queen)) -> icon.black_queen()
    Some(Piece(shared.Black, cheg.King)) -> icon.black_king()
    None -> element.none()
  }
}

fn special_square_marker(
  square_color: component.SquareColor,
  player_color: Option(shared.PlayerColor),
) -> Element(a) {
  let special_square_style = [
    attribute.class("absolute text-white"),
    attribute.class(case player_color {
      Some(shared.White) -> "bottom-0 left-2"
      Some(shared.Black) -> "top-0 right-2"
      None -> "bottom-0 left-2"
    }),
  ]
  case square_color {
    component.Blue ->
      html.div(
        [attribute.class("text-xl select-none"), ..special_square_style],
        [html.text("~")],
      )
    component.Brown ->
      html.div(
        [attribute.class("text-base select-none"), ..special_square_style],
        [html.text("][")],
      )
    _ -> element.none()
  }
}
