-module(gen_auction_SUITE).

-compile(export_all).

-include_lib("stdlib/include/ms_transform.hrl").
-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

suite() ->
    [{timetrap, {seconds, 5000}}].

init_per_group(Name, Config) when Name =:= bid; Name =:= ask ->
    [{bidask, Name} | Config];
init_per_group(Name, Config) when
    Name =:= reject;
    Name =:= allow;
    Name =:= update
->
    {Bids, ExpectedStatus, ExpectedResult, ExpectedBid, ExpectedMax} = expected(Name),
    [
        {options, [{duplicate, Name}]},
        {bids, Bids},
        {expected, ExpectedStatus},
        {result, ExpectedResult},
        {bid, ExpectedBid},
        {max, ExpectedMax}
        | Config
    ];
init_per_group(clear_ask, Config) ->
    [{bidask, ask} | Config];
init_per_group(clear_bid, Config) ->
    [{bidask, bid} | Config];
init_per_group(Name, Config) when Name =:= accepted; Name =:= rejected ->
    [{expected, Name} | Config];
init_per_group(timer, Config) ->
    [{time, 500}, {init, {{timer, 500}, {9, 2}}} | Config];
init_per_group(timeout, Config) ->
    [
        {time, 500},
        {init, {{timeout, 500}, {9, 2}}},
        {options, [{duplicate, allow}]}
        | Config
    ];
init_per_group(_Name, Config) ->
    Config.

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
    Options =
        case ?config(options, Config) of
            undefined -> [];
            Opts -> Opts
        end,
    Reserve = 9,
    Init =
        case ?config(init, Config) of
            undefined -> {Reserve, 2};
            Init_ -> Init_
        end,
    {ok, Pid} = gen_auction:start_link(simple_auction, Init, Options),
    Start = erlang:monotonic_time(millisecond),
    [{auction, Pid}, {reserve, Reserve}, {start, Start} | Config].

end_per_testcase(_Case, Config) ->
    gen_auction:stop(?config(auction, Config)).

all() ->
    [{group, bid}, {group, ask}, {group, auto}].

groups() ->
    [
        {bid, [parallel], [{group, duplicate}, {group, action}]},
        {ask, [parallel], [{group, duplicate}, {group, action}]},
        {duplicate, [parallel], [{group, reject}, {group, allow}, {group, update}]},
        {reject, [parallel], [duplicates, multi_proc]},
        {allow, [parallel], [duplicates, multi_proc]},
        {update, [parallel], [duplicates, multi_proc]},
        {action, [parallel], [{group, accepted}, {group, rejected}]},
        {accepted, [parallel], [clear]},
        {rejected, [parallel], [clear]},

        {auto, [parallel], [{group, timer}, {group, timeout}]},
        {timer, [parallel], [clear_timer, cancel_timer, restart_timer]},
        {timeout, [parallel], [clear_timeout, cancel_timeout, restart_timeout]}
    ].

clear_timeout() ->
    [{doc, "returning `{timeout, Time}` action from `init/1` starts a clearing timeout"}].
clear_timeout(Config) ->
    Auction = ?config(auction, Config),
    Reserve = ?config(reserve, Config),
    Time = ?config(time, Config),
    timer:sleep((Time div 5) * 3),
    accepted = gen_auction:bid(Auction, Reserve + 1),
    timer:sleep((Time div 5) * 3),
    accepted = gen_auction:bid(Auction, Reserve + 3),
    Start = erlang:monotonic_time(millisecond),
    timer:sleep(Time div 5),
    rejected = gen_auction:bid(Auction, Reserve + 4),
    [
        receive
            {gen_auction, Auction, {Result, Bid, [], R}} when
                Bid =:= Reserve + N,
                R =:= Reserve + 3
            ->
                End = erlang:monotonic_time(millisecond),
                Delay = End - Start,
                ?assert(abs(Delay - Time) < Time * 0.01),
                if
                    N =:= 1 -> ?assertEqual(loser, Result);
                    N =:= 3 -> ?assertEqual(winner, Result)
                end
        after Time * 2 ->
            ct:fail("auction did not clear correctly")
        end
     || N <- [1, 3]
    ].

restart_timeout() ->
    [{doc, "timeout can be restarted after it is canceled"}].
restart_timeout(Config) ->
    Auction = ?config(auction, Config),
    Reserve = ?config(reserve, Config),
    Time = ?config(time, Config),
    accepted = gen_auction:bid(Auction, Reserve + 1),
    Auction ! cancel_timeout,
    receive
        Msg -> ct:fail("received unexected message: ~p", [Msg])
    after Time + 100 -> ok
    end,
    rejected = gen_auction:bid(Auction, {rejected, [{timer, Time}], Reserve + 10}),
    receive
        {gen_auction, Auction, {winner, Max, _, Max}} when Max =:= Reserve + 1 ->
            ok
    after Time + (Time div 2) ->
        ct:fail("auction did not clear")
    end.

cancel_timeout() ->
    [{doc, "clearing timeout is canceled by returning a `{timeout, infinigy}` action"}].
cancel_timeout(Config) ->
    Auction = ?config(auction, Config),
    Reserve = ?config(reserve, Config),
    Time = ?config(time, Config),
    gen_auction:bid(Auction, Reserve + 1),
    Auction ! cancel_timeout,
    receive
        Any ->
            ct:fail("Gor unexpected message: ~p", [Any])
    after Time + (Time div 2) ->
        ok
    end,
    gen_auction:clear(Auction),
    receive
        {gen_auction, Auction, {winner, _, _, _}} ->
            ok
    after 100 ->
        ct:fail("auction not cleared")
    end.

restart_timer() ->
    [{doc, "timer can be restarted after it is canceled"}].
restart_timer(Config) ->
    Auction = ?config(auction, Config),
    Reserve = ?config(reserve, Config),
    Time = ?config(time, Config),
    accepted = gen_auction:bid(Auction, Reserve + 1),
    Auction ! cancel_timer,
    receive
        Msg -> ct:fail("received unexected message: ~p", [Msg])
    after Time + 100 -> ok
    end,
    rejected = gen_auction:bid(Auction, {rejected, [{timer, Time}], Reserve + 10}),
    receive
        {gen_auction, Auction, {winner, Max, _, Max}} when Max =:= Reserve + 1 ->
            ok
    after Time + (Time div 2) ->
        ct:fail("auction did not clear")
    end.

cancel_timer() ->
    [{doc, "clearing timer is canceled by returning a `{timer, infinity}` action"}].
cancel_timer(Config) ->
    Auction = ?config(auction, Config),
    Reserve = ?config(reserve, Config),
    Time = ?config(time, Config),
    gen_auction:bid(Auction, Reserve + 1),
    %% use the handle_info callback in simple_auction to cancel the timer
    Auction ! cancel_timer,
    receive
        Any ->
            ct:fail("Got unexpected message: ~p", [Any])
    after Time + 100 ->
        ok
    end,
    gen_auction:clear(Auction),
    receive
        {gen_auction, Auction, {winner, _, _, _}} ->
            ok
    after 100 ->
        ct:fail("auction was not cleared")
    end.

clear_timer() ->
    [{doc, "returning `{timer, Time}` action from `init/1` starts a clearing timer"}].
clear_timer(Config) ->
    Auction = ?config(auction, Config),
    Reserve = ?config(reserve, Config),
    Time = ?config(time, Config),
    Start = ?config(start, Config),
    gen_auction:bid(Auction, Reserve + 1),
    receive
        {gen_auction, Auction, {winner, _, _, _}} ->
            End = erlang:monotonic_time(millisecond),
            Delay = End - Start,
            %% Check that we are within 1 percent of the expected time
            ?assert(abs(Delay - Time) < Time * 0.01)
    after Time + 100 ->
        ct:fail("no message received within ~p ms", Time)
    end.

clear() ->
    [{doc, "returning `clear` action from `handle_{bid,ask}/3` triggers clearing"}].
clear(Config) ->
    Auction = ?config(auction, Config),
    BidAsk = ?config(bidask, Config),
    ExpectedResponse = ?config(expected, Config),
    Reserve = ?config(reserve, Config),
    Increment = ?config(reserve, Config),
    BidAmount = (Reserve + Increment) * 2,
    {ExpectedOutcome, WinningBid, ExpectedMax} =
        if
            ExpectedResponse =:= accepted ->
                {winner, {ExpectedResponse, [clear], BidAmount}, BidAmount};
            ExpectedResponse =:= rejected ->
                gen_auction:BidAsk(Auction, Reserve - 1),
                {loser, Reserve - 1, Reserve}
        end,
    ExpectedResponse = gen_auction:BidAsk(Auction, {ExpectedResponse, [clear], BidAmount}),
    receive
        {gen_auction, Auction, {ExpectedOutcome, WinningBid, [], ExpectedMax}} ->
            ok;
        Any ->
            ct:fail(
                "got unexpected message: ~w expected: ~w",
                [Any, {gen_auction, Auction, {ExpectedOutcome, WinningBid, [], ExpectedMax}}]
            )
    after 200 ->
        ct:fail("timeout waiting for auction result")
    end.

duplicates() ->
    [{doc, "handling of duplicate bids"}].
duplicates(Config) ->
    BidAsk = ?config(bidask, Config),
    Auction = ?config(auction, Config),
    [
        ?assertEqual(Expect, gen_auction:BidAsk(Auction, X))
     || {Expect, X} <- lists:zip(?config(expected, Config), ?config(bids, Config))
    ],
    gen_auction:clear(Auction),
    AuctionResults = lists:zip(?config(result, Config), ?config(bid, Config)),
    Max = max(?config(max, Config), ?config(reserve, Config)),
    [
        receive
            {gen_auction, Auction, {Result, Bid, [], Max}} ->
                ok
        after 1000 ->
            ct:fail("timeout waiting for auction result")
        end
     || {Result, Bid} <- AuctionResults
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
    BidAsk = ?config(bidask, Config),
    Auction = ?config(auction, Config),
    Self = self(),
    Pids = [
        spawn_link(fun() ->
            timer:sleep(X * 10),
            gen_auction:BidAsk(Auction, X),
            receive
                {gen_auction, Auction, {loser, X, [], Max}} ->
                    ?assert(X < Max),
                    Self ! {self(), 0};
                {gen_auction, Auction, {winner, X, [], Max}} ->
                    ?assert(X =:= Max),
                    Self ! {self(), 1}
            end
        end)
     || X <- lists:seq(2, 10, 2)
    ],
    timer:sleep(200),
    rejected = gen_auction:BidAsk(Auction, 8),
    gen_auction:clear(Auction),
    ?assertEqual(
        1,
        lists:sum([
            receive
                {Pid, N} -> N
            end
         || Pid <- Pids
        ])
    ),
    receive
        {gen_auction, Auction, Result} ->
            ct:fail("received result for rejected bid ~p", [Result]);
        Any ->
            ct:fail("received unexpected message ~p", [Any])
    after 10 ->
        ok
    end.
