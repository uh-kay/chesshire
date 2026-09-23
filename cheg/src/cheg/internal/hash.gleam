import cheg/internal/board
import cheg/internal/generated
import gleam/dict
import gleam/int

pub fn hash(board: board.Board, to_move: board.Color) {
  let hash = case to_move {
    board.White -> 0
    board.Black -> generated.black_to_move_hash
  }

  dict.fold(board, hash, fn(hash, position, square) {
    let #(piece, color) = square
    int.bitwise_exclusive_or(
      generated.hash_for_piece(piece, color, position),
      hash,
    )
  })
}

pub fn toggle_piece(
  hash: Int,
  position: Int,
  piece: board.Piece,
  color: board.Color,
) {
  int.bitwise_exclusive_or(
    generated.hash_for_piece(piece, color, position),
    hash,
  )
}

pub fn toggle_to_move(hash: Int) {
  int.bitwise_exclusive_or(hash, generated.black_to_move_hash)
}
