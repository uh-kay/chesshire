import gleam/erlang/process.{type Subject}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import server/game
import wisp.{type Request, type Response}

pub type Context {
  Context(registry: Subject(game.RegistryMsg))
}

pub fn middleware(
  req: Request,
  static_directory,
  handle_request: fn(Request) -> Response,
) {
  let req = wisp.method_override(req)
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use req <- wisp.handle_head(req)
  use <- wisp.serve_static(req, under: "/static", from: static_directory)
  use req <- wisp.csrf_known_header_protection(req)

  handle_request(req)
}

// <link rel="preconnect" href="https://fonts.googleapis.com">
// <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
// <link href="https://fonts.googleapis.com/css2?family=Comic+Relief:wght@400;700&family=Josefin+Sans:ital,wght@0,100..700;1,100..700&display=swap" rel="stylesheet">

pub fn serve_index() -> Response {
  html.html([], [
    html.head([], [
      html.meta([
        attribute.name("viewport"),
        attribute.content("width=device-width, initial-scale=1"),
      ]),
      html.title([], "Chesshire"),
      meta_og("title", "Play new chess variants for free"),
      meta_og(
        "description",
        "Free online chess server for various chess variants.",
      ),
      html.link([
        attribute.rel("icon"),
        attribute.href("/static/chesshire_favicon.svg"),
        attribute.type_("image/svg+xml"),
      ]),
      html.link([
        attribute.rel("stylesheet"),
        attribute.href("/static/client.css"),
      ]),
      html.link([
        attribute.rel("preconnect"),
        attribute.href("https://fonts.googleapis.com"),
      ]),
      html.link([
        attribute.rel("preconnect"),
        attribute.href("https://fonts.gstatic.com"),
        attribute.crossorigin("anonymous"),
      ]),
      html.link([
        attribute.href(
          "https://fonts.googleapis.com/css2?family=Comic+Relief:wght@400;700&family=Josefin+Sans:ital,wght@0,100..700;1,100..700&display=swap",
        ),
        attribute.rel("stylesheet"),
      ]),
      html.script(
        [attribute.type_("module"), attribute.src("/static/client.js")],
        "",
      ),
    ]),
    html.body([], [html.div([attribute.id("app")], [])]),
  ])
  |> element.to_document_string
  |> wisp.html_response(200)
}

fn meta_og(name: String, content: String) -> Element(_) {
  html.meta([attribute.attribute("property", name), attribute.content(content)])
}
