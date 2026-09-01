import cheg.{Guest, Host}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor.{type Next, type StartError, type Started}
import gleam/result
import gleam/string
import shared

pub type Chesshire {
  Chesshire(
    game: cheg.Game,
    time: shared.Time,
    invite_code: String,
    auth: Auth,
    game_state: cheg.GameState,
  )
}

pub type Auth {
  Auth(host_session: Option(String), guest_session: Option(String))
}

pub fn start_registry() -> Result(Started(Subject(RegistryMsg)), StartError) {
  let state = RegistryState(waiting: [], games: dict.new())
  actor.new(state)
  |> actor.on_message(registry_loop)
  |> actor.start
}

pub type GameMsg {
  Join(
    session: String,
    reply_to: Subject(JoinReply),
    socket: Subject(OutgoingMsg),
  )
  Move(session: String, move_json: String, reply_to: Subject(MoveReply))
  Disconnect(session: String)
}

pub type JoinReply {
  JoinOk(role: cheg.Role, model: Chesshire, guest_joined: Bool)
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
    spectator: GameActorStatus,
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
            JoinOk(Host, new_state.model, state.guest != Empty),
          )
          actor.continue(new_state)
        }

        // Host session matches but no guest, rejoin as host
        Disconnected(#(host_session, _)), _ if host_session == session -> {
          let new_state = GameActor(..state, host: Online(#(session, socket)))
          broadcast_payload(state, new_state)

          actor.send(
            reply_to,
            JoinOk(Host, new_state.model, state.guest != Empty),
          )
          actor.continue(new_state)
        }

        // There's already a host, join as guest
        Online(_), Empty -> {
          let new_state = GameActor(..state, guest: Online(#(session, socket)))
          broadcast_payload(state, new_state)

          actor.send(
            reply_to,
            JoinOk(Guest, new_state.model, state.guest != Empty),
          )
          actor.continue(new_state)
        }

        // Both slots filled but guest session matches, rejoin as guest
        _, Disconnected(#(guest_session, _)) if guest_session == session -> {
          let new_state = GameActor(..state, guest: Online(#(session, socket)))
          broadcast_payload(state, new_state)

          actor.send(
            reply_to,
            JoinOk(Guest, new_state.model, state.guest != Empty),
          )
          actor.continue(new_state)
        }

        // Both host and guest has joined, join as spectator
        Online(_), Online(_) -> {
          let state = GameActor(..state, spectator: Online(#(session, socket)))
          actor.send(reply_to, JoinOk(cheg.Spectator, state.model, True))
          actor.continue(state)
        }

        _, _ -> {
          actor.send(reply_to, JoinRejected("Game is over"))
          actor.continue(state)
        }
      }
    }
    Move(session:, move_json:, reply_to:) -> {
      let role = case state.host, state.guest {
        Online(#(s, _)), _ if s == session -> Some(Host)
        _, Online(#(s, _)) if s == session -> Some(Guest)
        _, _ -> None
      }

      let result = {
        use player_role <- result.try(case role {
          Some(cheg.Spectator) -> Error(UnknownPlayer)
          Some(role) -> Ok(role)
          None -> Error(UnknownPlayer)
        })
        let current_turn = cheg.role(state.model.game)
        use _ <- result.try(case player_role == current_turn {
          True -> Ok(Nil)
          False -> Error(OutOfTurn)
        })
        use move <- result.try(
          json.parse(move_json, cheg.move_decoder())
          |> result.replace_error(InvalidMoveFormat),
        )

        let legal_moves = cheg.legal_moves(state.model.game)

        use _ <- result.try(case list.contains(legal_moves, move) {
          True -> Ok(Nil)
          False -> Error(IllegalMove)
        })

        let game = cheg.apply_move(state.model.game, move)
        let state = GameActor(..state, model: Chesshire(..state.model, game:))
        let #(time, game_state) = get_time(game, state)

        let host_payload =
          cheg.game_view_to_json(cheg.GameView(
            game:,
            game_state:,
            role: cheg.Host,
            time:,
            guest_joined: state.guest != Empty,
            player_color: Some(cheg.White),
            lobby_id: state.invite_code,
          ))
          |> json.to_string
        let guest_payload =
          cheg.game_view_to_json(cheg.GameView(
            game:,
            game_state:,
            role: cheg.Guest,
            time:,
            guest_joined: state.guest != Empty,
            player_color: Some(cheg.Black),
            lobby_id: state.invite_code,
          ))
          |> json.to_string
        let spectator_payload =
          cheg.game_view_to_json(cheg.GameView(
            game:,
            game_state:,
            role: cheg.Spectator,
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

  let host_payload =
    cheg.game_view_to_json(cheg.GameView(
      game:,
      role: cheg.Host,
      game_state:,
      time:,
      guest_joined:,
      player_color: Some(cheg.White),
      lobby_id:,
    ))
    |> json.to_string
  let guest_payload =
    cheg.game_view_to_json(cheg.GameView(
      game:,
      role: cheg.Guest,
      game_state:,
      time:,
      guest_joined:,
      player_color: Some(cheg.Black),
      lobby_id:,
    ))
    |> json.to_string
  let spectator_payload =
    cheg.game_view_to_json(cheg.GameView(
      game:,
      role: cheg.Spectator,
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
  case state.spectator {
    Online(#(_, socket)) -> process.send(socket, StateUpdate(spectator_json))
    _ -> Nil
  }
}

pub type RegistryMsg {
  JoinPrivateLobby(invite_code: String, reply_to: Subject(Subject(GameMsg)))
  JoinPublicLobby(reply_to: Subject(Subject(GameMsg)))
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
            actor.new(new(invite_code))
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
            actor.new(new(id))
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
  }
}

fn new(invite_code: String) -> GameActor {
  let game = cheg.new()
  let game_state = cheg.state(game)
  let time = shared.new_time(shared.monotonic_time())

  GameActor(
    model: Chesshire(
      game:,
      time:,
      invite_code:,
      auth: Auth(guest_session: None, host_session: None),
      game_state:,
    ),
    invite_code:,
    host: Empty,
    guest: Empty,
    spectator: Empty,
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

  // Because the move has been applied, the current to_move is switched to the
  // opponent. That's why the time being reduced is not the to_move's time.
  let black_time = case to_move {
    cheg.Black -> state.model.time.black_time
    cheg.White -> state.model.time.black_time - elapsed
  }
  let white_time = case to_move {
    cheg.Black -> state.model.time.white_time - elapsed
    cheg.White -> state.model.time.white_time
  }

  let state = cheg.state(game)
  let time =
    shared.Time(
      black_time:,
      white_time:,
      black_tick: now,
      white_tick: now,
      started:,
    )

  case black_time, white_time, state {
    black_time, _, cheg.Continue if black_time <= 0 -> #(time, cheg.WhiteWin)
    _, white_time, cheg.Continue if white_time <= 0 -> #(time, cheg.BlackWin)
    _, _, state -> #(time, state)
  }
}

pub type RegistryState {
  RegistryState(waiting: List(String), games: Dict(String, Subject(GameMsg)))
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
