// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title EntropyLib
/// @notice Computes normalised Shannon entropy for a three-outcome vote distribution
///         (YES / NO / ABSTAIN) using WAD (1e18) fixed-point arithmetic.
///
/// Algorithm
/// ---------
/// H = -Σ pᵢ · log₂(pᵢ)
///
/// Normalised by H_max = log₂(3) ≈ 1.58496…, so the result is in [0, WAD].
///
/// log₂ is computed via:
///   1. Integer part  — standard MSB bit-scan.
///   2. Fractional part — iterative squaring method (60 iterations → ~60 bits
///      of precision, well within WAD's 60-bit resolution).
///
/// Gas note: the 60-iteration loop costs ~5 000 gas per call to _negPLog2P,
/// so ~15 000 gas per entropy evaluation.  Acceptable for an on-chain
/// governance primitive where this is called once per proposal.
library EntropyLib {
    uint256 internal constant WAD = 1e18;

    /// @dev log₂(3) × WAD  — used to normalise three-outcome distributions.
    ///      log₂(3) = 1.5849625007211562…
    uint256 internal constant LOG2_3_WAD = 1_584_962_500_721_156_120;

    // ─────────────────────────────────────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Compute normalised Shannon entropy ∈ [0, WAD].
    ///         Returns WAD when votes are perfectly uniform (maximum disorder).
    ///         Returns 0 when all votes fall in one bucket (perfect consensus).
    /// @param yes     Total YES effective weight
    /// @param no      Total NO effective weight
    /// @param abstain Total ABSTAIN effective weight
    function normalizedEntropy(
        uint256 yes,
        uint256 no,
        uint256 abstain
    ) internal pure returns (uint256) {
        uint256 total = yes + no + abstain;
        if (total == 0) return 0;

        uint256 h = 0;
        if (yes     > 0) h += _negPLog2P(yes,     total);
        if (no      > 0) h += _negPLog2P(no,       total);
        if (abstain > 0) h += _negPLog2P(abstain,  total);

        // h = H × WAD; normalise by H_max = log₂(3) × WAD
        return (h * WAD) / LOG2_3_WAD;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Returns −p · log₂(p) × WAD where p = num / total.
    ///      Equivalently: (num / total) · log₂(total / num) × WAD.
    function _negPLog2P(uint256 num, uint256 total) internal pure returns (uint256) {
        // num ≤ total by construction; log₂(total/num) ≥ 0
        uint256 log2Result = _log2WAD(total, num);
        // p · log₂(1/p) · WAD = (num / total) · log₂WAD
        return (num * log2Result) / total;
    }

    /// @dev Returns log₂(t / n) × WAD using integer MSB + squaring method.
    ///      Requires t ≥ n > 0.
    function _log2WAD(uint256 t, uint256 n) internal pure returns (uint256) {
        // ── Integer part ─────────────────────────────────────────────────────
        uint256 ratio = t / n; // floor(t/n), ≥ 1
        uint256 msb   = _msb(ratio);
        uint256 result = msb * WAD;

        // ── Fractional part via squaring method ──────────────────────────────
        // Normalise mantissa to Q63: r ∈ [2⁶³, 2⁶⁴)
        // represents (t/n) / 2^msb in Q63 fixed-point.
        //
        // Case msb ≤ 63:  r = (t << (63 - msb)) / n
        //   Max shift: 63 bits on t < 2^256 → safe.
        // Case msb > 63:  r = t / (n << (msb - 63))
        //   n << (msb-63) ≤ t, so no overflow in the shift provided n < 2^193,
        //   which is guaranteed for any realistic token supply.
        uint256 r;
        if (msb <= 63) {
            r = (t << (63 - msb)) / n;
        } else {
            r = t / (n << (msb - 63));
        }
        // r is now in [2⁶³, 2⁶⁴)

        // 60 squaring iterations: each doubles the bit precision of the result.
        // r² ≤ (2⁶⁴)² = 2¹²⁸ — fits in uint256 without overflow.
        for (uint256 i = 1; i <= 60; i++) {
            r = (r * r) >> 63;
            if (r >= (uint256(1) << 64)) {
                r >>= 1;
                result += WAD >> i;
            }
        }
        return result;
    }

    /// @dev Returns ⌊log₂(x)⌋ for x > 0.
    function _msb(uint256 x) internal pure returns (uint256 msb) {
        if (x >= 1 << 128) { x >>= 128; msb  = 128; }
        if (x >= 1 << 64)  { x >>= 64;  msb += 64;  }
        if (x >= 1 << 32)  { x >>= 32;  msb += 32;  }
        if (x >= 1 << 16)  { x >>= 16;  msb += 16;  }
        if (x >= 1 << 8)   { x >>= 8;   msb += 8;   }
        if (x >= 1 << 4)   { x >>= 4;   msb += 4;   }
        if (x >= 1 << 2)   { x >>= 2;   msb += 2;   }
        if (x >= 2)                    { msb += 1;   }
    }
}
