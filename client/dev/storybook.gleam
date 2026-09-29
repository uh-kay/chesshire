import client/component
import client/learn
import fable
import fable/internal/story
import gleam/dict
import gleam/dynamic/decode
import gleam/function
import gleam/int
import gleam/option.{None, Some}
import gleam/result
import lustre/attribute
import lustre/dev/query
import lustre/dev/simulate
import lustre/effect
import lustre/element
import lustre/element/html
import lustre/event

pub fn main() {
  let book =
    fable.book("Chesshire", [
      fable.chapter("Rabbit", [
        rabbit_story(),
      ]),
    ])
  let assert Ok(_) = fable.start(book)
}

fn rabbit_story() -> story.Story {
  let app =
    simulate.application(
      init: function.identity,
      update: fn(model: learn.Model, message: learn.Message) {
        learn.update(model, message)
      },
      view: fn(model: learn.Model) {
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
              learn.RiverKnight ->
                dict.get(model.river_knight_model.board, dragged_piece.from)
                |> result.unwrap(None)
              learn.PawnSacrifice ->
                dict.get(model.pawn_sacrifice_model.board, dragged_piece.from)
                |> result.unwrap(None)
              learn.BridgeMovement ->
                dict.get(model.bridge_movement_model.board, dragged_piece.from)
                |> result.unwrap(None)
              learn.RabbitPiece ->
                dict.get(model.rabbit_piece_model.board, dragged_piece.from)
                |> result.unwrap(None)
            }
          }
          None -> None
        }
        let board_style = [
          attribute.class("grid grid-cols-3 grid-rows-3 scale-y-[-1] shrink-0"),
          attribute.class("border-2 dark:border-dark-text"),
        ]

        html.div(
          [
            attribute.id("board"),
            attribute.class("flex p-8"),
            event.on("pointerup", decode.success(learn.UserDroppedPiece)),
          ],
          [
            html.div(
              board_style,
              learn.demo_view(
                learn.RabbitPiece,
                model.rabbit_piece_model.board,
                model.rabbit_piece_model.river_squares,
                model.rabbit_piece_model.bridge_squares,
                model.rabbit_piece_model.moves,
                dragged_over_square(learn.RabbitPiece),
                model.dragged_piece,
              ),
            ),
            case model.dragged_piece {
              Some(dragged_piece) ->
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
              None -> element.none()
            },
          ],
        )
      },
    )

  let from = query.element(query.id("rabbit_piece_2"))

  fable.story(name: "Rabbit", template: app, scenes: [
    fable.simulate(
      fable.scene("Rabbit Hop", #(learn.init(), effect.none())),
      fn(simulate) {
        simulate
        |> simulate.click(on: from)
        |> simulate.click(on: query.element(query.id("rabbit_piece_8")))
      },
    ),

    fable.simulate(
      fable.scene("Rabbit Hop (Drag and Drop)", #(learn.init(), effect.none())),
      fn(simulate) {
        simulate
        |> simulate.message(learn.UserDraggedPiece(
          for: learn.RabbitPiece,
          from: 2,
          width: 74,
          height: 74,
          pointer_x: 105,
          pointer_y: 150,
          offset_x: 0,
          offset_y: 0,
        ))
        |> simulate.event(
          on: query.element(query.id("rabbit_piece_5")),
          name: "pointerenter",
          data: [],
        )
        |> simulate.message(learn.UserDraggedPiece(
          for: learn.RabbitPiece,
          from: 2,
          width: 74,
          height: 74,
          pointer_x: 105,
          pointer_y: 100,
          offset_x: 0,
          offset_y: 0,
        ))
        |> simulate.message(learn.UserDraggedPiece(
          for: learn.RabbitPiece,
          from: 2,
          width: 74,
          height: 74,
          pointer_x: 105,
          pointer_y: 50,
          offset_x: 0,
          offset_y: 0,
        ))
        |> simulate.event(
          on: query.element(query.id("rabbit_piece_5")),
          name: "pointerleave",
          data: [],
        )
        |> simulate.event(
          on: query.element(query.id("rabbit_piece_8")),
          name: "pointerenter",
          data: [],
        )
        |> simulate.event(
          on: query.element(query.id("board")),
          name: "pointerup",
          data: [],
        )
      },
    ),

    fable.simulate(
      fable.scene("Rabbit Capture", #(learn.init(), effect.none())),
      fn(simulate) {
        simulate
        |> simulate.click(on: from)
        |> simulate.click(on: query.element(query.id("rabbit_piece_7")))
      },
    ),
    fable.simulate(
      fable.scene("Rabbit Sacrifice", #(learn.init(), effect.none())),
      fn(simulate) {
        simulate
        |> simulate.click(on: from)
        |> simulate.click(on: query.element(query.id("rabbit_piece_5")))
      },
    ),
  ])
}
