
- 原文链接 -- https://blog.openacid.com/algo/crc
- Python 示例代码地址 -- https://gist.github.com/drmingdrmer/2b49106b225ca7bf361fd21454f693da
- fuzhe at x  -- https://x.com/fuzhe19

**LevelDB CRC 实现**：
- LevelDB CRC32C 头文件 -- https://github.com/google/leveldb/blob/main/util/crc32c.h
- LevelDB CRC32C 实现文件 -- https://github.com/google/leveldb/blob/main/util/crc32c.cc
- LevelDB Block 格式文档 -- https://github.com/google/leveldb/blob/main/doc/table_format.md

## 数学理论基础

**CRC 算法原理**：
- Wikipedia: Cyclic redundancy check -- https://en.wikipedia.org/wiki/Cyclic_redundancy_check
- Wikipedia: Finite field arithmetic -- https://en.wikipedia.org/wiki/Finite_field_arithmetic
- Wikipedia: Irreducible polynomial -- https://en.wikipedia.org/wiki/Irreducible_polynomial

**多项式运算**：
- Wikipedia: Polynomial long division -- https://en.wikipedia.org/wiki/Polynomial_long_division
- Wikipedia: Galois field -- https://en.wikipedia.org/wiki/Galois_field

## CRC 标准和应用

**CRC-32C (Castagnoli)**：
- RFC 3720 - Internet Small Computer Systems Interface (iSCSI) -- https://tools.ietf.org/html/rfc3720
- Wikipedia: Cyclic redundancy check - CRC-32C -- https://en.wikipedia.org/wiki/Cyclic_redundancy_check#CRC-32C_(Castagnoli)

**其他 CRC 实现**：
- zlib CRC-32 实现 -- https://github.com/madler/zlib/blob/master/crc32.c

## 系统设计相关

**存储系统设计**：
- LevelDB 设计文档 -- https://github.com/google/leveldb/blob/main/doc/index.md
- LSM-Tree 论文 -- https://www.cs.umb.edu/~poneil/lsmtree.pdf

**数据完整性**：
- End-to-end data integrity -- https://queue.acm.org/detail.cfm?id=1317400

## 工程实践案例

**类似的 Mask 技术**：
- PostgreSQL CRC implementation -- https://github.com/postgres/postgres/blob/master/src/include/utils/pg_crc.h
- ZFS checksum algorithms -- https://openzfs.github.io/openzfs-docs/Basic%20Concepts/Checksums.html

**错误检测技术**：
- Reed-Solomon codes -- https://en.wikipedia.org/wiki/Reed%E2%80%93Solomon_error_correction
- Hamming codes -- https://en.wikipedia.org/wiki/Hamming_code

## 实用工具

**CRC 计算工具**：
- Online CRC Calculator -- https://crccalc.com/
- RevEng CRC Catalogue -- https://reveng.sourceforge.io/crc-catalogue/

**Python 实现**：
- crcmod Python library -- https://pypi.org/project/crcmod/
- zlib.crc32 文档 -- https://docs.python.org/3/library/zlib.html#zlib.crc32

## 学术资料

**密码学相关**：
- Handbook of Applied Cryptography -- http://cacr.uwaterloo.ca/hac/
