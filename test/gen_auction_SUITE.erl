-module(gen_auction_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").

suite() ->
    [{timetrap, {seconds, 5}}].

init_per_testcase(_Case, Config) ->
    {ok, Pid} = gen_auction:start_link(simple_auction, {10, 2}, []),
    [{auction, Pid} | Config].

end_per_testcase(_Case, Config) ->
    gen_auction:stop(?config(auction, Config)).

all() ->
    [submit_bid].

submit_bid(Config) ->
    rejected = gen_auction:bid(?config(auction, Config), 1),
    accepted = gen_auction:bid(?config(auction, Config), 2),
    rejected = gen_auction:bid(?config(auction, Config), 3),
    updated = gen_auction:bid(?config(auction, Config), 5).
