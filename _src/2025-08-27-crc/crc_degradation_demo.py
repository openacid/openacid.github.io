#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
LevelDB CRC Mask 机制演示代码
演示嵌套CRC的"自包含退化"现象以及mask方案的解决效果
"""

import os
import random
from typing import List

# CRC-32C (Castagnoli) 参数：
#  - 生成多项式（反射后）: 0x82F63B78
#  - refin = refout = True
#  - init = 0xFFFFFFFF
#  - xorout = 0xFFFFFFFF
POLY_REV = 0x82F63B78

def _make_crc32c_table() -> List[int]:
    """构建CRC-32C查找表"""
    tbl = []
    for i in range(256):
        crc = i
        for _ in range(8):
            if crc & 1:
                crc = (crc >> 1) ^ POLY_REV
            else:
                crc >>= 1
        tbl.append(crc & 0xFFFFFFFF)
    return tbl

_CRC32C_TABLE = _make_crc32c_table()

def crc32c(data: bytes) -> int:
    """标准 CRC-32C（Castagnoli）实现"""
    crc = 0xFFFFFFFF
    for b in data:
        crc = _CRC32C_TABLE[(crc ^ b) & 0xFF] ^ (crc >> 8)
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF

# LevelDB 的 Mask/Unmask（util/crc32c.h）
K_MASK_DELTA = 0xA282EAD8

def _rot_r32(x: int, n: int) -> int:
    """32位右旋转"""
    return ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF

def _rot_l32(x: int, n: int) -> int:
    """32位左旋转"""
    return ((x << n) | (x >> (32 - n))) & 0xFFFFFFFF

def mask(crc: int) -> int:
    """LevelDB mask函数：右旋15位 + 加常数"""
    return (_rot_r32(crc, 15) + K_MASK_DELTA) & 0xFFFFFFFF

def unmask(x: int) -> int:
    """LevelDB unmask函数：减常数 + 左旋15位"""
    return _rot_l32((x - K_MASK_DELTA) & 0xFFFFFFFF, 15)

def demonstrate_nested_crc_degradation():
    """演示嵌套CRC的退化现象"""
    # 模拟不同的LevelDB数据块
    leveldb_blocks = [
        b"user_data_1",
        b"user_data_2",
        b"important_record_12345",
        b"transaction_log_abcdef",
        bytes(range(50)),  # 二进制数据
    ]

    # 添加一些随机数据块
    for _ in range(5):
        leveldb_blocks.append(os.urandom(random.randint(10, 100)))

    print("=== 嵌套CRC退化验证 ===")
    outer_crcs = []

    for i, block_data in enumerate(leveldb_blocks):
        # 第一层：LevelDB内部CRC
        inner_crc = crc32c(block_data)
        leveldb_block = block_data + inner_crc.to_bytes(4, "little")

        # 第二层：外层协议CRC（如网络传输）
        outer_crc = crc32c(leveldb_block)
        complete_packet = leveldb_block + outer_crc.to_bytes(4, "little")

        outer_crcs.append(outer_crc)

        print(f"块 #{i+1:2d}: 数据长度={len(block_data):3d}, "
              f"内层CRC=0x{inner_crc:08X}, "
              f"外层CRC=0x{outer_crc:08X}")

    # 检查外层CRC是否都相同
    unique_outer_crcs = set(outer_crcs)
    print(f"\n不同外层CRC的数量: {len(unique_outer_crcs)}")
    print(f"所有外层CRC都是: 0x{list(unique_outer_crcs)[0]:08X}")
    print(">>> 外层CRC完全退化！无论内层数据如何变化，外层CRC都是固定值")

def demonstrate_mask_effect():
    """演示mask方案打破退化现象"""
    # 使用前面相同的LevelDB数据块
    leveldb_blocks = [
        b"user_data_1",
        b"user_data_2",
        b"important_record_12345",
        b"transaction_log_abcdef",
    ]

    print("\n=== 使用LevelDB mask后的结果 ===")
    outer_crcs_masked = []

    for i, block_data in enumerate(leveldb_blocks):
        # 第一层：LevelDB内部CRC + mask
        inner_crc = crc32c(block_data)
        masked_crc = mask(inner_crc)  # 关键：存储前mask
        leveldb_block_masked = block_data + masked_crc.to_bytes(4, "little")

        # 第二层：外层协议CRC
        outer_crc = crc32c(leveldb_block_masked)

        outer_crcs_masked.append(outer_crc)

        print(f"块 #{i+1}: 原CRC=0x{inner_crc:08X}, "
              f"Mask后=0x{masked_crc:08X}, "
              f"外层CRC=0x{outer_crc:08X}")

    unique_masked = set(outer_crcs_masked)
    print(f"\n使用mask后，不同外层CRC的数量: {len(unique_masked)}")
    print(">>> Mask成功！外层CRC现在随数据内容变化")

def verify_mask_reversibility():
    """验证mask操作的可逆性"""
    print("\n=== 验证mask可逆性 ===")
    test_values = [0, 1, 0x12345678, 0xFFFFFFFF, 0xA1B2C3D4]

    for v in test_values:
        masked = mask(v)
        unmasked = unmask(masked)
        print(f"原值: 0x{v:08X} -> Mask: 0x{masked:08X} -> Unmask: 0x{unmasked:08X} "
              f"{'✓' if unmasked == v else '✗'}")

def main():
    """主函数：运行所有演示"""
    # 验证标准CRC-32C测试向量
    assert crc32c(b"123456789") == 0xE3069283, "CRC-32C实现错误"
    print("CRC-32C实现验证通过")

    # 演示嵌套CRC退化
    demonstrate_nested_crc_degradation()

    # 演示mask方案效果
    demonstrate_mask_effect()

    # 验证mask可逆性
    verify_mask_reversibility()

if __name__ == "__main__":
    main()
