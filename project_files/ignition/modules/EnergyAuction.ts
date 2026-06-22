import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// Chainlink ETH/USD feeds use 8 decimals. On a local Hardhat node there is no
// real feed, so we deploy a MockV3Aggregator and point the auction at it.
const DECIMALS = 8;
// Non-price bootstrap value: the mock constructor and initiate() need a non-zero
// answer to deploy, but it carries no meaning — the real price is written by the
// keeper from Kraken on the first cycle. Kept minimal on purpose.
const BOOTSTRAP_ANSWER = 1n * 10n ** 8n; // 1.0, just so the feed is non-zero
const INTERVAL = 300; // settlement cadence in seconds

export default buildModule("EnergyAuction", (m) => {
  const decimals = m.getParameter("decimals", DECIMALS);
  const initialAnswer = m.getParameter("initialAnswer", BOOTSTRAP_ANSWER);
  const interval = m.getParameter("interval", INTERVAL);

  const priceFeed = m.contract("MockPriceFeed", [decimals, initialAnswer]);
  const auction = m.contract("EnergyAuction", [priceFeed, interval]);

  // Prime the first cycle (starts the interval clock); the real price arrives
  // on the first keeper cycle from Kraken.
  m.call(auction, "initiate", []);

  return { priceFeed, auction };
});
