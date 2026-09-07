import gleam/javascript/promise.{type Promise}

pub type Websocket

@external(javascript, "../client.ffi.mjs", "create_websocket")
pub fn create(uri: String) -> Websocket

@external(javascript, "../client.ffi.mjs", "send_message")
pub fn send_message(websocket: Websocket, message: String) -> Nil

@external(javascript, "../client.ffi.mjs", "receive_message")
pub fn receive_message(websocket: Websocket) -> Promise(String)

@external(javascript, "../client.ffi.mjs", "websocket_url")
pub fn websocket_url(path: String) -> String
