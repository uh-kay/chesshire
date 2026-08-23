import client/page/about
import gleam/http.{Get, Post}
import gleam/int
import gleam/json
import gleam/result
import gleam/string
import server/context.{type Context}
import server/game
import server/web
import wisp.{type Request, type Response, Signed}

pub fn handle_request(
  req: Request,
  static_directory: String,
  ctx: Context,
) -> Response {
  use req <- web.middleware(req, static_directory)

  case req.method, wisp.path_segments(req) {
    Get, ["ws", invite_code] -> game.handle_ws(req, invite_code, ctx)
    _, ["v1", ..segments] -> api_routes(req, segments)
    Get, ["about"] -> about.view() |> wisp.html_response(200)
    _, _ -> web.serve_index()
  }
}

fn api_routes(req: wisp.Request, segments: List(String)) {
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
      let invite_code = create_invite_code(8)

      let body =
        json.object([#("invite_code", json.string(invite_code))])
        |> json.to_string

      wisp.json_response(body, 200)
    }
    _, _ -> wisp.not_found()
  }
}

fn create_invite_code(length: Int) -> String {
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
