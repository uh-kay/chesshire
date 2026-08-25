import gleam/bool
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import internal/board
import internal/game.{type Game, Game}
import internal/hash
import internal/move/attack
import internal/move/direction.{type Direction}

pub type Move {
  Castle(from: Int, to: Int)
  Move(from: Int, to: Int, piece: board.Piece)
  Capture(from: Int, to: Int, piece: board.Piece, captured_piece: board.Piece)
  EnPassant(from: Int, to: Int)
  Promotion(
    from: Int,
    to: Int,
    piece: board.Piece,
    captured_piece: Option(board.Piece),
  )
}

pub fn moving_piece(move: Move) {
  case move {
    Capture(piece:, ..) | Move(piece:, ..) -> piece
    Castle(..) -> board.King
    EnPassant(..) | Promotion(..) -> board.Pawn
  }
}

pub fn legal(game: Game) -> List(Move) {
  use moves, position, #(piece, color) <- dict.fold(game.board, [])

  case color == game.to_move {
    True -> moves_for_piece(game, position, piece, moves)
    False -> moves
  }
}

pub fn any_legal(game: Game) {
  use any, position, #(piece, color) <- dict.fold(game.board, False)
  use <- bool.guard(any, any)

  case color == game.to_move {
    True -> moves_for_piece(game, position, piece, []) != []
    False -> any
  }
}

fn move_is_valid_with_pins(
  from: Int,
  to: Int,
  attack_information: attack.AttackInformation,
) {
  case dict.get(attack_information.pin_lines, from) {
    Error(_) -> True
    Ok(line) -> list.contains(line, to)
  }
}

fn can_move(from: Int, to: Int, attack_information: attack.AttackInformation) {
  case attack_information.in_check {
    False -> move_is_valid_with_pins(from, to, attack_information)
    True ->
      list.contains(attack_information.check_block_lines, to)
      && move_is_valid_with_pins(from, to, attack_information)
  }
}

fn king_can_move(to: Int, attack_information: attack.AttackInformation) {
  case attack_information.in_check {
    False -> !list.contains(attack_information.attacks, to)
    True ->
      !list.contains(attack_information.check_attack_squares, to)
      && !list.contains(attack_information.attacks, to)
  }
}

fn moves_for_piece(
  game: Game,
  position: Int,
  piece: board.Piece,
  moves: List(Move),
) {
  let river_squares = game.river_squares

  case piece {
    board.Pawn -> pawn_moves(game, position, moves)
    board.Knight ->
      knight_moves(game, position, moves, direction.knight_directions)
    board.King -> {
      let king_moves =
        king_moves(game, position, moves, direction.queen_directions)
        |> list.filter(fn(move) { !list.contains(river_squares, move.to) })
      list.append(moves, king_moves)
    }
    board.Bishop ->
      sliding_moves(game, piece, position, moves, direction.bishop_directions)
    board.Rook ->
      sliding_moves(game, piece, position, moves, direction.rook_directions)
    board.Queen ->
      sliding_moves(game, piece, position, moves, direction.queen_directions)
  }
}

fn pawn_moves(game: Game, position: Int, moves: List(Move)) {
  let #(forward, left, right, promotion_rank) = case game.to_move {
    board.White -> #(direction.up, direction.up_left, direction.up_right, 8)
    board.Black -> #(
      direction.down,
      direction.down_left,
      direction.down_right,
      0,
    )
  }
  let forward_one = direction.in_direction(position, forward)

  let is_promotion = forward_one / 8 == promotion_rank
  let rank = board.rank(position)

  let moves = case board.get(game.board, forward_one) {
    board.Empty -> {
      let moves = case
        can_move(position, forward_one, game.attack_information)
      {
        False -> moves
        True if is_promotion ->
          add_promotions(
            position,
            forward_one,
            None,
            moves,
            board.pawn_promotions,
          )
        True -> [Move(board.Pawn, from: position, to: forward_one), ..moves]
      }

      let can_double_move = case game.to_move, rank {
        board.White, 1 | board.Black, 7 -> True
        _, _ -> False
      }

      use <- bool.guard(!can_double_move, moves)

      let forward_two = direction.in_direction(forward_one, forward)
      case board.get(game.board, forward_two) {
        board.Empty ->
          case can_move(position, forward_two, game.attack_information) {
            False -> moves
            True -> [Move(board.Pawn, from: position, to: forward_two), ..moves]
          }
        board.Occupied(_, _) | board.OffBoard -> moves
      }
    }
    board.Occupied(_, _) | board.OffBoard -> moves
  }

  let new_position = direction.in_direction(position, left)
  let moves = case board.get(game.board, new_position) {
    board.Occupied(piece: captured_piece, color:) if color != game.to_move ->
      case can_move(position, new_position, game.attack_information) {
        False -> moves
        True if is_promotion ->
          add_promotions(
            position,
            new_position,
            Some(captured_piece),
            moves,
            board.pawn_promotions,
          )
        True -> [
          Capture(board.Pawn, from: position, to: new_position, captured_piece:),
          ..moves
        ]
      }
    board.Empty if game.en_passant_square == Some(new_position) ->
      case en_passant_is_valid(game, position, new_position) {
        False -> moves
        True -> [EnPassant(position, new_position), ..moves]
      }
    board.Empty | board.OffBoard | board.Occupied(_, _) -> moves
  }

  let new_position = direction.in_direction(position, right)
  case board.get(game.board, new_position) {
    board.Occupied(piece: captured_piece, color:) if color != game.to_move ->
      case can_move(position, new_position, game.attack_information) {
        False -> moves
        True if is_promotion ->
          add_promotions(
            position,
            new_position,
            Some(captured_piece),
            moves,
            board.pawn_promotions,
          )
        True -> [
          Capture(board.Pawn, from: position, to: new_position, captured_piece:),
          ..moves
        ]
      }
    board.Empty if game.en_passant_square == Some(new_position) ->
      case en_passant_is_valid(game, position, new_position) {
        False -> moves
        True -> [EnPassant(position, new_position), ..moves]
      }
    board.Empty | board.OffBoard | board.Occupied(_, _) -> moves
  }
}

fn en_passant_is_valid(game: Game, position: Int, new_position: Int) -> Bool {
  let captured_pawn_position = new_position % 8 + position / 8 * 8

  case game.attack_information.in_check {
    False ->
      move_is_valid_with_pins(position, new_position, game.attack_information)
    True ->
      {
        list.contains(
          game.attack_information.check_block_lines,
          captured_pawn_position,
        )
        || list.contains(
          game.attack_information.check_block_lines,
          new_position,
        )
      }
      && move_is_valid_with_pins(
        position,
        new_position,
        game.attack_information,
      )
  }
  && !in_check_after_en_passant(game, position, captured_pawn_position)
}

fn in_check_after_en_passant(
  game: Game,
  position: Int,
  captured_pawn_position: Int,
) -> Bool {
  let #(left_position, right_position) = sort(position, captured_pawn_position)

  case
    in_check_after_en_passant_loop(game, left_position, direction.left, NoPiece)
  {
    NoPiece | Both -> False
    found_piece ->
      in_check_after_en_passant_loop(
        game,
        right_position,
        direction.right,
        found_piece,
      )
      == Both
  }
}

type FoundPiece {
  NoPiece
  KingPiece
  EnemyPiece
  Both
}

fn sort(a: Int, b: Int) -> #(Int, Int) {
  case a < b {
    True -> #(a, b)
    False -> #(b, a)
  }
}

fn in_check_after_en_passant_loop(
  game: Game,
  position: Int,
  direction: Direction,
  found_piece: FoundPiece,
) -> FoundPiece {
  let new_position = direction.in_direction(position, direction)
  case board.get(game.board, new_position), found_piece {
    board.Empty, _ ->
      in_check_after_en_passant_loop(game, new_position, direction, found_piece)
    board.Occupied(piece: board.King, color:), NoPiece
      if color == game.to_move
    -> KingPiece
    board.Occupied(piece: board.King, color:), EnemyPiece
      if color == game.to_move
    -> Both
    board.Occupied(piece: board.Rook, color:), NoPiece
    | board.Occupied(piece: board.Queen, color:), NoPiece
      if color != game.to_move
    -> EnemyPiece
    board.Occupied(piece: board.Rook, color:), KingPiece
    | board.Occupied(piece: board.Queen, color:), KingPiece
      if color != game.to_move
    -> Both
    board.Occupied(_, _), _ | board.OffBoard, _ -> found_piece
  }
}

fn add_promotions(
  from: Int,
  to: Int,
  captured_piece: Option(board.Piece),
  moves: List(Move),
  _pieces: List(board.Piece),
) {
  // case pieces {
  //   [] -> moves
  //   [piece, ..pieces] ->
  //     add_promotions(
  //       from,
  //       to,
  //       captured_piece,
  //       [Promotion(from:, to:, piece: piece, captured_piece:), ..moves],
  //       pieces,
  //     )
  // }
  [Promotion(from:, to:, piece: board.Queen, captured_piece:), ..moves]
}

fn knight_moves(
  game: Game,
  position: Int,
  moves: List(Move),
  directions: List(Direction),
) {
  case directions {
    [] -> moves
    [direction, ..directions] -> {
      let new_position = direction.in_direction(position, direction)

      let moves = case board.get(game.board, new_position) {
        board.Empty ->
          case can_move(position, new_position, game.attack_information) {
            False -> moves
            True -> [
              Move(board.Knight, from: position, to: new_position),
              ..moves
            ]
          }
        board.Occupied(piece: captured_piece, color:) if color != game.to_move ->
          case can_move(position, new_position, game.attack_information) {
            False -> moves
            True -> [
              Capture(
                board.Knight,
                from: position,
                to: new_position,
                captured_piece:,
              ),
              ..moves
            ]
          }
        board.Occupied(_, _) | board.OffBoard -> moves
      }

      knight_moves(game, position, moves, directions)
    }
  }
}

fn king_moves(
  game: Game,
  position: Int,
  moves: List(Move),
  directions: List(Direction),
) {
  let moves = regular_king_moves(game, position, moves, directions)

  use <- bool.guard(game.attack_information.in_check, moves)

  let is_empty = fn(position) { board.get(game.board, position) == board.Empty }
  let can_move_through = fn(position) {
    board.get(game.board, position) == board.Empty
    && !list.contains(game.attack_information.attacks, position)
  }

  let moves = case game.to_move {
    board.White if game.castling.white_kingside ->
      case can_move_through(5) && can_move_through(6) {
        True -> [Castle(from: position, to: 6), ..moves]
        False -> moves
      }
    board.Black if game.castling.black_kingside ->
      case can_move_through(69) && can_move_through(70) {
        True -> [Castle(from: position, to: 70), ..moves]
        False -> moves
      }
    _ -> moves
  }

  case game.to_move {
    board.White if game.castling.white_queenside ->
      case can_move_through(3) && can_move_through(2) && is_empty(1) {
        True -> [Castle(from: position, to: 2), ..moves]
        False -> moves
      }
    board.Black if game.castling.black_queenside ->
      case can_move_through(68) && can_move_through(67) && is_empty(66) {
        True -> [Castle(from: position, to: 67), ..moves]
        False -> moves
      }
    _ -> moves
  }
}

fn regular_king_moves(
  game: Game,
  position: Int,
  moves: List(Move),
  directions: List(Direction),
) {
  case directions {
    [] -> moves
    [direction, ..directions] -> {
      let new_position = direction.in_direction(position, direction)

      let moves = case board.get(game.board, new_position) {
        board.Empty ->
          case king_can_move(new_position, game.attack_information) {
            False -> moves
            True -> [
              Move(board.King, from: position, to: new_position),
              ..moves
            ]
          }
        board.Occupied(piece: captured_piece, color:) if color != game.to_move ->
          case king_can_move(new_position, game.attack_information) {
            True -> [
              Capture(
                board.King,
                from: position,
                to: new_position,
                captured_piece:,
              ),
              ..moves
            ]
            False -> moves
          }
        board.Occupied(_, _) | board.OffBoard -> moves
      }
      regular_king_moves(game, position, moves, directions)
    }
  }
}

fn sliding_moves(
  game: Game,
  piece: board.Piece,
  position: Int,
  moves: List(Move),
  directions: List(Direction),
) -> List(Move) {
  case directions {
    [] -> moves
    [direction, ..directions] ->
      sliding_moves(
        game,
        piece,
        position,
        sliding_moves_in_direction(
          game,
          piece,
          position,
          position,
          direction,
          moves,
        ),
        directions,
      )
  }
}

fn sliding_moves_in_direction(
  game: Game,
  piece: board.Piece,
  start_position: Int,
  position: Int,
  direction: Direction,
  moves: List(Move),
) -> List(Move) {
  let new_position = direction.in_direction(position, direction)
  use <- bool.guard(list.contains(game.river_squares, new_position), [
    Move(piece, from: start_position, to: new_position),
    ..moves
  ])
  case board.get(game.board, new_position) {
    board.Empty ->
      sliding_moves_in_direction(
        game,
        piece,
        start_position,
        new_position,
        direction,
        case can_move(start_position, new_position, game.attack_information) {
          False -> moves
          True -> [Move(piece, from: start_position, to: new_position), ..moves]
        },
      )
    board.Occupied(color:, piece: captured_piece) if color != game.to_move ->
      case can_move(start_position, new_position, game.attack_information) {
        False -> moves
        True -> [
          Capture(
            piece,
            from: start_position,
            to: new_position,
            captured_piece:,
          ),
          ..moves
        ]
      }
    board.Occupied(_, _) | board.OffBoard -> moves
  }
}

pub fn apply(game: Game, move: Move) {
  case move {
    Castle(from:, to:) -> apply_castle(game, from, to, to % 8 == 2)
    Move(from:, to:, piece:) ->
      do_apply(game, piece, from, to, False, None, None)
    Capture(from:, to:, piece:, captured_piece:) ->
      do_apply(game, piece, from, to, False, None, Some(captured_piece))
    EnPassant(from:, to:) ->
      do_apply(game, board.Pawn, from, to, True, None, None)
    Promotion(from:, to:, piece:, captured_piece:) ->
      do_apply(game, board.Pawn, from, to, False, Some(piece), captured_piece)
  }
}

fn apply_castle(game: Game, from: Int, to: Int, long: Bool) -> Game {
  let Game(
    board:,
    to_move:,
    castling:,
    en_passant_square: _,
    attack_information: _,
    current_piece: _,
    current_piece_moves: _,
    half_moves:,
    full_moves:,
    black_pieces: game.PieceInfo(
      king_position: black_king_position,
      non_pawn_material: black_non_pawn_material,
      pawn_material: black_pawn_material,
    ),
    white_pieces: game.PieceInfo(
      king_position: white_king_position,
      non_pawn_material: white_non_pawn_material,
      pawn_material: white_pawn_material,
    ),
    zobrist_hash: previous_hash,
    previous_positions:,
    last_move: _,
    board_variant:,
    river_squares:,
    bridge_squares:,
  ) = game

  let castling = case to_move {
    board.White ->
      game.Castling(..castling, white_kingside: False, white_queenside: False)
    board.Black ->
      game.Castling(..castling, black_kingside: False, black_queenside: False)
  }

  let rook_rank = from / 9
  let #(rook_file_from, rook_file_to) = case long {
    True -> #(0, 3)
    False -> #(7, 5)
  }

  let rook_from = rook_rank * 8 + rook_file_from
  let rook_to = rook_rank * 8 + rook_file_to

  let board =
    board
    |> dict.delete(from)
    |> dict.delete(rook_from)
    |> dict.insert(to, #(board.King, to_move))
    |> dict.insert(rook_to, #(board.Rook, to_move))

  let zobrist_hash =
    previous_hash
    |> hash.toggle_to_move
    |> hash.toggle_piece(from, board.King, to_move)
    |> hash.toggle_piece(to, board.King, to_move)
    |> hash.toggle_piece(rook_from, board.Rook, to_move)
    |> hash.toggle_piece(rook_to, board.Rook, to_move)

  let en_passant_square = None
  let white_king_position = case to_move {
    board.White -> to
    board.Black -> white_king_position
  }
  let black_king_position = case to_move {
    board.White -> black_king_position
    board.Black -> to
  }
  let full_moves = case to_move {
    board.White -> full_moves
    board.Black -> full_moves + 1
  }
  let to_move = case to_move {
    board.White -> board.Black
    board.Black -> board.White
  }

  let half_moves = half_moves + 1

  let king_position = case to_move {
    board.White -> white_king_position
    board.Black -> black_king_position
  }

  let last_move = #(from, to)

  // TODO: calculate incrementally
  let attack_information = attack.calculate(board, king_position, to_move)

  Game(
    board:,
    to_move:,
    castling:,
    en_passant_square:,
    half_moves:,
    full_moves:,
    attack_information:,
    current_piece: None,
    current_piece_moves: [],
    white_pieces: game.PieceInfo(
      king_position: white_king_position,
      non_pawn_material: white_non_pawn_material,
      pawn_material: white_pawn_material,
    ),
    black_pieces: game.PieceInfo(
      king_position: black_king_position,
      non_pawn_material: black_non_pawn_material,
      pawn_material: black_pawn_material,
    ),
    zobrist_hash:,
    previous_positions:,
    last_move:,
    board_variant:,
    river_squares:,
    bridge_squares:,
  )
}

fn do_apply(
  game: Game,
  piece: board.Piece,
  from: Int,
  to: Int,
  en_passant: Bool,
  promotion: Option(board.Piece),
  captured_piece: Option(board.Piece),
) -> Game {
  let Game(
    board:,
    to_move:,
    castling:,
    en_passant_square:,
    half_moves:,
    full_moves:,
    attack_information: _,
    current_piece:,
    current_piece_moves:,
    black_pieces:,
    white_pieces:,
    zobrist_hash: previous_hash,
    previous_positions:,
    last_move: _,
    board_variant:,
    river_squares:,
    bridge_squares:,
  ) = game

  let #(
    game.PieceInfo(
      king_position: our_king_position,
      non_pawn_material: our_non_pawn_material,
      pawn_material: our_pawn_material,
    ),
    game.PieceInfo(
      king_position: opposing_king_position,
      pawn_material: opposing_pawn_material,
      non_pawn_material: opposing_non_pawn_material,
    ),
  ) = case to_move {
    board.White -> #(white_pieces, black_pieces)
    board.Black -> #(black_pieces, white_pieces)
  }

  let our_color = to_move
  let enemy_color = case to_move {
    board.White -> board.Black
    board.Black -> board.White
  }

  let castling = castling |> remove_castling(from) |> remove_castling(to)

  let one_way_move = captured_piece != None || piece == board.Pawn

  let zobrist_hash =
    previous_hash
    |> hash.toggle_to_move
    |> hash.toggle_piece(from, piece, our_color)

  let #(piece, our_pawn_material, our_non_pawn_material) = case promotion {
    None -> #(piece, our_pawn_material, our_non_pawn_material)
    Some(piece) -> #(
      piece,
      our_pawn_material - board.pawn_value,
      our_non_pawn_material + board.piece_value(piece),
    )
  }

  let zobrist_hash = hash.toggle_piece(zobrist_hash, to, piece, our_color)

  let #(zobrist_hash, opposing_pawn_material, opposing_non_pawn_material) = case
    captured_piece
  {
    Some(board.Pawn) -> #(
      hash.toggle_piece(zobrist_hash, to, board.Pawn, to_move),
      opposing_pawn_material - board.pawn_value,
      opposing_non_pawn_material,
    )
    Some(piece) -> #(
      hash.toggle_piece(zobrist_hash, to, piece, to_move),
      opposing_pawn_material,
      opposing_non_pawn_material - board.piece_value(piece),
    )
    None -> #(zobrist_hash, opposing_pawn_material, opposing_non_pawn_material)
  }

  let #(board, river_squares, bridge_squares) = case
    list.contains(game.river_squares, to)
  {
    True -> {
      let board = board |> dict.delete(from)
      let river_squares =
        list.filter(river_squares, fn(square) { square != to })
      let bridge_squares = list.prepend(bridge_squares, to)
      #(board, river_squares, bridge_squares)
    }
    False -> {
      let board =
        board |> dict.delete(from) |> dict.insert(to, #(piece, our_color))
      #(board, river_squares, bridge_squares)
    }
  }

  let #(board, zobrist_hash, opposing_pawn_material) = case
    en_passant,
    en_passant_square,
    our_color
  {
    True, Some(square), board.White -> {
      let ep_square = square - 8
      #(
        dict.delete(board, ep_square),
        hash.toggle_piece(zobrist_hash, ep_square, board.Pawn, board.Black),
        opposing_pawn_material - board.pawn_value,
      )
    }
    True, Some(square), board.Black -> {
      let ep_square = square + 8
      #(
        dict.delete(board, ep_square),
        hash.toggle_piece(zobrist_hash, ep_square, board.Pawn, board.White),
        opposing_pawn_material - board.pawn_value,
      )
    }
    _, _, _ -> #(board, zobrist_hash, opposing_pawn_material)
  }

  let en_passant_square = case piece, to - from {
    board.Pawn, 16 -> Some(from + 8)
    board.Pawn, -16 -> Some(from - 8)
    _, _ -> None
  }

  let full_moves = case to_move {
    board.White -> full_moves
    board.Black -> full_moves + 1
  }

  let our_king_position = case from == our_king_position {
    True -> to
    False -> our_king_position
  }

  let our_pieces =
    game.PieceInfo(
      king_position: our_king_position,
      pawn_material: our_pawn_material,
      non_pawn_material: our_non_pawn_material,
    )

  let opposing_pieces =
    game.PieceInfo(
      king_position: opposing_king_position,
      pawn_material: opposing_pawn_material,
      non_pawn_material: opposing_non_pawn_material,
    )

  let #(white_pieces, black_pieces) = case to_move {
    board.White -> #(our_pieces, opposing_pieces)
    board.Black -> #(opposing_pieces, our_pieces)
  }

  let to_move = enemy_color

  let #(half_moves, previous_positions) = case one_way_move {
    True -> #(0, [])
    False -> #(half_moves + 1, [previous_hash, ..previous_positions])
  }

  let last_move = #(from, to)

  // TODO: update incrementally
  let attack_information =
    attack.calculate(board, opposing_king_position, to_move)

  Game(
    board:,
    to_move:,
    castling:,
    en_passant_square:,
    half_moves:,
    full_moves:,
    attack_information:,
    current_piece:,
    current_piece_moves:,
    black_pieces:,
    white_pieces:,
    zobrist_hash:,
    previous_positions:,
    last_move:,
    board_variant:,
    river_squares:,
    bridge_squares:,
  )
}

fn remove_castling(castling: game.Castling, position: Int) -> game.Castling {
  case position {
    4 ->
      game.Castling(..castling, white_kingside: False, white_queenside: False)
    60 ->
      game.Castling(..castling, black_kingside: False, black_queenside: False)
    7 -> game.Castling(..castling, white_kingside: False)
    63 -> game.Castling(..castling, black_kingside: False)
    0 -> game.Castling(..castling, white_queenside: False)
    56 -> game.Castling(..castling, black_queenside: False)
    _ -> castling
  }
}
