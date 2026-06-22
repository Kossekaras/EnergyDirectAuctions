// Self-contained sanity check for the Chainlink migration. Runs against an
// in-process Hardhat network (no external node needed):
//   npx hardhat run scripts/verify-migration.ts
//
// The price is sourced from Kraken (the only price source in this project); the
// mock feed is seeded and refreshed from it, never from a hand-picked value.
import { network } from "hardhat";

const DECIMALS = 8;
const INTERVAL = 900n;

// Last-trade ETH/USD from Kraken, scaled to Chainlink's 8-decimal int.
async function krakenAnswer(): Promise<bigint> {
  const res = await fetch("https://api.kraken.com/0/public/Ticker?pair=ETHUSD");
  if (!res.ok) throw new Error(`Kraken HTTP ${res.status}`);
  const json: any = await res.json();
  if (json.error?.length) throw new Error(`Kraken error: ${json.error.join(", ")}`);
  const price = Number(json.result?.XETHZUSD?.c?.[0]);
  if (!Number.isFinite(price) || price <= 0) throw new Error("Unexpected Kraken payload");
  return BigInt(Math.round(price * 1e8));
}

async function main() {
  const { viem, provider } = await network.connect();

  const feed = await viem.deployContract("MockPriceFeed", [DECIMALS, await krakenAnswer()]);
  const auction = await viem.deployContract("EnergyAuction", [feed.address, INTERVAL]);

  await auction.write.initiate();
  console.log("after initiate -> ethPrice:", await auction.read.showethPrice(),
              "| cents:", await auction.read.ethPriceCents());

  // Refresh from Kraken, then advance time past one interval and run upkeep.
  await feed.write.updateAnswer([await krakenAnswer()]);
  await provider.request({ method: "evm_increaseTime", params: [Number(INTERVAL) + 1] });
  await provider.request({ method: "evm_mine", params: [] });

  const [needed] = await auction.read.checkUpkeep(["0x"]);
  console.log("checkUpkeep needed:", needed);
  if (needed) await auction.write.performUpkeep(["0x"]);

  const cents = (await auction.read.ethPriceCents()) as bigint;
  console.log("after upkeep   -> ethPrice:", await auction.read.showethPrice(), "| cents:", cents);

  // weiconversion('1.00') is 1 USD worth of wei == 100 * (1e18 / cents).
  const got = (await auction.read.weiconversion(["1.00"])) as bigint;
  const expected = 100n * (10n ** 18n / cents);
  console.log(`weiconversion('1.00') = ${got} wei (expect ${expected})`);
  console.log(got === expected ? "OK" : "MISMATCH");
}

main().catch((e) => { console.error(e); process.exitCode = 1; });
