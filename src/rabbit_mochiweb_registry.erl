-module(rabbit_mochiweb_registry).

-behaviour(gen_server).

-record(state, {selectors, fallback}).

-export([start_link/0]).
-export([add/3, set_fallback/1, lookup/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

add(Selector, Handler, Link) ->
    gen_server:call(?MODULE, {add, Selector, Handler, Link}).

set_fallback(FallbackHandler) ->
    gen_server:call(?MODULE, {set_fallback, FallbackHandler}).

lookup(Req) ->
    gen_server:call(?MODULE, {lookup, Req}).

%% Callback Methods

init([]) ->
    {ok, #state{selectors = [], fallback = fun listing_fallback_handler/1}}.

handle_call({add, Selector, Handler, Link}, _From,
            State = #state{selectors = Selectors}) ->
    UpdatedState =
        State#state{selectors = Selectors ++ [{Selector, Handler, Link}]},
    {reply, ok, UpdatedState};
handle_call({set_fallback, FallbackHandler}, _From,
            State) ->
    {reply, ok, State#state{fallback = FallbackHandler}};
handle_call({lookup, Req}, _From,
            State = #state{ selectors = Selectors, fallback = FallbackHandler }) ->

    case catch match_request(Selectors, Req) of
        {'EXIT', Reason} ->
            {reply, {lookup_failure, Reason}, State};
        no_handler ->
            {reply, {handler, FallbackHandler}, State};
        Handler ->
            {reply, {handler, Handler}, State}
    end;

handle_call(list, _From, State = #state{ selectors = Selectors }) ->
    {reply, [Link || {_S, _H, Link} <- Selectors], State};

handle_call(Req, _From, State) ->
    error_logger:format("Unexpected call to ~p: ~p~n", [?MODULE, Req]),
    {reply, unknown_request, State}.

handle_cast(_, State) ->
	{noreply, State}.

handle_info(_, State) ->
	{noreply, State}.

terminate(_, _) ->
	ok.

code_change(_, State, _) ->
	{ok, State}.

%%---------------------------------------------------------------------------

%% Internal Methods

match_request([], _) ->
    no_handler;
match_request([{Selector, Handler, _Link}|Rest], Req) ->
    case Selector(Req) of
        true  -> Handler;
        false -> match_request(Rest, Req)
    end.

%%---------------------------------------------------------------------------

listing_fallback_handler(Req) ->
    HTMLPrefix =
        "<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"en\">"
        "<head><title>RabbitMQ Web Server</title></head>"
        "<body><h1>RabbitMQ Web Server</h1><p>Contexts available:</p><ul>",
    HTMLSuffix = "</ul></body></html>",
    {ReqPath, _, _} = mochiweb_util:urlsplit_path(Req:get(raw_path)),
    Contexts = gen_server:call(?MODULE, list),
    List =
        case Contexts of
            [] ->
                "<li>No contexts installed</li>";
            _ ->
                [handler_listing(Path, ReqPath, Desc)
                 || {Path, Desc} <- Contexts]
        end,
    Req:respond({200, [], HTMLPrefix ++ List ++ HTMLSuffix}).

handler_listing(Path, ReqPath, Desc) ->
    io_lib:format("<li><a href=\"~s\">~s</a></li>", [
        rabbit_mochiweb_util:relativise(ReqPath, "/" ++ Path),
        case Desc of
            none -> Path;
            _    -> Desc
        end
    ]).
