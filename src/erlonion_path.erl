%% ===================================================================
%% erlonion_path.erl
%% Sunjay Bhatia 4/7/2015
%% ===================================================================

-module(erlonion_path).
-behaviour(gen_server).
-behaviour(ranch_protocol).

%% API
-export([start_link/4, register_node/1]).

%% Gen Server Callbacks
-export([init/1, init/4, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% Macros
-define(TIMEOUT, 5000).
-define(TAB, erlonion_ets).


%% ===================================================================
%% API Functions
%% ===================================================================

start_link(Ref, Sock, Transport, Opts) ->
    proc_lib:start_link(?MODULE, init, [Ref, Sock, Transport, Opts]).

register_node(Transport) ->
    {HostName, Port} = case erlonion_app:get_env_val(dir_addr, {error, none}) of
                           {error, none} -> {error, none}; % throw/print error and die
                           _DirAddr -> _DirAddr
                       end,
    {ok, {hostent, HName, _, _, _, _}} = inet:gethostbyname(HostName),
    case gen_tcp:connect(HName, Port, [binary, {active, once}, {nodelay, true}, {packet, raw}], 5000) of
        {ok, NewSock} ->
            Transport:send(NewSock, "");
        _ ->
            io:format("timed out or error connecting to directory node~n")
    end,
    ok.


%% ===================================================================
%% Gen Server Callbacks
%% ===================================================================

-record(state, {socket, transport}).

init([]) -> {ok, undefined}.

init(Ref, Sock, Transport, Opts) ->
    ok = proc_lib:init_ack({ok, self()}),
    ok = ranch:accept_ack(Ref),
    ok = Transport:setopts(Sock, [{active, once}]),
    io:format("opts: ~p~n", [Opts]),
    gen_server:enter_loop(?MODULE, [],
        #state{socket=Sock, transport=Transport},
        ?TIMEOUT).

handle_info({tcp, Sock, Data}, State=#state{socket=Sock, transport=Transport}) ->
    ok = Transport:setopts(Sock, [{active, once}]),
    {ok, MsgHandlerPid} = erlonion_sup:start_path_msghandler(),
    gen_server:cast(MsgHandlerPid, {tcp_msg, self(), Data, Transport}),
    {noreply, State, ?TIMEOUT};
handle_info({tcp_closed, _Sock}, State) ->
    {stop, normal, State};
handle_info({tcp_error, _, Reason}, State) ->
    {stop, Reason, State};
handle_info(timeout, State) ->
    {stop, normal, State};
handle_info(_Info, State) ->
    {stop, normal, State}.

handle_cast({http_response, Data}, State=#state{socket=Sock, transport=Transport}) ->
    % we have a valid HTTP response we can send back to the client
    Transport:send(Sock, Data),
    {noreply, State};
handle_cast(_Msg, State) ->
    io:format("erlonion_path handle_cast: ~p~n", [_Msg]),
    {noreply, State}.

handle_call(_Request, _From, State) -> {reply, ok, State}.

terminate(_Reason, _State) -> ok.

code_change(_OldVsn, State, _Extra) -> {ok, State}.
