import cheg.{Guest, Host}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/otp/actor.{type Next, type StartError, type Started}
import shared
import wisp

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
  actor.new(dict.new())
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
  )
}

type GameActorStatus {
  Online(#(String, Subject(OutgoingMsg)))
  Disconnected(#(String, Subject(OutgoingMsg)))
  Empty
}

fn handle_message(state: GameActor, message: GameMsg) -> Next(GameActor, _) {
  case message {
    Join(session:, reply_to:, socket:) -> {
      let role = case state.host, state.guest {
        Online(#(s, _)), _ if s == session -> Host
        _, Online(#(s, _)) if s == session -> Guest
        _, _ -> Host
      }

      let #(time, game_state) = get_time(state.model.game, state)

      let state =
        GameActor(..state, model: Chesshire(..state.model, time:, game_state:))

      case state.host, state.guest {
        // New game, first to join becomes host
        Empty, Empty -> {
          let new_state = GameActor(..state, host: Online(#(session, socket)))
          broadcast_payload(state, role, new_state)

          actor.send(
            reply_to,
            JoinOk(Host, new_state.model, state.guest != Empty),
          )
          actor.continue(new_state)
        }

        // Host session matches but no guest, rejoin as host
        Disconnected(#(host_session, _)), _ if host_session == session -> {
          let new_state = GameActor(..state, host: Online(#(session, socket)))
          broadcast_payload(state, role, new_state)

          actor.send(
            reply_to,
            JoinOk(Host, new_state.model, state.guest != Empty),
          )
          actor.continue(new_state)
        }

        // There's already a host, join as guest
        Online(_), Empty -> {
          let new_state = GameActor(..state, guest: Online(#(session, socket)))
          broadcast_payload(state, role, new_state)

          actor.send(
            reply_to,
            JoinOk(Guest, new_state.model, state.guest != Empty),
          )
          actor.continue(new_state)
        }

        // Both slots filled but guest session matches, rejoin as guest
        _, Disconnected(#(guest_session, _)) if guest_session == session -> {
          let new_state = GameActor(..state, guest: Online(#(session, socket)))
          broadcast_payload(state, role, new_state)

          actor.send(
            reply_to,
            JoinOk(Guest, new_state.model, state.guest != Empty),
          )
          actor.continue(new_state)
        }

        _, _ -> {
          actor.send(reply_to, JoinRejected("Game is full"))
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

      case role {
        None -> {
          actor.send(reply_to, MoveRejected("Not a player"))
          actor.continue(state)
        }
        Some(player_role) -> {
          let role = cheg.role(state.model.game)

          case player_role == role {
            False -> {
              actor.send(reply_to, MoveRejected("Not your turn"))
              actor.continue(state)
            }
            True ->
              case json.parse(move_json, cheg.move_decoder()) {
                Error(_) -> {
                  actor.send(reply_to, MoveRejected("Bad move format"))
                  actor.continue(state)
                }
                Ok(move) -> {
                  let game = cheg.apply_move(state.model.game, move)
                  let model = Chesshire(..state.model, game:)
                  let state = GameActor(..state, model:)

                  let #(time, game_state) = get_time(game, state)

                  let host_payload =
                    cheg.game_view_to_json(cheg.GameView(
                      game:,
                      game_state:,
                      role: cheg.Host,
                      time:,
                      guest_joined: state.guest != Empty,
                    ))
                    |> json.to_string
                  let guest_payload =
                    cheg.game_view_to_json(cheg.GameView(
                      game:,
                      game_state:,
                      role: cheg.Guest,
                      time:,
                      guest_joined: state.guest != Empty,
                    ))
                    |> json.to_string

                  let state =
                    GameActor(..state, model: Chesshire(..state.model, time:))

                  broadcast(state, host_payload, guest_payload)

                  actor.send(reply_to, MoveOk)
                  actor.continue(state)
                }
              }
          }
        }
      }
    }
    Disconnect(session:) -> {
      wisp.log_info(session)

      let new_state = case state.host, state.guest {
        Online(#(host_session, socket)), _ if host_session == session ->
          GameActor(..state, host: Disconnected(#(host_session, socket)))
        _, Online(#(guest_session, socket)) if guest_session == session ->
          GameActor(..state, guest: Disconnected(#(guest_session, socket)))
        _, _ -> state
      }

      case new_state.host, new_state.guest {
        Disconnected(_), Disconnected(_) -> actor.stop()
        _, _ -> actor.continue(new_state)
      }
    }
  }
}

fn broadcast_payload(
  state: GameActor,
  _role: cheg.Role,
  new_state: GameActor,
) -> Nil {
  let host_payload =
    cheg.game_view_to_json(cheg.GameView(
      game: state.model.game,
      role: cheg.Host,
      game_state: cheg.state(state.model.game),
      time: state.model.time,
      guest_joined: new_state.guest != Empty,
    ))
    |> json.to_string
  let guest_payload =
    cheg.game_view_to_json(cheg.GameView(
      game: state.model.game,
      role: cheg.Guest,
      game_state: cheg.state(state.model.game),
      time: state.model.time,
      guest_joined: new_state.guest != Empty,
    ))
    |> json.to_string

  broadcast(new_state, host_payload, guest_payload)
}

fn broadcast(state: GameActor, host_json: String, guest_json: String) -> Nil {
  case state.host {
    Online(#(_, socket)) -> process.send(socket, StateUpdate(host_json))
    _ -> Nil
  }
  case state.guest {
    Online(#(_, socket)) -> process.send(socket, StateUpdate(guest_json))
    _ -> Nil
  }
}

pub type RegistryMsg {
  GetOrStart(invite_code: String, reply_to: Subject(Subject(GameMsg)))
}

fn registry_loop(
  state: Dict(String, Subject(GameMsg)),
  msg: RegistryMsg,
) -> Next(Dict(String, Subject(GameMsg)), _) {
  case msg {
    GetOrStart(invite_code:, reply_to:) ->
      case dict.get(state, invite_code) {
        Ok(subject) -> {
          actor.send(reply_to, subject)
          actor.continue(state)
        }
        Error(_) -> {
          let assert Ok(started) =
            actor.new(new(invite_code))
            |> actor.on_message(handle_message)
            |> actor.start
          actor.send(reply_to, started.data)
          actor.continue(dict.insert(state, invite_code, started.data))
        }
      }
  }
}

fn new(invite_code) -> GameActor {
  let game = cheg.new()
  let game_state = cheg.state(game)
  let time = shared.new_time(monotonic_time())

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
  )
}

fn get_time(
  game: cheg.Game,
  state: GameActor,
) -> #(shared.Time, cheg.GameState) {
  let now = monotonic_time()
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
  let #(black_time, black_tick) = case to_move {
    cheg.Black -> #(state.model.time.black_time - elapsed, now)
    cheg.White -> #(state.model.time.black_time, now)
  }
  let #(white_time, white_tick) = case to_move {
    cheg.Black -> #(state.model.time.white_time, now)
    cheg.White -> #(state.model.time.white_time - elapsed, now)
  }
  let state = cheg.state(game)
  let time =
    shared.Time(black_time:, white_time:, black_tick:, white_tick:, started:)

  case black_time, white_time, state {
    black_time, _, cheg.Continue if black_time == 0 -> #(time, cheg.WhiteWin)
    _, white_time, cheg.Continue if white_time == 0 -> #(time, cheg.BlackWin)
    _, _, state -> #(time, state)
  }
}

// EXTERNALS -----------------------------------------------------------------

@external(erlang, "server_ffi", "monotonic_time")
pub fn monotonic_time() -> Int
