export function create_websocket(uri) {
  return new WebSocket(uri);
}

export function send_message(ws, message) {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(message);
  } else {
    ws.addEventListener("open", (_) => {
      ws.send(message);
    });
  }
}

export function receive_message(ws) {
  return new Promise((resolve, reject) => {
    ws.addEventListener(
      "message",
      (event) => {
        if (typeof event.data === "string") {
          resolve(event.data);
        } else {
          reject(new Error("expected string, got binary"));
        }
      },
      { once: true },
    );
  });
}

export function monotonic_time() {
  return performance.now();
}

export function set_timeout(delay, cb) {
  window.setTimeout(cb, delay);
}

export function websocket_url(path) {
  const protocol = window.location.protocol == "https:" ? "wss:" : "ws:";
  return `${protocol}//${window.location.host}${path}`;
}
