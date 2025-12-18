// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IEqToken} from "./EqToken.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface IVaultController {
    event Withdraw(address indexed user, uint256 value2User, uint256 value2Manage);

    function redeemCTF2USDC(bytes32 conditionId, uint256[] calldata indexSets) external;

    function getBalanceOfUSDC() external;

    function withdrawUSDC(address user) external; //TODO
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
        uint256 totalUSDC;
        address managerAddr;
        address ctfCore;
        address usdcToken;
        address eqTokenAddr;
    }

    // keccak256(abi.encode(uint256(keccak256("luna.storage.VaultController")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VAULT_STORAGE =
        0x708abef55fcad4f585e76d5caf7ef295fb3a1f94a39bab374db8ff1ae6b0c500;

    function _getVaultStorage() private pure returns (VaultStorage storage $) {
        assembly {
            $.slot := VAULT_STORAGE
        }
    }

    function __Vault_init(
        address initialOwner,
        uint256 _eqID,
        uint256 _managerRating,
        uint256 _ratingPrecision,
        address _managerAddr,
        address _ctfCore,
        address _usdcToken,
        address _eqTokenAddr
    ) public initializer {
        __Ownable_init(initialOwner);
        VaultStorage storage $ = _getVaultStorage();
        $.managerAddr = _managerAddr;
        $.managerRating = _managerRating;
        $.ctfCore = _ctfCore;
        $.eqTokenAddr = _eqTokenAddr;
        $.usdcToken = _usdcToken;
        $.eqID = _eqID;
        $.ratingPrecision = _ratingPrecision;
    }

    function _getUserEqTokenNum(
        address userAddr
    ) external view returns (uint256) {
        VaultStorage storage $ = _getVaultStorage();
        return IEqToken($.eqTokenAddr).balanceOf(userAddr, $.eqID);
    }

    function redeemCTF2USDC(
        bytes32 conditionId,
        uint256[] calldata indexSets
    ) external onlyOwner {
        VaultStorage storage $ = _getVaultStorage();
        IConditionalTokens($.ctfCore).redeemPositions(IERC20($.usdcToken), bytes32(0), conditionId, indexSets);
    }

    function getBalanceOfUSDC() external {
        VaultStorage storage $ = _getVaultStorage();
        $.totalUSDC = IERC20($.usdcToken).balanceOf(address(this));
    }

    function withdrawUSDC(address user) // TODO
    external onlyOwner {
        VaultStorage storage $ = _getVaultStorage();
        uint256 userEqAmount = IEqToken($.eqTokenAddr).balanceOf(user, $.eqID);
        uint256 totalEqAmount = IEqToken($.eqTokenAddr).getTotalAmount($.eqID);
        uint256 totalUSDCAmount = $.totalUSDC;
        uint256 value = Math.mulDiv(userEqAmount, totalUSDCAmount, totalEqAmount);
        uint256 managerValue = Math.mulDiv(value, $.managerRating, $.ratingPrecision);
        IERC20($.usdcToken).transfer(user, value - managerValue);
        IERC20($.usdcToken).transfer($.managerAddr, managerValue);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
