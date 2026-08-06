export function createWebsocket(uri) {
  return new WebSocket(uri);
}

export function sendMessage(ws, message) {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(message);
  } else {
    ws.addEventListener("open", (_) => {
      ws.send(message);
    });
  }
}

export function receiveMessage(ws) {
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

export function createTimer(interval, msg, dispatch) {
  const id = setInterval(() => {
    dispatch(msg);
  }, interval);
  return id;
}

export function removeTimer(id) {
  clearInterval(id);
}

export function set_timeout(delay, cb) {
  window.setTimeout(cb, delay);
}
