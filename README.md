# Unithive – Fractional Real Estate Ownership Platform

Unithive is a **Clarity smart contract** for **tokenized real estate ownership**, enabling investors to purchase fractional property shares, participate in governance, and receive proportional income distributions. It transforms real estate into liquid, community-governed assets.

---

## Core Features

* **Property Tokenization**: Each property is registered with a fixed total supply of tokens and a set price per token.
* **Fractional Ownership**: Investors can purchase property tokens, representing partial ownership.
* **Revenue Distribution**: Rental income or profits can be deposited and distributed proportionally among token holders.
* **Governance**: Token holders can propose and vote on property-related decisions (upgrades, sales, etc.).
* **Transparent Tracking**: Full record of balances, claims, proposals, and revenue distribution on-chain.

---

## Key Components

### Data Structures

* **`property-registry`** – Stores property metadata (name, location, supply, token price, admin, status).
* **`token-balances`** – Tracks token ownership per holder.
* **`token-supply`** – Tracks total tokens issued for a property.
* **`revenue-pool`** – Manages deposited revenue and revenue-per-token metrics.
* **`claim-history`** – Records investor withdrawals to prevent double-claims.
* **`governance-registry`** – Stores governance proposals and their status.
* **`voting-records`** – Tracks individual voting activity and weight.

### ID Counters

* **`property-counter`** – Tracks number of registered properties.
* **`proposal-counter`** – Manages proposal IDs per property.

---

## Public Functions

### Property Management

* **`register-property`** – Admin registers a new property with supply and price.
* **`purchase-tokens`** – Allows investors to buy fractional tokens.
* **`get-property-info`** – Read-only, fetch property details.
* **`get-properties-count`** – Read-only, returns total registered properties.

### Revenue Distribution

* **`deposit-revenue`** – Property admin deposits rental income/profit.
* **`withdraw-revenue`** – Investors claim proportional share of accumulated revenue.
* **`calculate-claimable`** – Read-only, calculates pending revenue for an account.

### Governance

* **`submit-proposal`** – Token holders (≥5% ownership) can propose changes.
* **`cast-vote`** – Token holders vote weighted by balance.
* **`execute-proposal`** – Executes proposals if quorum (≥10%) and majority approval are met.
* **`get-proposal-info`** – Read-only, fetch proposal details.

### Token Ownership

* **`get-token-balance`** – Read-only, checks how many tokens a user holds.

---

## Workflow Example

1. **Admin registers a property** → Defines supply and token price.
2. **Investors purchase tokens** → Each purchase transfers STX and issues fractional tokens.
3. **Property admin deposits income** → Revenue pool is updated with proportional distribution.
4. **Investors withdraw revenue** → Claim STX proportional to token holdings.
5. **Governance proposals** → Token holders propose and vote on property decisions.
6. **Execution** → Proposals that pass quorum and voting thresholds are executed.

---

## Error Codes

* **u100** – Unauthorized (admin-only actions).
* **u101** – Property or proposal not found.
* **u102** – Invalid input.
* **u103** – Property inactive.
* **u104** – Insufficient balance or ownership.
* **u105** – No revenue available for withdrawal.
* **u106** – Voting has ended.
* **u107** – Voting still in progress.
* **u108** – Proposal failed (quorum not met or rejected).
* **u109** – Proposal already executed.

---

## Use Cases

* **Real Estate Crowdfunding** – Tokenize a property and allow multiple investors to own shares.
* **Rental Income Distribution** – Automate distribution of rental revenue.
* **Property Governance** – Investors democratically decide on property upgrades, sales, or rent adjustments.
* **Liquidity in Real Estate** – Make traditionally illiquid assets tradable via tokens.
