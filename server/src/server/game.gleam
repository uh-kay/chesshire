import cheg.{Guest, Host, Spectator}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor.{type Next, type StartError, type Started}
import gleam/result
import gleam/string
import shared
import wisp.{type Request, type Response, Signed}
import wisp/websocket

type ConnState {
  Ready(session: String, role: cheg.Role, game: Subject(GameMsg))
  Rejected(reason: String)
}

pub fn handle_ws(
  registry: Subject(RegistryMsg),
  req: Request,
  id: String,
) -> Response {
  let #(session, new_token) = case wisp.get_cookie(req, "session_id", Signed) {
    Ok(session) -> #(session, None)
    Error(_) -> {
      let token = wisp.random_string(12)
      #(token, Some(token))
    }
  }

  let response =
    wisp.websocket(
      req,
      on_init: fn(connection) {
        let game_subject = case id {
          "" -> actor.call(registry, 1000, JoinPublicLobby)
          id -> actor.call(registry, 1000, JoinPrivateLobby(id, _))
        }
        let outgoing = process.new_subject()
        let join_result =
          actor.call(game_subject, 1000, Join(session, _, outgoing))

        case join_result {
          JoinOk(role:, model:, guest_joined:, host_color:, guest_color:) -> {
            let selector = process.new_selector() |> process.select(outgoing)
            let player_color = case role {
              Host ->
                Some(case host_color {
                  shared.Black -> cheg.Black
                  shared.White -> cheg.White
                })
              Guest ->
                Some(case guest_color {
                  shared.Black -> cheg.Black
                  shared.White -> cheg.White
                })
              Spectator -> None
            }

            let payload =
              cheg.game_view_to_json(cheg.GameView(
                game: model.game,
                role:,
                game_state: model.game_state,
                time: model.time,
                guest_joined:,
                player_color:,
                lobby_id: model.invite_code,
              ))
              |> json.to_string

            let _ = websocket.send_text(connection, payload)

            #(Ready(session:, role:, game: game_subject), Some(selector))
          }
          JoinRejected(reason:) -> {
            wisp.log_info(reason)
            #(Rejected(reason:), None)
          }
        }
      },
      on_message: fn(state, message, connection) {
        case state {
          Rejected(reason:) -> {
            let json =
              json.object([#("error", json.string(reason))])
              |> json.to_string
            let _ = websocket.send_text(connection, json)

            websocket.Stop
          }
          Ready(session:, game:, role: _) ->
            case message {
              websocket.Text(text) -> {
                case text {
                  "ping" -> websocket.Continue(state)
                  _ ->
                    case json.parse(text, cheg.move_decoder()) {
                      Ok(move) ->
                        case actor.call(game, 1000, Move(session, move, _)) {
                          MoveOk -> websocket.Continue(state)
                          MoveRejected(reason:) -> {
                            wisp.log_info(reason)
                            let json =
                              json.object([#("error", json.string(reason))])
                              |> json.to_string
                            let _ = websocket.send_text(connection, json)

                            websocket.Continue(state)
                          }
                        }

                      Error(_) -> websocket.Continue(state)
                    }
                }
              }

              websocket.Custom(StateUpdate(json)) -> {
                case websocket.send_text(connection, json) {
                  Ok(_) -> websocket.Continue(state)
                  Error(_) -> websocket.StopWithError("Failed to send message")
                }
              }
              websocket.Custom(Close(reason:)) -> {
                wisp.log_info(reason)
                websocket.Stop
              }
              websocket.Binary(_) | websocket.Closed | websocket.Shutdown -> {
                websocket.Stop
              }
            }
        }
      },
      on_close: fn(state) {
        case state {
          Ready(session:, role: _, game:) -> {
            actor.send(game, Disconnect(session))

            Nil
          }
          Rejected(reason: _) -> Nil
        }
      },
    )

  case new_token {
    Some(session_id) ->
      response
      |> wisp.set_cookie(
        req,
        name: "session_id",
        value: session_id,
        security: Signed,
        max_age: 60 * 60 * 24 * 7 * 30,
      )
    None -> response
  }
}

pub type Chesshire {
  Chesshire(
    game: cheg.Game,
    time: shared.Time,
    invite_code: String,
    game_state: cheg.GameState,
  )
}

pub type GameMsg {
  Join(
    session: String,
    reply_to: Subject(JoinReply),
    socket: Subject(OutgoingMsg),
  )
  Move(session: String, move: cheg.Move, reply_to: Subject(MoveReply))
  Disconnect(session: String)
}

pub type JoinReply {
  JoinOk(
    role: cheg.Role,
    model: Chesshire,
    guest_joined: Bool,
    host_color: shared.PlayerColor,
    guest_color: shared.PlayerColor,
  )
  JoinRejected(reason: String)
}

pub type MoveReply {
  MoveOk
  MoveRejected(reason: String)
}

pub type DisconnectReply {
  Quit(reason: String)
}

pub type OutgoingMsg {
  StateUpdate(json: String)
  Close(reason: String)
}

type GameActor {
  GameActor(
    model: Chesshire,
    invite_code: String,
    host: GameActorStatus,
    guest: GameActorStatus,
    host_color: shared.PlayerColor,
    guest_color: shared.PlayerColor,
    spectators: List(GameActorStatus),
  )
}

type GameActorStatus {
  Online(#(String, Subject(OutgoingMsg)))
  Disconnected(#(String, Subject(OutgoingMsg)))
  Empty
}

pub type GameError {
  UnknownPlayer
  OutOfTurn
  InvalidMoveFormat
  IllegalMove
}

fn handle_message(state: GameActor, message: GameMsg) -> Next(GameActor, _) {
  case message {
    Join(session:, reply_to:, socket:) -> {
      let #(time, game_state) = get_time(state.model.game, state)

      let state =
        GameActor(..state, model: Chesshire(..state.model, time:, game_state:))

      case state.host, state.guest {
        // New game, first to join becomes host
        Empty, Empty -> {
          let new_state = GameActor(..state, host: Online(#(session, socket)))
          broadcast_payload(state, new_state)

          actor.send(
            reply_to,
            JoinOk(
              Host,
              new_state.model,
              state.guest != Empty,
              host_color: state.host_color,
              guest_color: state.guest_color,
            ),
          )
          actor.continue(new_state)
        }

        // Host session matches but no guest, rejoin as host
        Disconnected(#(host_session, _)), _ if host_session == session -> {
          let new_state = GameActor(..state, host: Online(#(session, socket)))
          broadcast_payload(state, new_state)

          actor.send(
            reply_to,
            JoinOk(
              Host,
              new_state.model,
              state.guest != Empty,
              host_color: state.host_color,
              guest_color: state.guest_color,
            ),
          )
          actor.continue(new_state)
        }

        // There's already a host, join as guest
        Online(_), Empty -> {
          let new_state = GameActor(..state, guest: Online(#(session, socket)))
          broadcast_payload(state, new_state)

          actor.send(
            reply_to,
            JoinOk(
              Guest,
              new_state.model,
              state.guest != Empty,
              host_color: state.host_color,
              guest_color: state.guest_color,
            ),
          )
          actor.continue(new_state)
        }

        // Both slots filled but guest session matches, rejoin as guest
        _, Disconnected(#(guest_session, _)) if guest_session == session -> {
          let new_state = GameActor(..state, guest: Online(#(session, socket)))
          broadcast_payload(state, new_state)

          actor.send(
            reply_to,
            JoinOk(
              Guest,
              new_state.model,
              state.guest != Empty,
              host_color: state.host_color,
              guest_color: state.guest_color,
            ),
          )
          actor.continue(new_state)
        }

        // Both host and guest has joined, join as spectator
        Online(_), Online(_) -> {
          let state =
            GameActor(..state, spectators: [
              Online(#(session, socket)),
              ..state.spectators
            ])
          actor.send(
            reply_to,
            JoinOk(
              Spectator,
              state.model,
              True,
              host_color: state.host_color,
              guest_color: state.guest_color,
            ),
          )
          actor.continue(state)
        }

        _, _ -> {
          actor.send(reply_to, JoinRejected("Game is over"))
          actor.continue(state)
        }
      }
    }
    Move(session:, move:, reply_to:) -> {
      let role = case state.host, state.guest {
        Online(#(s, _)), _ if s == session -> Some(Host)
        _, Online(#(s, _)) if s == session -> Some(Guest)
        _, _ -> None
      }

      let result = {
        use player_role <- result.try(case role {
          Some(Spectator) -> Error(UnknownPlayer)
          Some(role) -> Ok(role)
          None -> Error(UnknownPlayer)
        })
        use player_color <- result.try(case player_role {
          Host -> Ok(state.host_color)
          Guest -> Ok(state.guest_color)
          Spectator -> Error(UnknownPlayer)
        })
        let player_color = case player_color {
          shared.Black -> cheg.Black
          shared.White -> cheg.White
        }
        let current_turn = cheg.to_move(state.model.game)
        use _ <- result.try(case player_color == current_turn {
          True -> Ok(Nil)
          False -> Error(OutOfTurn)
        })

        let legal_moves = cheg.legal_moves(state.model.game)

        use _ <- result.try(case list.contains(legal_moves, move) {
          True -> Ok(Nil)
          False -> Error(IllegalMove)
        })

        let game = cheg.apply_move(state.model.game, move)
        let state = GameActor(..state, model: Chesshire(..state.model, game:))
        let #(time, game_state) = get_time(game, state)

        let host_color = case state.host_color {
          shared.Black -> cheg.Black
          shared.White -> cheg.White
        }
        let guest_color = case state.guest_color {
          shared.Black -> cheg.Black
          shared.White -> cheg.White
        }

        let host_payload =
          cheg.game_view_to_json(cheg.GameView(
            game:,
            game_state:,
            role: Host,
            time:,
            guest_joined: state.guest != Empty,
            player_color: Some(host_color),
            lobby_id: state.invite_code,
          ))
          |> json.to_string
        let guest_payload =
          cheg.game_view_to_json(cheg.GameView(
            game:,
            game_state:,
            role: Guest,
            time:,
            guest_joined: state.guest != Empty,
            player_color: Some(guest_color),
            lobby_id: state.invite_code,
          ))
          |> json.to_string
        let spectator_payload =
          cheg.game_view_to_json(cheg.GameView(
            game:,
            game_state:,
            role: Spectator,
            time:,
            guest_joined: state.guest != Empty,
            player_color: None,
            lobby_id: state.invite_code,
          ))
          |> json.to_string

        let state = GameActor(..state, model: Chesshire(..state.model, time:))

        broadcast(state, host_payload, guest_payload, spectator_payload)
        Ok(state)
      }

      case result {
        Ok(state) -> {
          actor.send(reply_to, MoveOk)
          actor.continue(state)
        }
        Error(err) ->
          case err {
            UnknownPlayer -> {
              actor.send(reply_to, MoveRejected("Not a player"))
              actor.continue(state)
            }
            OutOfTurn -> {
              actor.send(reply_to, MoveRejected("Not your turn"))
              actor.continue(state)
            }
            InvalidMoveFormat -> {
              actor.send(reply_to, MoveRejected("Bad move format"))
              actor.continue(state)
            }
            IllegalMove -> {
              actor.send(reply_to, MoveRejected("Illegal move"))
              actor.continue(state)
            }
          }
      }
    }

    Disconnect(session:) -> {
      let new_state = case state.host, state.guest {
        Online(#(host_session, socket)), _ if host_session == session ->
          GameActor(..state, host: Disconnected(#(host_session, socket)))
        _, Online(#(guest_session, socket)) if guest_session == session ->
          GameActor(..state, guest: Disconnected(#(guest_session, socket)))
        _, _ -> state
      }

      case new_state.host, new_state.guest {
        Disconnected(_), Disconnected(_)
          if state.model.game_state != cheg.Continue
        -> actor.stop()
        _, _ -> actor.continue(new_state)
      }
    }
  }
}

fn broadcast_payload(state: GameActor, new_state: GameActor) -> Nil {
  let game = state.model.game
  let game_state = cheg.state(game)
  let time = state.model.time
  let guest_joined = new_state.guest != Empty
  let lobby_id = state.invite_code
  let host_color = case state.host_color {
    shared.Black -> cheg.Black
    shared.White -> cheg.White
  }
  let guest_color = case state.guest_color {
    shared.Black -> cheg.Black
    shared.White -> cheg.White
  }

  let host_payload =
    cheg.game_view_to_json(cheg.GameView(
      game:,
      role: Host,
      game_state:,
      time:,
      guest_joined:,
      player_color: Some(host_color),
      lobby_id:,
    ))
    |> json.to_string
  let guest_payload =
    cheg.game_view_to_json(cheg.GameView(
      game:,
      role: Guest,
      game_state:,
      time:,
      guest_joined:,
      player_color: Some(guest_color),
      lobby_id:,
    ))
    |> json.to_string
  let spectator_payload =
    cheg.game_view_to_json(cheg.GameView(
      game:,
      role: Spectator,
      game_state:,
      time:,
      guest_joined:,
      player_color: None,
      lobby_id:,
    ))
    |> json.to_string

  broadcast(new_state, host_payload, guest_payload, spectator_payload)
}

fn broadcast(
  state: GameActor,
  host_json: String,
  guest_json: String,
  spectator_json: String,
) -> Nil {
  case state.host {
    Online(#(_, socket)) -> process.send(socket, StateUpdate(host_json))
    _ -> Nil
  }
  case state.guest {
    Online(#(_, socket)) -> process.send(socket, StateUpdate(guest_json))
    _ -> Nil
  }
  list.each(state.spectators, fn(spectator) {
    case spectator {
      Online(#(_, socket)) -> process.send(socket, StateUpdate(spectator_json))
      _ -> Nil
    }
  })
}

fn new(invite_code: String, create_game: shared.CreateGame) -> GameActor {
  let game = cheg.new(create_game.board_variant, create_game.game_variant)
  let game_state = cheg.state(game)
  let time = shared.new_time(shared.monotonic_time())
  let guest_color = case create_game.host_side {
    shared.Black -> shared.White
    shared.White -> shared.Black
  }

  GameActor(
    model: Chesshire(game:, time:, invite_code:, game_state:),
    invite_code:,
    host: Empty,
    guest: Empty,
    spectators: [],
    host_color: create_game.host_side,
    guest_color:,
  )
}

fn get_time(
  game: cheg.Game,
  state: GameActor,
) -> #(shared.Time, cheg.GameState) {
  let now = shared.monotonic_time()
  let started = cheg.get_full_moves(game) >= 2
  let to_move = cheg.to_move(game)
  let last_tick = case to_move {
    cheg.Black -> state.model.time.black_tick
    cheg.White -> state.model.time.white_tick
  }
  let elapsed = case state.model.time.started {
    False -> 0
    True -> now - last_tick
  }

  let black_time = case to_move {
    cheg.Black -> state.model.time.black_time
    cheg.White -> state.model.time.black_time - elapsed
  }
  let white_time = case to_move {
    cheg.Black -> state.model.time.white_time - elapsed
    cheg.White -> state.model.time.white_time
  }
  let black_tick = case to_move {
    cheg.White -> now
    cheg.Black -> state.model.time.black_tick
  }
  let white_tick = case to_move {
    cheg.White -> state.model.time.white_tick
    cheg.Black -> now
  }

  let state = cheg.state(game)
  let time =
    shared.Time(black_time:, white_time:, black_tick:, white_tick:, started:)

  case black_time, white_time, state {
    black_time, _, cheg.Continue if black_time <= 0 -> #(time, cheg.WhiteWin)
    _, white_time, cheg.Continue if white_time <= 0 -> #(time, cheg.BlackWin)
    _, _, state -> #(time, state)
  }
}

pub fn create_invite_code(length: Int) -> String {
  create_invite_code_loop(length, "")
}

fn create_invite_code_loop(remaining: Int, invite_code: String) -> String {
  case remaining {
    0 -> invite_code
    _ -> {
      let alphabet =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
      let index = int.random(62)
      let char = string.slice(alphabet, index, 1)
      create_invite_code_loop(remaining - 1, invite_code <> char)
    }
  }
}

// REGISTRY -------------------------------------------------------------------

pub type RegistryState {
  RegistryState(waiting: List(String), games: Dict(String, Subject(GameMsg)))
}

pub type RegistryMsg {
  CreatePrivateLobby(
    invite_code: String,
    create_game: shared.CreateGame,
    reply_to: Subject(Subject(GameMsg)),
  )
  JoinPrivateLobby(invite_code: String, reply_to: Subject(Subject(GameMsg)))
  CreatePublicLobby(
    id: String,
    create_game: shared.CreateGame,
    reply_to: Subject(Subject(GameMsg)),
  )
  JoinPublicLobby(reply_to: Subject(Subject(GameMsg)))
}

pub fn start_registry() -> Result(Started(Subject(RegistryMsg)), StartError) {
  let state = RegistryState(waiting: [], games: dict.new())
  actor.new(state)
  |> actor.on_message(registry_loop)
  |> actor.start
}

fn registry_loop(
  state: RegistryState,
  msg: RegistryMsg,
) -> Next(RegistryState, _) {
  case msg {
    JoinPrivateLobby(invite_code:, reply_to:) ->
      case dict.get(state.games, invite_code) {
        Ok(subject) -> {
          actor.send(reply_to, subject)
          actor.continue(state)
        }
        Error(_) -> {
          let assert Ok(started) =
            actor.new(new(
              invite_code,
              shared.CreateGame(
                True,
                board_variant: shared.TwinPasses,
                game_variant: shared.RiverSacrifice,
                host_side: case int.random(2) {
                  0 -> shared.Black
                  _ -> shared.White
                },
              ),
            ))
            |> actor.on_message(handle_message)
            |> actor.start
          let state =
            RegistryState(
              ..state,
              games: dict.insert(state.games, invite_code, started.data),
            )
          actor.send(reply_to, started.data)
          actor.continue(state)
        }
      }
    JoinPublicLobby(reply_to:) -> {
      case state.waiting {
        [id, ..rest] -> {
          let assert Ok(subject) = dict.get(state.games, id)
          actor.send(reply_to, subject)
          actor.continue(RegistryState(..state, waiting: rest))
        }
        [] -> {
          let id = create_invite_code(8)
          let assert Ok(started) =
            actor.new(new(
              id,
              shared.CreateGame(
                True,
                board_variant: shared.TwinPasses,
                game_variant: shared.RiverSacrifice,
                host_side: case int.random(2) {
                  0 -> shared.Black
                  _ -> shared.White
                },
              ),
            ))
            |> actor.on_message(handle_message)
            |> actor.start
          let state =
            RegistryState(
              waiting: [id, ..state.waiting],
              games: dict.insert(state.games, id, started.data),
            )
          actor.send(reply_to, started.data)
          actor.continue(state)
        }
      }
    }
    CreatePrivateLobby(invite_code:, create_game:, reply_to:) -> {
      let assert Ok(started) =
        actor.new(new(invite_code, create_game))
        |> actor.on_message(handle_message)
        |> actor.start
      let state =
        RegistryState(
          ..state,
          games: dict.insert(state.games, invite_code, started.data),
        )
      actor.send(reply_to, started.data)
      actor.continue(state)
    }
    CreatePublicLobby(create_game:, reply_to:, id:) -> {
      let assert Ok(started) =
        actor.new(new(id, create_game))
        |> actor.on_message(handle_message)
        |> actor.start

      // Push the ID twice because host will join, pop the ID, then we'll have
      // one more ID for the guest.
      let state =
        RegistryState(
          waiting: [id, id, ..state.waiting],
          games: dict.insert(state.games, id, started.data),
        )

      actor.send(reply_to, started.data)
      actor.continue(state)
    }
  }
}
