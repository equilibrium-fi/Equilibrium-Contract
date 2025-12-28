// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IEqToken} from "./EqToken.sol";
import {IVaultController} from "./VaultController.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/**
 * TODO
 * 4.将deposit函数更改为将cashAccount中的ctf代币转账至Vault中
 * 5.做测试 
 * 6.gas优化
 */

/**
 * @title luna Vault Relayer
 * @author @sjhana(github)
 * @notice 作为CashAccount和Vault中间的转发层
 */

interface IVaultRelayer {
    /**
     * @notice 当deposit被成功调用时触发
     * @param vaultAddr 转账到的地址
     * @param stakeName 质押品名称
     * @param value 转账金额
     */
    event DepositTo(address indexed vaultAddr, string stakeName, uint256 value);

    /**
     * @notice 当有新的Vault注册时触发
     * @param vaultAddr 新的Vault地址(可被筛选)
     */
    event NewVault(address indexed vaultAddr);

    /**
     * @notice 当支持新的质押品时触发
     * @param stakeName 质押品的名字(可被筛选)
     * @param stakeAddr 质押品的合约地址
     */
    event SupportedStake(string indexed stakeName, address stakeAddr);

    /**
     * @notice 将cashAccount中的ctf代币转账至Vault中
     * @dev 只能被默认管理员调用,EqToken的数量和用户质押品数量相等,包括精度
     * @param stakeName 质押品名字
     * @param from 用户地址
     * @param vaultAddr vault地址
     * @param value 质押品数量
     */
    function depositBatch2Vault(string calldata stakeName, address from, address vaultAddr, uint256 value) external returns(bool);

    /**
     * @notice 注册新的vault
     * @dev 只能被默认管理员调用,被注册的vault将获得EqToken合约的controller权限
     * @param vaultAddr 被注册的vault地址
     */
    function vaultSignUp(address vaultAddr) external returns(bool);

    /**
     * @notice 添加新受支持的质押品
     * @dev 只能被默认管理员调用
     * @param stakeName 质押品的名字
     * @param stakeAddr 质押品的合约地址
     */
    function addNewStake(string calldata stakeName, address stakeAddr) external returns(bool);
}

contract VaultRelayer is
    IVaultRelayer,
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    struct VaultRelayerStorage {
        mapping(address vaultAddr => bool) vaultAddrsBook;
        mapping(string stakeName => address stakeAddr) stakeAddrsBook;
        address eqTokenAddr;
    }

    // controller权限
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");

    // keccak256(abi.encode(uint256(keccak256("luna.storage.VaultRelayer")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VAULTRELAYER_STORAGE =
        0xc926ccb7e1d837a5ee89d9417779ffef20b476f6beed9db414d81c76af2f7700;

    function _getVaultRelayerStorage()
        private
        pure
        returns (VaultRelayerStorage storage $)
    {
        assembly {
            $.slot := VAULTRELAYER_STORAGE
        }
    }

    /**
     * @notice VaultRelayer的初始化函数，设置默认管理员
     * @param admin 默认管理员地址
     */
    function __VaultRelayer_init(address admin) external {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(AccessControlUpgradeable) returns (bool) {
        return
            interfaceId == type(IVaultRelayer).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function deposit(
        string calldata stakeName,
        address from,
        address vaultAddr,
        uint256 value
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns(bool) {
        VaultRelayerStorage storage $ = _getVaultRelayerStorage();
        require($.vaultAddrsBook[vaultAddr], "vault is invaild");
        IERC20($.stakeAddrsBook[stakeName]).transferFrom(from, vaultAddr, value);
        IEqToken($.eqTokenAddr).mint(from, IVaultController(vaultAddr).getEqID(), value, "");
        emit DepositTo(vaultAddr, stakeName, value);
        return true;
    }

    function vaultSignUp(address vaultAddr) external onlyRole(DEFAULT_ADMIN_ROLE) returns(bool) {
        VaultRelayerStorage storage $ = _getVaultRelayerStorage();
        $.vaultAddrsBook[vaultAddr] = true;
        IEqToken($.eqTokenAddr).proposeRole(CONTROLLER_ROLE, vaultAddr);
        emit NewVault(vaultAddr);
        return true;
    }

    function addNewStake(
        string calldata stakeName,
        address stakeAddr
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns(bool) {
        VaultRelayerStorage storage $ = _getVaultRelayerStorage();
        $.stakeAddrsBook[stakeName] = stakeAddr;
        emit SupportedStake(stakeName, stakeAddr);
        return true;
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}