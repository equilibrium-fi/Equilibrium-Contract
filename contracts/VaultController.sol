// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IEqToken} from "./EqToken.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * 5.做测试
 */

/**
 * @title luna Vault Controller contract
 * @author @sjhana(github)
 * @notice 作为Vault的执行层
 */

interface IVaultController {
    /**
     * @notice 当用户所拥有的stake被赎回时触发
     * @param user 用户地址
     * @param value2User 分发给用户的金额
     * @param value2Manager 分发给manager
     */
    event Withdraw(address indexed user, uint256 value2User, uint256 value2Manager);

    /**
     * @notice 当合约初始化时触发
     * @dev 只支持ERC20代币作为抵押品，如果是原生coin，请使用他们的wrapped版本
     * @param stakeName 支持的抵押品名称
     * @param stakeAddr 抵押品的合约地址
     */
    event SupportStake(string indexed stakeName, address stakeAddr);

    /**
     * @notice 赎回Vault中所有的Stake
     * @dev 只能由owner调用
     * @param conditionIds 需要被赎回的condition ids(是个bytes32的数组类型)
     * @param indexSets 需要被赎回的token的掩码
     */
    function redeemCTF2Stake(bytes32[] calldata conditionIds, uint256[][] calldata indexSets) external returns(bool);

    /**
     * @notice 赎回用户所拥有的stake
     * @dev 可以被任何人调用
     * @param user 被赎回的地址
     */
    function withdrawStake(address user) external; //TODO

}

interface IConditionalTokens {
    function redeemPositions(IERC20 collateralToken, bytes32 parentCollectionId, bytes32 conditionId, uint[] calldata indexSets) external;
}

contract VaultController is
    IVaultController,
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    struct VaultStorage {
        uint256 eqID;
        uint256 managerRating;
        uint256 ratingPrecision;
        uint256 totalStake;
        address managerAddr;
        address ctfCore;
        address eqTokenAddr;
        address stakeAddr;
    }

    // keccak256(abi.encode(uint256(keccak256("luna.storage.VaultController")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VAULT_STORAGE =
        0x708abef55fcad4f585e76d5caf7ef295fb3a1f94a39bab374db8ff1ae6b0c500;

    function _getVaultStorage() private pure returns (VaultStorage storage $) {
        assembly {
            $.slot := VAULT_STORAGE
        }
    }

    /**
     * @notice Vault初始化函数
     * @dev 每个Vault只能调用一次
     * @param initialOwner 初始化owner地址
     * @param _eqID 该Vault所管理的eqID
     * @param _managerRating manager能拿到的收益比例
     * @param _ratingPrecision Rating的精度值
     * @param _managerAddr 基金经理的地址
     * @param _ctfCore ConditionalTokens地址
     * @param _stakeAddr 质押品地址
     * @param _eqTokenAddr EqToken合约地址
     * @param stakeName 质押品名字
     */
    function __Vault_init(
        address initialOwner,
        uint256 _eqID,
        uint256 _managerRating,
        uint256 _ratingPrecision,
        address _managerAddr,
        address _ctfCore,
        address _stakeAddr,
        address _eqTokenAddr,
        string calldata stakeName
    ) public initializer {
        __Ownable_init(initialOwner);
        VaultStorage storage $ = _getVaultStorage();
        $.managerAddr = _managerAddr;
        $.managerRating = _managerRating;
        $.ctfCore = _ctfCore;
        $.eqTokenAddr = _eqTokenAddr;
        $.stakeAddr = _stakeAddr;
        $.eqID = _eqID;
        $.ratingPrecision = _ratingPrecision;
        emit SupportStake(stakeName, _stakeAddr);
    }

    function redeemCTF2Stake(
        bytes32[] calldata conditionIds,
        uint256[][] calldata indexSets
    ) external onlyOwner returns(bool) {
        VaultStorage storage $ = _getVaultStorage();
        for (uint i = 0; i < conditionIds.length; i++) {
            IConditionalTokens($.ctfCore).redeemPositions(IERC20($.stakeAddr), bytes32(0), conditionIds[i], indexSets[i]);
        }
        $.totalStake = IERC20($.stakeAddr).balanceOf(address(this));
        return true;
    }

    function withdrawStake(address user) 
    external {
        VaultStorage storage $ = _getVaultStorage();
        uint256 userEqAmount = IEqToken($.eqTokenAddr).balanceOf(user, $.eqID);
        require(userEqAmount!=0, "this function can only be called by someone who has eqToken!");
        uint256 totalEqAmount = IEqToken($.eqTokenAddr).getTotalAmount($.eqID);
        uint256 totalStakeAmount = $.totalStake;
        uint256 value = Math.mulDiv(userEqAmount, totalStakeAmount, totalEqAmount);
        uint256 managerValue = Math.mulDiv(value, $.managerRating, $.ratingPrecision);
        IEqToken($.eqTokenAddr).controllerBurn(user, $.eqID, userEqAmount);
        IERC20($.stakeAddr).transfer(user, value - managerValue);
        IERC20($.stakeAddr).transfer($.managerAddr, managerValue);
        emit Withdraw(user, value - managerValue, managerValue);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
