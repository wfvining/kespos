-module(gen_auction).
-moduledoc """
A generic auction behavior.

## Automatic Clearing

Auctions may be configured to clear automatically either via options passed to
`start_link/4` or via actions returned from the callback functions. Timers for
timer-based clearing options passed to `start_link/4` are started immediately
after the `c:init/1` callback returns. The supported clearing modes are defined
in `t:clearing_mode/0`. The default mode is `manual` which means clearing only
happens in response to a `clear/1` call or when a callback returns the `clear`
action. `{bidcount, N}` or `{askcount, N}` mean the auction will be cleared
immediately after there are `N` accepted bids or asks respectively. Both of
these options may be specified in which case both conditions must be satisfied
before clearing is triggered.

There are also two timer-based clearing modes. The `{timer, T}` mode sets an
absolute timer for `T` milliseconds which triggers clearing when it expires. In
this mode the timer is only reset if a callback returns a new time via the
`{timer, TNew}` action which causes the old timer (if it exists) to be canceled
and a new timer to be started. The `{timeout, T}` mode starts a timer that is
reset after each accepted bid or ask, thus it expires when there have been no
new bids or asks for `T` milliseconds. As with `timer`, the `timeout` timer may
be reset or canceled by returning a `{timeout, TNew}` action. If `TNew` is
`infinity` the timer is canceled and a new one is not started.

By default when an auction is cleared, either manually or by an automatic
mechanism, all pending timers are canceled. This can be changed by using the
`{timer_mode, Mode}` and `{timeout_mode, Mode}` options when starting the
auction. The `Mode` parameter can be one of `cancel` (the default), `keep` (any
pending timers are left running), or `restart` (all pending timers are restarted
with their original duration).

""".

-behaviour(gen_server).

-export([start_link/3, start_link/4, stop/1]).
-export([bid/2, bid/3, ask/2, ask/3, clear/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, handle_continue/2]).

-export_type([
    auctionid/0,
    bidid/0,
    bid/0, bid/1,
    ask/0, ask/1,
    option/0,
    bidresponse/0,
    clearingmode/0,
    timermode/0
]).

-opaque bidid() :: reference().
-type bid(X) :: {bidid(), X}.
-type bid() :: bid(any()).
-type ask() :: ask(any()).
-type ask(X) :: bid(X).

-type auctionid() :: pid() | gen_server:server_name().
-type action() :: clear | clearingmode().
-type bidresponse() :: accepted | rejected | updated.
-type timermode() :: cancel | keep | restart.
-type option() ::
    {duplicate, mode()}
    | {timer_mode, timermode()}
    | {timeout_mode, timermode()}
    | {clearing, clearingmode()}.
-type clearingmode() ::
    {bidcount, pos_integer() | infinity}
    | {askcount, pos_integer() | infinity}
    | {timer, pos_integer() | infinity}
    | {timeout, pos_integer() | infinity}.
-type mode() :: reject | update | allow.

-doc "Initialize any state needed by the auction".
-callback init(Args :: any()) ->
    {ok, State :: any()}
    | {ok, State :: any(), ClearingModes :: [clearingmode()]}
    | {error, Reason :: any()}.

-doc """
Handle a new bid that has been submitted to the auction.

The return value indicates whether the bid is to be accepted or
rejected. Accepted does not mean that the bid is a winner, it just
means that the bid has been entered into the auction for
consideration. A rejected bid is discarded and has no bearing on the
auction. The return value `{updated, BidId}` can be used to replace an
existing bid with the bid just processed.

Along with accepting or rejecting the bid, the specific auction
implementation may use the `clear` action to force the auction to be
cleared. If this action is returned then the `c:clear/3` is called
immediately, before any pending messages are processed.
""".
-callback handle_bid(Bid :: bid(), BidMetadata :: any(), State :: any()) ->
    {BidAction, NewState :: any()}
    | {BidAction, NewState :: any(), [action()]}
when
    BidAction :: accpeted | rejected | {updated, bidid()}.

-doc """
Handle a new ask that has been submitted to the auction.

The return value is the same as for `c:handle_bid/2`.
""".
-callback handle_ask(Ask :: ask(), AskMetadata :: any(), State :: any()) ->
    {BidAction, NewState :: any()}
    | {BidAction, NewState :: any(), [action()]}
when
    BidAction :: accpeted | rejected | {updated, bidid()}.

-doc """
Determine winning bids.

The `Result` returned by this callbacks lists the winning bids (ans
asks). Instead of a list of winners, a tuple may be returned which
includes a list of winning bids/asks and a list of bids/asks that
should be retained. Bids and asks that are retained are included in
future calls to `c:clear/3`. Any bid or ask which is not listed as
retained is removed from the auction. The lists of winning and
retained bids/asks *may* overlap, allowing for a bid to win and be
retained for consideration in future rounds of the auction. Returning
only a list of winners is equivalent to returning `{Winners, []}`
indicating that no bids should be retained after the auction round is
complete.
""".
-callback clear(Bids :: [bid()], Asks :: [ask()], State :: any()) ->
    {cleared, Result, NewState}
    | {cleared, Result, NewState, [action()]}
    | {error, Reason :: any(), NewState}
when
    Result :: {BidResults, AskResults, ClearingData},
    BidResults :: [bid()] | {BidWinners :: [bid()], BidsRetained :: [bid()]},
    AskResults :: [ask()] | {AskWinners :: [ask()], AsksRetained :: [ask()]},
    ClearingData :: any(),
    NewState :: any().

-doc """
Handle a message that is not a bid, ask, or clear request.
""".
-callback handle_info(Info :: any(), State :: any()) ->
    {ok, NewState :: any()} | {ok, NewState :: any(), [action()]}.

-doc """
Notify bidders of the auction results.

This callback is invoked immediately following `c:clear/3`, before any
other messages are processed. The callback is optional, and if it is
not defined, the process which originally registered a bid will be
notified of its status via a message `{gen_auction, BidID :: bidid(),
Result :: bidresult(), ClearingData}` where `ClearingData` is the
extra data returned by the `c:clear/3` callback.
""".
-callback notify(WinningBids, RejectedBids, WinningAsks, RejectedAsks, ClearingData, State) ->
    {ok, NewState} | {error, Reason :: any()}
when
    WinningBids :: [{Bid, Metadata}],
    RejectedBids :: [{Bid, Metadata}],
    WinningAsks :: [{Ask, Metadata}],
    RejectedAsks :: [{Ask, Metadata}],
    ClearingData :: any(),
    Metadata :: any(),
    Bid :: bid(),
    Ask :: ask(),
    State :: any(),
    NewState :: any().

-optional_callbacks([handle_ask/3, handle_info/2, notify/6]).

-record(state, {
    module :: module(),
    auction_state :: any(),
    mode :: mode(),
    bids = #{} :: #{bidid() => {any(), any(), pid()}},
    bidders = #{} :: #{pid() => bidid()},
    asks = #{} :: #{bidid() => {any(), any(), pid()}},
    askers = #{} :: #{pid() => bidid()},
    timer :: undefined | {timer:tref(), reference()},
    timeout :: undefined | {timer:tref(), reference(), pos_integer()}
}).

-doc """
Start an auction.

`Module` is the callback module that implements the `gen_auction`
behavior. The argument `InitArg` will be passed to the `c:init/1`
callback.

The behavior of the generic auction can be customized using
`Options`. Currently the only option supported is `{duplicate, Mode}`
which determines how duplicate bids from the same process are
handled. If `Mode` is `reject` then all duplicate bids are rejected
without being passed to the callback module. In the `update` mode bids
are passed to the `c:handle_bid/3` callback and if they are accepted
then the previous bid from the calling process is replaced by the new
bid. Finally, `allow` means that duplicate bids are allowed; any bid
that is accepted by `c:handle_bid/3` is included in the auction,
regardless of the process that submitted the bid. The default is
`update`.
""".
-spec start_link(Module :: module(), InitArg :: any(), Options :: [option()]) ->
    gen_server:start_ret().
start_link(Module, InitArg, Options) ->
    gen_server:start_link(?MODULE, {Module, InitArg, Options}, []).

-doc """
Start a gen_auction process, registering it using `Name`.

For a description of the name parameter see
`gen_server:start_link/4`. All other parameters are the same as in
`start_link/3`.
""".
-spec start_link(
    Name :: gen_server:server_name(),
    Module :: module(),
    InitArg :: any(),
    Options :: [option()]
) -> gen_server:start_ret().
start_link(Name, Module, InitArg, Options) ->
    gen_server:start_link(Name, ?MODULE, {Module, InitArg, Options}, []).

-doc """
Trigger an auction clearing event.
""".
-spec clear(Auction :: auctionid()) -> ok.
clear(Auction) ->
    gen_server:cast(Auction, clear).

-doc #{equiv => bid(Auction, Bid, [])}.
-spec bid(Auction :: auctionid(), Bid :: any()) -> bidresponse().
bid(Auction, Bid) ->
    bid(Auction, Bid, []).

-doc """
Submit a bid to the auction.
""".
-spec bid(Auction :: auctionid(), Bid :: any(), Metadata :: any()) -> bidresponse().
bid(Auction, Bid, Metadata) ->
    Alias = alias([reply]),
    case gen_server:call(Auction, {bid, Bid, Metadata, self(), Alias}) of
        {updated, OldAlias} ->
            unalias(OldAlias),
            updated;
        rejected ->
            unalias(Alias),
            rejected;
        accepted ->
            accepted
    end.

-doc #{equiv => ask(Auction, Ask, [])}.
-spec ask(Auction :: auctionid(), Ask :: any()) -> bidresponse().
ask(Auction, Bid) ->
    ask(Auction, Bid, []).

-doc """
Submit an ask to the auction.
""".
-spec ask(Auction :: auctionid(), Ask :: any(), Metadata :: any()) -> bidresponse().
ask(Auction, Ask, Metadata) ->
    Alias = alias([reply]),
    case gen_server:call(Auction, {ask, Ask, Metadata, self(), Alias}) of
        {updated, OldAlias} ->
            unalias(OldAlias),
            updated;
        rejected ->
            unalias(Alias),
            rejected;
        accepted ->
            accepted
    end.

-doc """
Stop the auction process.
""".
-spec stop(Auction :: auctionid()) -> ok.
stop(Auction) ->
    gen_server:stop(Auction).

init({Module, InitArg, Options}) ->
    Mode = proplists:get_value(duplicate, Options, update),
    case Module:init(InitArg) of
        %% TODO handle actions returned by init
        {ok, State} ->
            {ok, #state{module = Module, auction_state = State, mode = Mode}};
        {ok, State, ClearingModes} ->
            State1 = #state{module = Module, auction_state = State, mode = Mode},
            {ok, set_clearing_mode(ClearingModes, State1)};
        {error, Reason} ->
            {stop, Reason}
    end.

handle_call({ask, Ask, Metadata, AskerPid, AskerAlias}, _From, State) ->
    case
        handle_bidask(
            State#state.mode,
            {State#state.module, handle_ask},
            AskerPid,
            {AskerAlias, Ask},
            Metadata,
            State#state.auction_state,
            State#state.askers,
            State#state.asks
        )
    of
        {Result, AuctionState, Askers, Asks} ->
            {reply, Result, State#state{askers = Askers, asks = Asks, auction_state = AuctionState},
                {continue, {after_bidask, ask, Result, []}}};
        {Result, AuctionState, Askers, Asks, Actions} ->
            {reply, Result, State#state{askers = Askers, asks = Asks, auction_state = AuctionState},
                {continue, {after_bidask, ask, Result, Actions}}}
    end;
handle_call({bid, Bid, Metadata, BidderPid, BidderAlias}, _From, State) ->
    case
        handle_bidask(
            State#state.mode,
            {State#state.module, handle_bid},
            BidderPid,
            {BidderAlias, Bid},
            Metadata,
            State#state.auction_state,
            State#state.bidders,
            State#state.bids
        )
    of
        {Result, AuctionState, Bidders, Bids} ->
            {reply, Result,
                State#state{
                    bidders = Bidders, bids = Bids, auction_state = AuctionState
                },
                {continue, {after_bidask, bid, Result, []}}};
        {Result, AuctionState, Bidders, Bids, Actions} ->
            {reply, Result,
                State#state{bidders = Bidders, bids = Bids, auction_state = AuctionState},
                {continue, {after_bidask, bid, Result, Actions}}}
    end.

handle_continue({after_bidask, BidAsk, Result, Actions}, State) ->
    NewState = do_actions(Actions, State),
    case Result of
        {updated, _} ->
            %% TODO check bid/ask counts
            {noreply, reset_timeout(NewState)};
        accepted ->
            %% TODO check bid/ask counts
            {noreply, reset_timeout(NewState)};
        rejected ->
            {noreply, NewState}
    end;
handle_continue({do_actions, Actions}, State) ->
    {noreply, do_actions(Actions, State)}.

handle_cast(clear, State) ->
    {noreply, State, {continue, {do_actions, [clear]}}}.

handle_info({'$clear', {timer, Ref}}, #state{timer = {_TRef, Ref}} = State) ->
    %% TODO restart timers???
    {noreply, State#state{timer = undefined}, {continue, {do_actions, [clear]}}};
handle_info({'$clear', {timer, _}}, State) ->
    %% Ref doesn't match so this is a message from a canceled timer. Ignore.
    {noreply, State};
handle_info({'$clear', {timeout, Ref}}, #state{timeout = {_TRef, Ref, _Time}} = State) ->
    %% TODO restart timers???
    {noreply, State#state{timeout = undefined}, {continue, {do_actions, [clear]}}};
handle_info({'$clear', {timeout, _}}, State) ->
    {noreply, State};
handle_info(Message, #state{auction_state = AuctionState, module = Module} = State) ->
    %% Let it crash if handle_info is not implemented
    case Module:handle_info(Message, AuctionState) of
        {ok, NewState} ->
            {noreply, State#state{auction_state = NewState}};
        {ok, NewState, Actions} ->
            {noreply, State#state{auction_state = NewState}, {continue, {do_actions, Actions}}}
    end.

do_actions(Actions, State) ->
    case lists:member(clear, Actions) of
        true ->
            {MoreActions, NewState} = do_clear(State),
            do_actions(lists:delete(clear, Actions) ++ MoreActions, NewState);
        false ->
            set_clearing_mode(Actions, State)
    end.

do_clear(#state{module = Module} = State) ->
    Bids = [{BidAlias, Bid} || {BidAlias, {Bid, _, _}} <- maps:to_list(State#state.bids)],
    Asks = [{AskAlias, Ask} || {AskAlias, {Ask, _, _}} <- maps:to_list(State#state.asks)],
    case Module:clear(Bids, Asks, State#state.auction_state) of
        {cleared, Result, AuctionState} ->
            NewState = notify_and_clear(Result, State#state{auction_state = AuctionState}),
            {[], NewState};
        {cleared, Result, AuctionState, Actions} ->
            NewState = notify_and_clear(Result, State#state{auction_state = AuctionState}),
            {Actions, NewState}
        %% TODO handle the {error, ...} return from clear/3
    end.

set_clearing_mode([], State) ->
    State;
set_clearing_mode([{timer, Time} | Rest], State) ->
    set_clearing_mode(Rest, set_timer(Time, State));
set_clearing_mode([{timeout, Time} | Rest], State) ->
    set_clearing_mode(Rest, set_timeout(Time, State));
set_clearing_mode([{bidcount, Count} | Rest], State) ->
    set_clearing_mode(Rest, State#state#{bidcount = Count});
set_clearing_mode([{askcount, Count} | Rest], State) ->
    set_clearing_mode(Rest, State#state{askcount = Count}).

reset_timeout(#state{timeout = {_TRef, _Ref, Time}} = State) ->
    set_timeout(Time, cancel_timeout(State));
reset_timeout(State) ->
    State.

set_timeout(infinity, State) ->
    cancel_timeout(State);
set_timeout(Time, State) ->
    State1 = cancel_timeout(State),
    Ref = erlang:make_ref(),
    {ok, TRef} = timer:send_after(Time, {'$clear', {timeout, Ref}}),
    State1#state{timeout = {TRef, Ref, Time}}.

set_timer(infinity, State) ->
    cancel_timer(State);
set_timer(Time, State) ->
    State1 = cancel_timer(State),
    Ref = erlang:make_ref(),
    {ok, TRef} = timer:send_after(Time, {'$clear', {timer, Ref}}),
    State1#state{timer = {TRef, Ref}}.

cancel_timeout(#state{timeout = {TRef, _Ref, _Time}} = State) ->
    timer:cancel(TRef),
    State#state{timeout = undefined};
cancel_timeout(State) ->
    State.

cancel_timer(#state{timer = {TRef, _Ref}} = State) ->
    timer:cancel(TRef),
    State#state{timer = undefined};
cancel_timer(#state{timer = undefined} = State) ->
    State.

notify_and_clear({WinningBids, WinningAsks, Data}, State) when is_list(WinningBids) ->
    notify_and_clear({{WinningBids, []}, WinningAsks, Data}, State);
notify_and_clear({WinningBids, WinningAsks, Data}, State) when is_list(WinningAsks) ->
    notify_and_clear({WinningBids, {WinningAsks, []}, Data}, State);
notify_and_clear(
    {{WinningBids, RetainedBids}, {WinningAsks, RetainedAsks}, Data},
    #state{module = Module} = State
) ->
    RejectedBids = bids(State) -- WinningBids -- RetainedBids,
    RejectedAsks = asks(State) -- WinningAsks -- RetainedAsks,
    NewState =
        case lists:member({notify, 6}, Module:module_info(exports)) of
            true ->
                {ok, AuctionState} = Module:notify(
                    WinningBids,
                    RejectedBids,
                    WinningAsks,
                    RejectedAsks,
                    Data,
                    State#state.auction_state
                ),
                State#state{auction_state = AuctionState};
            false ->
                notify_directly(WinningBids, RejectedBids, WinningAsks, RejectedAsks, Data, State)
        end,
    clear_bids(RetainedBids, RetainedAsks, NewState).

asks(#state{asks = Asks}) ->
    get_bids(Asks).

bids(#state{bids = Bids}) ->
    get_bids(Bids).

get_bids(Map) ->
    [{Alias, Bid} || {Alias, {Bid, _, _}} <- maps:to_list(Map)].

notify_directly(WinningBids, RejectedBids, WinningAsks, RejectedAsks, Data, State) ->
    Notify = fun(Winners, Losers) ->
        fun(Alias, {Bid, Metadata, _}) ->
            maybe
                true ?= (not lists:keymember(Bid, 2, Winners)) orelse winner,
                true ?= (not lists:keymember(Bid, 2, Losers)) orelse loser,
                ok
            else
                Outcome ->
                    Alias ! {gen_auction, self(), {Outcome, Bid, Metadata, Data}}
            end
        end
    end,
    maps:foreach(Notify(WinningBids, RejectedBids), State#state.bids),
    maps:foreach(Notify(WinningAsks, RejectedAsks), State#state.asks),
    State.

clear_bids(RetainedBids, RetainedAsks, State) ->
    BidAliases = [Alias || {Alias, _} <- RetainedBids],
    AskAliases = [Alias || {Alias, _} <- RetainedAsks],
    Bids = maps:with(BidAliases, State#state.bids),
    Asks = maps:with(AskAliases, State#state.asks),
    Bidders = maps:with(
        [element(3, maps:get(Alias, State#state.bids)) || Alias <- BidAliases],
        State#state.bidders
    ),
    Askers = maps:with(
        [element(3, maps:get(Alias, State#state.asks)) || Alias <- AskAliases],
        State#state.askers
    ),
    State#state{bids = Bids, asks = Asks, bidders = Bidders, askers = Askers}.

handle_bidask(
    Mode,
    {Module, Handler},
    Pid,
    {Alias, BidAskVal} = BidAsk,
    Metadata,
    AuctionState,
    Pids,
    BidAsks
) when
    not is_map_key(Pid, Pids);
    Mode =:= allow
->
    case Module:Handler(BidAsk, Metadata, AuctionState) of
        {accepted, NewAuctionState} ->
            {accepted, NewAuctionState, Pids#{Pid => Alias}, BidAsks#{
                Alias => {BidAskVal, Metadata, Pid}
            }};
        {accepted, NewAuctionState, Actions} ->
            {accepted, NewAuctionState, Pids#{Pid => Alias},
                BidAsks#{Alias => {BidAskVal, Metadata, Pid}}, Actions};
        {rejected, NewAuctionState} ->
            {rejected, NewAuctionState, Pids, BidAsks};
        {rejected, NewAuctionState, Actions} ->
            {rejected, NewAuctionState, Pids, BidAsks, Actions}
    end;
handle_bidask(
    update,
    {Module, Handler},
    Pid,
    {Alias, BidAskVal} = BidAsk,
    Metadata,
    AuctionState,
    Pids,
    BidAsks
) ->
    case Module:Handler(BidAsk, Metadata, AuctionState) of
        {accepted, NewAuctionState} when is_map_key(Pid, Pids) ->
            {OldAlias, Map} = maps:take(Pid, Pids),
            {{updated, OldAlias}, NewAuctionState, Pids#{Pid => Alias}, Map#{
                Alias => {BidAskVal, Metadata, Pid}
            }};
        {accepted, NewAuctionState, Actions} when is_map_key(Pid, Pids) ->
            {OldAlias, Map} = maps:take(Pid, Pids),
            {
                {updated, OldAlias},
                NewAuctionState,
                Pids#{Pid => Alias},
                Map#{Alias => {BidAskVal, Metadata, Pid}},
                Actions
            };
        {accepted, NewAuctionState} ->
            {accepted, NewAuctionState, Pids#{Pid => Alias}, BidAsks#{
                Alias => {BidAskVal, Metadata, Pid}
            }};
        {accepted, NewAuctionState, Actions} ->
            {accepted, NewAuctionState, Pids#{Pid => Alias},
                BidAsks#{Alias => {BidAskVal, Metadata, Pid}}, Actions};
        {rejected, NewAuctionState} ->
            {rejected, NewAuctionState, Pids, BidAsks};
        {rejected, NewAuctionState, Actions} ->
            {rejected, NewAuctionState, Pids, BidAsks, Actions}
    end;
handle_bidask(reject, _ModFun, _Pid, _BidAsk, _Metadata, AuctionState, Pids, BidAsks) ->
    {rejected, AuctionState, Pids, BidAsks}.
