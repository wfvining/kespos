-module(gen_auction_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").

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
