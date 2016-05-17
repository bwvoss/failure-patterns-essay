-module(worker).
-compile(export_all).

start() ->
  spawn(?MODULE, init, []).

start_link() ->
  register(?MODULE, Pid=spawn_link(?MODULE, init, [])),
  Pid.

init() ->
  receive
    health_check -> io:format("I'm alive!")
  end.
