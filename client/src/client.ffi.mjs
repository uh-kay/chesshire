/**
 *
 * @param {string} uri
 * @returns {WebSocket}
 */
export function create_websocket(uri) {
  return new WebSocket(uri);
}

/**
 *
 * @param {WebSocket} ws
 * @param {string} message
 * @returns {void}
 */
export function send_message(ws, message) {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(message);
  } else {
    ws.addEventListener("open", (_) => {
      ws.send(message);
    });
  }
}

/**
 *
 * @param {WebSocket} ws
 * @returns {Promise<string>}
 */
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

/**
 *
 * @param {number} delay
 * @param {TimerHandler} cb
 * @returns {void}
 */
export function set_timeout(delay, cb) {
  window.setTimeout(cb, delay);
}

/**
 *
 * @param {string} path
 * @returns {string}
 */
export function websocket_url(path) {
  const protocol = window.location.protocol == "https:" ? "wss:" : "ws:";
  return `${protocol}//${window.location.host}${path}`;
}

/**
 *
 * @param {Location} location
 * @returns {string}
 */
export function protocol(location) {
  return location.protocol;
}

/**
 *
 * @param {Element} element
 * @returns {DOMRect}
 */
export function getBoundingClientRect(element) {
  return element.getBoundingClientRect();
}

/**
 *
 * @param {Element} element
 * @param {number} pointerId
 * @returns {void}
 */
export function releasePointerCapture(element, pointerId) {
  if (element.hasPointerCapture?.(pointerId)) {
    element.releasePointerCapture(pointerId);
  }
}
