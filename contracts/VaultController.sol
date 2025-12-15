// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IEqToken} from "./EqToken.sol";

interface IVaultController {
    event ApproveSuccess(address indexed user);

    event DepositUSDC(address indexed user, uint256 value);

    event Withdraw(address indexed user, uint256 value2User, uint256 value2Manage);

    function userApprove(address owner, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;

    function depositUSDC(address user, uint256 value) external;

    function redeemCTF2USDC(bytes32 conditionId, uint256[] calldata indexSets, uint256 amount) external;

    function withdrawUSDC(address user) external; //TODO

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
        address _managerAddr,
        uint256 _managerRating,
        address _usdcToken,
        address _ctfCore,
        address _eqTokenAddr,
        uint256 _eqID
    ) public initializer {
        __Ownable_init(initialOwner);
        VaultStorage storage $ = _getVaultStorage();
        $.managerAddr = _managerAddr;
        $.managerRating = _managerRating;
        $.ctfCore = _ctfCore;
        $.eqTokenAddr = _eqTokenAddr;
        $.usdcToken = _usdcToken;
        $.eqID = _eqID;
    }

    function userApprove(
        address owner,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        VaultStorage storage $ = _getVaultStorage();
        IERC20Permit($.usdcToken).permit(
            owner,
            address(this),
            value,
            deadline,
            v,
            r,
            s
        );
        emit ApproveSuccess(owner);
    }

    function depositUSDC(address user, uint256 value) external onlyOwner {
        VaultStorage storage $ = _getVaultStorage();
        IERC20($.usdcToken).transferFrom(user, address(this), value);
        IEqToken($.eqTokenAddr).mint(user, $.eqID, value, "");
        emit DepositUSDC(user, value);
    }

    function _getUserEqTokenNum(
        address userAddr
    ) external view returns (uint256) {
        VaultStorage storage $ = _getVaultStorage();
        return IEqToken($.eqTokenAddr).balanceOf(userAddr, $.eqID);
    }

    function redeemCTF2USDC(
        bytes32 conditionId,
        uint256[] calldata indexSets,
        uint256 amount
    ) external onlyOwner {
        // TODO
    }

    function withdrawUSDC(address user) 
    external onlyOwner {
        // TODO
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
