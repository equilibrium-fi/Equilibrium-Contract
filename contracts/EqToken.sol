// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Arrays} from "@openzeppelin/contracts/utils/Arrays.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface IEqToken {
    event Version(uint256 version);

    event ManagerCreateID(address indexed managerAddr, uint256 indexed eqTokenID);

    event Strategy(address indexed managerAddr, uint256 indexed eqTokenID, uint256[] percents, bytes32[] ctfIDs, uint256[] indexSets);

    event RoleChanged(address indexed newAddr, address indexed oldAddr, bytes32 indexed role);

    event URIChanged(string indexed newuri);

    function generateID(uint256[] calldata percents, bytes32[] calldata ctfIDs, uint256[] calldata indexSets, address managerAddr) external returns(uint256);

    function setURI(string memory newUri) external;

    function mint(address to, uint256 id, uint256 value, bytes memory data) external;

    function burn(address from, uint256 id, uint256 value) external;

    function proposeRole(bytes32 role, address newAddr) external;

    function acceptRole(bytes32 role, address callerConfirmation, address oldAdmin) external;

    function balanceOf(address account, uint256 id) external view returns (uint256);
}

contract EqToken is
    Initializable,
    ERC1155Upgradeable,
    AccessControlUpgradeable,
    IEqToken,
    UUPSUpgradeable
{
    using Arrays for uint256[];
    using Arrays for address[];

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    struct _balanceBook {
        mapping(address account => uint256) _balance;
        bool isSet;
        uint256 totalAmount;
    }

    struct EqTokenStorage {
        mapping(uint256 id => _balanceBook) _idBalances;
        mapping(address account => mapping(address operator => bool)) _operatorApprovals;
        string _uri;
    }

    // keccak256(abi.encode(uint256(keccak256("luna.storage.EqToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant EQTOKEN_STORAGE =
        0xf9afef903494cbdf7c9cbc8fb66d8098ad598ef1fbde3ad77e4b311e21632b00;

    function _getEqTokenStorage()
        private
        pure
        returns (EqTokenStorage storage $)
    {
        assembly {
            $.slot := EQTOKEN_STORAGE
        }
    }

    function __EqToken_init(
        string memory _uri,
        address minter,
        address burner,
        address admin
    ) public initializer {
        __ERC1155_init(_uri);
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, minter);
        _grantRole(BURNER_ROLE, burner);
    }

    modifier isExistent(uint256 id) {
        EqTokenStorage storage $ = _getEqTokenStorage();
        require($._idBalances[id].isSet, "this token is not existent");
        _;
    }

    function getVersion() external {
        emit Version(1);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(AccessControlUpgradeable, ERC1155Upgradeable)
        returns (bool)
    {
        return
            interfaceId == type(IEqToken).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {

    }

    //TODO
    function burn(
        address from,
        uint256 id,
        uint256 value
    ) external onlyRole(BURNER_ROLE) isExistent(id) {
        // TODO 如何设置在点击赎回之前我们没有权限销毁用户的eqToken
        _burn(from, id, value);
    }

    function mint(
        address to,
        uint256 id,
        uint256 value,
        bytes memory data
    ) external onlyRole(MINTER_ROLE) isExistent(id) {
        EqTokenStorage storage $ = _getEqTokenStorage();
        _mint(to, id, value, data);
        $._idBalances[id].totalAmount += value;
    }

    function proposeRole(
        bytes32 role,
        address newAdmin
        ) onlyRole(role) external {
        _grantRole(role, newAdmin);
    }

    function acceptRole(bytes32 role, 
        address callerConfirmation, 
        address oldRole
        ) onlyRole(role) external {
        require(callerConfirmation != oldRole, "this function can not be called by the old Admin");
        _revokeRole(role, oldRole);
        emit RoleChanged(callerConfirmation, oldRole, role);
    }

    function generateID(
        uint256[] calldata percents,
        bytes32[] calldata ctfIDs,
        uint256[] calldata indexSets,
        address managerAddr
    ) external onlyProxy returns(uint256) {
        EqTokenStorage storage $ = _getEqTokenStorage();
        uint256 eqId = uint256(
            keccak256(abi.encode(percents, ctfIDs, indexSets, managerAddr))
        );
        $._idBalances[eqId].isSet = true;
        emit ManagerCreateID(managerAddr, eqId);
        emit Strategy(managerAddr, eqId, percents, ctfIDs, indexSets);
        return eqId;
    }

    function setURI(
        string memory newuri
    ) external onlyRole(DEFAULT_ADMIN_ROLE) onlyProxy {
        _setURI(newuri);
        emit URIChanged(newuri);
    }

    function getUserAmount(uint256 tokenID, address userAddr) view external returns(uint256 , uint256) {
        EqTokenStorage storage $ = _getEqTokenStorage();
        return (
            $._idBalances[tokenID]._balance[userAddr],
            $._idBalances[tokenID].totalAmount
        );
    }

    // override functions
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override {
        EqTokenStorage storage $ = _getEqTokenStorage();
        if (ids.length != values.length) {
            revert ERC1155InvalidArrayLength(ids.length, values.length);
        }

        address operator = _msgSender();

        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 id = ids.unsafeMemoryAccess(i);
            uint256 value = values.unsafeMemoryAccess(i);

            if (from != address(0)) {
                uint256 fromBalance = $._idBalances[id]._balance[from];
                if (fromBalance < value) {
                    revert ERC1155InsufficientBalance(
                        from,
                        fromBalance,
                        value,
                        id
                    );
                }
                unchecked {
                    // Overflow not possible: value <= fromBalance
                    $._idBalances[id]._balance[from] = fromBalance - value;
                }
            }

            if (to != address(0)) {
                $._idBalances[id]._balance[to] += value;
            }
        }

        if (ids.length == 1) {
            uint256 id = ids.unsafeMemoryAccess(0);
            uint256 value = values.unsafeMemoryAccess(0);
            emit TransferSingle(operator, from, to, id, value);
        } else {
            emit TransferBatch(operator, from, to, ids, values);
        }
    }

    function isApprovedForAll(
        address account,
        address operator
    ) public view override onlyProxy returns (bool) {
        EqTokenStorage storage $ = _getEqTokenStorage();
        return $._operatorApprovals[account][operator];
    }

    function _setApprovalForAll(
        address owner,
        address operator,
        bool approved
    ) internal override {
        EqTokenStorage storage $ = _getEqTokenStorage();
        if (owner == address(0)) {
            revert ERC1155InvalidApprover(address(0));
        }
        if (operator == address(0)) {
            revert ERC1155InvalidOperator(address(0));
        }
        $._operatorApprovals[owner][operator] = approved;
        emit ApprovalForAll(owner, operator, approved);
    }

    function _setURI(string memory newuri) internal override {
        EqTokenStorage storage $ = _getEqTokenStorage();
        $._uri = newuri;
    }

    function uri(
        uint256 /* id */
    ) public view override onlyProxy returns (string memory) {
        EqTokenStorage storage $ = _getEqTokenStorage();
        return $._uri;
    }

    function balanceOf(
        address account,
        uint256 id
    ) public view override(ERC1155Upgradeable, IEqToken) onlyProxy returns (uint256) {
        EqTokenStorage storage $ = _getEqTokenStorage();
        return $._idBalances[id]._balance[account];
    }

}