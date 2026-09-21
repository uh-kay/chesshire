import cheg
import client/component
import client/dom
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import lustre/attribute
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import shared

pub type Model {
  Model(
    dragged_piece: Option(DraggedPiece),
    dragged_over_square: Option(#(BoardType, Int)),
    move: Option(#(Int, Int)),
    river_knight_model: RiverKnightModel,
    pawn_sacrifice_model: PawnSacrificeModel,
    bridge_movement_model: BridgeMovementModel,
  )
}

pub type BoardType {
  RiverKnight
  PawnSacrifice
  BridgeMovement
}

pub type DraggedPiece {
  DraggedPiece(
    for: BoardType,
    width: Int,
    height: Int,
    from: Int,
    pointer_x: Int,
    pointer_y: Int,
    offset_x: Int,
    offset_y: Int,
  )
}

pub type RiverKnightModel {
  RiverKnightModel(
    board: Dict(Int, Option(#(cheg.PieceType, shared.PlayerColor))),
    moves: List(#(Int, Int)),
    can_move: Bool,
  )
}

pub type PawnSacrificeModel {
  PawnSacrificeModel(
    board: Dict(Int, Option(#(cheg.PieceType, shared.PlayerColor))),
    moves: List(#(Int, Int)),
    can_move: Bool,
    river_squares: List(Int),
    bridge_squares: List(Int),
  )
}

pub type BridgeMovementModel {
  BridgeMovementModel(
    board: Dict(Int, Option(#(cheg.PieceType, shared.PlayerColor))),
    moves: List(#(Int, Int)),
    can_move: Bool,
    river_squares: List(Int),
    bridge_squares: List(Int),
  )
}

pub type Message {
  UserClickedPiece(for: BoardType, from: Int)
  UserClickedTargetSquare(for: BoardType, move: #(Int, Int))
  UserDraggedPiece(
    for: BoardType,
    from: Int,
    width: Int,
    height: Int,
    pointer_x: Int,
    pointer_y: Int,
    offset_x: Int,
    offset_y: Int,
  )
  UserDraggedToTargetSquare(move: #(Int, Int), for: BoardType)
  UserDraggedOutOfTargetSquare
  UserMovedPiece(pointer_x: Int, pointer_y: Int)
  UserCanceledDrag
  UserDroppedPiece
}

pub fn init() {
  let river_knight_model =
    RiverKnightModel(
      board: dict.from_list([
        #(1, None),
        #(2, Some(#(cheg.Knight, shared.White))),
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
        #(2, Some(#(cheg.Pawn, shared.White))),
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
        #(1, Some(#(cheg.Bishop, shared.White))),
        #(2, None),
        #(3, None),
        #(4, None),
        #(5, None),
        #(6, None),
        #(7, None),
        #(8, None),
        #(9, Some(#(cheg.Pawn, shared.Black))),
      ]),
      moves: [],
      can_move: True,
      river_squares: [4, 6],
      bridge_squares: [5],
    )

  Model(
    river_knight_model:,
    pawn_sacrifice_model:,
    bridge_movement_model:,
    move: None,
    dragged_piece: None,
    dragged_over_square: None,
  )
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

    UserCanceledDrag -> {
      let model =
        Model(
          river_knight_model: RiverKnightModel(
            ..model.river_knight_model,
            moves: [],
          ),
          pawn_sacrifice_model: PawnSacrificeModel(
            ..model.pawn_sacrifice_model,
            moves: [],
          ),
          bridge_movement_model: BridgeMovementModel(
            ..model.bridge_movement_model,
            moves: [],
          ),
          move: None,
          dragged_over_square: None,
          dragged_piece: None,
        )

      #(model, effect.none())
    }
    UserDraggedPiece(
      for:,
      from:,
      pointer_x:,
      pointer_y:,
      offset_x:,
      offset_y:,
      width:,
      height:,
    ) -> {
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

      let model =
        Model(
          ..model,
          dragged_piece: Some(DraggedPiece(
            for:,
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
    UserMovedPiece(pointer_x:, pointer_y:) -> {
      let dragged_piece =
        option.map(model.dragged_piece, fn(dragged_piece) {
          DraggedPiece(..dragged_piece, pointer_x:, pointer_y:)
        })
      let model = Model(..model, dragged_piece:)

      #(model, effect.none())
    }
    UserDroppedPiece -> {
      let result = {
        use dragged_over_square <- result.try(option.to_result(
          model.dragged_over_square,
          Nil,
        ))
        use move <- result.try(option.to_result(model.move, Nil))
        let for = dragged_over_square.0

        let apply = fn(board) {
          let piece = case dict.get(board, move.0) {
            Ok(piece) -> piece
            Error(_) -> None
          }

          board
          |> dict.insert(move.0, None)
          |> dict.insert(move.1, piece)
        }
        let model = case for {
          RiverKnight -> {
            let board = apply(model.river_knight_model.board)
            Model(
              ..model,
              river_knight_model: RiverKnightModel(
                board:,
                moves: [],
                can_move: False,
              ),
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
            let board = apply(model.bridge_movement_model.board)
            Model(
              ..model,
              bridge_movement_model: BridgeMovementModel(
                ..model.bridge_movement_model,
                board:,
                moves: [],
                can_move: False,
              ),
            )
          }
        }

        Ok(model)
      }

      let model = case result {
        Ok(model) -> model
        Error(_) -> model
      }
      let model =
        Model(
          ..model,
          dragged_over_square: None,
          dragged_piece: None,
          move: None,
        )

      #(model, effect.none())
    }
    UserDraggedToTargetSquare(move:, for:) -> {
      let model =
        Model(
          ..model,
          dragged_over_square: Some(#(for, move.1)),
          move: Some(move),
        )

      #(model, effect.none())
    }
    UserDraggedOutOfTargetSquare -> {
      let model = Model(..model, dragged_over_square: None, move: None)

      #(model, effect.none())
    }
  }
}

// TODO: maybe also explain that pieces cannot attack across river?
pub fn view(model: Model) {
  let board_style =
    attribute.class("border grid grid-cols-3 grid-rows-3 scale-y-[-1] shrink-0")
  let dragged_over_square = fn(board_type) {
    case model.dragged_over_square {
      Some(dragged_square) if dragged_square.0 == board_type ->
        Some(dragged_square.1)
      _ -> None
    }
  }
  let piece = case model.dragged_piece {
    Some(dragged_piece) -> {
      case dragged_piece.for {
        RiverKnight ->
          dict.get(model.river_knight_model.board, dragged_piece.from)
          |> result.unwrap(None)
        PawnSacrifice ->
          dict.get(model.pawn_sacrifice_model.board, dragged_piece.from)
          |> result.unwrap(None)
        BridgeMovement ->
          dict.get(model.bridge_movement_model.board, dragged_piece.from)
          |> result.unwrap(None)
      }
    }
    None -> None
  }

  html.div(
    [
      event.on("pointermove", {
        use pointer_x <- decode.field("clientX", decode.float)
        use pointer_y <- decode.field("clientY", decode.float)
        decode.success(UserMovedPiece(
          float.truncate(pointer_x),
          float.truncate(pointer_y),
        ))
      }),
      event.on("pointerup", decode.success(UserDroppedPiece)),
    ],
    [
      html.div(
        [
          attribute.class("flex flex-col max-w-2xl min-h-screen mx-auto"),
        ],
        [
          html.h1([attribute.class("text-2xl pt-8 mb-8")], [
            html.text("Learn Chesshire"),
          ]),
          html.p([attribute.class("text-lg mb-8")], [
            html.text("Normal chess rule applies but with these additions:"),
          ]),
          html.h2([attribute.class("text-xl mb-4")], [html.text("River Square")]),
          html.div(
            [attribute.class("flex justify-between gap-8 items-center mb-4")],
            [
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
                  dragged_over_square(RiverKnight),
                ),
              ),
            ],
          ),
          html.div(
            [attribute.class("flex gap-8 items-center justify-between mb-8")],
            [
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
                  dragged_over_square(PawnSacrifice),
                ),
              ),
            ],
          ),
          html.h2([attribute.class("mb-4 text-xl")], [
            html.text("Bridge Square"),
          ]),
          html.div(
            [attribute.class("flex justify-between gap-8 items-center mb-4")],
            [
              html.p([attribute.class("text-lg")], [
                html.text(
                  "Any piece can use the bridge to move to the other side ",
                ),
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
                  dragged_over_square(BridgeMovement),
                ),
              ),
            ],
          ),
          case model.dragged_piece {
            Some(dragged_piece) -> {
              html.div(
                [
                  attribute.class("fixed z-50 pointer-events-none"),
                  attribute.style(
                    "left",
                    int.to_string(
                      dragged_piece.pointer_x - dragged_piece.offset_x,
                    )
                      <> "px",
                  ),
                  attribute.style(
                    "top",
                    int.to_string(
                      dragged_piece.pointer_y - dragged_piece.offset_y,
                    )
                      <> "px",
                  ),
                  attribute.style(
                    "width",
                    int.to_string(dragged_piece.width) <> "px",
                  ),
                  attribute.style(
                    "height",
                    int.to_string(dragged_piece.height) <> "px",
                  ),
                ],
                [component.piece_view(piece)],
              )
            }
            None -> element.none()
          },
        ],
      ),
    ],
  )
  |> component.layout
}

fn demo_view(
  for: BoardType,
  board: Dict(Int, Option(#(cheg.PieceType, shared.PlayerColor))),
  river_squares: List(Int),
  bridge_squares: List(Int),
  moves: List(#(Int, Int)),
  dragover_square: Option(Int),
) -> List(Element(Message)) {
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
      attribute.class("items-center relative touch-none"),
      component.square_color_style(square_color),
      case piece {
        Some(_) -> event.on_click(UserClickedPiece(for:, from: pos))
        None -> attribute.none()
      },
    ]

    let square_view =
      html.div(square_style, [
        html.div(
          [
            attribute.class("w-18 scale-y-[-1]"),
            event.on("pointerdown", {
              use pointer_x <- decode.field("clientX", decode.float)
              use pointer_y <- decode.field("clientY", decode.float)
              use pointer_id <- decode.field("pointerId", decode.int)
              use element <- decode.field("currentTarget", decode.dynamic)

              dom.release_pointer_capture(element, pointer_id)

              let pointer_x = float.truncate(pointer_x)
              let pointer_y = float.truncate(pointer_y)
              let rect = dom.get_rect(element)
              let offset_x = pointer_x - rect.x
              let offset_y = pointer_y - rect.y

              decode.success(UserDraggedPiece(
                for:,
                from: pos,
                pointer_x: pointer_x,
                pointer_y:,
                offset_x:,
                offset_y:,
                width: rect.width,
                height: rect.height,
              ))
            }),
          ],
          [component.piece_view(piece)],
        ),
        component.special_square_marker(square_color, Some(shared.White)),
      ])

    let has_piece = option.is_some(piece)
    let target_square_view = fn(move, is_dragover) {
      html.div(
        [
          attribute.class(case list.contains(river_squares, pos) || has_piece {
            True -> "inset-ring-2 inset-ring-red-500"
            False -> ""
          }),
          event.on_click(UserClickedTargetSquare(for, move)),
          event.on(
            "pointerenter",
            decode.success(UserDraggedToTargetSquare(move, for)),
          ),
          event.on("pointerleave", decode.success(UserDraggedOutOfTargetSquare)),
          ..square_style
        ],
        [
          html.div(
            [
              attribute.class(case piece, is_dragover {
                Some(_), True ->
                  "w-full h-full flex justify-center items-center bg-purple-700/15"
                Some(_), False -> "w-18 z-40 flex justify-center"
                None, False -> "w-3 h-3 rounded-full bg-black/30"
                None, True -> "w-full h-full bg-purple-700/15"
              }),
              attribute.class("scale-y-[-1]"),
            ],
            [component.piece_view(piece)],
          ),
          component.special_square_marker(square_color, Some(shared.White)),
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
        target_square_view(
          case list.find(moves, fn(move) { move.1 == pos }) {
            Ok(move) -> move
            Error(_) -> #(-1, -1)
          },
          dragover_square == Some(pos),
        )
      False -> square_view
    }
  })
}
