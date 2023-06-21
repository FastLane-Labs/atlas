This is a *rough* draft meant to illustrate a few key concepts.  It is absolutely not production ready and has dozens of security flaws and hundrews of missing lines of code. 

Apologies for the lack of readability - functionality/coverage comes first, then simplification. This might not be readable until July.

Gas optimization will come last and reader / getter funcs will come last.

The way the backend / frontend of this protocol works is thus:

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

Note that there is significant complexity in the lock system.  This was designed to handle
ALL cases, rather than having to deploy multiple contracts to handle SOME cases, so as to
avoid the fragmentation (capital inefficiency and upkeep effort) of the searcher's escrowed gas values.  Other factory contracts may be launched with less complexity - such as one that has no delegatecall and therefore no need to create a new contract each time - but the Escrow contract must be designed to handle the *most* complex of those designs or searchers' gas values will be fragmented.

Note that the backend will probably need to use a reputation system for searcher bids that aren't in the top three in order to not take up too much space in the block.  The further down the the searcherCalls[], the higher the
reputation requirement for inclusion by the backend. This isnt necessarily required - it's not an economic issue. It's more-so about just being a good member of the ecosystem and not wasting too much precious blockspace. With probabalistic searcher txs that have low success rate but high return-to-cost rate. 