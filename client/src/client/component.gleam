import cheg
import client/dom
import client/icon
import gleam/dict
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import shared

pub type Message {
  UserClickedPiece(
    piece: Option(#(cheg.PieceType, shared.PlayerColor)),
    position: Int,
  )
  UserClickedTargetSquare(move: cheg.Move)
  UserDraggedPiece(
    from: Int,
    pointer_x: Int,
    pointer_y: Int,
    offset_x: Int,
    offset_y: Int,
    width: Int,
    height: Int,
  )
  UserDraggedToTargetSquare(move: cheg.Move, position: Int)
  UserDraggedOutOfTargetSquare
  UserMovedPiece(pointer_x: Int, pointer_y: Int)
  UserDroppedPiece
  UserCancelledDrag
  UserClickedEmptySquare
}

pub type Model {
  Model(
    game: cheg.Game,
    moves: List(cheg.Move),
    player_color: Option(shared.PlayerColor),
    premove: Option(cheg.Move),
    dragged_over_square: Option(Int),
    dragged_piece: Option(DraggedPiece),
  )
}

pub type DraggedPiece {
  DraggedPiece(
    width: Int,
    height: Int,
    from: Int,
    pointer_x: Int,
    pointer_y: Int,
    offset_x: Int,
    offset_y: Int,
  )
}

pub type SquareColor {
  White
  Black
  Brown
  Blue
}

pub fn game_view(model: Model) -> Element(Message) {
  html.div([attribute.class("")], [
    html.div(
      [
        attribute.class("grid grid-cols-8 grid-rows-9 w-fit md:w-full"),
        attribute.class("min-h-fit md:min-h-108 outline-2"),
        case model.player_color {
          Some(shared.White) -> attribute.class("scale-y-[-1]")
          Some(shared.Black) -> attribute.class("scale-x-[-1]")
          None -> attribute.class("scale-y-[-1]")
        },
      ],
      board_view(model),
    ),
  ])
}

pub fn board_view(model: Model) -> List(Element(Message)) {
  let board = cheg.board(model.game)
  let new_board = dict.map_values(board, fn(_, v) { Some(v) })
  let dragged_piece_position = case model.dragged_piece {
    Some(dragged_piece) -> {
      dragged_piece.from
    }
    None -> -1
  }

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

  new_board
  |> dict.to_list
  |> list.sort(fn(a, b) {
    let #(pos_a, _) = a
    let #(pos_b, _) = b
    int.compare(pos_a, pos_b)
  })
  |> list.map(fn(square) {
    let #(pos, piece) = square
    let row = pos / 8
    let col = pos % 8

    let color = case { row + col } % 2 == 0 {
      True -> Black
      False -> White
    }
    let river_square = cheg.river_squares(model.game)
    let bridge_square = cheg.bridge_squares(model.game)
    let color = case list.contains(river_square, pos) {
      True -> Blue
      False ->
        case list.contains(bridge_square, pos) {
          True -> Brown
          False -> color
        }
    }

    let #(last_from, last_to) = cheg.last_move(model.game)

    let last_move = last_from == pos || last_to == pos
    let in_check = cheg.in_check(model.game)
    let checked_piece = case in_check, cheg.to_move(model.game) {
      True, shared.Black -> Some(#(cheg.King, shared.Black))
      True, shared.White -> Some(#(cheg.King, shared.White))
      _, _ -> None
    }
    let is_premove = case model.premove {
      Some(premove) ->
        cheg.move_from(premove) == pos || cheg.move_to(premove) == pos
      None -> False
    }

    case list.find(model.moves, fn(move) { cheg.move_to(move) == pos }) {
      Ok(move) ->
        target_square_view(
          pos,
          color,
          model.player_color,
          piece,
          move,
          last_move,
          list.contains(river_square, cheg.move_to(move)),
          model.dragged_over_square == Some(pos),
        )
      Error(_) ->
        square_view(
          pos,
          model.player_color,
          color,
          piece,
          last_move,
          checked_piece,
          is_premove,
          dragged_piece_position == pos,
        )
    }
  })
}

fn target_square_view(
  position: Int,
  square_color: SquareColor,
  player_color: Option(shared.PlayerColor),
  piece: Option(#(cheg.PieceType, shared.PlayerColor)),
  move: cheg.Move,
  is_last_move: Bool,
  is_river: Bool,
  is_dragover: Bool,
) -> Element(Message) {
  let has_piece = option.is_some(piece)

  html.div(
    [
      square_style(),
      square_color_style(square_color),
      attribute.class(case has_piece || is_river {
        True -> "inset-ring-2 inset-ring-red-500"
        False -> ""
      }),
      event.on_click(UserClickedTargetSquare(move)),
      event.on(
        "pointerenter",
        decode.success(UserDraggedToTargetSquare(move, position)),
      ),
      event.on("pointerleave", decode.success(UserDraggedOutOfTargetSquare)),
    ],
    [
      special_square_marker(square_color, player_color),
      html.div(
        [
          attribute.class(case piece, is_dragover {
            Some(_), True ->
              "w-full h-full flex justify-center items-center bg-purple-700/15"
            Some(_), False -> "w-18 z-40 flex justify-center"
            None, False -> "w-3 h-3 lg:w-5 lg:h-5 rounded-full bg-black/30"
            None, True -> "w-full h-full bg-purple-700/15"
          }),
          attribute.class(case piece, player_color {
            Some(_), Some(shared.White) -> "scale-y-[-1]"
            Some(_), Some(shared.Black) -> "scale-x-[-1]"
            Some(_), None -> "scale-y-[-1]"
            None, _ -> ""
          }),
        ],
        [
          html.div([attribute.class("w-full md:w-16 select-none touch-none")], [
            piece_view(piece),
          ]),
        ],
      ),
      html.div(
        [
          attribute.class(case is_last_move {
            True -> "absolute inset-0 bg-yellow-400/30"
            False -> ""
          }),
        ],
        [],
      ),
    ],
  )
}

fn square_view(
  position: Int,
  player_color: Option(shared.PlayerColor),
  square_color: SquareColor,
  piece: Option(#(cheg.PieceType, shared.PlayerColor)),
  is_last_move: Bool,
  checked_king: option.Option(#(cheg.PieceType, shared.PlayerColor)),
  is_premove: Bool,
  is_dragged: Bool,
) -> Element(Message) {
  html.div(
    [
      square_style(),
      square_color_style(square_color),
      attribute.class(case checked_king, piece {
        Some(checked_king), Some(piece) if checked_king == piece ->
          "bg-radial-[at_50%_50%] from-red-500 to-transparent"
        _, _ -> ""
      }),
      attribute.value("pos-" <> int.to_string(position)),
      case option.is_none(piece) {
        True -> event.on_click(UserClickedEmptySquare)
        False -> attribute.none()
      },
    ],
    [
      special_square_marker(square_color, player_color),
      html.div(
        [
          attribute.class("w-18 z-40 flex justify-center"),
          attribute.class(case player_color {
            Some(shared.White) -> "scale-y-[-1]"
            Some(shared.Black) -> "scale-x-[-1]"
            None -> "scale-y-[-1]"
          }),
        ],
        [
          html.div(
            [
              attribute.class("w-full md:w-16 select-none touch-none"),
              attribute.class(case is_dragged {
                True -> "opacity-20"
                False -> ""
              }),
              event.on_click(UserClickedPiece(piece, position)),
              event.on("pointerdown", {
                use pointer_x <- decode.field("clientX", decode.float)
                use pointer_y <- decode.field("clientY", decode.float)
                use current <- decode.field("currentTarget", decode.dynamic)
                use target <- decode.field("target", decode.dynamic)
                use pointer_id <- decode.field("pointerId", decode.int)

                dom.release_pointer_capture(target, pointer_id)

                let pointer_x = float.truncate(pointer_x)
                let pointer_y = float.truncate(pointer_y)
                let rect = dom.get_rect(current)
                let offset_x = pointer_x - rect.x
                let offset_y = pointer_y - rect.y

                decode.success(UserDraggedPiece(
                  from: position,
                  pointer_x:,
                  pointer_y:,
                  offset_x:,
                  offset_y:,
                  width: rect.width,
                  height: rect.height,
                ))
              }),
            ],
            [piece_view(piece)],
          ),
        ],
      ),
      html.div(
        [
          attribute.class("absolute inset-0"),
          attribute.class(case is_dragged {
            True -> "bg-purple-700/15"
            False -> ""
          }),
        ],
        [],
      ),
      last_move_indicator(is_last_move),
      premove_indicator(is_premove),
    ],
  )
}

fn square_style() {
  attribute.class("flex justify-center items-center relative aspect-square")
}

pub fn square_color_style(square_color: SquareColor) {
  attribute.class(case square_color {
    White -> "bg-white-square"
    Black -> "bg-black-square"
    Blue -> "bg-river-square"
    Brown -> "bg-bridge-square"
  })
}

pub fn special_square_marker(
  square_color: SquareColor,
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
    Blue ->
      html.div(
        [attribute.class("text-xl select-none"), ..special_square_style],
        [html.text("~")],
      )
    Brown ->
      html.div(
        [attribute.class("text-base select-none"), ..special_square_style],
        [html.text("][")],
      )
    _ -> element.none()
  }
}

fn last_move_indicator(is_last_move: Bool) -> Element(a) {
  html.div(
    [
      attribute.class(case is_last_move {
        True -> "absolute inset-0 bg-yellow-400/30"
        False -> ""
      }),
    ],
    [],
  )
}

fn premove_indicator(is_premove: Bool) {
  html.div(
    [
      attribute.class(case is_premove {
        True -> "absolute inset-0 bg-pink-400/30"
        False -> ""
      }),
    ],
    [],
  )
}

pub fn piece_view(
  piece: Option(#(cheg.PieceType, shared.PlayerColor)),
) -> Element(_) {
  case piece {
    Some(#(cheg.Pawn, shared.White)) -> icon.white_pawn()
    Some(#(cheg.Rabbit, shared.White)) -> icon.white_rabbit()
    Some(#(cheg.Knight, shared.White)) -> icon.white_knight()
    Some(#(cheg.Bishop, shared.White)) -> icon.white_bishop()
    Some(#(cheg.Rook, shared.White)) -> icon.white_rook()
    Some(#(cheg.Queen, shared.White)) -> icon.white_queen()
    Some(#(cheg.King, shared.White)) -> icon.white_king()
    Some(#(cheg.Pawn, shared.Black)) -> icon.black_pawn()
    Some(#(cheg.Rabbit, shared.Black)) -> icon.black_rabbit()
    Some(#(cheg.Knight, shared.Black)) -> icon.black_knight()
    Some(#(cheg.Bishop, shared.Black)) -> icon.black_bishop()
    Some(#(cheg.Rook, shared.Black)) -> icon.black_rook()
    Some(#(cheg.Queen, shared.Black)) -> icon.black_queen()
    Some(#(cheg.King, shared.Black)) -> icon.black_king()
    None -> element.none()
  }
}

pub fn dragged_piece_view(
  game: cheg.Game,
  dragged_piece: Option(DraggedPiece),
) -> Element(a) {
  case dragged_piece {
    Some(dragged_piece) -> {
      let piece =
        dict.get(cheg.board(game), dragged_piece.from)
        |> option.from_result()
      html.div(
        [
          attribute.class("fixed z-50 pointer-events-none"),
          attribute.style(
            "left",
            int.to_string(dragged_piece.pointer_x - dragged_piece.offset_x)
              <> "px",
          ),
          attribute.style(
            "top",
            int.to_string(dragged_piece.pointer_y - dragged_piece.offset_y)
              <> "px",
          ),
          attribute.style("width", int.to_string(dragged_piece.width) <> "px"),
          attribute.style("height", int.to_string(dragged_piece.height) <> "px"),
        ],
        [piece_view(piece)],
      )
    }
    None -> element.none()
  }
}

fn captured_piece_view(
  value: #(cheg.PieceType, shared.PlayerColor),
  side: shared.PlayerColor,
  fill_color: String,
) -> Element(Message) {
  let #(piece, piece_color) = value

  case piece_color == side {
    True ->
      case piece {
        cheg.Pawn ->
          html.div([attribute.class("w-6 h-6")], [icon.pawn(fill_color)])
        cheg.Rabbit ->
          html.div([attribute.class("w-6 h-6")], [icon.rabbit(fill_color)])
        cheg.Knight ->
          html.div([attribute.class("w-6")], [icon.knight(fill_color)])
        cheg.Bishop ->
          html.div([attribute.class("w-6")], [icon.bishop(fill_color)])
        cheg.Rook -> html.div([attribute.class("w-6")], [icon.rook(fill_color)])
        cheg.Queen ->
          html.div([attribute.class("w-6")], [icon.queen(fill_color)])
        cheg.King -> html.div([attribute.class("w-6")], [element.none()])
      }

    False -> element.none()
  }
}

pub fn clock_view(
  black_time: Int,
  white_time: Int,
  player_color: Option(shared.PlayerColor),
  state: cheg.GameState,
  captured_pieces: cheg.CapturedPieces,
) -> Element(_) {
  let #(material_advantage, material_differences) =
    calculate_material_difference(captured_pieces.captured)
  let black_time = format_time(black_time)
  let white_time = format_time(white_time)

  html.div(
    [
      attribute.class("md:ml-8 mt-4 md:mt-0 flex justify-between items-start"),
      attribute.class("flex-col md:flex-col-reverse"),
    ],
    [
      html.div(
        [
          attribute.class("flex justify-between w-full md:h-full"),
          attribute.class(case player_color {
            Some(shared.Black) -> "md:flex-col-reverse"
            _ -> "flex-row-reverse md:flex-col"
          }),
        ],
        [
          html.div(
            [
              attribute.class("flex flex-col"),
              attribute.class(case player_color {
                Some(shared.Black) -> "md:flex-col-reverse"
                _ -> ""
              }),
            ],
            [
              captured_pieces_view(
                material_advantage,
                material_differences,
                shared.White,
              ),
              time_view(black_time),
            ],
          ),

          html.div(
            [
              attribute.class("rounded-lg border-black dark:border-dark"),
              attribute.class("divide-y-2 divide-black dark:divide-dark w-full"),
              attribute.class("truncate hidden md:inline"),
              attribute.class(case state == cheg.Continue {
                True -> ""
                False -> "border-2"
              }),
            ],
            [
              state_view(state, False),

              sacrificed_pieces_view(
                captured_pieces.sacrificed,
                False,
                state == cheg.Continue,
              ),
            ],
          ),

          html.div(
            [
              attribute.class("flex gap-2"),
              attribute.class(case player_color {
                Some(shared.White) -> "flex-col-reverse md:flex-col-reverse"
                _ -> "flex-col-reverse md:flex-col-reverse"
              }),
            ],
            [
              captured_pieces_view(
                material_advantage,
                material_differences,
                shared.Black,
              ),
              time_view(white_time),
            ],
          ),
        ],
      ),

      // Small screen
      html.div(
        [
          attribute.class("rounded-lg border-black dark:border-dark"),
          attribute.class("divide-y-2 divide-black dark:divide-dark md:w-full"),
          attribute.class("truncate flex flex-col md:hidden mx-auto mt-4"),
          attribute.class(case state == cheg.Continue {
            True -> ""
            False -> "border-2"
          }),
        ],
        [
          state_view(state, True),
          sacrificed_pieces_view(
            captured_pieces.sacrificed,
            True,
            state == cheg.Continue,
          ),
        ],
      ),
    ],
  )
}

fn time_view(time: String) -> Element(Message) {
  html.p(
    [
      attribute.class("w-30 rounded-md bg-blue-300 px-4 py-3 border-2"),
      attribute.class("text-center text-3xl dark:bg-blue-600 dark:border-dark"),
      attribute.class("truncate font-comic"),
    ],
    [html.text(time)],
  )
}

fn captured_pieces_view(
  material_advantage: #(Int, shared.PlayerColor),
  material_differences: List(#(cheg.PieceType, shared.PlayerColor)),
  color,
) -> Element(Message) {
  html.div([], [
    case material_advantage.1 == color {
      False -> element.none()
      True ->
        case material_advantage.0 > 0 {
          True ->
            html.div([attribute.class("flex")], [
              html.div(
                [attribute.class("flex max-w-30 flex-wrap gap-1")],
                remove_duplicate_piece(color, material_differences)
                  |> list.map(fn(value) {
                    case value.1 == color {
                      False -> element.none()
                      True -> captured_piece_view(value, color, "#6a7282")
                    }
                  }),
              ),
              html.p([], [
                html.text("+" <> int.to_string(material_advantage.0)),
              ]),
            ])
          False -> element.none()
        }
    },
  ])
}

fn state_view(state: cheg.GameState, is_mobile: Bool) -> Element(Message) {
  let text_box_style = [
    attribute.class("font-comic dark:bg-blue-600 flex justify-center"),
    attribute.class("bg-blue-300 p-2 text-wrap text-center items-center"),
    attribute.class(case is_mobile {
      True -> "max-w-64"
      False -> "max-w-30"
    }),
  ]

  case state {
    cheg.Continue -> element.none()
    cheg.Draw(reason:) ->
      html.div(text_box_style, [
        html.p([], [
          html.text(case reason {
            cheg.ThreefoldRepetition -> "Draw: threefold repetition"
            cheg.InsufficientMaterial -> "Draw: insufficient material"
            cheg.Stalemate -> "Draw: stalemate"
            cheg.FiftyMoves -> "Draw: fifty move rule"
          }),
        ]),
      ])
    cheg.WhiteWin ->
      html.div(text_box_style, [html.p([], [html.text("White wins")])])
    cheg.BlackWin ->
      html.div(text_box_style, [html.p([], [html.text("Black wins")])])
  }
}

fn sacrificed_pieces_view(
  sacrificed_pieces: List(#(cheg.PieceType, shared.PlayerColor)),
  is_mobile: Bool,
  has_border: Bool,
) -> Element(Message) {
  case list.is_empty(sacrificed_pieces) {
    True -> element.none()
    False ->
      html.div(
        [
          attribute.class("flex flex-col bg-blue-300 p-2 text-center"),
          attribute.class("dark:bg-blue-600 rounded-lg dark:border-dark-text"),
          attribute.class(case is_mobile {
            True -> "max-w-64"
            False -> "max-w-30"
          }),
          attribute.class(case has_border {
            True -> "border-2"
            False -> "rounded-t-none"
          }),
        ],
        [
          html.p([attribute.class("mb-2 text-md font-comic")], [
            html.text("Sacrificed:"),
          ]),
          html.div(
            [attribute.class("flex")],
            list.map(sacrificed_pieces, fn(value) {
              let #(_, color) = value
              let fill_color = case color {
                shared.Black -> "#000"
                shared.White -> "#fff"
              }
              captured_piece_view(value, color, fill_color)
            }),
          ),
        ],
      )
  }
}

pub fn navbar() -> Element(_) {
  html.nav(
    [
      attribute.class("p-4 h-[60px] border-b-2 bg-blue-200 border-black"),
      attribute.class("dark:bg-dark-secondary dark:border-dark"),
    ],
    [
      html.div(
        [attribute.class("flex justify-between items-center max-w-4xl mx-auto")],
        [
          html.a(
            [
              attribute.class("flex items-center text-2xl font-comic"),
              attribute.href("/"),
            ],
            [
              html.img([
                attribute.class("w-8 mr-2"),
                attribute.src("/chesshire_favicon.svg"),
                attribute.alt("Chesshire logo"),
              ]),
              html.text("Chesshire"),
            ],
          ),
          html.div([attribute.class("flex gap-4")], [
            html.a(
              [
                attribute.class("hover:text-blue-500 text-lg font-comic"),
                attribute.href("/learn"),
              ],
              [html.text("Learn")],
            ),
            html.a(
              [
                attribute.href("https://github.com/uh-kay/chesshire"),
                attribute.class("w-6 dark:text-dark hover:text-blue-600"),
              ],
              [icon.github()],
            ),
          ]),
        ],
      ),
    ],
  )
}

fn format_time(time: Int) {
  let time = time / 1000
  let minutes = time / 60
  let seconds = time % 60

  int.to_string(minutes)
  <> ":"
  <> string.pad_start(int.to_string(seconds), 2, "0")
}

pub fn layout(content: Element(a)) -> Element(a) {
  html.div(
    [attribute.class("bg-blue-100 min-h-dvh dark:bg-dark-base dark:text-dark")],
    [
      navbar(),
      html.main([], [content]),
    ],
  )
}

pub fn button_group(label_text: String, buttons: List(Element(a))) {
  html.div([], [
    html.label([attribute.class("font-comic text-xl")], [
      html.text(label_text),
    ]),
    html.div(
      [
        attribute.class("flex flex-row md:flex-col mt-2 border-2"),
        attribute.class("border-black rounded-xl truncate"),
        attribute.class("font-comic w-full divide-x-2"),
        attribute.class("md:divide-x-0 md:divide-y-2 divide-black"),
      ],
      buttons,
    ),
  ])
}

pub fn game_layout(
  content: Element(msg),
  dragged_piece: Option(DraggedPiece),
  to_msg: fn(Message) -> msg,
) -> Element(msg) {
  html.div(
    [
      case dragged_piece {
        Some(_) ->
          event.on("pointermove", {
            use pointer_x <- decode.field("clientX", decode.float)
            use pointer_y <- decode.field("clientY", decode.float)

            decode.success(
              to_msg(UserMovedPiece(
                pointer_x: float.truncate(pointer_x),
                pointer_y: float.truncate(pointer_y),
              )),
            )
          })
        None -> attribute.none()
      },
      event.on("pointerup", decode.success(to_msg(UserDroppedPiece))),
      event.on("pointercancel", decode.success(to_msg(UserCancelledDrag))),
      attribute.class("bg-blue-100 min-h-dvh dark:bg-dark-base dark:text-dark"),
    ],
    [
      navbar(),
      html.main([], [content]),
    ],
  )
}

fn remove_duplicate_piece(
  filtered_color: shared.PlayerColor,
  list: List(#(cheg.PieceType, shared.PlayerColor)),
) {
  skip_until_item(filtered_color, list, [])
}

fn skip_until_item(
  filtered_color: shared.PlayerColor,
  list: List(#(cheg.PieceType, shared.PlayerColor)),
  acc: List(#(cheg.PieceType, shared.PlayerColor)),
) {
  case list {
    [] -> list.reverse(acc)
    [first, ..rest]
      if first.1 == filtered_color
      && { first.0 == cheg.Pawn || first.0 == cheg.Rabbit }
    -> remove_piece(filtered_color, rest, [first, ..acc])
    [first, ..rest] -> skip_until_item(filtered_color, rest, [first, ..acc])
  }
}

fn remove_piece(
  filtered_color: shared.PlayerColor,
  list: List(#(cheg.PieceType, shared.PlayerColor)),
  acc: List(#(cheg.PieceType, shared.PlayerColor)),
) {
  case list {
    [] -> list.reverse(acc)
    [first, ..rest]
      if first.1 == filtered_color
      && { first.0 == cheg.Pawn || first.0 == cheg.Rabbit }
    -> remove_piece(filtered_color, rest, acc)
    [first, ..rest] -> remove_piece(filtered_color, rest, [first, ..acc])
  }
}

fn calculate_material_difference(
  list: List(#(cheg.PieceType, shared.PlayerColor)),
) -> #(#(Int, shared.PlayerColor), List(#(cheg.PieceType, shared.PlayerColor))) {
  let white_pieces = list.filter(list, fn(value) { value.1 == shared.White })
  let black_pieces = list.filter(list, fn(value) { value.1 == shared.Black })
  let black_piece_types = list.map(black_pieces, fn(value) { value.0 })
  let white_piece_types = list.map(white_pieces, fn(value) { value.0 })

  let only_white =
    list.filter(list, fn(value) {
      value.1 == shared.White && !list.contains(black_piece_types, value.0)
    })
  let only_black =
    list.filter(list, fn(value) {
      value.1 == shared.Black && !list.contains(white_piece_types, value.0)
    })

  let piece_differences = list.append(only_white, only_black)
  let black_material =
    list.fold(piece_differences, 0, fn(acc, value) {
      material_value(acc, value, shared.Black)
    })
  let white_material =
    list.fold(piece_differences, 0, fn(acc, value) {
      material_value(acc, value, shared.White)
    })
  let material_advantage = case black_material - white_material > 0 {
    True -> #(black_material - white_material, shared.Black)
    False -> #(white_material - black_material, shared.White)
  }

  #(material_advantage, piece_differences)
}

fn material_value(
  acc: Int,
  piece: #(cheg.PieceType, shared.PlayerColor),
  color: shared.PlayerColor,
) {
  let piece_value = case piece.0 {
    cheg.Pawn -> 1
    cheg.Rabbit -> 1
    cheg.Knight -> 3
    cheg.Bishop -> 3
    cheg.Rook -> 5
    cheg.Queen -> 9
    cheg.King -> 9001
  }
  case piece.1 == color {
    True -> acc + piece_value
    False -> acc
  }
}

pub fn button_style(
  attributes: List(attribute.Attribute(a)),
) -> List(attribute.Attribute(a)) {
  [
    attribute.class("px-2 py-3 bg-blue-600 text-white rounded-md flex"),
    attribute.class("hover:cursor-pointer transition-all gap-1 border-2"),
    attribute.class("border-black font-comic drop-shadow-[4px_4px_0_#000]"),
    attribute.class("hover:translate-x-[4px] hover:translate-y-[4px]"),
    attribute.class("hover:drop-shadow-none active:translate-x-[4px]"),
    attribute.class("active:translate-y-[4px] active:drop-shadow-none"),
    attribute.class("dark:drop-shadow-[4px_4px_0_hsl(217_100_90)]"),
    attribute.class("dark:border-dark"),
    ..attributes
  ]
}

pub fn variant_button_view(
  current_variant: a,
  active_variant: a,
  on_click: b,
  label: String,
) -> Element(b) {
  html.button(
    [
      attribute.class("px-2 py-3 w-full md:h-fit"),
      attribute.class("text-nowrap rounded-b-none"),
      attribute.class(case current_variant == active_variant {
        True -> "bg-blue-500 dark:bg-blue-600 text-white"
        False -> "hover:bg-blue-300 dark:hover:bg-blue-500"
      }),
      event.on_click(on_click),
    ],
    [html.text(label)],
  )
}
