import gleam/erlang/process.{type Subject}
import server/game

pub type Context {
  Context(registry: Subject(game.RegistryMsg))
}
