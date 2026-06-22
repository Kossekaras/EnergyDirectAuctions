// Local "keeper" for the running Hardhat node. Chainlink Automation nodes don't
// run against a local chain, so this script plays their role: it polls the
// auction and calls performUpkeep once a real `interval` has actually elapsed
// since the current cycle started (the contract's lastTimeStamp). It does NOT
// fast-forward the chain clock — it respects real time, like a real keeper.
//
// It also acts as the off-chain price source: when a cycle is due it fetches the
// live ETH/USD price from Kraken (the same endpoint the old Provable code used)
// and writes it into the MockPriceFeed via updateAnswer() right before settling.
// The contract itself stays pure Chainlink — it only ever reads latestRoundData().
//
// It runs cycles continuously until you stop it (Ctrl-C):
//   npx hardhat run scripts/keeper.ts --network localhost
//
// Addresses are read from the Ignition deployment (chain-31337) or from the
// AUCTION_ADDRESS / FEED_ADDRESS env vars.
import { network } from "hardhat";
import { readFileSync, existsSync } from "node:fs";

type Hex = `0x${string}`;

function loadAddresses(): { auction: Hex; feed: Hex } {
  let auction = process.env.AUCTION_ADDRESS as Hex | undefined;
  let feed = process.env.FEED_ADDRESS as Hex | undefined;
  const file = new URL(
    "../ignition/deployments/chain-31337/deployed_addresses.json",
    import.meta.url,
  );
  if ((!auction || !feed) && existsSync(file)) {
    const j = JSON.parse(readFileSync(file, "utf8")) as Record<string, string>;
    auction = (auction ?? j["EnergyAuction#EnergyAuction"]) as Hex;
    feed = (feed ?? j["EnergyAuction#MockPriceFeed"]) as Hex;
  }
  if (!auction || !feed) {
    throw new Error(
      "Could not resolve addresses. Deploy with Ignition first, or set AUCTION_ADDRESS and FEED_ADDRESS.",
    );
  }
  return { auction, feed };
}

// Fetch the last-trade ETH/USD price from Kraken. Response shape:
//   { result: { XETHZUSD: { c: ["<lastTradePrice>", "<lotVolume>"] } } }
async function fetchKrakenEthUsd(): Promise<number> {
  const res = await fetch("https://api.kraken.com/0/public/Ticker?pair=ETHUSD");
  if (!res.ok) throw new Error(`Kraken HTTP ${res.status}`);
  const json: any = await res.json();
  if (json.error?.length) throw new Error(`Kraken error: ${json.error.join(", ")}`);
  const price = Number(json.result?.XETHZUSD?.c?.[0]);
  if (!Number.isFinite(price) || price <= 0) {
    throw new Error(`Unexpected Kraken payload: ${JSON.stringify(json.result)}`);
  }
  return price;
}

// Write the Kraken-sourced USD price into the mock feed (Chainlink 8-decimals).
async function pushPrice(viem: any, feedAddr: Hex, priceUsd: number) {
  const feedC = await viem.getContractAt("MockPriceFeed", feedAddr);
  const answer = BigInt(Math.round(priceUsd * 1e8));
  await feedC.write.updateAnswer([answer]);
  console.log(`Feed updated to $${priceUsd.toFixed(2)} (Kraken)`);
}

async function runCycle(viem: any, provider: any, auctionAddr: Hex, feedAddr: Hex) {
  // Advance the chain to the current real time (mine an empty block), then see
  // where the on-chain cycle stands — no time is fabricated.
  await provider.request({ method: "evm_mine", params: [] });
  const block = (await provider.request({
    method: "eth_getBlockByNumber",
    params: ["latest", false],
  })) as { timestamp: string };
  const now = BigInt(block.timestamp);

  const auction = await viem.getContractAt("EnergyAuction", auctionAddr);
  const interval = (await auction.read.interval()) as bigint;
  const lastTimeStamp = (await auction.read.lastTimeStamp()) as bigint;
  const elapsed = now > lastTimeStamp ? now - lastTimeStamp : 0n;

  // Respect the interval: do nothing until a full one has really elapsed.
  if (elapsed < interval) {
    console.log(
      `cycle started ${elapsed}s ago (interval ${interval}s) — ${interval - elapsed}s remaining, not due yet.`,
    );
    return;
  }

  // Due: refresh the price from Kraken right before settling, then settle.
  try {
    await pushPrice(viem, feedAddr, await fetchKrakenEthUsd());
  } catch (e) {
    console.warn(`Kraken fetch failed, keeping previous price: ${(e as Error).message}`);
  }

  const [needed] = (await auction.read.checkUpkeep(["0x"])) as [boolean, Hex];
  if (!needed) {
    console.log("checkUpkeep: not needed yet.");
    return;
  }
  const hash = await auction.write.performUpkeep(["0x"]);
  console.log(
    `cycle due after ${elapsed}s — performUpkeep tx ${hash} | price now ` +
      `${await auction.read.showethPrice()} USD (${await auction.read.ethPriceCents()} cents)`,
  );
}

async function main() {
  const { viem, provider } = await network.connect();
  const { auction, feed } = loadAddresses();
  console.log(`auction=${auction} feed=${feed}`);

  // Run cycles continuously: each iteration fetches the Kraken price, fast-forwards
  // the chain by one interval, and settles.
  while (true) {
    await runCycle(viem, provider, auction, feed);
    await new Promise((r) => setTimeout(r, 15_000));
  }
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
