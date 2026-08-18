import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import wisp.{type Request, type Response}

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
