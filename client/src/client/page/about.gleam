import client/component
import icon
import lustre/attribute
import lustre/element
import lustre/element/html

pub fn view() -> String {
  [
    component.navbar(),
    html.main([attribute.class("max-w-2xl mx-auto bg-ctp-base flex")], [
      // html.h1([], [html.text("About")]),
      html.h2([attribute.class("text-2xl my-8")], [html.text("Our Team")]),
      html.div([attribute.class("flex gap-4")], [
        html.div([attribute.class("flex flex-col items-center")], [
          html.img([attribute.class("w-32 h-32 border rounded-full mb-2")]),
          html.p([], [html.text("uhkay")]),
          html.p([], [html.text("Software Engineer")]),
          html.div([attribute.class("flex gap-2")], [
            html.a(
              [
                attribute.class("flex gap-2 hover:text-blue-500"),
                attribute.href(
                  "https://discordapp.com/users/821003323515469865",
                ),
              ],
              [
                html.div([attribute.class("w-6")], [icon.discord()]),
              ],
            ),
            html.a([attribute.href("https://github.com/uh-kay")], [
              html.div([attribute.class("w-6")], [icon.github()]),
            ]),
          ]),
        ]),

        html.div([attribute.class("flex flex-col items-center")], [
          html.img([attribute.class("w-32 h-32 border rounded-full mb-2")]),
          html.p([], [html.text("Karyaprover")]),
          html.p([], [html.text("Designer")]),
          html.a(
            [
              attribute.class("flex gap-2 hover:text-blue-500"),
              attribute.href("https://discordapp.com/users/962622474061754400"),
            ],
            [html.div([attribute.class("w-6")], [icon.discord()])],
          ),
        ]),
      ]),
    ]),
  ]
  |> layout
}

fn layout(content: List(element.Element(a))) -> String {
  html.html([], [
    html.head([], [
      html.meta([
        attribute.name("viewport"),
        attribute.content("width=device-width, initial-scale=1"),
      ]),
      html.title([], "About Chesshire"),
      meta_og("title", "About Chesshire"),
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
    html.body([], content),
  ])
  |> element.to_document_string
}

fn meta_og(name: String, content: String) -> element.Element(a) {
  html.meta([attribute.attribute("property", name), attribute.content(content)])
}
