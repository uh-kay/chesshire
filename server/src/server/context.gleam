import gleam/erlang/process.{type Subject}
import server/game_actor

pub type Context {
  Context(registry: Subject(game_actor.RegistryMsg))
}
