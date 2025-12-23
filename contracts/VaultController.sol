// SPDX-License-Identifier: MIT
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
 * 6.gas优化
 */

/**
 * @title luna Vault Controller contract
 * @author @sjhana(github)
 * @notice 作为Vault的执行层
 * @dev Owner的作用为指定新的升级合约
 */

interface IVaultController {
    /**
     * @notice 当Vault的所有仓位赎回后触发
     * @param totalRedeemed 共赎回的Stake数量
     * @param newTotalStake 最新的Stake总量
     */
    event RedeemCTF(uint256 totalRedeemed, uint256 newTotalStake);

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
    function withdrawStake(address user) external;

    /**
     * @notice 返回Vault所对应的EqID
     */
    function getEqID() view external returns(uint);

    /**
     * @notice 返回Vault隶属的Gnosis Safe地址
     */
    function getAvartar() view external returns(address);
}

interface IGnosisSafe {
    function execTransactionFromModule(
        address to,
        uint256 value, 
        bytes memory data, 
        uint8 operation
    ) external returns(bool success);
}

interface IConditionalTokens {
    function redeemPositions(IERC20 collateralToken, bytes32 parentCollectionId, bytes32 conditionId, uint[] calldata indexSets) external;
}

abstract contract Enum {
    enum Operation {
        Call,
        DelegateCall
    }
}

contract VaultController is
    IVaultController,
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    Enum
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
        address avatar;
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
     * @param _eqTokenAddr EqToken 合约地址
     * @param _avatar Gnosis Safe 合约地址
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
        address _avatar,
        string calldata stakeName
    ) public initializer {
        __Ownable_init(initialOwner);
        VaultStorage storage $ = _getVaultStorage();
        require(_avatar!=address(0), "Invaild Gnosis Safe address");
        $.avatar = _avatar;
        $.managerAddr = _managerAddr;
        $.managerRating = _managerRating;
        $.ctfCore = _ctfCore;
        $.eqTokenAddr = _eqTokenAddr;
        $.stakeAddr = _stakeAddr;
        $.eqID = _eqID;
        $.ratingPrecision = _ratingPrecision;
        emit SupportStake(stakeName, _stakeAddr);
    }
    
    /**
     * @dev 内部辅助函数：让 Safe 执行交易
     */
    function _exec(address to, uint256 value, bytes memory data) internal {
        VaultStorage storage $ = _getVaultStorage();
        bool success = IGnosisSafe($.avatar).execTransactionFromModule(
            to,
            value,
            data,
            uint8(Operation.Call)
        );
        require(success, "Module execution failed");
    }

    function redeemCTF2Stake(
        bytes32[] calldata conditionIds,
        uint256[][] calldata indexSets
    ) external returns(bool) {
        VaultStorage storage $ = _getVaultStorage();

        for (uint i = 0; i < conditionIds.length; i++) {
            bytes memory data = abi.encodeWithSelector(
                IConditionalTokens.redeemPositions.selector,
                $.stakeAddr,
                bytes32(0),
                conditionIds[i],
                indexSets[i]
            );
            _exec($.ctfCore, 0, data);
        }
        $.totalStake = IERC20($.stakeAddr).balanceOf($.avatar);
        emit RedeemCTF($.totalStake, $.totalStake);
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
        bytes memory burnUserEqToken = abi.encodeWithSelector(
            IEqToken.controllerBurn.selector,
            user,
            $.eqID,
            userEqAmount
        );
        bytes memory userTransfer = abi.encodeWithSelector(
            IERC20.transfer.selector,
            user,
            value - managerValue
        );
        bytes memory managerTransfer = abi.encodeWithSelector(
            IERC20.transfer.selector,
            user,
            managerValue
        );
        _exec($.eqTokenAddr, 0, burnUserEqToken);
        _exec($.stakeAddr, 0, userTransfer);
        _exec($.stakeAddr, 0, managerTransfer);
        emit Withdraw(user, value - managerValue, managerValue);
    }

    function getEqID() view external returns(uint) {
        VaultStorage storage $ = _getVaultStorage();
        return $.eqID;
    }

    function getAvartar() view external returns(address) {
        VaultStorage storage $ = _getVaultStorage();
        return $.avatar;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
