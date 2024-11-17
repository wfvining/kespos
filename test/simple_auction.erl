%% @doc A "simple" auction for testing the gen_auction module. At a
%% basic level it implements an auction with a reserve price and a
%% minimum bid increment.
%%
%% It gets less simple, however, due to an attempt at maximum
%% laziness. The auction will accept bids OR asks (but will choke in
%% `clear/3` if you give it both) which enables testing the
%% `gen_auction` code that handles both types independently of each
%% other. This leaves the combination of both bids and asks to be
%% tested by some other means.
-module(simple_auction).

-behaviour(gen_auction).

-export([start_link/2, start_link/3]).
-export([init/1, handle_bid/3, handle_ask/3, clear/3]).

start_link(Reserve, Increment) ->
    start_link(Reserve, Increment, []).

start_link(Reserve, Increment, Options) ->
    gen_auction:start_link(?MODULE, {Reserve, Increment}, Options).

init({Reserve, Increment}) ->
    {ok, {0, Increment, Reserve}}.

handle_bid({_BidId, {accepted, Actions, BidAmount}}, _Metadata, {_Last, Increment, Reserve}) ->
    {accepted, {BidAmount, Increment, Reserve}, Actions};
handle_bid({_BidId, {rejected, Actions, _BidAmount}}, _Metadata, {Last, Increment, Reserve}) ->
    {rejected, {Last, Increment, Reserve}, Actions};
handle_bid({_BidId, BidAmount}, _Metadata, {Last, Increment, Reserve}) when
    BidAmount - Increment >= Last
->
    {accepted, {BidAmount, Increment, Reserve}};
handle_bid(_, _Metadata, State) ->
    {rejected, State}.

handle_ask(Ask, Metadata, State) ->
    handle_bid(Ask, Metadata, State).

clear(Bids, [], State) ->
    {Winners, Data} = do_clear(Bids, State),
    {cleared, {Winners, [], Data}, State};
clear([], Asks, State) ->
    {Winners, Data} = do_clear(Asks, State),
    {cleared, {[], Winners, Data}, State}.

do_clear(_, {Last, _, Reserve}) when Last < Reserve ->
    {[], Reserve};
do_clear(Bids, {Last, _, _}) ->
    [Winner | _] = lists:reverse(lists:keysort(2, Bids)),
    {[Winner], Last}.
