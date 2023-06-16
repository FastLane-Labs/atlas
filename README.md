ok, so hear me out... 

The contract looks like an absolute monster.  Why would anyone ever use this? Who is it meant for? 

*for loops in a mainnet contract?!*.  Heresy. 

This is a *rough* draft meant to illustrate a few key concepts.  It is absolutely not production ready and has dozens of security flaws and hundrews of missing lines of code. 

There are *clearly* some trusted party assumptions going on here.  This clearly wasn't meant for users or searchers to call like they would a regular contract.  Because it isn't a regular contract.

This the MEV game entirely, because it allows MEV collection at the protocol level in a way that is *uninteruptable* by builders, validators, or other searchers. 

How?  By using a meta tx / account abstraction model.  The breakthrough, though, is *who* is doing the bundling.

This isn't searchers acting as bundlers for users transactions.  This is users, assisted by an integrated frontend, acting as bundlers for *searchers'* transactions.

Then the user signs the whole thing, and it's all one giant transaction and there's not a damn thing a builder, searcher, or validator can do to get in between the user's MEV-generating tx and the searcher's tx because they're literally the same tx. 

But how can the user know to trust the searcher?  It's the same way the validators on Polygon know that they can trust the FastLane searchers there - by wrapping the searcher's entire meta transaction inside a system of checks and balances that will cause the searcher's entire tx to revert if they don't pay the user, protocol, or validator what they promised to pay. 

But these users aren't sophisticated enough to do this...

Not a problem.. we already know that they aren't sophisticated enough to put together the calldata and encryption for the transaction they're going to sign... that's the job of the protocol's centralized front end. What we're doing is giving the frontend - a centralized party for sure, but one that users *already* fully trust - a lot of extra data, composability, and functionality. 

Before the transaction is signed, before it hits the wallet, before it hits the RPC... it has to be *built*.  We are going to the very top of the food chain with a composable protocol designed to work with virtually any protocol that wants more control over what happens to the MEV they generate.  

Refund the user? we can do that.  
Offset impermanent loss? Easy. 
Claim liquidation profits? The front end will do it for you *automatically* and there's not a damn thing anyone else can do about it. 

The way it works is thus:

1. A protocol will enter into a partnership with FastLane Labs & our partners.
2. The protocol will integrate the FastLane Frontend API into their own front end.
3. When a user goes to the protocol's front end and begins making a transaction, their input data will be picked up by the FastLane Frontend API where it will be rapidly disseminated to searchers. 
4. How rapidly?  We plan to use the current FastLane auction duration of 250ms.  Searchers experienced with FastLane on Polygon are already used to this short time and already have experience integrating with our unique contracts and meta-tx style of MEV auctions. 
5.  At the end of the auction, the FastLane Frontend API will have collected searchers signed meta transactions.
6.  The frontend will then *build* the user's transaction and embed the searcher(s) meta transactions inside of it.
7.  The *user* will then sign it and just drop it in the mempool or whatever, doesn't really matter. 
8.  The smart contract will then set up the user's transaction and log a few things.
9. It'll then execute the user's transaction.
10. It'll then start executing searchers' transactions, with the highest-paying transaction being executed first.  
11.  The searcher is required to have gas payments escrowed on the FastLaneProtoCall (im sorry) Contract - the user will be reimbursed for gas spent by searchers.  
12. If the searcher's transaction doesn't generate the profit that it said it would and deposit it on the FastLaneProtoCall Contract, we revert the searcher's whole transaction and execute the next one. Reverted searcher txs don't get their gas money back - the user is refunded either way.
13. Once the profit is collected, the FastLaneProtoCall Contract will then distribute it out to the beneficiaries *as decided by the protocol*. 
14. It then runs some more safety checks - as determined by the protocol - and calls it a day.  