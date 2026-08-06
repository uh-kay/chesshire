-module(server_ffi).

-export([monotonic_time/0]).

monotonic_time() ->
    StartTime = erlang:system_info(start_time),
    CurrentTime = erlang:monotonic_time(),
    Difference = CurrentTime - StartTime,
    erlang:convert_time_unit(Difference, native, millisecond).
