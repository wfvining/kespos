-module(gen_auction).
-moduledoc """
A generic auction behavior.
""".

-behaviour(gen_server).

-export([start_link/3, start_link/4, stop/1]).
-export([bid/2, bid/3, ask/2, ask/3, clear/1]).
-export([init/1, handle_call/3, handle_cast/2]).

-export_type([auctionid/0, bidid/0, bid/0, bid/1, ask/0, ask/1, option/0, bidresponse/0]).

-opaque bidid() :: reference().
-type bid(X) :: {bidid(), X}.
-type bid() :: bid(any()).
-type ask() :: ask(any()).
-type ask(X) :: bid(X).

-type auctionid() :: pid() | gen_server:server_name().
-type action() :: clear.
-type bidresponse() :: accepted | rejected | updated.
-type option() :: {duplicate, mode()}.
-type mode() :: reject | update | allow.

-doc "Initialize any state needed by the auction".
-callback init(Args :: any()) -> {ok, State :: any()} | {error, Reason :: any()}.

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

The elements from `Bids` and the elements from `Asks` that are winners
are returned. Any bid or ask that is not returned is considered a
looser.
""".
-callback clear(Bids :: [Bid], Asks :: [Ask], State :: any()) ->
    {ok, WinningBids, WinningAsks, ClearingData, NewState}
    | {error, Reason :: any(), NewState}
when
    Bid :: bid(),
    Ask :: ask(),
    WinningBids :: [Bid],
    WinningAsks :: [Ask],
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
    bidders = #{} :: #{pid() => bidid()}
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
    gen_server:call(Auction, {ask, Ask, Metadata, Alias}).

-doc """
Stop the auction process.
""".
-spec stop(Auction :: auctionid()) -> ok.
stop(Auction) ->
    gen_server:stop(Auction).

init({Module, InitArg, Options}) ->
    Mode = proplists:get_value(duplicate, Options, update),
    case Module:init(InitArg) of
        {ok, State} -> {ok, #state{module = Module, auction_state = State, mode = Mode}};
        {error, Reason} -> {stop, Reason}
    end.

handle_call(
    {bid, Bid, Metadata, BidderPid, BidderAlias},
    _From,
    #state{module = Module, auction_state = AuctionState} = State
) when
    not (is_map_key(BidderPid, State#state.bidders));
    State#state.mode =:= allow
->
    case Module:handle_bid({BidderAlias, Bid}, Metadata, AuctionState) of
        {accepted, NewAuctionState, [clear]} ->
            NewState = State#state{auction_state = NewAuctionState},
            {reply, accepted, store_bid(BidderPid, BidderAlias, Bid, Metadata, NewState),
                {continue, clear}};
        {accepted, NewAuctionState} ->
            NewState = State#state{auction_state = NewAuctionState},
            {reply, accepted, store_bid(BidderPid, BidderAlias, Bid, Metadata, NewState)};
        {rejected, NewAuctionState, [clear]} ->
            {reply, rejected, State#state{auction_state = NewAuctionState}, {continue, clear}};
        {rejected, NewAuctionState} ->
            {reply, rejected, State#state{auction_state = NewAuctionState}}
    end;
handle_call(
    {bid, Bid, Metadata, BidderPid, BidderAlias},
    _From,
    #state{module = Module, auction_state = AuctionState} = State
) when
    State#state.mode =:= update
->
    Alias = maps:get(BidderPid, State#state.bidders),
    case Module:handle_bid({BidderAlias, Bid}, Metadata, AuctionState) of
        {accepted, NewAuctionState, [clear]} ->
            NewState = State#state{auction_state = NewAuctionState},
            {reply, {updated, Alias}, store_bid(BidderPid, BidderAlias, Bid, Metadata, NewState),
                {continue, clear}};
        {accepted, NewAuctionState} ->
            NewState = State#state{auction_state = NewAuctionState},
            {reply, {updated, Alias}, store_bid(BidderPid, BidderAlias, Bid, Metadata, NewState)};
        {rejected, NewAuctionState, [clear]} ->
            {reply, rejected, State#state{auction_state = NewAuctionState}, {continue, clear}};
        {rejected, NewAuctionState} ->
            {reply, rejected, State#state{auction_state = NewAuctionState}}
    end;
handle_call(_, _From, State) ->
    %% Unconditionally reject duplicate bids.
    {reply, rejected, State}.

handle_cast(_Cast, State) ->
    %% TODO
    {noreply, State}.

store_bid(Bidder, BidderAlias, Bid, Metadata, #state{bids = Bids, bidders = Bidders} = State) ->
    NewBids = Bids#{BidderAlias => {Bid, Metadata, Bidder}},
    NewBidders = Bidders#{Bidder => BidderAlias},
    State#state{bids = NewBids, bidders = NewBidders}.
