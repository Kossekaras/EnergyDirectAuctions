import { defineConfig } from "hardhat/config";
import hardhatIgnitionViemPlugin from "@nomicfoundation/hardhat-ignition-viem";

export default defineConfig({
  plugins: [hardhatIgnitionViemPlugin],
  solidity: {
    version: "0.8.35",
  },
  networks: {
    // The standalone node started with `npx hardhat node`.
    localhost: {
      type: "http",
      url: "http://127.0.0.1:8545",
    },
  },
});