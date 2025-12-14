// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title VaultLogic
 * @dev 逻辑合约（Implementation），通过 delegatecall 被 Proxy 调用
 * 功能：
 * - 接收用户 USDC 存款
 * - 允许 Relayer（owner）执行 fillOrder 交易
 * - 接收/返还 CTF Outcome Tokens
 */
contract VaultLogic is Ownable, UUPSUpgradeable {
    // ====== 状态变量（Proxy 的 storage layout 必须与此一致） ======
    address public usdcToken;           // USDC 合约地址
    address public ctfCore;             // Conditional Tokens Framework 地址
    address public exchangeWrapper;     // Polymarket Exchange Wrapper

    // ====== 初始化 ======
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    //防止通过构造函数绕过初始化检查，增加安全性

    function initialize(
        address _usdc,
        address _ctfCore,
        address _exchangeWrapper,
        address _owner
    ) external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();

        require(_usdc != address(0), "USDC zero");
        require(_ctfCore != address(0), "CTF zero");
        require(_exchangeWrapper != address(0), "Exchange zero");

        usdcToken = _usdc;
        ctfCore = _ctfCore;
        exchangeWrapper = _exchangeWrapper;

        _transferOwnership(_owner); // Relayer 作为 owner
    }

    //用户存款 
    function depositUSDC(uint256 amount) external {
        require(amount > 0, "Amount zero");
        IERC20(usdcToken).transferFrom(msg.sender, address(this), amount);
    }

    //Relayer 执行交易 
    function executeFillOrder(
        bytes memory makerSignature,
        bytes memory takerSignature,
        uint256[] memory amounts
    ) external onlyOwner returns (bool success) {
        // 构造 fillOrder 调用数据
        bytes memory callData = abi.encodeWithSelector(
            bytes4(keccak256("fillOrder(bytes,bytes,uint256[])")),
            makerSignature,
            takerSignature,
            amounts
        );

        // 因为我们要从 Vault（this）划出资产，所以用普通 call
        (success, ) = exchangeWrapper.call(callData);
        require(success, "FillOrder failed");
    }

    // 提现 USDC 
    function withdrawUSDC(address to, uint256 amount) external onlyOwner {
        IERC20(usdcToken).transfer(to, amount);
    }

    // 不需要 withdrawCTF！CTF 必须留在 Vault 中

    // 事件结算后：用 CTF 换回 USDC
    function redeemCTFForUSDC(
    address conditionId,
    uint256[] calldata indexSets,
    uint256 amount
) external onlyOwner {
    require(conditionId != address(0), "Condition zero");
    require(amount > 0, "Amount zero");

    (bool success, ) = ctfCore.call(
        abi.encodeWithSelector(
            bytes4(keccak256("redeemPositions(address,bytes32,bytes32,uint256[],uint256)")),
            usdcToken,
            bytes32(0),
            bytes32(uint256(uint160(conditionId))),
            indexSets,
            amount
        )
    );
    require(success, "CTF redeem failed");
}

    //升级支持
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}
} 