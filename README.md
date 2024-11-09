# ***[Kespos](https://www.cornishdictionary.org.uk/#kespos)*** — *balance, equilibrium*

A prototype application for playing with auction mechanisms. To start
`kespos` only supports periodic auctions; however, I would like to
build in support for online auctions weventually. That said, the
application supports a mechanism for triggering auction clearing that
would enable the implementation an online auction with only a small
amount of extra verbosity (see the `gen_auction:action()` type).

The `kespos` application is implemented as a library application,
without any supervision trees. At the core of the library is the
`gen_auction` behavior that attempts to abstract away the generic
functionality of an auction and supports a few callbacks that can be
used to implement any auction mechanism you wish.

## Generic Auctions

The core functions of an auction is listed below.

* accept bids (and asks)
* determine winning bid(s) (and ask(s))
* notify bidders of the outcome

This functionality is provided by the `gen_auction` API, and leverages
the `handle_bid/2`, `handle_ask/2`, `clear/3`, and `notify/6`
callbacks to provide the implementation specific behavior needed for
each of these capabilities. (The `notify/6` callback is optional and
when omitted `gen_auction` provides a simple notification mechanism
via Erlang messages.)

As alluded to, there is a mechanism for triggering auction clearing
via the `handle_bid/2` and `handle_ask/2` callbacks. Clearing can also
be triggered manually via `gen_auction:clear/1`. There are a number of
other methods for triggering clearing that are not yet implemented,
but may be added in the future.

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

The final significant capability that `gen_auction` tries to provide
is handling of duplicate bids. By default if a single process submits
two or more bids, the duplicate bid is treated as an update to the
previous bid from the same process. Alternative modes where duplicates
are allowed (without being considered updates) or are rejected
unconditionally are also supported.
