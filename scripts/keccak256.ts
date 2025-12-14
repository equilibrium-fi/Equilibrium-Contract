import { 
    id, 
    keccak256, 
    AbiCoder, 
    toBeHex 
} from "ethers";

/**
 * 计算 ERC-7201 风格的存储槽
 * 目标公式: keccak256(abi.encode(uint256(keccak256(NAMESPACE)) - 1)) & ~bytes32(uint256(0xff))
 */
function calculateStorageSlot(namespace: string): string {
    console.log(`\n--- 计算 Namespace: "${namespace}" ---`);

    // 步骤 1: keccak256("luna.storage.EqToken")
    // 使用 ethers.id 可以直接计算字符串的 keccak256
    const namespaceHash = id(namespace);
    console.log(`1. Namespace Hash: ${namespaceHash}`);

    // 步骤 2: uint256(...) - 1
    // 将 Hash (Hex 字符串) 转为 BigInt 进行数学减法
    const namespaceBn = BigInt(namespaceHash);
    const decrementedBn = namespaceBn - 1n;
    // (可选：打印中间结果)
    // console.log(`2. Decremented:    0x${decrementedBn.toString(16)}`);

    // 步骤 3: abi.encode(...)
    // 将减 1 后的数值编码为 uint256 格式
    const coder = AbiCoder.defaultAbiCoder();
    const encoded = coder.encode(["uint256"], [decrementedBn]);
    console.log(`3. ABI Encoded:    ${encoded}`);

    // 步骤 4: keccak256(...)
    // 对编码后的数据再次哈希
    const outerHash = keccak256(encoded);
    console.log(`4. Outer Hash:     ${outerHash}`);

    // 步骤 5: & ~bytes32(uint256(0xff))
    // 逻辑：将哈希值的最后一个字节（最后两位 16 进制）清零
    // 在 Solidity 中，这是通过位掩码实现的。在 TS 中，最安全的方法是用位移操作。
    // 右移 8 位丢弃最后 1 字节，再左移 8 位补回 0。
    const outerHashBn = BigInt(outerHash);
    const maskedBn = (outerHashBn >> 8n) << 8n;

    // 步骤 6: 转换回 32 字节的 Hex 字符串
    // 使用 ethers 的 toBeHex 确保长度为 32 字节 (64字符 + 0x)
    const finalSlot = toBeHex(maskedBn, 32);
    
    console.log(`5. Final Slot:     ${finalSlot}`);
    return finalSlot;
}

// --- 执行 ---
const TARGET_NAMESPACE = "luna.storage.VaultController";
calculateStorageSlot(TARGET_NAMESPACE);