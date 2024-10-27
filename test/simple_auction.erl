-module(simple_auction).

-behaviour(gen_auction).

-export([start_link/2, start_link/3]).
-export([init/1, handle_bid/3, clear/3]).

start_link(Reserve, Increment) ->
    start_link(Reserve, Increment, []).

start_link(Reserve, Increment, Options) ->
    gen_auction:start_link(?MODULE, {Reserve, Increment}, Options).

init({Reserve, Increment}) ->
    {ok, {0, Increment, Reserve}}.

handle_bid({_BidId, BidAmount}, _Metadata, {Last, Increment, Reserve}) when
    BidAmount - Increment >= Last
->
    {accepted, {BidAmount, Increment, Reserve}};
handle_bid(_, _Metadata, State) ->
    {rejected, State}.

clear(_, _, {Last, _, Reserve} = State) when Last < Reserve ->
    {cleared, {[], [], Reserve}, State};
clear(Bids, _, {Last, _, _} = State) ->
    [Winner | _] = lists:reverse(lists:keysort(2, Bids)),
    {cleared, {[Winner], [], Last}, State}.
