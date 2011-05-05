-module(rabbit_mochiweb_web).

-export([start/0, stop/0]).

%% ----------------------------------------------------------------------
%% HTTPish API
%% ----------------------------------------------------------------------

start() ->
    PortL = case application:get_env(port) of
        {ok, P} -> [{port, P}];
        _       -> [{port, 55672}]
    end,
    Options = case application:get_env(mochiweb_http_options) of
		  {ok, L} -> L ++ PortL;
		  _       -> PortL
	      end,
    Loop = fun loop/1,
    mochiweb_http:start([{name, ?MODULE}, {loop, Loop}] ++ Options).

stop() ->
    mochiweb_http:stop(?MODULE).

loop(Req) ->
    case rabbit_mochiweb_registry:lookup(Req) of
        no_handler ->
            Req:not_found();
        {lookup_failure, Reason} ->
            Req:respond({500, [], "Registry Error: " ++ Reason});
        {handler, Handler} ->
            Handler(Req)
    end.
