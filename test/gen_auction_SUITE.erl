-module(gen_auction_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

suite() ->
    [{timetrap, {seconds, 5}}].

init_per_group(Name, Config) ->
    {Bids, ExpectedStatus, ExpectedResult, ExpectedBid, ExpectedMax} = expected(Name),
    [{options, [{duplicate, Name}]},
     {bids, Bids},
     {expected, ExpectedStatus},
     {result, ExpectedResult},
     {bid, ExpectedBid},
     {max, ExpectedMax}
    |Config].

expected(reject) ->
    Bids = [1, 2, 3, 10, 11],
    Status = [rejected, accepted, rejected, rejected, rejected],
    Result = [loser],
    Bid = [2],
    Max = 2,
    {Bids, Status, Result, Bid, Max};
expected(allow) ->
    Bids = [1, 2, 3, 10, 11],
    Status = [rejected, accepted, rejected, accepted, rejected],
    Result = [loser, winner],
    Bid = [2, 10],
    Max = 10,
    {Bids, Status, Result, Bid, Max};
expected(update) ->
    Bids = [1, 2, 3, 10, 11],
    Status = [rejected, accepted, rejected, updated, rejected],
    Result = [winner],
    Bid = [10],
    Max = 10,
    {Bids, Status, Result, Bid, Max};
expected(_) ->
    {[], [], [], 0, []}.

end_per_group(_, Config) ->
    Config.

init_per_testcase(_Case, Config) ->
    case ?config(options, Config) of
        undefined ->
            Options = [];
        Options ->
            Options = Options
    end,
    Reserve = 9,
    {ok, Pid} = gen_auction:start_link(simple_auction, {Reserve, 2}, Options),
    [{auction, Pid}, {reserve, Reserve} | Config].

end_per_testcase(_Case, Config) ->
    gen_auction:stop(?config(auction, Config)).

all() ->
    [{group, reject},
     {group, allow},
     {group, update}].

groups() ->
    [{reject, [parallel], [duplicates, multi_proc]},
     {allow, [parallel], [duplicates, multi_proc]},
     {update, [parallel], [duplicates, multi_proc]}].

duplicates() ->
    [{doc, "handling of duplicate bids"}].
duplicates(Config) ->
    Auction = ?config(auction, Config),
    [?assertEqual(Expect, gen_auction:bid(Auction, X))
     || {Expect, X} <- lists:zip(?config(expected, Config), ?config(bids, Config))],
    gen_auction:clear(Auction),
    Max = max(?config(max, Config), ?config(reserve, Config)),
    ct:pal("Max = ~p", [Max]),
    [
     receive
         {gen_auction, Auction, {Result, Bid, [], Max}} -> ok;
         Any -> ct:fail("got unexpecte message ~p", [Any])
     after 500 ->
            ct:fail("timeout waiting for auction result")
     end
     || {Result, Bid} <- lists:zip(?config(result, Config), ?config(bid, Config))
    ],
    receive
        Any ->
             ct:fail("got unexpected message ~p", [Any])
    after 10 ->
            ok
    end.

multi_proc() ->
    [{doc, "Bids from multiple processes are handled"}].
multi_proc(Config) ->
    Auction = ?config(auction, Config),
    Self = self(),
    Pids = [spawn_link(fun() ->
                          timer:sleep(X * 10),
                          gen_auction:bid(Auction, X),
                          receive
                              {gen_auction, Auction, {loser, X, [], Max}} ->
                                  ?assert(X < Max),
                                  Self ! {self(), 0};
                              {gen_auction, Auction, {winner, X, [], Max}} ->
                                  ?assert(X =:= Max),
                                  Self ! {self(), 1}
                          end
                       end)
            || X <- lists:seq(2, 10, 2)],
    timer:sleep(200),
    rejected = gen_auction:bid(Auction, 8),
    gen_auction:clear(Auction),
    ?assertEqual(1, lists:sum([receive {Pid, N} -> N end || Pid <- Pids])),
    receive
        {gen_auction, Auction, Result} ->
            ct:fail("received result for rejected bid ~p", [Result]);
        Any ->
            ct:fail("received unexpected message ~p", [Any])
    after 10 ->
            ok
    end.
