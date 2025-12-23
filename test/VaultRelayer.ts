import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { VaultRelayer } from "../typechain-types";

describe("VaultRelayer", function () {
    // 定义 Fixture 作为每个测试组的重用版本
    async function deployVaultRelayerFixture() {
        /**
         * @param admin 后端EOA管理钱包地址
         * @param user 用户EOA钱包地址
         */
        const [admin, user] = await ethers.getSigners();

        // 1.部署测试Token
        const MonkeyTypeTokenFactory = await ethers.getContractFactory("MonkeyType");
        const token = await MonkeyTypeTokenFactory.deploy("Test Token", "TST");
        await token.waitForDeployment();
        const tokenAddress = await token.getAddress();

        // 2.部署VaultRelayer
        const VaultRelayerFactory = await ethers.getContractFactory("VaultRelayer");
        const relayer = await upgrades.deployProxy(
            VaultRelayerFactory,
            [admin.address],
            {
                initializer: "__VaultRelayer_init",
                kind: "uups"
            }
        );
        await relayer.waitForDeployment();
        const relayerAddr = await relayer.getAddress();
        
        // 3.部署Vault
        const VaultFactory = 
        
        // 4.部署EqToken
        const EqTokenFactory = await ethers.getContractFactory("EqToken");
        
        // 使用 upgrades 插件部署代理
        const eqToken = await upgrades.deployProxy(
            EqTokenFactory,
            [
                "https://api.example.com/v1/\{id\}.json",
                
            ],
            {
                initializer: "__EqToken_init",
                kind: "uups"
            }
        )
    }

    // 测试添加新支持的Stake

    // 测试用户成功调用
})