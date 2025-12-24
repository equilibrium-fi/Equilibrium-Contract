// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Arrays} from "@openzeppelin/contracts/utils/Arrays.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * TODO
 * 1.做测试
 * 2.gas优化
 * 3.考虑预留二元EqToken，可以参考ConditionalToken的设计架构，预留一个indexSets
 */

/**
 * @title luna EqToken Contract
 * @author @sjhana(github)
 * @notice 用于管理Narrative对应的eqToken合约
 */

interface IEqToken {
    /**
     * @notice 获取当前合约版本号
     * @param version 版本号
     */
    event Version(uint256 version);

    /**
     * @notice 当eqToken id生成时触发
     * @param managerAddr 创建Narrative的经理地址
     * @param eqTokenID 被创建的Narrative所对应的eqToken id
     */
    event ManagerCreateID(address indexed managerAddr, uint256 indexed eqTokenID);

    /**
     * @notice 当eqToken id生成时触发,显示Narrative的具体策略
     * @param managerAddr 创建Narrative的经理地址
     * @param eqTokenID 被创建的Narrative所对应的eqToken id
     * @param percents 每种ctf Token占总数量的比例(默认精度为2)
     * @param conditionalIds 每种ctf Token所对应的conditional ids
     * @param indexSets 每种ctf Token的掩码值(决定最终结果是哪个，如果是二元预测，则1代表no，2代表yes)
     */
    event Strategy(address indexed managerAddr, uint256 indexed eqTokenID, uint256[] percents, bytes32[] conditionalIds, uint256[] indexSets);

    /**
     * @notice 当有新地址被赋予职责时触发
     * @param newAddr 被赋予新职责的地址
     * @param role 被赋予的职责
     */
    event RoleChanged(address indexed newAddr, bytes32 indexed role);

    /**
     * @notice 当有地址被撤销职责时触发
     * @param revokedAddr 被撤销职责的地址
     * @param role 被撤销的职责
     */
    event RevokeRole(address indexed revokedAddr, bytes32 indexed role);

    /**
     * @notice 当更新了eqToken id所对应的链下数据的uri时触发
     * @param newuri 所指向的新的uri
     */
    event URIChanged(string indexed newuri);

    /**
     * @notice 生成Narrative所对应的唯一eqToken id
     * @dev 此函数使用keccak256中的encode将函数的四个入参按照顺序串型传入。将最终得到的hash值使用uint256强制转化成最终的eqToken id
     * @param percents 每种ctf Token占总数量的比例(默认精度为2)
     * @param conditionalIds 每种ctf Token的所对应的conditional id
     * @param indexSets 每种ctf Token的掩码值(决定最终结果是哪个。如果是二元预测，则1代表no，2代表yes；如果有多种结果，则以每种结果所对应的掩码为准)
     * @param managerAddr 创建Narrative的经理地址
     */
    function generateID(uint256[] calldata percents, bytes32[] calldata conditionalIds, uint256[] calldata indexSets, address managerAddr) external returns(uint256);

    /**
     * @notice 重新设置新的uri(只有默认管理员才能调用)
     * @dev 将ERC1155中的_setURI函数暴露出来，并设置为只有拥有默认管理员权限的地址才能调用
     * @param newUri 新的URI地址
     */
    function setURI(string memory newUri) external;

    /**
     * @notice 铸造所需数量和特定id eqToken(只有拥有MINTER role才能调用)
     * @dev 使用ERC1155中的_mint函数，并记录在eqToken中所增加的对应id的总流通量(即_idBalances[id].totalAmount)
     * @param to 最终获得铸造代币的地址
     * @param id 需要铸造的eqToken id
     * @param value 需要铸造的数量
     * @param data 留空即可("")
     */
    function mint(address to, uint256 id, uint256 value, bytes memory data) external;

    /**
     * @notice 销毁对应id和数量的eqToken
     * @dev 该函数只能被拥有controller权限的合约调用
     * @param from 被销毁eqToken的用户地址
     * @param id 被销毁的eqToken id
     * @param value 被销毁的eqToken数量
     */
    function controllerBurn(address from, uint256 id, uint256 value) external;

    /**
     * @notice 为新的地址赋予新的role
     * @dev 只能被拥有对应role管理权限的地址调用
     * @param role 被赋予的职责
     * @param newAddr 被赋予职责的新地址
     */
    function proposeRole(bytes32 role, address newAddr) external;

    /**
     * @notice 撤销拥有Role权限的地址
     * @param role 被撤销的Role
     * @param revokedAddr 被撤销Role的地址
     */
    function revokeRole(bytes32 role, address revokedAddr) external;

    /**
     * @notice 查询账户对应id的EqToken余额
     * @param account 账户地址
     * @param id 要查询的EqToken id
     */
    function balanceOf(address account, uint256 id) external view returns (uint256);

    /**
     * @notice 历史累计铸造量(controllerBurn函数不会减少总量的记录)
     * @param tokenID 需要查询的eqToken id
     */
    function getTotalAmount(uint256 tokenID) view external returns(uint256);
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
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");
    bytes32 public constant CONTROLLER_ADMIN_ROLE = keccak256("CONTROLLER_ADMIN_ROLE");

    struct _balanceBook {
        mapping(address account => uint256 value) _balance;
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

    /**
     * @notice EqToken合约初始化函数
     * @dev 只能被代理合约调用一次，收到initializer修饰器保护
     * @param _uri 用于设置合约中所有代币共享的元数据 URI 模板（通常包含 {id} 占位符），以便客户端能根据 Token ID 动态解析出每个代币的图片和属性信息
     * @param minter 拥有mint权限的地址 | 该权限赋予给Relayer
     * @param controllerAdmin 拥有赋予新地址controller权限的controllerAdmin地址(controller 可以销毁token) | 该权限赋予给Relayer
     * @param admin 拥有最高管理员权限的地址
     */
    function __EqToken_init(
        string memory _uri,
        address minter,
        address controllerAdmin,
        address admin
    ) public initializer {
        __ERC1155_init(_uri);
        __AccessControl_init();
        _setRoleAdmin(CONTROLLER_ROLE, CONTROLLER_ADMIN_ROLE);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, minter);
        _grantRole(CONTROLLER_ADMIN_ROLE, controllerAdmin);
    }

    /**
     * @notice 判断所要操作的Token是否存在
     * @dev 如果所要操作的eqToken不存在，则revert
     * @param id 所要操作的eqToken id
     */
    modifier isExistent(uint256 id) {
        EqTokenStorage storage $ = _getEqTokenStorage();
        require($._idBalances[id].isSet, "this token is not existent");
        _;
    }

    /// @inheritdoc ERC1155Upgradeable
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

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {

    }
    
    /// @notice 获取版本号
    function getVersion() external {
        emit Version(1);
    }

    function controllerBurn(
        address from,
        uint256 id,
        uint256 value
    ) external onlyRole(CONTROLLER_ROLE) isExistent(id) {
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
        ) onlyRole(getRoleAdmin(role)) external {
        _grantRole(role, newAdmin);
        emit RoleChanged(newAdmin, role);
    }

    function revokeRole(
        bytes32 role,
        address revokedAddr
    ) onlyRole(getRoleAdmin(role)) override(AccessControlUpgradeable, IEqToken) public {
        _revokeRole(role, revokedAddr);
        emit RevokeRole(revokedAddr, role);
    }

    function generateID(
        uint256[] calldata percents,
        bytes32[] calldata conditionalIds,
        uint256[] calldata indexSets,
        address managerAddr
    ) external onlyProxy returns(uint256) {
        EqTokenStorage storage $ = _getEqTokenStorage();
        uint256 eqId = uint256(
            keccak256(abi.encode(percents, conditionalIds, indexSets, managerAddr))
        );
        $._idBalances[eqId].isSet = true;
        emit ManagerCreateID(managerAddr, eqId);
        emit Strategy(managerAddr, eqId, percents, conditionalIds, indexSets);
        return eqId;
    }

    function setURI(
        string memory newuri
    ) external onlyRole(DEFAULT_ADMIN_ROLE) onlyProxy {
        _setURI(newuri);
        emit URIChanged(newuri);
    }

    function getTotalAmount(uint256 tokenID) view external returns(uint256) {
        EqTokenStorage storage $ = _getEqTokenStorage();
        return (
            $._idBalances[tokenID].totalAmount
        );
    }

    // override functions
    /// @inheritdoc ERC1155Upgradeable
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

    /// @inheritdoc ERC1155Upgradeable
    function isApprovedForAll(
        address account,
        address operator
    ) public view override onlyProxy returns (bool) {
        EqTokenStorage storage $ = _getEqTokenStorage();
        return $._operatorApprovals[account][operator];
    }

    /// @inheritdoc ERC1155Upgradeable
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

    /// @inheritdoc ERC1155Upgradeable
    function _setURI(string memory newuri) internal override {
        EqTokenStorage storage $ = _getEqTokenStorage();
        $._uri = newuri;
    }

    /// @inheritdoc ERC1155Upgradeable
    function uri(
        uint256 /* id */
    ) public view override onlyProxy returns (string memory) {
        EqTokenStorage storage $ = _getEqTokenStorage();
        return $._uri;
    }

    /// @inheritdoc ERC1155Upgradeable
    function balanceOf(
        address account,
        uint256 id
    ) public view override(ERC1155Upgradeable, IEqToken) onlyProxy returns (uint256) {
        EqTokenStorage storage $ = _getEqTokenStorage();
        return $._idBalances[id]._balance[account];
    }

}