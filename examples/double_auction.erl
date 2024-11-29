-module(double_auction).
-moduledoc """
This module implements a simple multi unit double auction. The
clearing mechanism requires that each bid be fully filled (i.e. no
winning bidder ever receives less than the volume they request). Asks
need not be completely filled. The assumption is that either the
market maker will pay out the unfilled part of the ask in order to
make the asker whole, or that askers will tolerate a partial order.

The `notify/6` callback simply prints the auction results.
""".

-behaviour(gen_auction).

-export([start_link/0]).
-export([init/1, handle_bid/3, handle_ask/3, clear/3, notify/6]).

-record(state, {period = 60_000 :: pos_integer()}).

start_link() ->
    gen_auction:start_link(?MODULE, [], [{duplicate, allow}]).

init(Options) ->
    Period = proplists:get_value(period, Options, 60_000),
    {ok, #state{period = Period}, [{timer, Period}]}.

handle_bid({_BidId, _Bid}, _Metadata, State) ->
    {accepted, State}.

handle_ask({_AskId, _Ask}, _Metadata, State) ->
    {accepted, State}.

clear(Bids, Asks, State) ->
    OrderedBids = lists:reverse(lists:keysort(2, Bids)),
    OrderedAsks = lists:keysort(2, Asks),
    {WinningBids, WinningAsks, Data} = do_clear(OrderedBids, OrderedAsks),
    {cleared, {WinningBids, WinningAsks, Data}, State, [{timer, State#state.period}]}.

notify(WinningBids, RejectedBids, WinningAsks, RejectedAsks,
       #{sell_price := SellPrice,
         buy_price := BuyPrice,
         volume := Volume,
         shortfall := Shortfall,
         shortfall_price := ShortfallPrice}, State) ->
    io:format(
      "sell-price:\t\t~p~n"
      "buy-price:\t\t~p~n"
      "volume:\t\t~p~n"
      "shortfall:\t\t~p~n"
      "shortfall-price:\t~p~n~n",
      [SellPrice, BuyPrice, Volume, Shortfall, ShortfallPrice]),
    io:format("Bids~n"),
    [io:format("~p\t~p~n", [BidPrice, BidVolume])
     || {_, {BidPrice, BidVolume}} <- WinningBids ++ RejectedBids],
    io:format("~nAsks~n"),
    [io:format("~p\t~p~n", [AskPrice, AskVolume])
     || {_, {AskPrice, AskVolume}} <- WinningAsks ++ RejectedAsks],
    {ok, State};
notify(_, _, _, _, _, State) ->
    io:format("failed to clear~n"),
    {ok, State}.

do_clear(Bids, Asks) ->
    case match_bids(Bids, Asks) of
        [] -> {[], [], #{}};
        Matched ->
            %% All matched bids are fully satisfied (i.e. the full
            %% volume is matched), but one ask may not be.
            MatchedAsks = lists:foldl(
                            fun ({AskId, Volume}, [{AskId, TotalVolume} | Acc]) ->
                                    [{AskId, Volume + TotalVolume} | Acc];
                                (Ask, Acc) ->
                                    [Ask | Acc]
                            end,
                            [],
                            lists:append([MatchAsks || {_, MatchAsks, _} <- Matched])),
            WinningBids = [Bid || Bid = {BidId, _} <- Bids, lists:keymember(BidId, 1, Matched)],
            WinningAsks = [Ask || Ask = {AskId, _} <- Asks, lists:keymember(AskId, 1, MatchedAsks)],
            SellPrice = lists:max([Price || {_, {Price, _}} <- WinningAsks]),
            BuyPrice = lists:min([Price || {_, {Price, _}} <- WinningBids]),
            {AskId, MatchedAskVolume} = hd(lists:reverse(MatchedAsks)),
            {AskId, {ShortfallPrice, Volume}} = lists:keyfind(AskId, 1, Asks),
            Shortfall = Volume - MatchedAskVolume,
            Data = #{sell_price => SellPrice,
                     buy_price => BuyPrice,
                     volume => lists:sum([Volume || {_, {_, Volume}} <- WinningBids]),
                     shortfall => Shortfall,
                     shortfall_price => ShortfallPrice,
                     matches => Matched,
                     bids => [Bid || {_, Bid} <- Bids],
                     asks => [Ask || {_, Ask} <- Asks]},
            {WinningBids, WinningAsks, Data}
    end.

match_bids(Bids, Asks) ->
    match_bids(Bids, Asks, []).

match_bids([{BidId, _} | _], [], [{BidId, _, _} | Acc]) ->
    %% if the last bid could not be fully satisfied, it is discarded.
    Acc;
match_bids(Bids, Asks, Acc) when length(Bids) =:= 0; length(Asks) =:= 0 ->
    Acc;
match_bids([{BidId, {BidPrice, _}} | _], [{_, {AskPrice, _}} | _], [{BidId, _, _} | Acc])
  when BidPrice =< AskPrice ->
    %% if the last bid could not be fully satisfied, it is discarded.
    Acc;
match_bids([{_, {BidPrice, _}} | _], [{_, {AskPrice, _}} | _], Acc)
  when BidPrice =< AskPrice ->
    Acc;
match_bids([{BidId, {BidPrice, BidVolume}} | RestBids],
           [{AskId, {AskPrice, AskVolume}} | RestAsks],
           [{BidId, Asks, TotalBidVolume} | Acc]) ->
    if BidVolume < AskVolume ->
            RemainingVolume = AskVolume - BidVolume,
            match_bids(
              RestBids,
              [{AskId, {AskPrice, RemainingVolume}} | RestAsks],
              [{BidId, [{AskId, BidVolume} | Asks], TotalBidVolume} | Acc]);
       BidVolume =:= AskVolume ->
            match_bids(
              RestBids,
              RestAsks,
              [{BidId, [{AskId, BidVolume} | Asks], TotalBidVolume} | Acc]);
       BidVolume > AskVolume ->
            RemainingVolume = BidVolume - AskVolume,
            match_bids(
              [{BidId, {BidPrice, RemainingVolume}} | RestBids],
              RestAsks,
              [{BidId, [{AskId, AskVolume} | Asks], TotalBidVolume} | Acc])
    end;
match_bids([{BidId, {BidPrice, BidVolume}} | RestBids],
           [{AskId, {AskPrice, AskVolume}} | RestAsks],
           Acc) ->
    if BidVolume < AskVolume ->
            RemainingVolume = AskVolume - BidVolume,
            match_bids(
              RestBids,
              [{AskId, {AskPrice, RemainingVolume}} | RestAsks],
              [{BidId, [{AskId, BidVolume}], BidVolume} | Acc]);
       BidVolume =:= AskVolume ->
            match_bids(RestBids, RestAsks, [{BidId, [AskId], BidVolume} | Acc]);
       BidVolume > AskVolume ->
            RemainingVolume = BidVolume - AskVolume,
            match_bids(
              [{BidId, {BidPrice, RemainingVolume}} | RestBids],
              RestAsks,
              [{BidId, [{AskId, AskVolume}], BidVolume} | Acc])
    end.
