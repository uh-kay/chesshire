import envoy
import gleam/erlang/process
import gleam/int
import gleam/result
import mist
import server/context
import server/game_actor
import server/router
import wisp
import wisp_mist

pub fn main() -> Nil {
  wisp.configure_logger()

  let secret_key = envoy.get("SECRET_KEY") |> result.unwrap("")
  let assert Ok(started) = game_actor.start_registry()
  let ctx = context.Context(registry: started.data)
  let assert Ok(priv_directory) = wisp.priv_directory("server")
  let static_directory = priv_directory <> "/static"

  let port_str = result.unwrap(envoy.get("PORT"), "8000")
  let assert Ok(port) = int.parse(port_str)

  let assert Ok(_) =
    wisp_mist.handler(
      router.handle_request(_, static_directory, ctx),
      secret_key,
    )
    |> mist.new
    |> mist.port(port)
    |> mist.start

  process.sleep_forever()
}
