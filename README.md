# EnergyDirectAuctions
Designing and implementing a Local Energy Market application using Blockchain technologies.

For more information see EnergyAuction_FINAL.pdf

## UPDATE: June 2026

The project has been migrated to Hardhat, since Truffle & Ganache are deprecated

The oracle has also been migrated off Provable/Oraclize to Chainlink: the ETH/USD
parity now comes from a Chainlink Data Feed (a `MockPriceFeed`/`MockV3Aggregator`
locally) and the recurring settlement is driven by Chainlink Automation
(`checkUpkeep`/`performUpkeep`) instead of the old timed Provable query.

### Running on a local node

All commands are run from `project_files/`.

1. **Start the local chain** (leave it running in its own terminal):

   ```bash
   npx hardhat node
   ```

2. **Compile and deploy** the mock ETH/USD feed + `EnergyAuction` via Ignition.
   The mock starts at a neutral non-price placeholder; the real ETH/USD value is
   pulled from Kraken by the keeper on the first cycle (step 3). The module calls
   `initiate()` to start the interval clock:

   ```bash
   npx hardhat ignition deploy ignition/modules/EnergyAuction.ts --network localhost
   ```

   The printed addresses (`EnergyAuction#MockPriceFeed`, `EnergyAuction#EnergyAuction`)
   are saved under `ignition/deployments/chain-31337/`. The deploy defaults can be
   overridden — see "Overriding deploy parameters" below.

3. **Drive the settlement cycles.** Chainlink Automation does not run against a
   local node, so `scripts/keeper.ts` plays the keeper (addresses are read from the
   Ignition deployment automatically).

   ```bash
   npx hardhat run scripts/keeper.ts --network localhost   # runs cycles continuously (Ctrl-C to stop)
   ```

   The keeper polls continuously and settles a cycle only once a full `interval`
   has really elapsed since the cycle started (it respects real time rather than
   fast-forwarding the chain). When a cycle is due it fetches the real price from
   `https://api.kraken.com/0/public/Ticker?pair=ETHUSD`, writes it into the mock
   feed via `updateAnswer()`, and calls `performUpkeep`. The contract still only
   reads a Chainlink feed; the keeper is just the off-chain source standing in for
   an oracle node locally. With `interval` at 300s expect a settlement roughly
   every 5 minutes — for faster local testing, deploy with a shorter interval via
   an Ignition parameters file (see "Overriding deploy parameters" below).

4. **Interact** with the auction from your usual web3 client (MetaMask / frontend)
   at `http://127.0.0.1:8545` using the deployed `EnergyAuction` address: members
   call `participating`, then `offering` / `buying`, and `showethPrice` /
   `weiconversion` read the cached Chainlink price.

To sanity-check the whole flow in-process (no separate node), run
`npx hardhat run scripts/verify-migration.ts`.

#### Overriding deploy parameters

`decimals`, `initialAnswer`, and `interval` are Ignition parameters. To change one
(e.g. a shorter interval for testing), pass a parameters file:

```bash
echo '{ "EnergyAuction": { "interval": 20 } }' > params.json
npx hardhat ignition deploy ignition/modules/EnergyAuction.ts --parameters params.json --network localhost
```

### Example: a 2-seller / 2-buyer auction

Run this against a node that already has a fresh deployment (steps 1–2 above).
Open a console:

```bash
npx hardhat console --network localhost
```

Then paste the following (one statement per line). Replace `ADDR` with the deployed
`EnergyAuction` address. Accounts `[1..4]` act as the four market members; `[0]` is
the deployer.

```js
// connect + per-member contract handles
const { viem, provider } = await network.connect()
const ADDR = "0x...EnergyAuction"
const w = await viem.getWalletClients()
const read    = await viem.getContractAt("EnergyAuction", ADDR)
const sellerA = await viem.getContractAt("EnergyAuction", ADDR, { client: { wallet: w[1] } })
const sellerB = await viem.getContractAt("EnergyAuction", ADDR, { client: { wallet: w[2] } })
const buyerA  = await viem.getContractAt("EnergyAuction", ADDR, { client: { wallet: w[3] } })
const buyerB  = await viem.getContractAt("EnergyAuction", ADDR, { client: { wallet: w[4] } })

// register 4 members. Every neighbor id must already be registered, so the first
// member joins with an empty neighbor list and the rest chain off it (1-2-3-4).
await sellerA.write.participating([1n, []])
await sellerB.write.participating([2n, [1n]])
await buyerA.write.participating([3n, [2n]])
await buyerB.write.participating([4n, [3n]])
await read.read.showmembers()

// sellers offer: (id, kWh available, $/kWh) — no ETH sent
await sellerA.write.offering([1n, 10n, "0.04"])
await sellerB.write.offering([2n, 10n, "0.05"])

// buyers bid: (id, kWh wanted, $/kWh) — must send value = kWh * weiconversion(price)
const pA = await read.read.weiconversion(["0.06"])
await buyerA.write.buying([3n, 8n, "0.06"], { value: pA * 8n })
const pB = await read.read.weiconversion(["0.05"])
await buyerB.write.buying([4n, 15n, "0.05"], { value: pB * 15n })

// settle: fast-forward past the interval, then run the upkeep (anyone may call it)
const interval = await read.read.interval()
await provider.request({ method: "evm_increaseTime", params: [Number(interval) + 1] })
await provider.request({ method: "evm_mine", params: [] })
await read.write.performUpkeep("0x")
```

Things to know:

- **First member needs an empty neighbor list**, and each later member must list only
  already-registered ids — otherwise `participating` reverts with *"…need to be
  connected to the network."* Ids must also be unique.
- **Buyers must send ETH**: `buying` is `payable` and requires
  `msg.value >= kWh * weiconversion(price)`. Sellers send nothing.
- **A trade happens only when a buyer's price ≥ a seller's price.** Settlement matches
  the highest bidders to the cheapest sellers and refunds buyers' unspent ETH.
- **`performUpkeep` performs the settlement** (running `transferring()` and emitting
  `EnergyTransfer` / `TransactionsCompleted`). In the console you fast-forward time to
  make it due; the keeper does the equivalent on its own.
- Unless a keeper cycle has pulled the real price, `ethPriceInCents` is the bootstrap
  **$1.00**, so e.g. `"0.04"` $/kWh = 0.04 ETH/kWh — fine for exercising the matching
  logic; the dollar amounts just scale with the ETH/USD rate in effect at order time.
