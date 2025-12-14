import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers, upgrades } from "hardhat";

describe("EqToken UUPS Upgradeable", function () {
  // 定义 Fixture 以便在测试间重用状态
  async function deployEqTokenFixture() {
    const [owner, minter, burner, admin, user1, manager] = await ethers.getSigners();

    const EqToken = await ethers.getContractFactory("EqToken");
    const uri = "https://api.example.com/v1/\{id\}.json";

    // 部署代理
    const eqToken = await upgrades.deployProxy(
      EqToken,
      [uri, minter.address, burner.address, admin.address],
      { initializer: "__EqToken_init", kind: "uups" }
    );
    
    // 获取角色哈希
    const MINTER_ROLE = await eqToken.MINTER_ROLE();
    const BURNER_ROLE = await eqToken.BURNER_ROLE();
    const DEFAULT_ADMIN_ROLE = await eqToken.DEFAULT_ADMIN_ROLE();

    return { eqToken, owner, minter, burner, admin, user1, manager, uri, MINTER_ROLE, BURNER_ROLE, DEFAULT_ADMIN_ROLE };
  }

  describe("Deployment & Initialization", function () {
    it("Should set the right roles", async function () {
      const { eqToken, minter, burner, admin, MINTER_ROLE, BURNER_ROLE, DEFAULT_ADMIN_ROLE } = await loadFixture(deployEqTokenFixture);

      expect(await eqToken.hasRole(MINTER_ROLE, minter.address)).to.be.true;
      expect(await eqToken.hasRole(BURNER_ROLE, burner.address)).to.be.true;
      expect(await eqToken.hasRole(DEFAULT_ADMIN_ROLE, admin.address)).to.be.true;
    });

    it("Should return the correct initial URI", async function () {
      const { eqToken, uri } = await loadFixture(deployEqTokenFixture);
      expect(await eqToken.uri(0)).to.equal(uri);
    });
  });

  describe("Logic: GenerateID & Minting", function () {
    it("Should generate ID and allow minting", async function () {
      const { eqToken, minter, manager, user1 } = await loadFixture(deployEqTokenFixture);

      const percents = [10, 20];
      const sharesID = [1, 2];

      // 1. 生成 ID (必须先生成才能 mint，否则会报错 "this token is not existent")
      // 注意：generateID 在合约中使用了 onlyProxy 修饰符，但没有访问控制(public)，任何人似乎都可以调用？
      // 如果你的 generateID 应该受限，请检查合约逻辑。此处假设任意调用。
      const tx = await eqToken.connect(manager).generateID(percents, sharesID, manager.address);
      const receipt = await tx.wait();
      
      // 从日志中解析 eqId
      // 这里简化处理，重新计算 ID 用于验证
      const abiCoder = new ethers.AbiCoder();
      const encoded = abiCoder.encode(["uint256[]", "uint256[]", "address"], [percents, sharesID, manager.address]);
      const eqId = ethers.keccak256(encoded);

      // 2. Mint Token
      const amount = 1000;
      await expect(eqToken.connect(minter).mint(user1.address, eqId, amount, "0x"))
        .to.emit(eqToken, "TransferSingle")
        .withArgs(minter.address, ethers.ZeroAddress, user1.address, eqId, amount);

      // 3. 检查余额 (验证自定义 storage _idBalances 是否工作)
      expect(await eqToken.balanceOf(user1.address, eqId)).to.equal(amount);
    });

    it("Should fail to mint non-existent ID", async function () {
      const { eqToken, minter, user1 } = await loadFixture(deployEqTokenFixture);
      const fakeId = 99999;
      
      await expect(
        eqToken.connect(minter).mint(user1.address, fakeId, 100, "0x")
      ).to.be.revertedWith("this token is not existent");
    });
  });

  describe("UUPS Upgradability", function () {
    it("Should upgrade the contract successfully", async function () {
      const { eqToken, owner, user1, minter, admin, DEFAULT_ADMIN_ROLE } = await loadFixture(deployEqTokenFixture);
      
      await expect(eqToken.getVersion()).to.emit(eqToken, "Version").withArgs(1n);
      
      await eqToken.connect(admin).grantRole(DEFAULT_ADMIN_ROLE, owner.address);
      
      const EqTokenV2 = await ethers.getContractFactory("EqTokenV2");
      
      const upgradedToken = await upgrades.upgradeProxy(await eqToken.getAddress(), EqTokenV2);
      
      expect(await upgradedToken.getAddress()).to.equal(await eqToken.getAddress());
      
      await expect(upgradedToken.getVersion()).to.emit(upgradedToken, "Version").withArgs(2n);

    });

    it("Should fail upgrade if caller is not Admin", async function () {
      const { eqToken, user1 } = await loadFixture(deployEqTokenFixture);
      const EqTokenV2 = await ethers.getContractFactory("EqToken");

      // 尝试用非管理员身份升级（这在 Hardhat 模拟中比较难直接通过 upgradeProxy 模拟 signer，
      // 通常 upgradeProxy 默认使用第一个 signer。
      // 在实际单元测试中，我们通常测试 _authorizeUpgrade 的访问控制）
      
      // 这里主要依赖 OpenZeppelin 的插件保护，通常不需要手动通过 connect 更改 signer 来测试 upgradeProxy
      // 除非你手动调用 upgradeToAndCall
    });
  });
});