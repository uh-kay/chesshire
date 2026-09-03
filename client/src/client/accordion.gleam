import client/icon
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

// MODEL ----------------------------------------------------------------------

pub type Model {
  Model(items: List(Item), open: Int)
}

pub type Item {
  Item(id: Int, title: String, body: Element(Message))
}

pub type Message {
  UserClickedItem(id: Int)
}

pub fn init(items) {
  Model(items, open: -1)
}

// UPDATE ---------------------------------------------------------------------
pub fn update(model: Model, message: Message) {
  case message {
    UserClickedItem(id:) -> {
      case model.open == id {
        True -> Model(..model, open: -1)
        False -> Model(..model, open: id)
      }
    }
  }
}

// VIEW -----------------------------------------------------------------------
pub fn view(model: Model) {
  html.div(
    [attribute.class("mt-4 flex flex-col gap-4")],
    list.map(model.items, fn(item) { item_view(item, item.id == model.open) }),
  )
}

fn item_view(item: Item, is_open: Bool) {
  html.div([], [
    html.button(
      [
        attribute.class("px-4 rounded-md py-3 text-left border flex"),
        event.on_click(UserClickedItem(item.id)),
      ],
      [
        html.text(item.title),
        case is_open {
          True -> icon.chevron_down()
          False -> icon.chevron_right()
        },
      ],
    ),
    case is_open {
      True -> item.body
      False -> element.none()
    },
  ])
}
