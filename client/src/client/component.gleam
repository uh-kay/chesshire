import cheg.{Guest, Host}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import icon
import internal/board
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Message {
  UserClickedSquare(
    piece: Option(#(cheg.PieceType, cheg.PieceColor)),
    position: Int,
  )
  UserClickedTargetSquare(move: cheg.Move)
  UserClickedNewGame
}

pub type Model {
  Model(game: cheg.Game, moves: List(cheg.Move), role: Option(cheg.Role))
}

pub type CellColor {
  White
  Black
  Brown
  Blue
}

pub fn game_view(model: Model) -> Element(Message) {
  html.div(
    [
      attribute.class(
        "grid grid-cols-8 lg:max-w-[calc(88*8px)] max-w-[calc(64*8px)] outline-1",
      ),
      case model.role {
        Some(role) ->
          case role {
            Host -> attribute.class("scale-y-[-1]")
            Guest -> attribute.class("scale-x-[-1]")
          }
        None -> attribute.none()
      },
    ],
    board_view(model),
  )
}

pub fn board_view(model: Model) -> List(Element(Message)) {
  let board = cheg.board(model.game)
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

    let color = case { row + col } % 2 {
      0 -> Black
      _ -> White
    }
    let color = case list.contains(board.river_square, pos) {
      True -> Blue
      False ->
        case list.contains(board.bridge_square, pos) {
          True -> Brown
          False -> color
        }
    }

    let #(last_from, last_to) = cheg.last_move(model.game)

    case model.role {
      Some(role) -> {
        let last_move = last_from == pos || last_to == pos
        let in_check = cheg.in_check(model.game)
        let checked_piece = case in_check, cheg.to_move(model.game) {
          True, cheg.Black -> Some(#(cheg.King, cheg.Black))
          True, cheg.White -> Some(#(cheg.King, cheg.White))
          _, _ -> None
        }

        case list.find(model.moves, fn(move) { cheg.move_to(move) == pos }) {
          Ok(move) -> dot_cell(color, role, piece, move, last_move)
          Error(_) -> cell(pos, role, color, piece, last_move, checked_piece)
        }
      }
      None -> element.none()
    }
  })
}

fn dot_cell(
  cell_color: CellColor,
  role: cheg.Role,
  piece: Option(#(cheg.PieceType, cheg.PieceColor)),
  move: cheg.Move,
  last_move: Bool,
) -> Element(Message) {
  html.div(
    [
      attribute.class("flex items-center justify-center"),
      attribute.class(case cell_color {
        White -> "bg-green-200/50"
        Black -> "bg-green-700/70"
        Blue -> "bg-blue-700/70"
        Brown -> "bg-amber-900/70"
      }),
      attribute.class(case piece {
        Some(_) -> "border-2 border-red-500"
        None -> ""
      }),
      attribute.class(case last_move {
        True -> "bg-yellow-400/30"
        False -> ""
      }),
      event.on_click(UserClickedTargetSquare(move)),
    ],
    [
      html.div(
        [
          attribute.class(case piece {
            Some(_) ->
              "w-18"
              <> case role {
                Host -> " scale-y-[-1]"
                Guest -> " scale-x-[-1]"
              }
            None -> "w-3 h-3 lg:w-5 lg:h-5 rounded-full bg-black/30"
          }),
        ],
        [piece_view(piece)],
      ),
    ],
  )
}

fn cell(
  pos: Int,
  role: cheg.Role,
  cell_color: CellColor,
  piece: Option(#(cheg.PieceType, cheg.PieceColor)),
  last_move: Bool,
  checked_king: option.Option(#(cheg.PieceType, cheg.PieceColor)),
) -> Element(Message) {
  html.div(
    [
      attribute.class("w-12 h-12 md:w-16 md:h-16 lg:w-22 lg:h-22"),
      attribute.class("flex justify-center items-center relative"),
      attribute.class(case cell_color {
        White -> "bg-green-200/50"
        Black -> "bg-green-700/70"
        Blue -> "bg-blue-700/70"
        Brown -> "bg-amber-900/70"
      }),
      attribute.class(case checked_king, piece {
        Some(checked_king), Some(piece) if checked_king == piece ->
          "aspect-square bg-radial-[at_50%_50%] from-red-500 to-transparent"
        _, _ -> ""
      }),
      attribute.data("pos", int.to_string(pos)),
      event.on_click(UserClickedSquare(piece, pos)),
    ],
    [
      html.div(
        [
          attribute.class("w-18 z-40 flex justify-center"),
          attribute.class(case role {
            Host -> "scale-y-[-1]"
            Guest -> "scale-x-[-1]"
          }),
        ],
        [
          html.div([attribute.class("w-10 md:w-14 lg:w-18")], [
            piece_view(piece),
          ]),
        ],
      ),
      html.div(
        [
          attribute.class(case last_move {
            True -> "absolute inset-0 bg-yellow-400/30"
            False -> ""
          }),
        ],
        [],
      ),
    ],
  )
}

fn piece_view(
  piece: Option(#(cheg.PieceType, cheg.PieceColor)),
) -> Element(Message) {
  case piece {
    Some(#(cheg.Pawn, cheg.White)) -> icon.white_pawn()
    Some(#(cheg.Knight, cheg.White)) -> icon.white_knight()
    Some(#(cheg.Bishop, cheg.White)) -> icon.white_bishop()
    Some(#(cheg.Rook, cheg.White)) -> icon.white_rook()
    Some(#(cheg.Queen, cheg.White)) -> icon.white_queen()
    Some(#(cheg.King, cheg.White)) -> icon.white_king()
    Some(#(cheg.Pawn, cheg.Black)) -> icon.black_pawn()
    Some(#(cheg.Knight, cheg.Black)) -> icon.black_knight()
    Some(#(cheg.Bishop, cheg.Black)) -> icon.black_bishop()
    Some(#(cheg.Rook, cheg.Black)) -> icon.black_rook()
    Some(#(cheg.Queen, cheg.Black)) -> icon.black_queen()
    Some(#(cheg.King, cheg.Black)) -> icon.black_king()
    None -> element.none()
  }
}

pub fn clock_view(
  black_time: Int,
  white_time: Int,
  player_role: Option(cheg.Role),
  state: cheg.GameState,
) -> Element(_) {
  let result = {
    use player_role <- result.try(
      case player_role {
        Some(role) -> Ok(role)
        None -> Error(Nil)
      }
      |> result.replace_error(element.none()),
    )

    let black_time = black_time / 1000
    let white_time = white_time / 1000
    let #(black_minutes, black_seconds) = #(
      case black_time / 60 {
        0 -> "00"
        _ -> int.to_string(black_time / 60)
      },
      case black_time % 60 {
        0 -> "00"
        _ -> int.to_string(black_time % 60)
      },
    )
    let #(white_minutes, white_seconds) = #(
      case white_time / 60 {
        0 -> "00"
        _ -> int.to_string(white_time / 60)
      },
      case white_time % 60 {
        0 -> "00"
        _ -> int.to_string(white_time % 60)
      },
    )

    let state = case state {
      cheg.Continue -> element.none()
      cheg.Draw(reason:) ->
        html.p([], [
          html.text(case reason {
            cheg.ThreefoldRepetition -> "Draw: threefold repetition"
            cheg.InsufficientMaterial -> "Draw: insufficient material"
            cheg.Stalemate -> "Draw: stalemate"
            cheg.FiftyMoves -> "Draw: fifty move rule"
          }),
        ])
      cheg.WhiteWin -> html.p([], [html.text("White wins")])
      cheg.BlackWin -> html.p([], [html.text("Black wins")])
    }

    Ok(
      html.div(
        [
          attribute.class("md:ml-8 flex justify-between"),
          attribute.class(case player_role {
            Host -> "mt-4 flex-row md:flex-col"
            Guest -> "mt-4 flex-row-reverse md:flex-col-reverse"
          }),
        ],
        [
          html.p(
            [
              attribute.class("text-3xl min-w-28 text-center bg-blue-300"),
              attribute.class("px-4 py-3 rounded-md"),
            ],
            [
              html.text(black_minutes <> ":" <> black_seconds),
            ],
          ),
          state,
          html.p(
            [
              attribute.class("text-3xl min-w-28 text-center bg-blue-300"),
              attribute.class("px-4 py-3 rounded-md"),
            ],
            [
              html.text(white_minutes <> ":" <> white_seconds),
            ],
          ),
        ],
      ),
    )
  }

  case result {
    Ok(el) -> el
    Error(el) -> el
  }
}

pub fn navbar() -> Element(_) {
  html.nav([attribute.class("p-4 border-b bg-blue-200 border-blue-500")], [
    html.div([attribute.class("flex justify-between max-w-4xl mx-auto")], [
      html.a([attribute.href("/")], [html.text("Chesshire")]),
    ]),
  ])
}
