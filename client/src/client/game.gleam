import cheg
import client/component
import client/icon
import gleam/bool
import gleam/dict
import gleam/int
import gleam/javascript/promise
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}
import gleam/uri
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import modem
import off_topic.{type Subscription, type WebsocketMessage}
import plinth/browser/clipboard
import shared

// MODEL ----------------------------------------------------------------------

pub type Model {
  Model(
    game: cheg.Game,
    guest_joined: Bool,
    link_copied: Bool,
    current_piece_moves: List(cheg.Move),
    player_color: Option(shared.PlayerColor),
    time: shared.Time,
    role: Option(cheg.Role),
    game_state: cheg.GameState,
    current_page_uri: Option(uri.Uri),
    websocket_url: Option(String),
    current_piece: Option(#(Int, Option(#(cheg.PieceType, shared.PlayerColor)))),
    offset: Int,
    lobby_id: String,
    is_public: Bool,
    premove: Option(cheg.Move),
    dragged_over_square: Option(Int),
    dragged_piece: Option(component.DraggedPiece),
    current_move: Option(cheg.Move),
  )
}

pub type Message {
  ComponentProducedMessage(component.Message)
  UserClickedCopyLink(lobby_url: String)
  TimerExpired
  ClockStoppedTicking
  ClientConnected
  ClientFailedToConnect(reason: String)
  ServerSentMessage(message: WebsocketMessage)
  ClockTickedForward(Timestamp)
}

pub fn init(
  current_page_uri: Option(uri.Uri),
  websocket_url: Option(String),
  lobby_id: String,
) -> #(Model, Effect(Message)) {
  let game = cheg.new(shared.TwinPasses, shared.RiverSacrifice)
  let time = shared.new_time(shared.monotonic_time())

  let model =
    Model(
      game:,
      guest_joined: False,
      link_copied: False,
      current_piece_moves: [],
      player_color: None,
      time:,
      role: None,
      game_state: cheg.Continue,
      current_page_uri:,
      current_piece: None,
      // in the future calculate offset based on latency
      offset: 0,
      lobby_id:,
      is_public: False,
      premove: None,
      dragged_over_square: None,
      dragged_piece: None,
      current_move: None,
      websocket_url:,
    )

  #(model, effect.none())
}

// UPDATE ---------------------------------------------------------------------

pub fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
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
      let piece = dict.get(cheg.board(model.game), from) |> option.from_result
      let current_piece_moves = case model.player_color {
        Some(player_color) -> {
          let to_move = cheg.to_move(model.game)

          case piece {
            Some(#(_, piece_color))
              if player_color == to_move
              && player_color == piece_color
              && model.game_state == cheg.Continue
            -> cheg.legal_moves_for_piece(model.game, from)
            Some(#(_, piece_color))
              if player_color == piece_color && model.game_state == cheg.Continue
            -> cheg.legal_premoves_for_piece(model.game, from, player_color)
            _ -> []
          }
        }
        None -> []
      }
      let dragged_piece =
        Some(component.DraggedPiece(
          width:,
          height:,
          from:,
          pointer_x:,
          pointer_y:,
          offset_x:,
          offset_y:,
        ))

      let model = Model(..model, current_piece_moves:, dragged_piece:)

      #(model, effect.none())
    }

    ComponentProducedMessage(component.UserDraggedOutOfTargetSquare) -> {
      let model = Model(..model, dragged_over_square: None, current_move: None)

      #(model, effect.none())
    }

    ComponentProducedMessage(component.UserDraggedToTargetSquare(
      position:,
      move:,
    )) -> {
      let model =
        Model(
          ..model,
          dragged_over_square: Some(position),
          current_move: Some(move),
        )

      #(model, effect.none())
    }

    ComponentProducedMessage(component.UserMovedPiece(pointer_x:, pointer_y:)) -> {
      let model = case model.dragged_piece {
        Some(dragged_piece) ->
          Model(
            ..model,
            dragged_piece: Some(
              component.DraggedPiece(..dragged_piece, pointer_x:, pointer_y:),
            ),
          )
        None -> model
      }

      #(model, effect.none())
    }

    ComponentProducedMessage(component.UserDroppedPiece) -> {
      let #(game, premove, effect) = case model.current_move {
        Some(move) -> apply_move(move, model)
        None -> #(model.game, model.premove, effect.none())
      }

      let model =
        Model(
          ..model,
          game:,
          current_piece: None,
          current_piece_moves: [],
          premove:,
          dragged_piece: None,
          dragged_over_square: None,
          current_move: None,
        )

      #(model, effect)
    }

    ComponentProducedMessage(component.UserCancelledDrag) -> {
      let model =
        Model(
          ..model,
          dragged_piece: None,
          dragged_over_square: None,
          current_move: None,
          current_piece_moves: [],
        )

      #(model, effect.none())
    }

    ComponentProducedMessage(component.UserClickedPiece(piece:, position:)) -> {
      let current_piece_moves = case model.player_color {
        Some(player_color) -> {
          let to_move = cheg.to_move(model.game)

          case piece {
            Some(#(_, piece_color))
              if player_color == to_move
              && player_color == piece_color
              && model.game_state == cheg.Continue
            -> cheg.legal_moves_for_piece(model.game, position)
            Some(#(_, piece_color))
              if player_color == piece_color && model.game_state == cheg.Continue
            -> cheg.legal_premoves_for_piece(model.game, position, player_color)
            _ -> []
          }
        }
        None -> []
      }

      let model = Model(..model, current_piece_moves:)

      #(model, effect.none())
    }

    ComponentProducedMessage(component.UserClickedTargetSquare(move:)) -> {
      let #(game, premove, effect) = apply_move(move, model)
      let model =
        Model(
          ..model,
          game:,
          current_piece: None,
          current_piece_moves: [],
          premove:,
          dragged_over_square: None,
        )

      #(model, effect)
    }

    ComponentProducedMessage(component.UserClickedEmptySquare) -> {
      #(Model(..model, premove: None), effect.none())
    }

    UserClickedCopyLink(lobby_url:) -> {
      let model = Model(..model, link_copied: True)
      let effect =
        effect.batch([
          copy_link(lobby_url),
          off_topic.after(duration.seconds(1), TimerExpired),
        ])

      #(model, effect)
    }

    TimerExpired -> #(Model(..model, link_copied: False), effect.none())

    ClockStoppedTicking -> {
      let black_time =
        int.clamp(model.time.black_time, shared.min_time, shared.max_time)
      let white_time =
        int.clamp(model.time.white_time, shared.min_time, shared.max_time)

      let game_state = case model.game_state == cheg.Continue, black_time <= 0 {
        True, True -> cheg.WhiteWin
        True, False -> cheg.BlackWin
        _, _ -> model.game_state
      }

      let model =
        Model(
          ..model,
          time: shared.Time(
            ..model.time,
            black_time:,
            white_time:,
            started: False,
          ),
          game_state:,
          premove: None,
        )

      #(model, effect.none())
    }
    ClientConnected -> #(model, effect.none())
    ServerSentMessage(message:) ->
      case message {
        off_topic.TextFrame(data:) -> {
          case json.parse(data, cheg.server_message_decoder()) {
            Ok(server_message) ->
              case server_message {
                cheg.ServerReturnedGame(game_view) -> {
                  let black_tick = case cheg.to_move(game_view.game) {
                    shared.Black -> shared.monotonic_time()
                    shared.White -> model.time.black_tick
                  }
                  let white_tick = case cheg.to_move(game_view.game) {
                    shared.Black -> model.time.white_tick
                    shared.White -> shared.monotonic_time()
                  }

                  let game = game_view.game

                  let #(premove, premove_effect) = case model.premove {
                    None -> #(None, effect.none())
                    Some(move) -> {
                      use <- bool.guard(
                        game_view.game_state != cheg.Continue,
                        #(None, effect.none()),
                      )

                      let to_move = cheg.to_move(game)
                      let payload =
                        json.object([
                          #("type", json.string("move")),
                          #("move", cheg.move_to_json(move)),
                        ])

                      case model.player_color {
                        Some(player_color) if player_color == to_move -> {
                          case list.contains(cheg.legal_moves(game), move) {
                            True -> {
                              case model.websocket_url {
                                Some(url) -> {
                                  #(None, send(url, payload))
                                }
                                None -> #(None, effect.none())
                              }
                            }
                            False -> #(None, effect.none())
                          }
                        }
                        _ -> #(model.premove, effect.none())
                      }
                    }
                  }

                  let effect =
                    effect.batch([
                      case game_view.game_state != cheg.Continue {
                        True -> stop_clock()
                        False -> effect.none()
                      },
                      case game_view.guest_joined {
                        False -> {
                          modem.push("/game/" <> game_view.lobby_id, None, None)
                        }
                        _ -> effect.none()
                      },
                      premove_effect,
                    ])
                  let model =
                    Model(
                      ..model,
                      game:,
                      time: shared.Time(
                        ..game_view.time,
                        black_tick:,
                        white_tick:,
                      ),
                      guest_joined: game_view.guest_joined,
                      role: Some(game_view.role),
                      game_state: game_view.game_state,
                      player_color: game_view.player_color,
                      is_public: game_view.is_public,
                      premove:,
                    )

                  #(model, effect)
                }
                cheg.Ping -> {
                  let payload =
                    json.object([
                      #("type", json.string("message")),
                      #("message", json.string("pong")),
                    ])

                  let effect = case model.websocket_url {
                    Some(url) -> {
                      send(url, payload)
                    }
                    None -> effect.none()
                  }

                  #(model, effect)
                }
              }
            Error(_) -> #(model, effect.none())
          }
        }
        off_topic.BinaryFrame(_) -> #(model, effect.none())
      }

    ClientFailedToConnect(reason: _) -> #(model, effect.none())

    ClockTickedForward(_) -> {
      let offset = model.offset

      let #(time, effect) = case cheg.to_move(model.game), model.time.started {
        shared.Black, True -> {
          let black_tick = shared.monotonic_time()
          let black_time =
            current_time(model.time.black_time, model.time.black_tick, offset)

          let effect = case black_time <= 0 {
            True -> stop_clock()
            False -> effect.none()
          }
          #(shared.Time(..model.time, black_time:, black_tick:), effect)
        }
        shared.White, True -> {
          let white_tick = shared.monotonic_time()
          let white_time =
            current_time(model.time.white_time, model.time.white_tick, offset)
          let effect = case white_time <= 0 {
            True -> stop_clock()
            False -> effect.none()
          }

          #(shared.Time(..model.time, white_time:, white_tick:), effect)
        }
        _, _ -> #(model.time, effect.none())
      }
      let model = Model(..model, time:)

      #(model, effect)
    }
  }
}

fn send(url: String, json: Json) {
  let frame = off_topic.TextFrame(data: json.to_string(json))
  off_topic.websocket_send(url, frame)
}

fn apply_move(
  move: cheg.Move,
  model: Model,
) -> #(cheg.Game, Option(cheg.Move), effect.Effect(Message)) {
  let payload =
    json.object([
      #("type", json.string("move")),
      #("move", cheg.move_to_json(move)),
    ])

  let to_move = cheg.to_move(model.game)
  let #(game, premove) = case model.player_color {
    Some(player_color) ->
      case player_color != to_move {
        True -> #(model.game, Some(move))
        False -> #(cheg.apply_move(model.game, move), None)
      }
    None -> #(model.game, model.premove)
  }

  let premove_effect = case premove {
    Some(_) -> effect.none()
    None -> {
      case model.websocket_url {
        Some(url) -> send(url, payload)
        None -> effect.none()
      }
    }
  }
  #(game, premove, premove_effect)
}

fn current_time(remaining: Int, tick: Int, offset: Int) -> Int {
  let elapsed = shared.monotonic_time() + offset - tick
  remaining - elapsed
}

// SUBSCRIPTIONS --------------------------------------------------------------

pub fn subscriptions(model: Model) -> Subscription(Message) {
  let websocket = case model.websocket_url {
    Some(url) ->
      off_topic.websocket(
        url:,
        on_open: ClientConnected,
        on_message: fn(message) { ServerSentMessage(message) },
        on_error: fn(reason) { ClientFailedToConnect(reason) },
      )
    None -> off_topic.none()
  }
  let timer = off_topic.every(duration.seconds(1), True, ClockTickedForward)

  off_topic.batch([websocket, timer])
}

// EFFECTS --------------------------------------------------------------------

fn copy_link(lobby_url: String) -> Effect(Message) {
  effect.from(fn(_) {
    promise.tap(clipboard.write_text(lobby_url), fn(_) { Nil })
    Nil
  })
}

fn stop_clock() -> Effect(Message) {
  use dispatch <- effect.from

  dispatch(ClockStoppedTicking)
}

// VIEW -----------------------------------------------------------------------

pub fn view(model: Model) -> Element(Message) {
  let lobby_url = case model.current_page_uri {
    Some(uri) -> uri.to_string(uri)
    None -> ""
  }

  case model.guest_joined, model.is_public {
    False, False -> {
      let content =
        html.div([attribute.class("mx-auto max-w-xl p-8")], [
          html.p([], [
            html.text("Send this link to invite someone to play:"),
          ]),
          html.div([attribute.class("mt-4 flex")], [
            html.p(
              [
                attribute.class("p-2 border-y-2 border-l-2 w-fit rounded-l"),
                attribute.class("border-blue-500"),
              ],
              [html.text(lobby_url)],
            ),
            html.button(
              [
                attribute.class("rounded-r-md p-2 cursor-pointer"),
                attribute.class("bg-blue-500 text-white"),
                attribute.class("hover:bg-blue-600"),
                event.on_click(UserClickedCopyLink(lobby_url)),
              ],
              [
                case model.link_copied {
                  True -> icon.check()
                  False -> icon.clipboard()
                },
              ],
            ),
          ]),
        ])

      component.layout(content)
    }
    False, True -> {
      let content =
        html.p(
          [
            attribute.class("pt-8 px-3 md:p-8 max-w-fit mx-auto"),
            attribute.class("flex flex-col md:flex-row text-xl"),
          ],
          [
            html.text("Waiting for someone to join"),
            html.span([attribute.class("ellipsis")], [
              html.text("..."),
            ]),
          ],
        )

      component.layout(content)
    }
    True, _ -> {
      let captured_pieces = cheg.get_captured_pieces(model.game)

      html.div(
        [
          attribute.class("pt-8 px-3 md:p-8 max-w-fit mx-auto"),
          attribute.class("flex flex-col md:flex-row"),
        ],
        [
          component.dragged_piece_view(model.game, model.dragged_piece),
          component.game_view(component.Model(
            game: model.game,
            moves: model.current_piece_moves,
            player_color: model.player_color,
            premove: model.premove,
            dragged_over_square: model.dragged_over_square,
            dragged_piece: model.dragged_piece,
          )),
          component.clock_view(
            model.time.black_time,
            model.time.white_time,
            model.player_color,
            model.game_state,
            captured_pieces,
          ),
        ],
      )
      |> element.map(ComponentProducedMessage)
      |> component.game_layout(model.dragged_piece, ComponentProducedMessage)
    }
  }
}
