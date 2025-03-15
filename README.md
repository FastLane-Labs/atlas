# Atlas

## Concept

Atlas is a permissionless and modular smart contract framework for Execution Abstraction. It provides applications and frontends with an auction system where Solvers compete to provide optimal solutions for user intents or MEV redistribution. A User Operation is collected by the app's frontend via the Atlas SDK and sent to an app-designated bundler, which combines it with Solver Operations into a single transaction.

## DApp Integration

A frontend or API wishing to integrate with Atlas must complete four steps:

1. Embed the Atlas SDK into their frontend or API to generate User Operations (userOps).
2. Choose an Operations Relay to facilitate communication between users and solvers.
3. Create and publish a DAppControl contract containing logic specific to the application.
4. Interact with the Atlas contract to initialize the DAppControl contract and link it to the Atlas SDK on their frontend or API.

## Network Overview

Atlas is infrastructure-agnostic, allowing each app to choose how User and Solver Operations are aggregated via its preferred Operations Relay. Examples include:

1. **BloXroute**: When Atlas launches, BloXroute's BDN will support the low-latency aggregation of User and Solver Operations.
2. **SUAVE**: Once live, operations can be sent to the SUAVE network, aggregated into a transaction by the SUAVE Atlas implementation, and then made available for use by bundlers.
3. **On-Chain**: If gas costs and throughput are not concerns, Solver Operations may be sent on-chain and aggregated by any party, including a smart contract.
4. **Cross-Chain**: Solver Operations may be posted and aggregated on another chain, with the output used to settle the Atlas transaction on the settlement chain.

## Auctioneer Overview

Each frontend may choose a party to act as the auctioneer. **It is strongly recommended that the auction beneficiary also act as the auctioneer**, as this is the most trust-minimized solution. Most frontends are expected to select the user as the auctioneer and handle auctioneer duties automatically through the Atlas SDK in the frontend/API. Since the user explicitly trusts the frontend/API, this simplifies the process.

The auctioneer is responsible for signing a **DAppOperation** that includes a **CallChainHash**, ensuring the bundler cannot tamper with the execution order of **SolverOperations**. This hash can be generated using the *getCallChainHash(SolverOperations[])* function. Infrastructure networks with programmable guarantees, such as SUAVE, may not require this step, as it can be handled trustlessly within the network.

### Auctioneer Example (Using BloXroute as the Operations Relay)

1. The user connects to a frontend and receives a session key.
2. The user signs their UserOperation, which is propagated over the BloXroute BDN to solvers.
3. The frontend receives SolverOperations via the BDN.
4. The frontend calls *getCallChainHash()* via the user’s wallet’s RPC.
5. The frontend uses the session key from step 1 to sign the **DAppOperation**, which includes the **CallChainHash**.
6. The frontend propagates the DAppOperation over the BDN to a designated bundler, assuming the user is not the bundler.

Any bundler that tampers with the order of SolverOperations will cause the transaction to revert, blocking any gas reimbursement from Atlas. User input is required only for step 2; all other steps occur in the background, ensuring a seamless user experience.

## Atlas Transaction Structure

### DAppControl

The **DAppControl** contract defines functions executed at specific stages during an Atlas transaction. It also contains app-specific settings, such as permitted bundler addresses and whether asynchronous processing of user nonces is allowed. These functions and settings allow the Atlas smart contract to create a trustless environment that integrates seamlessly with a DApp’s existing smart contracts—without requiring upgrades or redeployments.

The **DAppControl** contract can define which entities are permitted to act as the Bundler:

1. **DAppProxy** – A specific address (or addresses) is permitted to bundle operations.
2. **User** – The user can bundle operations.
3. **Builder** – The builder (*block.coinbase*) is permitted to bundle operations.
4. **Solver** – The top-bidding solver can bundle the User Operation with their Solver Operation but cannot include other solvers’ operations.
5. **Conditional** – A specific function determines complex bundler designation logic.
6. **Time Limit** – For on-chain auctions, any party may trigger execution once a specified minimum auction duration has passed.

The **DAppControl** contract must define the following functions:

1. **BidFormat** – Defines the base currency (or currencies) for the auction.
2. **BidValue** – Determines how bids are ranked for sorting by the auctioneer.
3. **AllocateValue** – Allocates any accrued value to the Execution Environment after a solver’s operation executes successfully.

Additionally, it may define functions that execute at various stages:

- **PreOps** – Runs before the user’s operation.
- **PreSolver** – Runs after the user’s operation but before a solver’s operation.
- **PostSolver** – Runs after the user’s operation and solver’s operation.
- **PostOps** – Runs after a solver’s operation and value allocation.

These functions execute via *delegatecall* within the Execution Environment.

### Ex-Post Bids

When bid amounts are known in advance, the `_bidKnownIteration()` function sorts bids by amount and executes them until one succeeds. When bid amounts are unknown (e.g., in blind on-chain solving), `_bidFindingIteration()` calculates bid amounts by calling `_executeSolverOperation()`, measuring the contract’s balance before and after execution.

### Permit69

Each user requires an Execution Environment (EE) instance for each DApp they interact with. Since EE addresses are known beforehand, they can be deployed during order execution, with solvers covering gas costs to avoid impacting UX. The EE initiates token transfers via *delegateCall* and uses **Permit69** to allow Atlas to transfer funds on the user’s behalf. **Permit69** also enables DApps to transfer accumulated tokens in their DAppControl contract.

### ExecutionBase

- `_availableFundsERC20()` – Checks user and DApp-approved balances available for withdrawal via Permit69.
- `_transferDAppERC20()` & `_transferUserERC20()` – Allow module developers to access funds.
- `_contribute()` – Allows actors to sponsor transaction gas by donating ETH to the Atlas escrow balance.
- `_borrow()` – Enables flash loans from the Atlas escrow balance, requiring repayment within the same Atlas transaction.

### Atlas Frontend / Infrastructure Flow

![AtlasFlow](./AtlasFlow.jpeg)

## Advantages

- Atlas Solvers have **exclusive first access** to value created by the User Operation before wallets, RPCs, relays, builders, validators, and sequencers.
- By acting as the auctioneer and beneficiary, Governance avoids the "trusted auctioneer" problem.
- MEV allocation is **modular and customizable**, allowing DApps to refund gas, support liquidity providers, or buy governance tokens for users.
- The **Execution Environment** provides extra protection against allowance-based exploits.
- Successful solvers pay full gas costs, though DApp Governance may subsidize costs based on execution results.
- By retaining MEV before RPCs or relays see the transaction, Atlas reduces the centralization risk of private order flow.

## Disadvantages

- Solvers **must pay for failed operations**, unlike early Ethereum transactions with "free reverts." This discourages spam but increases solver risk.
- Atlas **uses more block space** than traditional MEV systems due to additional trustless checks and verifications. However, the extra cost is only incurred when its benefit outweighs the cost.

## Notes

Auctioneers and Operations Relays may implement **reputation systems** for solver bids to optimize block space usage. While not required, responsible ecosystem members should avoid flooding block space with low-success, high-profit transactions.

## Development

Conflicting `foundry` formatter versions can cause CI/CD failures. Developers should lock their local `foundry` version to match the repository workflow:

```sh
foundryup -v nightly-0d8302880b79fa9c3c4aa52ab446583dece19a34
```

