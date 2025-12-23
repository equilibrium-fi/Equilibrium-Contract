import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "dotenv/config";

const RPC_URL = process.env.RPC_URL!;

const config: HardhatUserConfig = {
  solidity: "0.8.24",
  networks: {
    hardhat: {
      forking: {
        url: RPC_URL,
        blockNumber: 24066007
      }
    },
    localhost: {
      url: "http://127.0.0.1:8545",
    }
  }
};

export default config;
