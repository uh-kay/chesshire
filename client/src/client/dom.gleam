import gleam/dynamic

pub type Rect {
  Rect(
    x: Int,
    y: Int,
    width: Int,
    height: Int,
    top: Int,
    right: Int,
    bottom: Int,
    left: Int,
  )
}

@external(javascript, "../client.ffi.mjs", "getBoundingClientRect")
pub fn get_rect(element: dynamic.Dynamic) -> Rect

@external(javascript, "../client.ffi.mjs", "releasePointerCapture")
pub fn release_pointer_capture(element: dynamic.Dynamic, pointer_id: Int) -> Nil
