/*
 * Copyright (C) 2022 - 2026, Stephan Mueller <smueller@chronox.de>
 *
 * License: see LICENSE file in root directory
 *
 * THIS SOFTWARE IS PROVIDED ``AS IS AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE, ALL OF
 * WHICH ARE HEREBY DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
 * OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
 * BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE
 * USE OF THIS SOFTWARE, EVEN IF NOT ADVISED OF THE POSSIBILITY OF SUCH
 * DAMAGE.
 */

/*
 * This is an auto-generated header file including all leancrypto
 * header files for easy use.
 */

/** \mainpage Leancrypto Post-Quantum Cryptographic Library
 *
 * \section intro_sec Introduction
 *
 * The leancrypto library is a cryptographic library that exclusively contains
 * only PQC-resistant cryptographic algorithms. The algorithm implementations
 * have the following properties:
 *
 * * minimal dependencies: only minimal POSIX environment needed - function
 *   calls are abstracted into helper code that may need to be replaced for
 *   other environments (see the Linux kernel support in `linux_kernel` for
 *   replacing the POSIX calls)
 *
 * * extractable: the algorithms can be extracted and compiled as part of a
 *   separate project,
 *
 * * flexible: you can disable algorithms on an as-needed basis using
 *   `meson configure`,
 *
 * * fully thread-safe when using different cipher contexts for an invocation:
 *   there is no global state maintained for the algorithms,
 *
 * * stack-only support: all algorithms can be allocated on stack if needed. In
 *   addition, allocation functions for a usage on heap is also supported,
 *
 * * size: minimizing footprint when statically linking by supporting dead-code
 *   stripping,
 *
 * * performance: provide optimized code invoked with minimal overhead, thus
 *   significantly faster than other libraries like OpenSSL,
 *
 * * testable: all algorithm implementations are directly accessible via their
 *   data structures at runtime, and
 *
 * * side-channel-resistant: A valgrind-based dynamic side channel analysis is
 *   applied to find time-variant code paths based on secret data.
 *
 * \section install_sec Installation
 *
 * \subsection lib_subsec Library Build
 *
 * If you want to build the leancrypto shared library, use the provided `Meson`
 * build system:
 *
 * 1. Setup: `meson setup build`
 *
 * 2. Compile: `meson compile -C build`
 *
 * 3. Test: `meson test -C build`
 *
 * 4. Install: `meson install -C build`
 *
 * \subsection linux_subsec Library Build for Linux Kernel
 *
 * The leancrypto library can also be built as an independent Linux kernel
 * module. This kernel module offers the same APIs and functions as the user
 * space version of the library. This implies that a developer wanting to
 * develop kernel and user space users of cryptographic mechanisms do not need
 * to adjust to a new API.
 *
 * Note: The user space and kernel space versions of leancrypto are fully
 * independent of each other. Neither requires the presence of the other for
 * full operation.
 *
 * To build the leancrypto Linux kernel module, use the `Makefile` in the
 * directory `linux_kernel`:
 *
 * 1. cd `linux_kernel`
 *
 * 2. make
 *
 * 3. the leancrypto library is provided with `leancrypto.ko`
 *
 * Note, the compiled test kernel modules are only provided for regression
 * testing and are not required for production use. Insert the kernel modules
 * and check `dmesg` for the results. Unload the kernel modules afterwards.
 *
 * The API specified by the header files installed as part of the
 * `meson install -C build` command for the user space library is applicable to
 * the kernel module as well. When compiling kernel code, the flag
 * `-DLINUX_KERNEL` needs to be set.
 *
 * For more details, see `linux_kernel/README.md` in the source code
 * distribution.
 *
 * \subsection win_subsec Library Build for Windows
 *
 * The `leancrypto` library can be built on Windows using
 * [MSYS2](https://www.msys2.org/). Once `MSYS2` is installed along with `meson`
 * and the `mingw` compiler, the standard compilation procedure outlined above
 * for `meson` can be used.
 *
 * The support for full assembler acceleration is enabled.
 *
 * \section devel_sec Development with Leancrypto
 *
 * The leancrypto API is documented in the exported header files. The only
 * header file that needs to be included in the target code is
 * `#include <leancrypto.h>`. This header file includes all algorithm-specific
 * header files for the compiled and supported algorithms.
 *
 * To fully understand the API, please consider the following base concept of
 * leancrypto: Different algorithm implementations are accessible via common
 * APIs. For example, different random number generator algorithms are
 * accessible via the RNG API. To ensure the common APIs act on the proper
 * algorithm, the caller must use algorithm-specific initialization functions.
 * The initialization logic returns a "cipher handle" that can be used with the
 * common API for all subequent operations.
 *
 * \note The various header files contain data structures which are provided
 * solely for the purpose that appropriate memory on stack can be allocated.
 * These data structures do not consititute an API in the sense that calling
 * applications should access member variables directly. If access to member
 * variables is desired, proper accessor functions are available. This implies
 * that changes to the data structures in newer versions of the library are not
 * considered as API changes!
 *
 * \note The leancrypto library performs an automated initialization during
 * its startup using constructors. If your execution environment does not offer
 * such constructors, or the library is compiled statically, the function
 * `lc_init` must be called by the consuming application before any leancrypto
 * API is invoked.
 */

#include <leancrypto/lc_memory_support.h>
#include <leancrypto/lc_hash.h>
#include <leancrypto/lc_ascon_hash.h>
#include <leancrypto/lc_aead.h>
#include <leancrypto/lc_cshake_crypt.h>
#include <leancrypto/lc_hash_crypt.h>
#include <leancrypto/lc_kmac_crypt.h>
#include <leancrypto/lc_ascon_aead.h>
#include <leancrypto/lc_ascon_lightweight.h>
#include <leancrypto/lc_ascon_keccak.h>
#include <leancrypto/lc_symhmac.h>
#include <leancrypto/lc_symkmac.h>
#include <leancrypto/lc_chacha20_poly1305.h>
#include <leancrypto/lc_aes_gcm.h>
#include <leancrypto/lc_bike_5.h>
#include <leancrypto/lc_bike_3.h>
#include <leancrypto/lc_bike_1.h>
#include <leancrypto/lc_bike.h>
#include <leancrypto/lc_x25519.h>
#include <leancrypto/lc_ed25519.h>
#include <leancrypto/lc_ed448.h>
#include <leancrypto/lc_x448.h>
#include <leancrypto/lc_chacha20_drng.h>
#include <leancrypto/lc_kmac256_drng.h>
#include <leancrypto/lc_cshake256_drng.h>
#include <leancrypto/lc_xdrbg.h>
#include <leancrypto/lc_hash_drbg.h>
#include <leancrypto/lc_hmac_drbg_sha512.h>
#include <leancrypto/lc_ctr_drbg.h>
#include <leancrypto/lc_drbg.h>
#include <leancrypto/lc_rng.h>
#include <leancrypto/lc_sha256.h>
#include <leancrypto/lc_sha512.h>
#include <leancrypto/lc_cshake.h>
#include <leancrypto/lc_sha3.h>
#include <leancrypto/lc_poly1305.h>
#include <leancrypto/lc_hqc_256.h>
#include <leancrypto/lc_hqc_192.h>
#include <leancrypto/lc_hqc_128.h>
#include <leancrypto/lc_hqc.h>
#include <leancrypto/ext_headers.h>
#include <leancrypto/lc_init.h>
#include <leancrypto/lc_memcmp_secure.h>
#include <leancrypto/lc_memcpy_secure.h>
#include <leancrypto/lc_memset_secure.h>
#include <leancrypto/lc_status.h>
#include <leancrypto/lc_uuid.h>
#include <leancrypto/lc_hkdf.h>
#include <leancrypto/lc_kdf_ctr.h>
#include <leancrypto/lc_kdf_fb.h>
#include <leancrypto/lc_kdf_dpi.h>
#include <leancrypto/lc_pbkdf2.h>
#include <leancrypto/lc_kyber_1024.h>
#include <leancrypto/lc_kyber_768.h>
#include <leancrypto/lc_kyber_512.h>
#include <leancrypto/lc_kyber.h>
#include <leancrypto/lc_hotp.h>
#include <leancrypto/lc_totp.h>
#include <leancrypto/lc_dilithium_87.h>
#include <leancrypto/lc_dilithium_65.h>
#include <leancrypto/lc_dilithium_44.h>
#include <leancrypto/lc_dilithium.h>
#include <leancrypto/lc_sphincs_shake_256s.h>
#include <leancrypto/lc_sphincs_shake_256f.h>
#include <leancrypto/lc_sphincs_shake_192s.h>
#include <leancrypto/lc_sphincs_shake_192f.h>
#include <leancrypto/lc_sphincs_shake_128s.h>
#include <leancrypto/lc_sphincs_shake_128f.h>
#include <leancrypto/lc_sphincs.h>
#include <leancrypto/lc_chacha20.h>
#include <leancrypto/lc_aes.h>
#include <leancrypto/lc_sym.h>
#include <leancrypto/lc_x509_parser.h>
#include <leancrypto/lc_x509_csr_parser.h>
#include <leancrypto/lc_x509_generator.h>
#include <leancrypto/lc_x509_csr_generator.h>
#include <leancrypto/lc_asn1.h>
#include <leancrypto/lc_x509_common.h>
#include <leancrypto/lc_pkcs7_common.h>
#include <leancrypto/lc_pkcs7_parser.h>
#include <leancrypto/lc_pkcs7_generator.h>
#include <leancrypto/lc_pkcs8_common.h>
#include <leancrypto/lc_pkcs8_parser.h>
#include <leancrypto/lc_pkcs8_generator.h>
#include <leancrypto/lc_pem.h>
#include <leancrypto/lc_hmac.h>
#include <leancrypto/lc_kmac.h>
