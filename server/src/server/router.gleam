import gleam/http.{Get, Post}
import gleam/json
import gleam/result
import server/context.{type Context}
import server/game
import server/game_actor
import server/web
import wisp.{type Request, type Response, Signed}

pub fn handle_request(
  req: Request,
  static_directory: String,
  ctx: Context,
) -> Response {
  use req <- web.middleware(req, static_directory)

  case req.method, wisp.path_segments(req) {
    Get, ["ws"] -> game.handle_ws(ctx, req, "")
    Get, ["ws", id] -> game.handle_ws(ctx, req, id)
    _, ["v1", ..segments] -> api_routes(ctx, req, segments)
    _, _ -> web.serve_index()
  }
}

fn api_routes(_ctx: Context, req: wisp.Request, segments: List(String)) {
  case req.method, segments {
    Post, ["session"] -> {
      let token = wisp.random_string(12)

      let has_session =
        wisp.get_cookie(req, "session_id", Signed) |> result.is_ok

      case has_session {
        True -> wisp.ok()
        False ->
          wisp.ok()
          |> wisp.set_cookie(
            req,
            name: "session_id",
            value: token,
            security: Signed,
            max_age: 60 * 60 * 24 * 7 * 30,
          )
      }
    }
    Post, ["game"] -> {
      let invite_code = game_actor.create_invite_code(8)

      let body =
        json.object([#("invite_code", json.string(invite_code))])
        |> json.to_string

      wisp.json_response(body, 200)
    }
    _, _ -> wisp.not_found()
  }
}
