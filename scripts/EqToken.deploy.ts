import { ethers, upgrades } from "hardhat";

async function main() {
  const [deployer, minter, burner, admin] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  const EqToken = await ethers.getContractFactory("EqToken");

  // 初始化参数
  const uri = "https://api.example.com/metadata/{id}.json";

  // 部署代理合约 (Proxy)
  //以此调用 __EqToken_init(uri, minter, burner, admin)
  const eqToken = await upgrades.deployProxy(
    EqToken, 
    [uri, minter.address, burner.address, admin.address], 
    { 
      initializer: '__EqToken_init', // 指定你的自定义初始化函数名
      kind: 'uups' 
    }
  );

  await eqToken.waitForDeployment();

  const proxyAddress = await eqToken.getAddress();
  console.log("EqToken Proxy deployed to:", proxyAddress);
  
  // 验证实现合约地址 (可选，用于Etherscan验证)
  const implementationAddress = await upgrades.erc1967.getImplementationAddress(proxyAddress);
  console.log("Implementation deployed to:", implementationAddress);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});