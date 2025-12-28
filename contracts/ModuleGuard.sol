// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// 放行情况:
// 1. stake 转账至 CTFExchange Contract 中 | 此步由 CTFExchange 使用 safeTransferFrom 转出， 所以在转出前需要进行一次授权 ERC20 approve (由EOA发起)
// 2. 将挂单失败的 stake 返回给 用户
// 3. CTF 在 Conditional Token Framework 中赎回成 stake
// 4. 允许调用 VaultController 的 withdrawStake 函数
// 5. 考虑 isValidSignature 覆盖问题 EIP1271 (写在Guard还是Module Guard需要商榷)
// 6. 采用UUPS可升级合约架构