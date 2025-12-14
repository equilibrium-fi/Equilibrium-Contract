// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IVaultController {

}

contract VaultController is IVaultController, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    struct VaultStorage {
        mapping(address => uint256) _USDCbook;
        uint256 manageRating;
        address manageAddr;
    }

    // keccak256(abi.encode(uint256(keccak256("luna.storage.VaultController")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VAULT_STORAGE =
        0x708abef55fcad4f585e76d5caf7ef295fb3a1f94a39bab374db8ff1ae6b0c500;

    function _getVaultStorage()
        private
        pure
        returns (VaultStorage storage $)
    {
        assembly {
            $.slot := VAULT_STORAGE
        }
    }

    function __Vault_init(address initialOwner) public initializer {
        __Ownable_init(initialOwner);
    }

    function depositUSDC() external {

    }

    function withdrawUSDC() external onlyOwner {

    }

    function getUserEqTokenNum(address userAddr) external view returns(uint256) {
        VaultStorage storage $ = _getVaultStorage();
        return $._USDCbook[userAddr];
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}