import cheg
import gleam/erlang/process.{type Subject}
import gleam/json
import gleam/option.{None, Some}
import gleam/otp/actor
import server/context.{type Context}
import server/game_actor.{type GameMsg, Join} as game
import wisp.{type Request, type Response, Signed}
import wisp/websocket

type ConnState {
  Ready(session: String, role: cheg.Role, game: Subject(GameMsg))
  Rejected(reason: String)
}

pub fn handle_ws(ctx: Context, req: Request, id: String) -> Response {
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
          "" -> actor.call(ctx.registry, 1000, game.JoinPublicLobby)
          id -> actor.call(ctx.registry, 1000, game.JoinPrivateLobby(id, _))
        }
        let outgoing = process.new_subject()
        let join_result =
          actor.call(game_subject, 1000, Join(session, _, outgoing))

        case join_result {
          game.JoinOk(role:, model:, guest_joined:) -> {
            let selector = process.new_selector() |> process.select(outgoing)
            let player_color = case role {
              cheg.Host -> Some(cheg.White)
              cheg.Guest -> Some(cheg.Black)
              cheg.Spectator -> None
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
          game.JoinRejected(reason:) -> {
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
              websocket.Text(text) ->
                case actor.call(game, 1000, game.Move(session, text, _)) {
                  game.MoveOk -> websocket.Continue(state)
                  game.MoveRejected(reason:) -> {
                    wisp.log_info(reason)
                    let json =
                      json.object([#("error", json.string(reason))])
                      |> json.to_string
                    let _ = websocket.send_text(connection, json)

                    websocket.Continue(state)
                  }
                }
              websocket.Custom(game.StateUpdate(json)) -> {
                case websocket.send_text(connection, json) {
                  Ok(_) -> websocket.Continue(state)
                  Error(_) -> websocket.StopWithError("Failed to send message")
                }
              }
              websocket.Custom(game.Close(reason:)) -> {
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
            actor.send(game, game.Disconnect(session))

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
