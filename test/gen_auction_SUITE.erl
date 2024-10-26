-module(gen_auction_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

suite() ->
    [{timetrap, {seconds, 5}}].

init_per_testcase(_Case, Config) ->
    {ok, Pid} = gen_auction:start_link(simple_auction, {9, 2}, []),
    [{auction, Pid} | Config].

end_per_testcase(_Case, Config) ->
    gen_auction:stop(?config(auction, Config)).

all() ->
    [submit_bid, multi_proc].

submit_bid(Config) ->
    Auction = ?config(auction, Config),
    rejected = gen_auction:bid(Auction, 1),
    accepted = gen_auction:bid(Auction, 2),
    rejected = gen_auction:bid(Auction, 3),
    updated = gen_auction:bid(Auction, 10),
    gen_auction:clear(?config(auction, Config)),
    receive
        {gen_auction, Auction, {winner, 10, [], 10}} ->
            ok;
        Any ->
            ct:fail("got unexpected message ~p", [Any])
    after 2000 ->
        ct:fail("timeout waiting for auction results")
    end.

multi_proc(Config) ->
    Auction = ?config(auction, Config),
    Self = self(),
    Pids = [spawn_link(fun() ->
                          timer:sleep(X * 10),
                          gen_auction:bid(Auction, X),
                          receive
                              {gen_auction, Auction, {loser, X, [], Max}} ->
                                  ?assert(X < Max),
                                  Self ! 0;
                              {gen_auction, Auction, {winner, X, [], Max}} ->
                                  ?assert(X =:= Max),
                                  Self ! 1
                          end
                       end)
            || X <- lists:seq(2, 10, 2)],
    timer:sleep(200),
    rejected = gen_auction:bid(Auction, 8),
    gen_auction:clear(Auction),
    ?assertEqual(1, lists:sum([receive N -> N end || _Pid <- Pids])),
    receive
        {gen_auction, Auction, Result} ->
            ct:fail("received unexpected auction result message ~p", [Result]);
        Any ->
            ct:fail("received unexpected message ~p", [Any])
    after 10 ->
            ok
    end.
