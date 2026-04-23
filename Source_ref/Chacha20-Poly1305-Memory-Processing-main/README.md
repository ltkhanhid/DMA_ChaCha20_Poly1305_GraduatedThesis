ChaCha20-Poly1305 RTL Repository

This repository contains Verilog implementations of the ChaCha20-Poly1305 authenticated encryption algorithm along with testbenches and supporting modules for hardware simulation and integration.

chacha20_poly1305_bus.v

This module provides a bus interface wrapper around the ChaCha20-Poly1305 core, allowing it to be integrated into a memory-mapped system. It handles read and write transactions from a host, manages init, next, and encryption/decryption commands, and provides output data and authentication tags. The bus interface ensures proper handshaking, making the core accessible in a SoC environment.

chacha20_poly1305_core.v

This is the top-level ChaCha20-Poly1305 core, combining the ChaCha20 block cipher with the Poly1305 MAC computation. It accepts 512-bit input blocks, a 256-bit key, and a nonce, and produces encrypted output with an authentication tag. The core handles the sequencing of ChaCha20 blocks and Poly1305 accumulation, providing valid and tag_ok signals for output verification.

chacha_block.v

Implements a single ChaCha20 block transformation, performing 20 rounds of the ChaCha quarter-round function. It takes the initial state, applies the ChaCha20 permutation, and outputs a 512-bit block. This module is the building block for the ChaCha20 core and can be used independently for hardware testing or pipelining.

chacha_core.v

This module implements the ChaCha20 core encryption engine. It handles block-wise processing with init and next signals, manages ready/valid handshakes, and computes the XOR of the ChaCha20 keystream with input data. The core maintains internal state and controls block execution through the chacha_block module, making it suitable for sequential encryption of multiple blocks.

chacha_functions.v

Contains supporting functions for ChaCha20, including the quarter-round operation, rotations, additions, and XOR logic. These functions are used inside the core modules to implement the ChaCha20 rounds efficiently in hardware, ensuring correct bit-level transformations for encryption.

mult_130x128_limb.v

This module implements a limb-based multiplier for Poly1305 computation. It multiplies a 130-bit number with a 128-bit number using 16-bit limbs, generating a 258-bit partial product. This approach improves synthesis performance and allows pipelined or multi-cycle multiplication in hardware.

reduce_mod_poly1305.v

Performs modular reduction for the Poly1305 authentication code. After accumulation in the MAC, this module reduces the intermediate values to generate the final 128-bit authentication tag. It ensures correctness of the MAC in hardware implementation.

tb_chacha20_poly1305_bus.v

Testbench for the bus-interface module. It simulates host read/write transactions, drives init and next commands, and checks the output data and authentication tag. This testbench verifies correct integration of the bus wrapper with the ChaCha20-Poly1305 core under various scenarios.

tb_chacha20_poly1305_core.v

Testbench for the ChaCha20-Poly1305 core. It initializes keys, nonces, and input data blocks, asserts init and encdec, and monitors valid and tag_ok signals. This ensures that the core correctly encrypts and authenticates input data over multiple blocks.

tb_chacha_core.v

Testbench for the ChaCha20 core module. It validates block-wise encryption, proper ready/valid handshake, and the correctness of the output keystream. This testbench drives init and next signals and compares the core output against expected results.
