import cheg.{Guest, Host, Spectator}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import gleam/string
import icon
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Message {
  UserClickedSquare(piece: Option(#(cheg.PieceType, cheg.Color)), position: Int)
  UserClickedTargetSquare(move: cheg.Move)
  UserClickedNewGame
}

pub type Model {
  Model(game: cheg.Game, moves: List(cheg.Move), role: Option(cheg.Role))
}

pub type SquareColor {
  White
  Black
  Brown
  Blue
}

pub fn game_view(model: Model) -> Element(Message) {
  html.div(
    [
      attribute.class("grid grid-cols-8 grid-rows-9 w-full min-h-108 "),
      attribute.class("aspect-square outline-1"),
      case model.role {
        Some(role) ->
          case role {
            Host -> attribute.class("scale-y-[-1]")
            Guest -> attribute.class("scale-x-[-1]")
            Spectator -> attribute.class("scale-y-[-1]")
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
          Ok(move) ->
            target_square_view(
              pos,
              color,
              role,
              piece,
              move,
              last_move,
              list.contains(river_square, cheg.move_to(move)),
            )
          Error(_) ->
            square_view(pos, role, color, piece, last_move, checked_piece)
        }
      }
      None -> element.none()
    }
  })
}

fn target_square_view(
  position: Int,
  square_color: SquareColor,
  role: cheg.Role,
  piece: Option(#(cheg.PieceType, cheg.Color)),
  move: cheg.Move,
  is_last_move: Bool,
  is_river: Bool,
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
      attribute.data("pos", int.to_string(position)),
      event.on_click(UserClickedTargetSquare(move)),
    ],
    [
      special_square_marker(square_color, role),
      html.div(
        [
          attribute.class(case piece {
            Some(_) -> "w-18 z-40 flex justify-center"
            None -> "w-3 h-3 lg:w-5 lg:h-5 rounded-full bg-black/30"
          }),
          attribute.class(case piece, role {
            Some(_), Host -> "scale-y-[-1]"
            Some(_), Guest -> "scale-x-[-1]"
            Some(_), Spectator -> "scale-y-[-1]"
            None, _ -> ""
          }),
        ],
        [html.div([attribute.class("w-10 md:w-14")], [piece_view(piece)])],
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
  role: cheg.Role,
  square_color: SquareColor,
  piece: Option(#(cheg.PieceType, cheg.Color)),
  is_last_move: Bool,
  checked_king: option.Option(#(cheg.PieceType, cheg.Color)),
) -> Element(Message) {
  html.div(
    [
      square_style(),
      square_color_style(square_color),
      attribute.class(case checked_king, piece {
        Some(checked_king), Some(piece) if checked_king == piece ->
          "aspect-square bg-radial-[at_50%_50%] from-red-500 to-transparent"
        _, _ -> ""
      }),
      attribute.data("pos", int.to_string(position)),
      event.on_click(UserClickedSquare(piece, position)),
    ],
    [
      special_square_marker(square_color, role),
      html.div(
        [
          attribute.class("w-18 z-40 flex justify-center"),
          attribute.class(case role {
            Host -> "scale-y-[-1]"
            Guest -> "scale-x-[-1]"
            Spectator -> "scale-y-[-1]"
          }),
        ],
        [html.div([attribute.class("w-10 md:w-14")], [piece_view(piece)])],
      ),
      last_move_indicator(is_last_move),
    ],
  )
}

fn square_style() {
  attribute.class("flex justify-center items-center relative")
}

fn square_color_style(square_color: SquareColor) {
  attribute.class(case square_color {
    White -> "bg-green-200/50"
    Black -> "bg-green-700/70"
    Blue -> "bg-[#1861eb]"
    Brown -> "bg-amber-900/70"
  })
}

fn special_square_marker(
  square_color: SquareColor,
  role: cheg.Role,
) -> Element(a) {
  let special_square_style = [
    attribute.class("absolute text-white"),
    attribute.class(case role {
      Host -> "bottom-0 left-2"
      Guest -> "top-0 right-2"
      Spectator -> "bottom-0 left-2"
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

fn piece_view(
  piece: Option(#(cheg.PieceType, cheg.Color)),
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

    let black_time = format_time(black_time)
    let white_time = format_time(white_time)

    let state = case state {
      cheg.Continue -> element.none()
      cheg.Draw(reason:) ->
        html.p([], [
          html.text(case reason {
            cheg.ThreefoldRepetition -> "🤝 Draw: threefold repetition"
            cheg.InsufficientMaterial -> "🤝 Draw: insufficient material"
            cheg.Stalemate -> "🤝 Draw: stalemate"
            cheg.FiftyMoves -> "🤝 Draw: fifty move rule"
          }),
        ])
      cheg.WhiteWin -> html.p([], [html.text("White wins 🎉")])
      cheg.BlackWin -> html.p([], [html.text("Black wins 🎉")])
    }

    Ok(
      html.div(
        [
          attribute.class("md:ml-8 flex justify-between items-start"),
          attribute.class(case player_role {
            Host -> "flex-row md:flex-col"
            Guest -> "flex-row-reverse md:flex-col-reverse"
            Spectator -> "flex-row md:flex-col"
          }),
        ],
        [
          html.p(
            [
              attribute.class("min-w-28 rounded-md bg-blue-300 px-4 py-3"),
              attribute.class("text-center text-3xl"),
            ],
            [
              html.text(black_time),
            ],
          ),
          state,
          html.p(
            [
              attribute.class("min-w-28 rounded-md bg-blue-300 px-4 py-3"),
              attribute.class("text-center text-3xl"),
            ],
            [
              html.text(white_time),
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
      html.a(
        [attribute.class("flex items-center text-2xl"), attribute.href("/")],
        [
          html.img([
            attribute.class("w-8 mr-2"),
            attribute.src("/static/chesshire_favicon.svg"),
          ]),
          html.text("Chesshire"),
        ],
      ),
    ]),
  ])
}

fn format_time(time: Int) {
  let time = time / 1000
  let minutes = time / 60
  let seconds = time % 60

  int.to_string(minutes)
  <> ":"
  <> string.pad_start(int.to_string(seconds), 2, "0")
}
