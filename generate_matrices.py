"""
gen_vectors.py
Generates random INT8 matrices A and B, computes C = A @ B using numpy,
and writes everything to a file that systolic_array_tb.v reads.

Usage:
    python gen_vectors.py

Output:
    test_vectors.txt  — put this in the same folder as your Vivado project
"""

import numpy as np

N = 4  # matrix size, must match your Verilog parameter

# ── Generate random INT8 matrices (0–127 to avoid overflow issues) ──────────
rng = np.random.default_rng(seed=42)  # fixed seed = reproducible
A = rng.integers(0, 128, size=(N, N), dtype=np.uint8)
B = rng.integers(0, 128, size=(N, N), dtype=np.uint8)

# ── Compute expected output using full precision, then wrap to 16-bit ────────
# This matches what your hardware does: accumulate in 16-bit, wrap on overflow
C_full = A.astype(np.int32) @ B.astype(np.int32)
C_wrapped = (C_full % (2**16)).astype(np.uint32)  # mod 2^16, matches ACC_WIDTH=16

# ── Print to console so you can see what's being tested ─────────────────────
print("A matrix (INT8):")
print(A)
print("\nB matrix (INT8):")
print(B)
print("\nC = A @ B (full precision):")
print(C_full)
print("\nC wrapped to 16 bits (what hardware produces):")
print(C_wrapped)

# ── Write test_vectors.txt ───────────────────────────────────────────────────
with open("test_vectors.txt", "w") as f:
    # Format: one value per line
    # Testbench reads: N*N A values, then N*N B values, then N*N expected C values

    f.write("// A matrix (row-major)\n")
    for i in range(N):
        for j in range(N):
            f.write(f"{int(A[i][j])}\n")

    f.write("// B matrix (row-major)\n")
    for i in range(N):
        for j in range(N):
            f.write(f"{int(B[i][j])}\n")

    f.write("// Expected C = A @ B (row-major, wrapped to 16 bits)\n")
    for i in range(N):
        for j in range(N):
            f.write(f"{int(C_wrapped[i][j])}\n")

print("\nWrote test_vectors.txt")
print("Copy test_vectors.txt into your Vivado project directory,")
print("then run the systolic_array_tb simulation.")