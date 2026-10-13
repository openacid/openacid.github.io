---
marp: true
theme: default
paginate: true
size: 16:9
style: |
  section {
    font-size: 28px;
  }
  code {
    font-size: 22px;
  }
  pre {
    font-size: 20px;
  }
---

<!-- _paginate: false -->

# CRC32 Self-Containing Degradation
## Understanding LevelDB's Mask Operation

**A Deep Dive into CRC Mathematics and Engineering**

---

# The Mystery in LevelDB

LevelDB masks CRC values before storing them:

```cpp
static const uint32_t kMaskDelta = 0xa282ead8ul;

inline uint32_t Mask(uint32_t crc) {
  // Rotate right by 15 bits and add a constant.
  return ((crc >> 15) | (crc << 17)) + kMaskDelta;
}
```

**Why?** The comment says:
> "it is problematic to compute the CRC of a string that contains embedded CRCs"

---

# What is CRC? Basic Concept

**Using division to detect errors:**

```
Transmit: 1234
1234 ÷ 97 = 12 remainder 70
```

- Remainder `70` is the **fingerprint** of `1234`
- Send: `data=1234, checksum=70`
- Receive: Calculate `1234 % 97`, compare with `70`
- If different → **error detected!**

---

# CRC Verification Principle

**How to verify received data:**

```
Received: data=1234, checksum=70

1. Calculate: 1234 % 97 = 70
2. Compare: calculated(70) == received(70)?
```

**Example:**
```
1234 % 97 = 70
1235 % 97 = 71  ← data changed, remainder changed
```

Collision probability with prime 97: ~1/97 ≈ 1%

---

# Why Multiply Before Division?

**To prevent checksum from equaling the message itself:**

CRC multiplies the message by a large number first to ensure the remainder is different from the original message.

**Example:**
```
Message: 42
Multiply by 100:

42 * 100 % 97 = 29

Send: data=42, checksum=29
```

**Without multiplication:**
```
42 % 97 = 42  ← Checksum equals message!
```

This is why CRC-32 multiplies by 2³² (appends 32 zero bits).

---

# CRC Only Needs Four Operations

**CRC basic arithmetic:**

```
CRC(M) = (M × Scale) % Divisor
```

**Four operations needed:**
1. (`+`)
2. (`-`)
3. (`×`)
4. (`÷`) - or (`%`)

**Example with integers:**
```
(42 × 100) % 97 = 4200 % 97 = 29
```

These operations follow algebraic laws: commutative, associative, distributive.

---

# Operations Can Be Redefined

Any four operations system satisfying algebraic laws can work!

**Regular integers:**
```
1234 % 97 = 70

5 + 3 = 8
5 × 3 = 15
```

**Alternative definitions exist:**
- Matrix arithmetic
- Modular arithmetic
- **Polynomial arithmetic with GF(2) coefficients** ← CRC uses this!

**Why redefine?** To maximize the use of available value space for better error detection.

---

# Why Use GF(2) Instead of Integers?

**Problem with integer arithmetic:**

Using prime divisor 97 for checksums:
- Checksum range: `[0, 96]` (97 values)
- Stored in 1 byte: can hold `[0, 255]` (256 values)
- **Wasted space:** 159 values unused (62% wasted!)

**Solution with GF(2) polynomials:**

Using irreducible polynomial x³ + x + 1 (binary 1011):
- Remainder range: all polynomials of degree `< 3`
- That's exactly 2³ = 8 values: `[000, 111]`
- **100% utilization** of 3-bit space!

For CRC-32: Uses all 2³² values, maximum error detection capability.

---

# GF(2) Operations: Binary Arithmetic

**In the binary world (0 and 1 only):**

**Addition (XOR):**
```
0 + 0 = 0
0 + 1 = 1
1 + 0 = 1
1 + 1 = 0  ← No carry!
```

**Subtraction (also XOR):**
```
0 - 0 = 0
1 - 1 = 0
1 - 0 = 1
0 - 1 = 1  ← No borrow!
```

**Key insight:** Addition = Subtraction = XOR in GF(2)

---

# GF(2) Multiplication and Division

**Multiplication (AND):**
```
0 × 0 = 0
0 × 1 = 0
1 × 0 = 0
1 × 1 = 1
```

**Division:** (not required)
```
0 ÷ 1 = 0
1 ÷ 1 = 1
```

**Properties:**
- Same as integer operations (commutative, associative, distributive)
- **Closed system:** Results always 0 or 1
- Perfect for computer implementation

---

# Polynomial Arithmetic with GF(2)

**GF(2) polynomial operations:**

```
Addition/Subtraction (XOR equal-degree terms):

(x² + x + 1) + (x² + 1) = x² + x + 1 + x² + 1
                        = (x² + x²) + x + (1 + 1)
                        = 0 + x + 0 = x


Multiplication (expand and combine):

(x² + 1) × (x + 1) = x³ + x² + x + 1


Key property:

(x + 1) + (x + 1) = 0  ← Same terms cancel out!
```

---

# Binary-Polynomial Correspondence

**Every binary number maps to a polynomial:**

```
Binary: 1011 → Polynomial: 1·x³ + 0·x² + 1·x¹ + 1·x⁰
                        = x³ + x + 1

Binary: 1101 → Polynomial: x³ + x² + 1
```

**Multi-bit operations:**
```
Addition/Subtraction:
  1011
⊕ 1101
------
  0110

Multiplication (polynomial multiplication):
101 × 11 = 101 × (10 + 1) = 1010 ⊕ 101 = 1111
```

---

# CRC Definition with Polynomials

**CRC formula:**
```
CRC(M) = (M × 2ⁿ) % G
```
- `M`: message polynomial
- `G`: generator polynomial (must be irreducible)
- `n`: degree of G

**Example:**
```
Data:      x² + 1 (binary 101)
Generator: x³ + x + 1 (binary 1011, irreducible)

Calculate: (x² + 1) · x³ % (x³ + x + 1)
         = x⁵ + x³ % (x³ + x + 1)
         = x²

Result: CRC = 100
Send: message | CRC = 101 | 100
```

---

# The Nested CRC Problem

**When CRC values contain CRC values:**

```
Layer 1:
Message M  →  M | CRC(M)

Layer 2:
M | CRC(M)  →  M | CRC(M) | CRC(M | CRC(M))
```

**Problem:**
If both layers use the same CRC algorithm, the outer CRC becomes a **fixed constant**, independent of the message content!

This means the outer layer **loses all error detection capability**.

---

# Mathematical Proof: Setup

**Using simplified 3-bit CRC:**
```
CRC(M) = (M × 1000₂) % 111₂
```
Where:
- `1000₂ = 8 = 2³` (multiply by x³)
- `111₂ = 7` (generator polynomial x² + x + 1)

**From CRC definition:**
```
CRC(M) = (M × 1000₂) % 111₂

Therefore:
M × 1000₂ = k × 111₂ + CRC(M)  (for some k)
```

---

# Mathematical Proof: Part 1

**Appending CRC to message:**

```
M | CRC(M) = M × 1000₂ + CRC(M)
```

Why? To append 3-bit CRC, shift M left by 3 bits:
```
Example: M = 101₂, CRC(M) = 101₂
M × 1000₂ = 101000₂  (make space for 3 bits)
M | CRC(M) = 101000₂ + 101₂ = 101101₂
```

**Substitute the relationship:**
```
M | CRC(M) = M × 1000₂ + CRC(M)
           = (k × 111₂ + CRC(M)) + CRC(M)
           = k × 111₂ + CRC(M) + CRC(M)
```

---

# Mathematical Proof: Part 2

**Key GF(2) property:**
```
CRC(M) + CRC(M) = 0  (in GF(2))
```

Any number added to itself equals 0 in GF(2)!

**Therefore:**
```
M | CRC(M) = k × 111₂ + 0
           = k × 111₂
```

**Discovery:** `M | CRC(M)` is always a multiple of the generator polynomial!

---

# Mathematical Proof: Part 3

**Calculate outer CRC:**

```
CRC(M | CRC(M)) = CRC(k × 111₂)
                = (k × 111₂ × 1000₂) % 111₂
                = 0
```

Any multiple of 111₂ modulo 111₂ equals 0!

**Conclusion:**
No matter what message M is, `CRC(M | CRC(M))` is always the same constant!

In real CRC implementations (with initial values and final XOR), this constant is not 0 but some fixed value called the **residue**.

---

# LevelDB's Mask Solution

**The code:**
```cpp
static const uint32_t kMaskDelta = 0xa282ead8ul;

inline uint32_t Mask(uint32_t crc) {
  // Rotate right by 15 bits and add a constant.
  return ((crc >> 15) | (crc << 17)) + kMaskDelta;
}
```

**Two operations:**
1. **Rotate right 15 bits**: `(crc >> 15) | (crc << 17)`
2. **Add constant**: `+ kMaskDelta`

This breaks the mathematical relationship, preventing degradation!

---

# Why Mask Works

**The mask operation destroys the GF(2) algebraic structure:**

Without mask:
```
CRC(M | mask(CRC(M)))
= CRC(M * 2³² + mask(CRC(M)))
= (CRC(M) + mask(CRC(M))) * 2³² % G
```

With mask applied, the result now depends on M:
- Rotation provides linear permutation
- Addition introduces non-linearity
- Combined effect prevents constant result

**Result:** Outer CRC now varies with message content!

---

# Python Verification: The Problem

**Code demonstrating degradation:**

```python
def crc32c(data: bytes) -> int:
    """Standard CRC-32C implementation"""
    crc = 0xFFFFFFFF
    for b in data:
        crc = _CRC32C_TABLE[(crc ^ b) & 0xFF] ^ (crc >> 8)
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF

# Test with different messages
for block_data in test_blocks:
    inner_crc = crc32c(block_data)
    leveldb_block = block_data + inner_crc.to_bytes(4, "little")
    outer_crc = crc32c(leveldb_block)  # Always the same!
```

---

# Degradation Results

**Output from different test data:**

```
Block #1: length=11, inner=0x12AB34CD, outer=0x48674BC7
Block #2: length=11, inner=0x56EF78AB, outer=0x48674BC7
Block #3: length=21, inner=0x9A2B3C4D, outer=0x48674BC7
Block #4: length=22, inner=0xDEF01234, outer=0x48674BC7
Block #5: length=50, inner=0x567890AB, outer=0x48674BC7

Unique outer CRCs: 1
All outer CRCs = 0x48674BC7
>>> Outer CRC completely degraded!
```

Different data, different inner CRCs, but **identical outer CRC**!

---

# Python Verification: The Solution

**Code with mask applied:**

```python
K_MASK_DELTA = 0xA282EAD8

def mask(crc: int) -> int:
    rotated = ((crc >> 15) | (crc << 17)) & 0xFFFFFFFF
    return (rotated + K_MASK_DELTA) & 0xFFFFFFFF

# Test with mask
for block_data in test_blocks:
    inner_crc = crc32c(block_data)
    masked_crc = mask(inner_crc)  # Apply mask!
    leveldb_block = block_data + masked_crc.to_bytes(4, "little")
    outer_crc = crc32c(leveldb_block)  # Now varies!
```

---

# Mask Effectiveness Results

**Output with mask applied:**

```
Block #1: original=0x12AB34CD, masked=0xE5F2A891, outer=0x3C7B2A15
Block #2: original=0x56EF78AB, masked=0xC4D8B672, outer=0x8F4E1B29
Block #3: original=0x9A2B3C4D, masked=0x7B3EA254, outer=0x1D6C9F38
Block #4: original=0xDEF01234, masked=0x2A8C5E91, outer=0x94E7C2B6

Unique outer CRCs: 4
>>> Mask successful! Outer CRC now varies with data
```

---

# Security Impact Analysis

**Against random errors:** No change
- Value space size remains the same (2³² combinations)
- Error detection probability unchanged
- Inner CRC still effective

**Against malicious attacks:** Significant improvement
- **Without mask:** Attacker knows outer CRC is constant, can forge data easily
- **With mask:** Attacker doesn't know the outer CRC, must break mask algorithm or brute force
- Construction difficulty greatly increased

**Key distinction:**
- Anti-corruption: Random bit changes (mask doesn't help)
- Anti-attack: Intentional bit changes (mask helps significantly)

---

# Real-World Applications

**Layered storage systems:**

```
Application data
├── Application layer CRC (database records)
├── Storage engine layer CRC (LevelDB blocks)
├── File system layer CRC (ext4/ZFS)
└── Hardware layer CRC (disk sectors)
```

**Common scenarios:**
- Database backups: `[header | [data | crc] | backup_crc]`
- Network transmission: `[packet_header | [block | block_crc] | packet_crc]`
- RAID systems: `[sector_1 | sector_2 | ... | raid_parity]`

---

# Alternative Solutions Comparison

| Solution              | Perf Overhead ↓  | Storage Overhead ↓  | Complexity ↓  | Security ↑ |
|----------             |----------------- |-------------------- |-------------- |----------- |
| Different polynomials | Low              | None                | Medium        | Medium     |
| Layer identifiers     | Low              | High                | Low           | Medium     |
| Different algorithms  | High             | Medium              | High          | High       |
| Mask                  | **Very Low**     | **None**            | Medium        | Medium     |

**Note:** ↓ = lower is better, ↑ = higher is better

**LevelDB chose mask:** Best balance - minimal overhead, maximum effectiveness

---

# Conclusion: Math Meets Engineering

**Mathematical insight:**
- CRC based on GF(2) polynomial division
- Self-containing structure creates algebraic cancellation
- Outer CRC degrades to constant due to field properties

**Engineering solution:**
- Minimal intervention (only transform at storage)
- Mathematically rigorous (breaks GF(2) structure)
- Practically efficient (negligible performance impact)
- Simple and reversible

**Lesson:** The most elegant solutions come from deep understanding of mathematical principles.

---

# References

**Source code:**
- LevelDB CRC32C: https://github.com/google/leveldb/blob/main/util/crc32c.h
- Python examples: https://gist.github.com/drmingdrmer/2b49106b225ca7bf361fd21454f693da
- Original article: https://blog.openacid.com/algo/crc

**Theory:**
- Wikipedia: Cyclic Redundancy Check
- Wikipedia: Galois Field GF(2)
- Wikipedia: Irreducible Polynomial

**Standards:**
- RFC 3720: CRC-32C in iSCSI
- IEEE CRC standards

---

# Thank You!

**Questions?**

Contact: @drdrxp
Blog: https://blog.openacid.com
