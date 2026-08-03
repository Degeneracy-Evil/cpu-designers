## 附录F：扩展历史说明

本附录包含了RISC-V ISA扩展在被批准时的理由。与ISA规范不同，本附录按时间顺序排列，以便传达每个扩展在被批准时的动机和架构推理。对于在本附录构思之前（约2025年）批准的扩展，理由将随时间推移添加。在理由未被记录的情况下，作者和编辑将从历史记录中综合出来。

## F.1. "Zihintpause"扩展用于暂停提示

PAUSE指令向hart提示它应该暂时降低其执行速率。它通常用于在轮询时节省能量和执行资源，例如在等待自旋锁变为空闲时。

围绕此扩展的许多辩论集中在是否应该提供一个类似于x86的MONITOR/MWAIT的设施。我们得出结论，即使这样的设施被定义给RISC-V，它也不会取代PAUSE。PAUSE在轮询非内存事件时、轮询多个事件时，或当软件不知道它在轮询什么事件时更合适。（也许令人惊讶的是，后一种情况普遍存在，部分原因是它是Linux内核的 `cpu_relax` API期望的机制。）

## F.2. "Zicond"扩展用于整数条件操作

用条件选择或条件移动指令替换不可预测的分支可以减轻一类代价高昂的分支误预测。不幸的是，条件选择指令需要三个源操作数。这些指令是出于其他原因包含三源整数指令的ISA的逻辑补充，但在其他情况下代价太高。

一些ISA提供了条件移动指令，这些指令消耗更少的编码空间，并在简单微架构中避免了额外的寄存器读取。不幸的是，在寄存器重命名的微架构中，这些指令产生的代价类似于条件选择，或需要额外的微架构结构和微操作发射约束。

Zicond扩展被定义为解决与条件选择和条件移动相同的问题，但对复杂微架构的增量成本非常小。它提供了条件零指令，该指令读取两个源操作数，并根据第二个操作数是否为零，产生第一个操作数或零。这些指令可用作三指令序列的一部分来合成条件选择。几种常见的条件执行惯用语句只需要两条指令，就像条件选择或移动一样，包括条件加法、减法以及按位AND、OR和XOR。

包含了两个条件零指令：一个在比较数为零时写入零，另一个在比较数非零时写入零。考虑过执行与零大小比较的变体，但最终因缺乏足够的定量证明而被排除。

## F.3. "Zacas"扩展用于原子比较并交换（CAS）指令

虽然XLEN宽度数据的比较并交换可以使用LR/SC完成，但CAS原子指令比LR/SC更好地扩展到高度并行系统。许多无锁算法，如无锁队列，需要操作指针变量。简单的CAS操作可能不足以防范此类操作指针变量的算法中通常所称的ABA问题。为了避免ABA问题，算法将引用计数器与指针变量关联，并使用四字比较并交换（同时对指针和计数器）执行更新。

双字和四字CAS指令支持实现ABA问题避免的算法。

CAS指令支持C++11原子比较和交换操作。

## F.4. "Zabha"扩展用于字节和半字原子内存操作，版本1.0

A扩展为 _字_、_双字_ 和 _四字_（仅用于 `AMOCAS`）提供原子内存操作（AMO）指令。缺乏对子字数据类型的原子操作需要模拟策略。对于按位操作，此模拟可以通过字大小的按位AMO*指令执行。对于非按位操作，可以使用字大小的 `LR` / `SC` 指令实现模拟。

这种模拟方法产生了几个局限性：

1. 在大规模或非一致内存访问（NUMA）配置的系统中，基于 `LR` / `SC` 的模拟引入了与可扩展性和公平性相关的问题，特别是在高争用条件下。
2. 通过在非幂等IO内存区域上使用更宽的AMO*指令来模拟较窄的AMO，可能导致意外的副作用。
3. 使用更宽的AMO*指令来模拟较窄的AMO，存在激活无关断点或观察点的风险。
4. 在缺少对子字原子操作的原生支持情况下，编译器通常采用内联代码序列来提供所需的模拟。这种做法导致代码大小增加，从而影响系统性能和内存利用率。

Zabha扩展通过为RISC-V非特权ISA添加对 _字节_ 和 _半字_ 原子内存操作的支持来解决这些局限性。

## 索引

@

(调用约定标准), 154 (压缩格式), 154 (压缩. C.BREAKPOINTINSTR), 162 (压缩. C.CA), 161 (压缩. C.CR), 161 (压缩. C.DIINST), 162 (压缩. C.NOPINSTR), 162 (寄存器源说明符c-ext), 154

A

原子操作 未对齐, 85

B 双端, 19

C 压缩 C.ANDI, 161 C.SRLI C.SRAI, 160 cb-format load and store, 159 CI, 160 CIW, 160 cj-format load and store, 158 cr-format load and store, 158 cs-format load and store, 157 integer constant generation, 159 integer register-immediate, 159 register-based load and store, 157 core accelerator, 14 cluster multiprocessors, 14 component, 14 extensions coprocessor, 14

D

decomposition, 86 design high performance, 85 scalable, 85 double-precision floating point, 121 to single-precision, 123

E

endian bi-, 19 little and big, 19 exceptions, 20

F

FENCE, 85 FENCE.I finer-grained, 46 forward compatibility, 46 synchronization, 45 floating point convert and move, 123 double precision, 121 fused multiply-add, 116 load and store, 122 floating-point classification, 119 classify, 124 compare, 124 conversion, 117 exception flag, 114 requirements, 121 supported precisions, 121

H

hart execution environment, 15 HINT PAUSE, 59

I

ILEN, 19 IMAFD, 19 interrupts, 20 ISA definition, 13

M

memory access implicit and explicit, 18, 18 MUL DIV, 65 div by zero, 66 DIVU, 65 MULH, 65 MULHSU, 65 MULHU, 65 Zmmul, 66

N

NaN generation, 115 propagation, 115

U

unspecified behaviors, 21 values, 21

O

operations memory, 85 subnormal, 115

P

PAUSE duration, 59 encoding, 59 energy consumption, 59 HINT, 59 LR/RC sequences, 59

R RV32E design, 40 difference from RV32I, 40 RV64I compares, 41 HINT, 43 LD, 43 LUI, 42 RV64I-only, 41 shifts, 41 SLLI, 41 SRAIW, 41 SRLIW, 41 RV64I-only ADDW, 42 SLLW, 42 SRAW, 42 SRLW, 42 SUBW, 42 RVWMO, 85

S SFENCE, 85 single-precision to double-precision, 123 store instruction word not included, 45

T tininess handling, 115 traps, 20

## 参考文献

_RISC-V ELF psABI Specification_ . github.com/riscv/riscv-elf-psabi-doc/ .

_RISC-V Assembly Programmer's Manual_ . github.com/riscv/riscv-asm-manual .

_SAIL ISA Specification Language_ . github.com/rems-project/sail

_ANSI/IEEE Std 754-2008, IEEE standard for floating-point arithmetic_ . (2008). "Institute of Electrical and Electronic Engineers".

_GB/T 32905-2016: SM3 Cryptographic Hash Algorithm_ . (2016). Also GM/T 0004-2012. Standardization Administration of China. <www.gmbz.org.cn/upload/2018-07-24/1532401392982079739.pdf>

_GB/T 32907-2016: SM4 Block Cipher Algorithm_ . (2016). Also GM/T 0002-2012. Standardization Administration of China. <www.gmbz.org.cn/upload/2018-04-04/1522788048733065051.pdf>

AMD. (2017). _AMD Random Number Generator_ . Advanced Micro Devices. <www.amd.com/system/files/> TechDocs/amd-random-number-generator.pdf

Amdahl, G. M., Blaauw, G. A., & F. P. Brooks, J. (1964). Architecture of the IBM System/360. _IBM Journal of R. & D._ , _8_ (2).

Anderson, R. J. (2020). _Security engineering - a guide to building dependable distributed systems (3. ed.)_ . Wiley. <www.cl.cam.ac.uk/> rja14/book.html

Aoki, K., Ichikawa, T., Kanda, M., Matsui, M., Moriai, S., Nakajima, J., & Tokita, T. (2000). Camellia: A 128bit block cipher suitable for multiple platforms—design andanalysis. _International Workshop on Selected Areas in Cryptography_ , 39–56.

ARM. (2017). _ARM TrustZone True Random Number Generator: Technical Reference Manual_ . ARM. infocenter.arm.com/help/index.jsp?topic=/com.arm.doc.100976_0000_00_en

Bak, P. (1986). The Devil's Staircase. _Phys. Today_ , _39_ (12), 38–45. doi.org/10.1063/1.881047

Banik, S., Bogdanov, A., Isobe, T., Shibutani, K., Hiwatari, H., Akishita, T., & Regazzoni, F. (2015). Midori: A block cipher for low energy. _International Conference on the Theory and Application of Cryptology and Information Security_ , 411–436.

Banik, S., Pandey, S. K., Peyrin, T., Sasaki, Y., Sim, S. M., & Todo, Y. (2017). GIFT: a small present. _International Conference on Cryptographic Hardware and Embedded Systems_ , 321–345.

Bardou, R., Focardi, R., Kawamoto, Y., Simionato, L., Steel, G., & Tsay, J.-K. (2012). Efficient Padding Oracle Attacks on Cryptographic Hardware. In R. Safavi-Naini & R. Canetti (Eds.), _Advances in Cryptology - CRYPTO 2012 - 32nd Annual Cryptology Conference, Santa Barbara, CA, USA, August 19-23, 2012. Proceedings_ (Vol. 7417, pp. 608–625). Springer. doi.org/10.1007/978-3-642-32009-5_36

Barker, E., & Kelsey, J. (2015). _Recommendation for Random Number Generation Using Deterministic Random Bit Generators_ . NIST Special Publication SP 800-90A Revision 1. doi.org/10.6028/NIST.SP.800-90Ar1

Barker, E., Kelsey, J., Roginsky, A., Turan, M. S., Buller, D., & Kaufer, A. (2021). _Recommendation for Random Bit Generator (RBG) Constructions_ . Draft NIST Special Publication SP 800-90C.

Baudet, M., Lubicz, D., Micolod, J., & Tassiaux, A. (2011). On the Security of Oscillator-Based Random Number Generators. _J. Cryptology_ , _24_ (2), 398–425. doi.org/10.1007/s00145-010-9089-3

Beierle, C., Jean, J., Kölbl, S., Leander, G., Moradi, A., Peyrin, T., Sasaki, Y., Sasdrich, P., & Sim, S. M. (2016). The SKINNY family of block ciphers and its low-latency variant MANTIS. _Annual International Cryptology Conference_ , 123–153.

Blum, L., Blum, M., & Shub, M. (1986). A Simple Unpredictable Pseudo-Random Number Generator. _SIAM J. Comput._ , _15_ (2), 364–383. doi.org/10.1137/0215025

Blum, M. (1986). Independent unbiased coin flips from a correlated biased source – A finite state Markov chain. _Combinatorica_ , _6_ (2), 97–108. doi.org/10.1007/BF02579167

Bogdanov, A., Knudsen, L. R., Leander, G., Paar, C., Poschmann, A., Robshaw, M. J. B., Seurin, Y., & Vikkelsoe, C. (2007). PRESENT: An ultra-lightweight block cipher. _International Workshop on Cryptographic Hardware and Embedded Systems_ , 450–466.

Buchholz, W. (1962). _Planning a computer system: Project Stretch_ . McGraw-Hill Book Company.

Criteria, C. (2017). _Common Methodology for Information Technology Security Evaluation: Evaluation methodology_ . Specification: Version 3.1 Revision 5. commoncriteriaportal.org/cc/

Dworkin, M. (2007). _Recommendation for Block Cipher Modes of Operation: Galois/Counter Mode (GCM) and GMAC_ . NIST Special Publication SP 800-38D. doi.org/10.6028/NIST.SP.800-38D

Evtyushkin, D., & Ponomarev, D. V. (2016). Covert Channels through Random Number Generator: Mechanisms, Capacity Estimation and Mitigations. In E. R. Weippl, S. Katzenbeisser, C. Kruegel, A. C. Myers, & S. Halevi (Eds.), _Proceedings of the 2016 ACM SIGSAC Conference on Computer and Communications Security, Vienna, Austria, October 24-28, 2016_ (pp. 843–857). ACM. doi.org/10.1145/2976749.2978374

Gharachorloo, K., Lenoski, D., Laudon, J., Gibbons, P., Gupta, A., & Hennessy, J. (1990). Memory Consistency and Event Ordering in Scalable Shared-Memory Multiprocessors. _In Proceedings of the 17th Annual International Symposium on Computer Architecture_ , 15–26.

Grover, L. K. (1996). A Fast Quantum Mechanical Algorithm for Database Search. _Proceedings of the TwentyEighth Annual ACM Symposium on Theory of Computing_ , 212–219. doi.org/10.1145/237814.237866

Hajimiri, A., & Lee, T. H. (1998). A general theory of phase noise in electrical oscillators. _IEEE Journal of Solid-State Circuits_ , _33_ (2), 179–194. doi.org/10.1109/4.658619

Hajimiri, A., Limotyrakis, S., & Lee, T. H. (1999). Jitter and phase noise in ring oscillators. _IEEE Journal of Solid-State Circuits_, _34_ (6), 790–804. doi.org/10.1109/4.766813

Hamburg, M., Kocher, P., & Marson, M. E. (2012). _Analysis of Intel's Ivy Bridge Digital Random Number Generator_ . Technical Report, Cryptography Research (Prepared for Intel).

Heil, T. H., & Smith, J. E. (1996). _Selective Dual Path Execution_ . University of Wisconsin - Madison.

Hurley-Smith, D., & Hernández-Castro, J. C. (2020). Quantum Leap and Crash: Searching and Finding Bias in Quantum Random Number Generators. _ACM Transactions on Privacy and Security_ , _23_ (3), 1–25. doi.org/ 10.1145/3403643

ISO. (2016). _Information technology – Security techniques – Testing methods for the mitigation of non-invasive attack classes against cryptographic modules_ (Standard ISO/IEC 17825:2016; Issue ISO/IEC 17825:2016). International Organization for Standardization.

ISO/IEC. (2018). _IT Security techniques – Hash-functions – Part 3: Dedicated hash-functions_ . ISO/IEC Standard 10118-3:2018.

ISO/IEC. (2018). _Information technology – Security techniques – Encryption algorithms – Part 3: Block ciphers. Amendment 2: SM4_ . ISO/IEC Standard 18033-3:2010/DAmd 2 (en).

ITU. (2019). _Quantum noise random number generator architecture_ . International Telecommunications Union. <www.itu.int/rec/T-REC-X.1702-201911-I/en>

Jaques, S., Naehrig, M., Roetteler, M., & Virdia, F. (2020). Implementing Grover Oracles for Quantum Key Search on AES and LowMC. In A. Canteaut & Y. Ishai (Eds.), _Advances in Cryptology - EUROCRYPT 2020 - 39th Annual International Conference on the Theory and Applications of Cryptographic Techniques, Zagreb, Croatia, May 10-14, 2020, Proceedings, Part II_ (Vol. 12106, pp. 280–310). Springer. doi.org/10.1007/978-3030-45724-2_10

Karaklajic, D., Schmidt, J.-M., & Verbauwhede, I. (2013). Hardware Designer's Guide to Fault Attacks. _IEEE Trans. Very Large Scale Integr. Syst._ , _21_ (12), 2295–2306. doi.org/10.1109/TVLSI.2012.2231707

Katevenis, M. G. H., Sherburne, R. W., Jr., Patterson, D. A., & Séquin, C. H. (1983, August). The RISC II micro-architecture. _Proceedings VLSI 83 Conference_ .

Killmann, W., & Schindler, W. (2001). _A Proposal for: Functionality classes and evaluation methodology for true (physical) random number generators_ . BSI. <www.bsi.bund.de/SharedDocs/Downloads/DE/BSI/> Zertifizierung/Interpretationen/ AIS_31_Functionality_classes_evaluation_methodology_for_true_RNG_e.html

Killmann, W., & Schindler, W. (2011). _A Proposal for: Functionality classes for random number generators_ . BSI. <www.bsi.bund.de/SharedDocs/Downloads/DE/BSI/Zertifizierung/Interpretationen/> AIS_31_Functionality_classes_for_random_number_generators_e.html

Kim, H., Mutlu, O., Stark, J., & Patt, Y. N. (2005). Wish Branches: Combining Conditional Branching and Predication for Adaptive Predicated Execution. _Proceedings of the 38th Annual IEEE/ACM International Symposium on Microarchitecture_ , 43–54.

Klauser, A., Austin, T., Grunwald, D., & Calder, B. (1998). Dynamic Hammock Predication for NonPredicated Instruction Set Architectures. _Proceedings of the 1998 International Conference on Parallel Architectures and Compilation Techniques_ .

Kwon, D., Kim, J., Park, S., Sung, S. H., Sohn, Y., Song, J. H., Yeom, Y., Yoon, E.-J., Lee, S., Lee, J., & others. (2003). New block cipher: ARIA. _International Conference on Information Security and Cryptology_ , 432–445.

Lacharme, P. (2008). Post-Processing Functions for a Biased Physical Random Number Generator. In K. Nyberg (Ed.), _Fast Software Encryption, 15th International Workshop, FSE 2008, Lausanne, Switzerland, February 10-13, 2008, Revised Selected Papers_ (Vol. 5086, pp. 334–342). Springer. doi.org/10.1007/978-3540-71039-4_21

Lee, D. D., Kong, S. I., Hill, M. D., Taylor, G. S., Hodges, D. A., Katz, R. H., & Patterson, D. A. (1989). A VLSI Chip Set for a Multiprocessor Workstation–Part I: An RISC Microprocessor with Coprocessor Interface and Support for Symbolic Processing. _IEEE JSSC_ , _24_ (6), 1688–1698.

Lee, R. B., Shi, Z. J., Yin, Y. L., Rivest, R. L., & Robshaw, M. J. B. (2004). On permutation operations in cipher design. _International Conference on Information Technology: Coding and Computing, 2004. Proceedings. ITCC 2004._ , _2_ , 569–577.

Liberty, J. S., Barrera, A., Boerstler, D. W., Chadwick, T. B., Cottier, S. R., Hofstee, H. P., Rosser, J. A., & Tsai, M. L. (2013). True hardware random number generation implemented in the 32-nm SOI POWER7+ processor. _IBM J. Res. Dev._ , _57_ (6). doi.org/10.1147/JRD.2013.2279599

Markettos, A. T., & Moore, S. W. (2009). The Frequency Injection Attack on Ring-Oscillator-Based True Random Number Generators. In C. Clavier & K. Gaj (Eds.), _Cryptographic Hardware and Embedded Systems - CHES 2009, 11th International Workshop, Lausanne, Switzerland, September 6-9, 2009, Proceedings_ (Vol. 5747, pp. 317–331). Springer. doi.org/10.1007/978-3-642-04138-9_23

Marshall, B., Newell, G. R., Page, D., Saarinen, M.-J. O., & Wolf, C. (2020). The design of scalar AES Instruction Set Extensions for RISC-V. _IACR Transactions on Cryptographic Hardware and Embedded Systems_ , _2021_ (1), 109–136. doi.org/10.46586/tches.v2021.i1.109-136

Marshall, B., Page, D., & Pham, T. (2019). _XCrypto: a cryptographic ISE for RISC-V_ (No.1.0.0; Issue 1.0.0). github.com/scarv/xcrypto

Mechalas, J. P. (2018). _Intel Digital Random Number Generator (DRNG) Software Implementation Guide_ . Intel Technical Report, Version 2.1. software.intel.com/content/www/us/en/develop/articles/intel-digitalrandom-number-generator-drng-software-implementation-guide.html

Michael, M. M., & Scott, M. L. (1996). Simple, Fast, and Practical Non-Blocking and Blocking Concurrent Queue Algorithms. _Proceedings of the Fifteenth Annual ACM Symposium on Principles of Distributed Computing_ , 267–275. doi.org/10.1145/248052.248106

Moghimi, D., Sunar, B., Eisenbarth, T., & Heninger, N. (2020). TPM-FAIL: TPM meets Timing and Lattice Attacks. _29th USENIX Security Symposium (USENIX Security 20)_ , To appear. <www.usenix.org/conference/> usenixsecurity20/presentation/moghimi-tpm

Müller, S. (2020). _Documentation and Analysis of the Linux Random Number Generator, Version 3.6_ . Prepared for BSI by atsec information security GmbH. <www.bsi.bund.de/SharedDocs/Downloads/EN/BSI/> Publications/Studies/LinuxRNG/LinuxRNG_EN.pdf

NIST. (2001). _Advanced Encryption Standard (AES)_ . Federal Information Processing Standards Publication FIPS 197. doi.org/10.6028/NIST.FIPS.197

NIST. (2013). _Digital Signature Standard (DSS)_ . Federal Information Processing Standards Publication FIPS 186-4. doi.org/10.6028/NIST.FIPS.186-4

NIST. (2015). _Secure Hash Standard (SHS)_ . Federal Information Processing Standards Publication FIPS 1804. doi.org/10.6028/NIST.FIPS.180-4

NIST. (2015). _SHA-3 Standard: Permutation-Based Hash and Extendable-Output Functions_ . Federal Information Processing Standards Publication FIPS 202. doi.org/10.6028/NIST.FIPS.202

NIST. (2016). _Submission Requirements and Evaluation Criteria for the Post-Quantum Cryptography Standardization Process_ . Official Call for Proposals, National Institute for Standards and Technology. csrc.nist.gov/groups/ST/post-quantum-crypto/documents/call-for-proposals-final-dec-2016.pdf

NIST. (2019). _Security Requirements for Cryptographic Modules_ . Federal Information Processing Standards Publication FIPS 140-3. doi.org/10.6028/NIST.FIPS.140-3

NIST, & CCCS. (2021). _Implementation Guidance for FIPS 140-3 and the Cryptographic Module Validation Program_ . CMVP. csrc.nist.gov/CSRC/media/Projects/cryptographic-module-validation-program/ documents/fips%20140-3/FIPS%20140-3%20IG.pdf

NSA/CSS. (2015). _Commercial National Security Algorithm Suite_ . apps.nsa.gov/iaarchive/programs/iadinitiatives/cnsa-suite.cfm

Pan, H., Hindman, B., & Asanović, K. (2009, March). Lithe: Enabling Efficient Composition of Parallel Libraries. _Proceedings of the 1st USENIX Workshop on Hot Topics in Parallelism (HotPar '09)_ .

Pan, H., Hindman, B., & Asanović, K. (2010, June). Composing Parallel Software Efficiently with Lithe. _31st Conference on Programming Language Design and Implementation_ .

Patterson, D. A., & Séquin, C. H. (1981). RISC I: A Reduced Instruction Set VLSI Computer. _ISCA_ , 443–458.

Rajwar, R., & Goodman, J. R. (2001). Speculative lock elision: enabling highly concurrent multithreaded execution. _Proceedings of the 34th Annual ACM/IEEE International Symposium on Microarchitecture_ , 294–305.

Rambus. (2020). _TRNG-IP-76 / EIP-76 Family of FIPS Approved True Random Generators_ . Commercial Crypto IP. Formerly (2017) available from Inside Secure. <www.rambus.com/security/crypto-accelerator-hardwarecores/basic-crypto-blocks/trng-ip-76/>

Roux, P. (2014). Innocuous Double Rounding of Basic Arithmetic Operations. _Journal of Formalized Reasoning_ , _7_ (1), 131–142. doi.org/10.6092/issn.1972-5787/4359

Saarinen, M.-J. O. (2020). _Lightweight SHA ISA_ . github.com/mjosaarinen/lwsha_isa .

Saarinen, M.-J. O. (2020). _Lightweight AES ISA_ . github.com/mjosaarinen/lwaes_isa .

Saarinen, M.-J. O. (2021). _On Entropy and Bit Patterns of Ring Oscillator Jitter_ . Preprint. arxiv.org/abs/ 2102.02196

Shor, P. W. (1994). Algorithms for quantum computation: Discrete logarithms and factoring. _35th Annual Symposium on Foundations of Computer Science, Santa Fe, New Mexico, USA, 20-22 November 1994_ , 124–134. doi.org/10.1109/SFCS.1994.365700

Sinharoy, B., Kalla, R., Starke, W. J., Le, H. Q., Cargnoni, R., Van Norstrand, J. A., Ronchetti, B. J., Stuecheli, J., Leenstra, J., Guthrie, G. L., Nguyen, D. Q., Blaner, B., Marino, C. F., Retter, E., & Williams, P. (2011). IBM POWER7 multicore server processor. _IBM Journal of Research and Development_ , _55_ (3), 1–1.

Suzaki, T., Minematsu, K., Morioka, S., & Kobayashi, E. (2012). TWINE: A Lightweight Block Cipher for Multiple Platforms. _International Conference on Selected Areas in Cryptography_ , 339–354.

Thornton, J. E. (1965). Parallel Operation in the Control Data 6600. _Proceedings of the October 27-29, 1964, Fall Joint Computer Conference, Part II: Very High Speed Computer Systems_ , 33–40.

Tremblay, M., Chan, J., Chaudhry, S., Conigliaro, A. W., & Tse, S. S. (2000). The MAJC Architecture: A Synthesis of Parallelism and Scalability. _IEEE Micro_ , _20_ (6), 12–25.

Tseng, J., & Asanović, K. (2000). Energy-Efficient Register Access. _Proc. of the 13th Symposium on Integrated Circuits and Systems Design_ , 377–384.

Turan, M. S., Barker, E., Kelsey, J., McKay, K. A., Baish, M. L., & Boyle, M. (2018). _Recommendation for the Entropy Sources Used for Random Bit Generation_ . NIST Special Publication SP 800-90B. doi.org/10.6028/ NIST.SP.800-90B

Ungar, D., Blau, R., Foley, P., Samples, D., & Patterson, D. (1984). Architecture of SOAR: Smalltalk on a RISC. _ISCA_ , 188–197.

Valtchanov, B., Fischer, V., Aubert, A., & Bernard, F. (2010). Characterization of randomness sources in ring oscillator-based true random number generators in FPGAs. In E. Gramatová, Z. Kotásek, A. Steininger, H. T. Vierhaus, & H. Zimmermann (Eds.), _13th IEEE International Symposium on Design and Diagnostics of Electronic Circuits and Systems, DDECS 2010, Vienna, Austria, April 14-16, 2010_ (pp. 48–53). IEEE Computer Society. doi.org/10.1109/DDECS.2010.5491819

Varchola, M., & Drutarovský, M. (2010). New High Entropy Element for FPGA Based True Random Number Generators. In S. Mangard & F.-X. Standaert (Eds.), _Cryptographic Hardware and Embedded Systems, CHES 2010, 12th International Workshop, Santa Barbara, CA, USA, August 17-20, 2010. Proceedings_ (Vol. 6225, pp. 351–365). Springer. doi.org/10.1007/978-3-642-15031-9_24

von Neumann, J. (1951). Various Techniques Used in Connection with Random Digits. In A. S. Householder, G. E. Forsythe, & H. H. Germond (Eds.), _Monte Carlo Method_ (Vol. 12, pp. 36–38). US Government Printing Office. mcnp.lanl.gov/pdf_files/nbs_vonneumann.pdf

Waterman, A. (2011). _Improving Energy Efficiency and Reducing Code Size with RISC-V Compressed_ (Issue UCB/EECS-2011-63) [Master's thesis]. University of California, Berkeley.

Waterman, A. (2016). _Design of the RISC-V Instruction Set Architecture_ (Issue UCB/EECS-2016-1) [PhD thesis]. University of California, Berkeley.

Waterman, A., Lee, Y., Patterson, D. A., & Asanović, K. (2011). _The RISC-V Instruction Set Manual, Volume I: Base User-Level ISA_ (UCB/EECS-2011-62; Issue UCB/EECS-2011-62). EECS Department, University of California, Berkeley.

Waterman, A., Lee, Y., Patterson, D. A., & Asanović, K. (2014). _The RISC-V Instruction Set Manual, Volume I: Base User-Level ISA Version 2.0_ (UCB/EECS-2014-54; Issue UCB/EECS-2014-54). EECS Department, University of California, Berkeley.

Zhang, W., Bao, Z., Lin, D., Rijmen, V., Yang, B., & Verbauwhede, I. (2015). RECTANGLE: a bit-slice lightweight block cipher suitable for multiple platforms. _Science China Information Sciences_ , _58_ (12), 1–15.
