# Kespos

A prototype application for playing with auction mechanisms for EV
charging reservations.

I'm not sure what the components are yet. Ultimately I would like to
explore both periodic and online auctions. I'm going to start with
periodic auctions though.

What does an auction application (or library?) look like? Probably the
first question should be whether or not to make this a pure
library. While that is kind of appealing, I think a supervision tree
maintaining some state could be useful. That said, I will try do
design it as if it were a normal library.

What I'm leaning towards is basically a generic `auction` behavior
that would make it easy to implement (and use) different auction
mechanisms without needing to worry about the common functionality
shared by all auctions. That raises the question of what are the
generic parts of an auction?

## Generic Auctions

The core functions of an auction is listed below.

* solicit bids
* accept bids
* determine winning bid(s)
* notify bidders of the outcome

For double-auctions the actions are slightly more complex. In addition
to soliciting and accepting bids, the auction must also solicit and
accept asks. This means that the act of soliciting bids is not totally
generic. I'm not sure what the right approach is. We need to enable
users to start an auction with a specific "lot" up and immediately
accepting bids, to start an auction without a specific "lot" and
accept both bids and asks simultaneously, or to start an auction
without a "lot" and accepting no bids until provided a lot and
instructed to begin accepting bids. I'm left with the following
specific API which covers roughly half the functionality listed above.

```erlang
-callback init(Arg) -> {ok, State} | {error, Reason}.
-callback handle_bid(Bid, State) -> {accept | reject, NewState}.
-callback handle_ask(Ask, State) -> {accept | reject, NewState}.
```

The last two bullet points less straightforward. For notifications
there are two options. Either the generic part handles the
notifications in a pre-determined (and non-flexible) way, or there is
some kind of `notify` callback. I like the former better because it
keeps the specialized auction module from needing to worry about
anything other than the core functionality (accept bids/asks, decide
winners).

Determining winners seems simple enough. All it requires is something
like the following.

```erlang
-opaque bidid() :: reference(). %% for example

-callback clear(Bids :: [{bidid(), any()}],
                Asks :: [{bidid(), any()}],
                State :: any()) ->
    {ok, Winners :: [{bidid(), Detail :: any()}], NewState :: any()} |
    {error, Reason :: any()}.
```

The hard part is to determine *when* `clear/3` should be
called. Because this will vary with the details of the specific
auction, it will need to be defined by the callback module in some
way. Before discussing how to do that, consider the different
"triggers" that we should support.

* **manual** - some process directly calls an API function from the
  generic auction module that triggers `clear/3`.
* **timer** - a timer triggers the callback a specified time after the
  auction was started.
* **timeout** - if no bids (or asks) are received within some
  specified interval of the last bid/ask, then the callback is
  triggered.
* **count** - the callback is triggered after some specific number of
  bids (and a specific number of asks) is received. Specific, in this
  case, does not mean pre-specified and unchangeable. An example
  of this is be an auction where bidders register their intention to
  bid before actually bidding.

There are a few ways to implement these options. The simplest is to
pass the auction "mode" as a parameter when starting the auction
(e.g. `gen_auction:start_link(..., [{mode, manual}])`). This is a good
option, but it makes changing the mode kind of ugly
(`gen_auction:setopts(Auction, [{mode, {timeout, 12345}}])`). The real
downfall, however, is in handling a count based trigger. I'm inclined
to punt on it though, because I think it will work out as something
that can be handled exclusively by the generic module. Finally, I want
the specific auction module to be able to trigger the
`choose_winners/3` callback via the return values of `handle_bid/2`
and `handle_ask/2`. So the new spec would look like this.

```erlang
-callback handle_bid(Bid, State) ->
    {AcceptReject, NewState} |
    {AcceptReject, NewState, [Action]}
  where AcceptReject :: accept | reject,
        Action :: clear.
```
