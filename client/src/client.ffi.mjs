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
