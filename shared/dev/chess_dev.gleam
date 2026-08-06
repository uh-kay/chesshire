import gleam/int
import internal/board
import simplifile as file

const generated_file_path = "src/chess/generated.gleam"

pub fn main() {
  let imports =
    "import chess/board.{Bishop, Black, King, Knight, Pawn, Queen, Rook, White}"
  let generated_code = imports <> "\n\n" <> generate_hash_data() <> "\n"
  let assert Ok(Nil) = file.write(generated_file_path, generated_code)
}

const max_60_bit_int = 576_460_752_303_423_500

const piece_count = 12

fn generate_hash_data() {
  let function_head =
    "pub fn hash_for_piece(piece: board.Piece, colour: board.Color, position: Int) -> Int {
  case piece, colour, position {"
  let length = piece_count * board.size
  let hash_for_piece = generate_hash_data_loop(function_head, 0, length)
  let black_to_move =
    "pub const black_to_move_hash = 0x"
    <> int.to_base16(int.random(max_60_bit_int))

  hash_for_piece <> "\n\n" <> black_to_move
}

fn generate_hash_data_loop(acc: String, generated: Int, length: Int) {
  case generated >= length {
    True -> acc <> "\n }\n}"
    False -> {
      let position = generated / piece_count
      let position = case position == board.size - 1 {
        True -> "_"
        False -> int.to_string(position)
      }
      let piece = case generated % piece_count {
        0 -> "Pawn, White"
        1 -> "Pawn, Black"
        2 -> "Knight, White"
        3 -> "Knight, Black"
        4 -> "Bishop, White"
        5 -> "Bishop, Black"
        6 -> "Rook, White"
        7 -> "Rook, Black"
        8 -> "Queen, White"
        9 -> "Queen, Black"
        10 -> "King, White"
        _11 -> "King, Black"
      }
      let acc =
        acc
        <> "\n    "
        <> piece
        <> ", "
        <> position
        <> " -> 0x"
        <> int.to_base16(int.random(max_60_bit_int))
      generate_hash_data_loop(acc, generated + 1, length)
    }
  }
}
