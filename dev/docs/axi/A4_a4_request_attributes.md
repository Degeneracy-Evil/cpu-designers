# A4 Request attributes

Chapter A4
Request attributes
This chapter describes request attributes that indicate how the request should be handled by downstream
components. It contains the following sections:
• A4.1 Subordinate types
• A4.2 Memory attributes
• A4.3 Memory types
• A4.4 Protocol errors
• A4.5 Protection attributes
• A4.6 Memory Encryption Contexts
• A4.7 Multiple region interfaces
• A4.8 QoS signaling
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
66


Chapter A4. Request attributes
A4.1. Subordinate types
A4.1 Subordinate types
Subordinates are classified as either a Memory Subordinate or a Peripheral Subordinate.
Memory Subordinate
A Memory Subordinate is required to handle all transaction types correctly.
Peripheral Subordinate
A Peripheral Subordinate has an IMPLEMENTATION DEFINED method of access. Typically, the method of access is
defined in the component data sheet that describes the transaction types that the Subordinate handles correctly.
Any access to the Peripheral Subordinate that is not part of the IMPLEMENTATION DEFINED method of access
must complete, in compliance with the protocol. However, when such an access has been made, there is no
requirement that the Peripheral Subordinate continues to operate correctly. The Subordinate is only required to
continue to complete further transactions in a protocol compliant manner.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
67


Chapter A4. Request attributes
A4.2. Memory attributes
A4.2 Memory attributes
This section describes the attributes that determine how a request should be treated by system components such as
caches, buffers, and memory controllers.
The AWCACHE and ARCACHE signals specify the memory attributes of a request. They control:
• How a transaction progresses through the system.
• How any system-level buffers and caches handle the transaction.
In this specification, the term AxCACHE refers collectively to the AWCACHE and ARCACHE signals. Table
A4.1 describes the AWCACHE and ARCACHE signals.
Table A4.1: AxCACHE signals
Name
Width
Default
Description
AWCACHE,
ARCACHE
4
0x0
The memory attributes of a request control how a
transaction progresses through the system and how
caches and buffers handle the request.
The CACHE_Present property is used to determine if the AxCACHE signals are present on an interface.
Table A4.2: CACHE_Present property
CACHE_Present
Default
Description
True
Y
AWCACHE and ARCACHE are present.
False
AWCACHE and ARCACHE are not
present.
AWCACHE bits are encoded as:
• [0] Bufferable
• [1] Modifiable
• [2] Other Allocate
• [3] Allocate
ARCACHE bits are encoded as:
• [0] Bufferable
• [1] Modifiable
• [2] Allocate
• [3] Other Allocate
Note that the Allocate and Other Allocate bits are in different positions for read and write requests.
A4.2.1
Bufferable, AxCACHE[0]
For write transactions:
• If the Bufferable bit is deasserted and AWCACHE[3:2] are both deasserted, the write response indicates that
the data has reached its final destination.
• If the Bufferable bit is asserted, the write response can be sent from an intermediate point, when the
observability requirements have been met.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
68


Chapter A4. Request attributes
A4.2. Memory attributes
For read transactions where ARCACHE[3:2] are deasserted (Non-cacheable) and ARCACHE[1] is asserted
(Modifiable):
• If the Bufferable bit is deasserted, the read data must be obtained from the final destination.
• If the Bufferable bit is asserted, the read data can be obtained from the final destination or from a write that is
progressing to the final destination.
For other combinations of ARCACHE[3:1], the Bufferable bit has no effect.
A4.2.2
Modifiable, AxCACHE[1]
When AxCACHE[1] is asserted, the transaction is Modifiable which indicates that the characteristics of the
transaction can be modified. When AxCACHE[1] is deasserted, the transaction is Non-modifiable.
The following sections describe the properties of Non-modifiable and Modifiable transactions.
Non-modifiable transactions
A Non-modifiable transaction must not be split into multiple transactions or merged with other transactions.
In a Non-modifiable transaction, the parameters that are shown in Table A4.3 must not be changed.
Table A4.3: Parameters fixed as Non-modifiable
Parameter
Signals
Address
AxADDR, and therefore AxREGION
Size
AxSIZE
Length
AxLEN
Burst type
AxBURST
Protection attributes
AxPROT, AxNSE, AxPAS, AxINST, AxPRIV
The AxCACHE attribute can only be modified to convert a transaction from being Bufferable to Non-bufferable.
No other change to AxCACHE is permitted.
The transaction ID and the QoS values can be modified.
A Non-modifiable transaction with Length greater than 16 can be split into multiple transactions. Each resulting
transaction must meet the requirements that are given in this subsection, except that:
• The Length is reduced.
• The address of the generated transactions is adapted appropriately.
A Non-modifiable transaction that is an exclusive access, as indicated by AxLOCK asserted, is permitted to have
the Size, AxSIZE, and Length, AxLEN, modified if the total number of bytes accessed remains the same.
There are circumstances where it is not possible to meet the requirements of Non-modifiable transactions. For
example, when downsizing to a data width narrower than required by Size, the transaction must be modified.
A component that performs such an operation can optionally include an IMPLEMENTATION DEFINED mechanism
to indicate that a modification has occurred. This mechanism can assist with software debug.
Modifiable transactions
A Modifiable transaction can be modified in the following ways:
• A transaction can be broken into multiple transactions.
• Multiple transactions can be merged into a single transaction.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
69


Chapter A4. Request attributes
A4.2. Memory attributes
• A read transaction can fetch more data than required.
• A write transaction can access a larger address range than required using the WSTRB signals to ensure that
only the appropriate locations are updated.
• In each generated transaction, the following attributes can be modified:
– Address, AxADDR
– Size, AxSIZE
– Length, AxLEN
– Burst type, AxBURST
The following must not be changed:
• Exclusive access indicator: AxLOCK
• The access and address space attributes: AxPROT, AxINST, AxPRIV, AxNSE, AxPAS,
AxMMUPASUNKNOWN.
AxCACHE can be modified, but any modification must ensure that the visibility of transactions by other
components is not reduced, either by preventing propagation of transactions to the required point, or by changing
the need to look up a transaction in a cache. Any modification to the memory attributes must be consistent for all
transactions to the same address range.
The transaction ID and QoS values can be modified.
No transaction modification is permitted that:
• Causes accesses to a different 4KB address space than that of the original transaction.
• Causes a single access to a single-copy atomicity sized region to be performed as multiple accesses.
See A6.1 Single-copy atomicity size.
A4.2.3
Allocate and Other Allocate, AxCACHE[2], and AxCACHE[3]
If the Allocate bit is asserted:
• The data might have been previously allocated, so the line must be looked up in a cache.
• It is recommended that the data is allocated into a cache for future use.
If the Other Allocate bit is asserted:
• The data might have been previously allocated, so the line must be looked up in a cache.
• It is not recommended that the data is allocated as it is not expected to be accessed again.
If Allocate and Other Allocate are both deasserted, the request is not required to look up in any cache.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
70


Chapter A4. Request attributes
A4.3. Memory types
A4.3 Memory types
The combination of AxCACHE signals indicates a memory type. Table A4.4 shows the memory type encodings.
Values in brackets are permitted but not preferred. Values that are not shown in the table are reserved.
Table A4.4: Memory type encoding
ARCACHE[3:0]
AWCACHE[3:0]
Memory type
0b0000
0b0000
Device Non-bufferable
0b0001
0b0001
Device Bufferable
0b0010
0b0010
Normal Non-cacheable Non-bufferable
0b0011
0b0011
Normal Non-cacheable Bufferable
0b1010
0b0110
Write-Through No-Allocate
0b1110 (0b0110)
0b0110
Write-Through Read-Allocate
0b1010
0b1110 (0b1010)
Write-Through Write-Allocate
0b1110
0b1110
Write-Through Read and Write-Allocate
0b1011
0b0111
Write-Back No-Allocate
0b1111 (0b0111)
0b0111
Write-Back Read-Allocate
0b1011
0b1111 (0b1011)
Write-Back Write-Allocate
0b1111
0b1111
Write-Back Read and Write-Allocate
A4.3.1
Memory type requirements
This section specifies the required behavior for each of the memory types.
Device Non-bufferable
The required behavior for Device Non-bufferable memory is:
• The write response must be obtained from the final destination.
• Read data must be obtained from the final destination.
• Transactions are Non-modifiable, see A4.2.2 Non-modifiable transactions.
• Read data must not be prefetched.
• Write transactions must not be merged.
Device Bufferable
The required behavior for the Device Bufferable memory type is:
• The write response can be obtained from an intermediate point.
• Write transactions must be made visible at the final destination in a timely manner.
• Read data must be obtained from the final destination.
• Transactions are Non-modifiable, see A4.2.2 Non-modifiable transactions.
• Read data must not be prefetched.
• Write transactions must not be merged.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
71


Chapter A4. Request attributes
A4.3. Memory types
Both Device memory types are Non-modifiable. In this specification, the terms Device memory and
Non-modifiable memory are interchangeable.
For read transactions, there is no difference in the required behavior for Device Non-bufferable and Device
Bufferable memory types.
Normal Non-cacheable Non-bufferable
The required behavior for the Normal Non-cacheable Non-bufferable memory type is:
• The write response must be obtained from the final destination.
• Read data must be obtained from the final destination.
• Transactions are Modifiable, see A4.2.2 Modifiable transactions.
• Write transactions can be merged.
Normal Non-cacheable Bufferable
The required behavior for the Normal Non-cacheable Bufferable memory type is:
• The write response can be obtained from an intermediate point.
• Write transactions must be made visible at the final destination in a timely manner, as defined in the glossary.
There is no mechanism to determine when a write transaction is visible at its final destination.
• Read data must be obtained from either:
– The final destination.
– A write transaction that is progressing to its final destination.
• If read data is obtained from a write transaction:
– It must be obtained from the most recent version of the write.
– The data must not be cached to service a later read.
• Transactions are Modifiable, see A4.2.2 Modifiable transactions.
• Write transactions can be merged.
For a Normal Non-cacheable Bufferable read, data can be obtained from a write transaction that is still progressing
to its final destination. This data is indistinguishable from the read and write transactions propagating to arrive at
the final destination at the same time. Read data that is returned in this manner does not indicate that the write
transaction is visible at the final destination.
Write-Through No-Allocate
The required behavior for the Write-Through No-Allocate memory type is:
• The write response can be obtained from an intermediate point.
• Write transactions must be made visible at the final destination in a timely manner, as defined in the glossary.
There is no mechanism to determine when a write transaction is visible at the final destination.
• Read data can be obtained from an intermediately cached copy.
• Transactions are Modifiable, see A4.2.2 Modifiable transactions.
• Read data can be prefetched.
• Write transactions can be merged.
• A cache lookup is required for read and write transactions.
• The No-Allocate attribute is an allocation hint, that is, it is a recommendation to the memory system that for
performance reasons, these transactions are not allocated. However, the allocation of read and write
transactions is not prohibited.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
72


Chapter A4. Request attributes
A4.3. Memory types
Write-Through Read-Allocate
The required behavior for the Write-Through Read-Allocate memory type is the same as for Write-Through
No-Allocate memory. For performance reasons:
• Allocation of read transactions is recommended.
• Allocation of write transactions is not recommended.
Write-Through Write-Allocate
The required behavior for the Write-Through Write-Allocate memory type is the same as for Write-Through
No-Allocate memory. For performance reasons:
• Allocation of read transactions is not recommended.
• Allocation of write transactions is recommended.
Write-Through Read and Write-Allocate
The required behavior for the Write-Through Read and Write-Allocate memory type is the same as for
Write-Through No-Allocate memory. For performance reasons:
• Allocation of read transactions is recommended.
• Allocation of write transactions is recommended.
Write-Back No-Allocate
The required behavior for the Write-Back No-Allocate memory type is:
• The write response can be obtained from an intermediate point.
• Write transactions are not required to be made visible at the final destination.
• Read data can be obtained from an intermediately cached copy.
• Transactions are Modifiable, see A4.2.2 Modifiable transactions.
• Read data can be prefetched.
• Write transactions can be merged.
• A cache lookup is required for read and write transactions.
• The No-Allocate attribute is an allocation hint, that is, it is a recommendation to the memory system that for
performance reasons, these transactions are not allocated. However, the allocation of read and write
transactions is not prohibited.
Write-Back Read-Allocate
The required behavior for the Write-Back Read-Allocate memory type is the same as for Write-Back No-Allocate
memory. For performance reasons:
• Allocation of read transactions is recommended.
• Allocation of write transactions is not recommended.
Write-Back Write-Allocate
The required behavior for the Write-Back Write-Allocate memory type is the same as for Write-Back No-Allocate
memory. For performance reasons:
• Allocation of read transactions is not recommended.
• Allocation of write transactions is recommended.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
73


Chapter A4. Request attributes
A4.3. Memory types
Write-Back Read and Write-Allocate
The required behavior for the Write-Back Read and Write-Allocate memory type is the same as for Write-Back
No-Allocate memory. For performance reasons:
• Allocation of read transactions is recommended.
• Allocation of write transactions is recommended.
A4.3.2
Mismatched memory attributes
Multiple agents that are accessing the same area of memory, can use mismatched memory attributes. However, for
functional correctness, the following rules must be obeyed:
• All Managers accessing the same area of memory must have a consistent view of the cacheability of that area
of memory at any level of hierarchy. The rules to be applied are:
– If the address region is Non-cacheable, all Managers must use transactions with both AxCACHE[3:2]
deasserted.
– If the address region is Cacheable, all Managers must use transactions with either of AxCACHE[3:2]
asserted.
• Different Managers can use different allocation hints.
• If an addressed region is Normal Non-cacheable, any Manager can access it using a Device memory
transaction.
• If an addressed region has the Bufferable attribute, any Manager can access it using transactions that do not
permit Bufferable behavior. For example, a transaction that requires the response from the final destination
does not permit Bufferable behavior.
A4.3.3
Changing memory attributes
The attributes for a particular memory region can be changed from one type to another incompatible type. For
example, the attribute can be changed from Write-Through Cacheable to Normal Non-cacheable. This change
requires a suitable process to perform the change.
Typically, the following process is performed:
1. All Managers stop accessing the region.
2. A single Manager performs any required cache maintenance operations.
3. All Managers restart accessing the memory region, using the new attributes.
A4.3.4
Transaction buffering
Write access to the following memory types do not require a transaction response from the final destination, but do
require that write transactions are made visible at the final destination in a timely manner:
• Device Bufferable
• Normal Non-cacheable Bufferable
• Write-Through
For write transactions, all three memory types require the same behavior.
For read transactions, the required behavior is as follows:
• For Device Bufferable memory, read data must be obtained from the final destination.
• For Normal Non-cacheable Bufferable memory, read data must be obtained either from the final destination
or from a write transaction that is progressing to its final destination.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
74


Chapter A4. Request attributes
A4.3. Memory types
• For Write-Through memory, read data can be obtained from an intermediately cached copy.
In addition to ensuring that write transactions progress towards their final destination in a timely manner,
intermediate buffers must behave as follows:
• An intermediate buffer that can respond to a transaction must ensure that over time, any read transaction to
Normal Non-cacheable Bufferable propagates towards its destination. This propagation means that when
forwarding a read transaction, the attempted forwarding must not continue indefinitely, and any data that is
used for forwarding must not persist indefinitely. The protocol does not define a mechanism to determine the
duration for which data used in forwarding a read transaction, can be retained. However, in such a
mechanism, the act of reading the data must not reset the data timeout period.
Without this requirement, continued polling of the same location can prevent the timeout of a read that is
held in the buffer, preventing the read progressing towards its destination.
• An intermediate buffer that can hold and merge write transactions must ensure that transactions do not
remain in its buffer indefinitely. For example, merging write transactions must not reset the mechanism that
determines when a write is drained towards its final destination.
Without this requirement, continued writes to the same location can prevent the timeout of a write held in the
buffer, preventing the write progressing towards its destination.
For information about the required behavior of read accesses to these memory types, see:
• A4.3.1 Device Bufferable
• A4.3.1 Normal Non-cacheable Bufferable
• A4.3.1 Write-Through No-Allocate
A4.3.5
Example use of Device memory types
The specification supports the combined use of Device Non-bufferable and Device Bufferable memory types to
force write transactions to reach their final destination and ensure that the issuing Manager knows when the
transaction is visible to all other Managers.
A write transaction that is marked as Device Bufferable is required to reach its final destination in a timely manner.
However, the write response for the transaction can be signaled by an intermediate buffer. Therefore, the issuing
Manager cannot know when the write is visible to all other Managers.
If a Manager issues a Device Bufferable write transaction, or stream of write transactions, followed by a Device
Non-bufferable write transaction, and all transactions use the same AXI ID, then the AXI ordering requirements
force all of the Device Bufferable write transactions to reach the final destination before a response is given to the
Device Non-bufferable transaction. Therefore, the response to the Device Non-bufferable transaction indicates that
all the transactions are visible to all Managers.
A Device Non-bufferable transaction can only guarantee the completion of Device Bufferable transactions that are
issued with the same ID, and are to the same Subordinate device.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
75


Chapter A4. Request attributes
A4.4. Protocol errors
A4.4 Protocol errors
The AXI protocol defines two categories of protocol errors, a software protocol error and a hardware protocol error.
A4.4.1
Software protocol error
A software protocol error occurs when multiple accesses to the same location are made with mismatched
shareability or cacheability attributes. A software protocol error can cause a loss of coherency and result in the
corruption of data values. The protocol requires that the system does not deadlock for a software protocol error,
and that transactions always progress through a system.
A software protocol error for an access in one 4KB memory region must not cause data corruption in a different
4KB memory region. For locations held in Normal memory, the use of appropriate software barriers and cache
maintenance can be used to return memory locations to a defined state.
When accessing a peripheral device, if Modifiable transactions are used (AxCACHE[1] is asserted), then the
correct operation of the peripheral cannot be guaranteed. The only requirement is that the peripheral continues to
respond to transactions in a protocol compliant manner. To restore a peripheral device that has been accessed
incorrectly, to a known operational state, involves a sequence of events that are IMPLEMENTATION DEFINED.
A4.4.2
Hardware protocol error
A hardware protocol error is defined as any protocol error that is not a software protocol error. No support is
required for hardware protocol errors.
If a hardware protocol error occurs, then recovery from the error is not guaranteed. The system might crash, lock
up, or suffer some other non-recoverable failure.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
76


Chapter A4. Request attributes
A4.5. Protection attributes
A4.5 Protection attributes
AXI requests can have attributes that can be used to protect memory from unexpected accesses. These attributes
are physical address space (PAS), Privileged, and Instruction.
A4.5.1
Signaling for protection attributes
Table A4.5 shows the signals that can be used to indicate protection attributes.
Table A4.5: Protection signals
Name
Width
Default
Presence
Description
AWPROT,
ARPROT
3
0b000
PROT_Present
The protection attributes for a request.
AWNSE,
ARNSE
1
0b0
RME_Support == True and
PROT_Present == True
Extends AxPROT[1] to include Root
and Realm address spaces.
AWPRIV,
ARPRIV
1
0b0
INSTPRIV_Present
LOW to indicate this is an unprivileged
access, HIGH for a privileged access.
Equivalent to AxPROT[0].
AWINST,
ARINST
1
0b0
INSTPRIV_Present
LOW to indicate this is a data access,
HIGH for an instruction access.
Equivalent to AxPROT[2].
AWPAS,
ARPAS
PAS_WIDTH
All zeros
(Secure)
PAS_WIDTH > 0
Physical address space (PAS) of a
transaction.
Table A4.6 shows the properties used to define the protection signaling.
Table A4.6: Protection properties
Name
Values
Default
Description
PROT_Present
True,
False
True
Indicates if AxPROT signals are present on an interface.
True
AWPROT and ARPROT are present.
False
AWPROT and ARPROT are not present.
INSTPRIV_Present
True,
False
False
Indicates if AxINST and AxPRIV signals are present on an
interface.
True
AWPRIV, ARPRIV, AWINST and ARINST are present.
False
AWPRIV, ARPRIV, AWINST and ARINST are not
present.
PAS_WIDTH
0..3
0
Width of the AWPAS and ARPAS signals in bits.
AxPROT and AxNSE signals have been superseded by AxPRIV, AxINST and AxPAS for signaling protection
attributes. An interface must not include both sets of signals, the following rules apply:
• If PROT_Present is True, PAS_WIDTH must be 0.
• If PROT_Present is True, INSTPRIV_Present must be False.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
77


Chapter A4. Request attributes
A4.5. Protection attributes
A4.5.2
Privileged and Instruction attributes
An AXI Manager might support more than one level of operating privilege, and can optionally extend this concept
of privilege to memory access. Some processors support multiple levels of privilege, see the documentation for the
selected processor to determine the mapping to AXI privilege levels. The only distinction AXI can provide is
between privileged and unprivileged access.
Access privilege can be signaled using either AxPROT[0] or AxPRIV:
• 0b0: Unprivileged
• 0b1: Privileged
An access can be labeled as an instruction access or a data access, using either AxPROT[2] or AxINST:
• 0b0: Data access
• 0b1: Instruction access
The AXI protocol defines this indication as a hint. It is not accurate in all cases, for example, where a transaction
contains a mix of instruction and data items. It is recommended that a Manager indicates a data access unless the
access is known to be an instruction access.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
78


Chapter A4. Request attributes
A4.5. Protection attributes
A4.5.3
Physical address space (PAS)
An AXI request can include a physical address space identifier. Requests with the same address but to different
physical address spaces can decode to different memory locations. Some memory locations might have access
restrictions based on the PAS.
Table A4.7 shows the physical address spaces with signal encodings and property that must be True to enable a
Manager to use that encoding. An interface can include AxPAS or AxPROT/AxNSE signals, not both.
Table A4.7: Physical address space encodings
Physical address space
AxPAS
AxPROT[1]
AxNSE
Property
Secure
0b000
0b0
0b0
-
Non-secure (NS)
0b001
0b1
0b0
-
Root
0b010
0b0
0b1
RME_Support
Realm
0b011
0b1
0b1
RME_Support
System Agent (SA)
0b100
-
-
GDI_Support
Non-secure Protected (NSP)
0b101
-
-
GDI_Support
Other values of AxPAS are reserved.
A4.5.4
Realm Management Extension
Memory protection can be extended using the Realm Management Extension (RME) [3]. This provides
hardware-based isolation that allows execution contexts to run in different Security states and share resources in
the system.
When RME is used, it adds the Root and Realm physical address spaces, affects the operation of cache
maintenance operations and extends the MPAM signals.
RME support is defined using the RME_Support property.
Table A4.8: RME_Support property
RME_Support
Default
Description
True
RME is supported.
False
Y
RME is not supported.
A4.5.5
Granular Data Isolation
Granular Data Isolation (GDI) is an extension to the Arm Realm Management Extension (RME).
The GDI feature is designed to enable memory isolation between data flows from Processing Elements (PEs) and
non-Processing Elements, within an RME system. To achieve this, two physical address spaces (PAS) are defined
for specific use cases:
• Non-secure Protected (NSP)
– Intended for media pipelines, with flexible Non-secure software management and strong data
confidentiality.
– Memory is managed by a Processing Element (PE), using the SMMU, on behalf of a Non-secure device
in protected mode.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
79


Chapter A4. Request attributes
A4.5. Protection attributes
• System Agent (SA)
– Intended for use by higher security on chip sub-systems that require memory allocation on request.
– Fully isolated from PEs, and any additional memory management is independent from the PEs.
– Requests to the System Agent PAS are physically addressed but might require access checks.
PEs are not permitted to directly access either of these new PAS, except for performing Cache Maintenance
through to the Point of Physical Aliasing (PoPA).
Both new physical address spaces are permitted to make use of the RME Memory Encryption Contexts (MEC)
feature, see A4.6 Memory Encryption Contexts.
For more information on the GDI architecture, see [3].
See Table A4.7 for the NSP and SA physical address space encodings.
The property GDI_Support determines whether an interface supports Granular Data Isolation.
Table A4.9: GDI_Support property
GDI_Support
Default
Description
True
GDI is supported. NSP and SA address spaces can
be used.
False
Y
GDI is not supported.
The following rules apply to the GDI_Support property:
• When RME_Support is False, GDI_Support must be False.
• When GDI_Support is True, PAS_WIDTH must be 3.
• When GDI_Support is True, Untranslated_Transactions must be False or v4.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
80


Chapter A4. Request attributes
A4.6. Memory Encryption Contexts
A4.6 Memory Encryption Contexts
Memory Encryption Contexts (MEC) is an extension to the Arm Realm Management Extension (RME) that allows
each Realm to have its own unique encryption context. The MEC extension assigns memory encryption contexts
to all memory accesses within the Realm physical address space. All memory transactions are associated with
a MECID, which is determined by the Security state, translation regime, translation tables and the MEC system
registers. The MECID is used by a memory encryption engine as an index into a table of encryption contexts,
either keys or tweaks, that contribute to the external memory encryption.
Use of MEC can help protect Realm data in memory, by enabling each set of Realm data to be encrypted in a
different way. This means that a malicious agent that has access to the physical memory device and is able to
decipher one set of Realm data, cannot use the same decryption method to access other sets of Realm data. Before
the Point of Encryption (PoE) the data that moves between components is in plaintext form.
Realm management software at R-EL2 controls MECID policy and assignment to Realms.
For more information on MEC, see [3] and [4].
Note that the MEC architecture specification [3] details several implementation options for when a MECID value
mismatch occurs. This MEC implementation assumes that Managers and caches do not perform any MECID
checks. For example, if a read access associated with a MECID targets a location that has a copy present in a cache
and is associated with a different MECID, the read access succeeds as though the MECID values did not mismatch.
Additional protection is not needed here as Realm management software at R-EL2 ensures that one context can be
prevented from accessing locations that belong to a different context, thus ensuring plaintext leakages do not occur.
A4.6.1
MEC signaling
The MEC_Support property determines whether an interface supports Memory Encryption Contexts.
Table A4.10: MEC_Support property
MEC_Support
Default
Description
True
MEC is supported, AxMECID signals are present.
False
Y
MEC is not supported, AxMECID signals are not
present.
MEC is an extension of RME, so if the RME_Support property is False, MEC_Support must be False.
The following signals are required to support MEC.
Table A4.11: MECID signals
Name
Width
Default
Description
AWMECID,
ARMECID
MECID_WIDTH
All zeros
RME Memory Encryption Context identifier
(MECID).
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
81


Chapter A4. Request attributes
A4.6. Memory Encryption Contexts
The parameter MECID_WIDTH defines the width of the AxMECID signals.
Table A4.12: MECID_WIDTH property
Name
Values
Default
Description
MECID_WIDTH
0, 16
0
Width of AWMECID and ARMECID in bits.
The following rules apply to the MECID_WIDTH property:
• If MECID_WIDTH is 0, AWMECID and ARMECID are not present on the interface.
• If MEC_Support is False, MECID_WIDTH must be 0.
• If MEC_Support is True, MECID_WIDTH must not be 0.
Note that the width of MECID does not indicate how many different values are used by a component. It might be
possible to reduce the storage requirements of MECID by using a narrower internal width.
The compatibility between Manager and Subordinate interfaces according to the values of the MEC_Support
property is shown in Table A4.13.
Table A4.13: MEC_Support compatibility
MEC_Support
Subordinate: False
Subordinate: True
Manager: False
Compatible.
Compatible.
AxMECID inputs are tied LOW.
Manager: True
Compatible.
Downstream memory is not encrypted
using MEC.
Compatible.
A4.6.2
MECID usage
The MECID value range is bounded, dependent on the physical address space being accessed.
Table A4.14: MECID constraints
Physical address space
MECID constraints
Secure
Must be zero
Non-secure
Must be zero
Root
Must be zero
Realm
Can take any valuea
System Agent
Can take any valuea
Non-Secure Protected
Can take any valuea
a Depends on the MEC_Support and MECID_Width properties.
MECID is inapplicable and can take any value for the following request Opcodes:
• CMO
• CleanInvalid
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
82


Chapter A4. Request attributes
A4.6. Memory Encryption Contexts
• MakeInvalid
• CleanShared
• CleanSharedPersist
• InvalidateHint
• StashTranslation
• UnstashTranslation
MECID is inapplicable and must be 0 for the following request Opcodes:
• DVM Complete
Components that propagate transactions and support MECID on their Subordinate and Manager interfaces must
preserve the MECID on requests where it is applicable. Components that perform address translation might
change the MECID.
A cache that stores data which has an associated MECID must also store the MECID and provide it with the data
during a write-back.
A CleanInvalidPoPA operation can be used to ensure that a cache line is cleaned and invalidated from all caches
upstream of the Point of Encryption. See A9.9 Cache maintenance and Realm Management Extension for more
information on CleanInvalidPoPA.
A4.6.3
MEC and GDI
When using MEC and GDI, MECID must be valid for all accesses to Non-secure Protected or System Agent
physical address spaces. MECID mismatches must not result in a loss of confidentiality of data between Memory
Encryption Contexts.
A cache must enforce the following rules for the System Agent and Non-secure Protected physical address spaces
when there is a difference between the incoming request MECID and the previously cached MECID value.
• For a read transaction:
– Any returned data must be masked to an IMPLEMENTATION SPECIFIC value. Arm recommends, but
does not require, that this value is all ones.
– The cache is permitted to retain the line.
• For a partial write transaction:
– Cached data must be masked to an IMPLEMENTATION SPECIFIC value. Arm recommends, but does not
require, that this value is all ones.
– The partial write data is then merged into this masked value.
– The cached MECID for the location must be updated to the MECID of the incoming write.
• For a full cache line write transaction:
– The write data overwrites the previously cached value.
– The cached MECID must be updated to the MECID of the incoming write.
For more information on GDI, see A4.5.5 Granular Data Isolation.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
83


Chapter A4. Request attributes
A4.7. Multiple region interfaces
A4.7 Multiple region interfaces
This section describes the use of a region identifier with a request, to support interfaces with multiple address
regions within a single interface.
A4.7.1
Region identifier signaling
The property REGION_Present determines whether an interface supports region identifier signaling.
Table A4.15: REGION_Present property
REGION_Present
Default
Description
True
Y
AWREGION and ARREGION are present.
False
AWREGION and ARREGION are not
present.
The signals to indicate a region are shown in Table A4.16.
Table A4.16: Region signals
Name
Width
Default
Description
AWREGION,
ARREGION
4
0x0
A 4-bit region identifier which can be used to
identify different address regions.
A4.7.2
Using the region identifier
The 4-bit region identifier can be used to uniquely identify up to 16 different regions. The region identifier can
provide a decode of higher-order address bits. The region identifier must remain constant within any 4K-byte
address space.
The use of region identifiers means that a single physical interface on a Subordinate can provide multiple logical
interfaces, each with a different location in the system address map. The use of the region identifier means that the
Subordinate does not have to support the address decode between the different logical interfaces.
This specification expects an interconnect to produce AxREGION signals when performing the address decode
function for a single Subordinate that has multiple logical interfaces. If a Subordinate only has a single physical
interface in the system address map, the interconnect must use the default AxREGION values.
There are several usage models for the region identifier including, but not limited to, the following:
• A peripheral can have its main data path and control registers at different locations in the address map, and
be accessed through a single interface without the need for the Subordinate to perform an address decode.
• A Subordinate can exhibit different behaviors in different memory regions. For example, a Subordinate
might provide read and write access in one region, but read-only access in another region.
A Subordinate must ensure that the correct protocol signaling and the correct ordering of transactions are
maintained. A Subordinate must ensure that it provides the responses to two requests to different regions with the
same transaction ID in the correct order.
A Subordinate must also ensure the correct protocol signaling for any values of AxREGION. If a Subordinate
implements fewer than sixteen regions, then the Subordinate must ensure the correct protocol signaling on any
attempted access to an unsupported region. How this is achieved is IMPLEMENTATION DEFINED. For example, the
Subordinate might ensure this by:
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
84


Chapter A4. Request attributes
A4.7. Multiple region interfaces
• Providing an error response for any transaction that accesses an unsupported region.
• Aliasing supported regions across all unsupported regions, to ensure that a protocol compliant response is
given for all accesses.
The AxREGION signals only provide an address decode of the existing address space that can be used by
Subordinates to remove the need for an address decode function. The signals do not create new independent
address spaces. AxREGION must only be present on an interface that is downstream of an address decode
function.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
85


Chapter A4. Request attributes
A4.8. QoS signaling
A4.8 QoS signaling
AXI supports Quality of Service (QoS) schemes through the features of:
• A4.8.1 QoS identifiers
• A4.8.2 QoS acceptance indicators
A4.8.1
QoS identifiers
An AXI request has an optional identifier which can be used to distinguish between different traffic streams as
shown in Table A4.17.
Table A4.17: QoS signals
Name
Width
Default
Description
AWQOS,
ARQOS
4
0x0
Quality of Service identifier used to distinguish
between different traffic streams.
The QOS_Present property is used to define whether an interface includes the AxQOS signals.
Table A4.18: QOS_Present property
QOS_Present
Default
Description
True
Y
AWQOS and ARQOS are present.
False
AWQOS and ARQOS are not present.
The protocol does not specify the exact use of the QoS identifier. It is recommended to use AxQOS as a priority
indicator for the associated write or read request, where a higher value indicates a higher priority request.
Using the QoS identifiers
A Manager can produce its own AxQOS values, and if it can produce multiple streams of traffic, it can choose
different QoS values for the different streams.
Support for QoS requires a system-level understanding of the QoS scheme in use, and collaboration between all
participating components. For this reason, it is recommended that a Manager component includes some
programmability that can be used to control the exact QoS values that are used for any given scenario.
If a Manager component does not support a programmable QoS scheme, it can use QoS values that represent the
relative priorities of the transactions it generates. These values can then be mapped to alternative system level QoS
values if appropriate.
This specification expects that many interconnect component implementations will support programmable
registers that can be used to assign QoS values to connected Managers. These values replace the QoS values,
either programmed or default, supplied by the Managers.
The default system-level implementation of QoS is that any component with a choice of more than one transaction
to process selects the request with the higher QoS value to process first. This selection only occurs when there is
no other AXI constraint that requires the requests to be processed in a particular order. This means that the AXI
ordering rules take precedence over ordering for QoS purposes.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
86


Chapter A4. Request attributes
A4.8. QoS signaling
A4.8.2
QoS acceptance indicators
The QoS acceptance indicators as shown in Table A4.19 are output signals from a Subordinate interface that
indicate the minimum QoS value it will accept without delay.
The signals are synchronous to ACLK but are unrelated to any other AXI channel.
Table A4.19: QoS acceptance signals
Name
Width
Default
Description
VAWQOSACCEPT
4
0x0
An output from a Subordinate that indicates the
QoS value for which it accepts requests from the
AW channel.
VARQOSACCEPT
4
0x0
An output from a Subordinate that indicates the
QoS value for which it accepts requests from the
AR channel.
QoS Accept signaling is intended for Subordinate components that have different resources available for different
QoS values, which is typically the case with memory controllers. The Subordinate can indicate that it only accepts
requests at a certain QoS value or above when the resources available to lower QoS values are in use.
QoS Accept signaling can be used as an input to a Manager interface that might have several different requests to
select from. This permits the Manager interface to only issue requests that are likely to be accepted, which avoids
unnecessary blocking of the interface. By preventing the issue of requests that might be stalled for a significant
period, the interface remains available for the issue of higher priority requests that might arrive at a later point in
time.
In this specification, the term VAxQOSACCEPT refers collectively to the VAWQOSACCEPT and
VARQOSACCEPT signals.
The rules and recommendations for the VAxQOSACCEPT signals are:
• Any requests with QoS level equal to or higher than VAxQOSACCEPT are accepted by the Subordinate.
• Any request with QoS level below VAxQOSACCEPT might be stalled for a significant time.
This specification does not define a time period during which the Subordinate is required to accept a
request at, or above, the QoS level indicated. However, it is expected that for a given Subordinate there
will be a deterministic maximum number of clock cycles taken to accept a transaction, after taking into
account implementation aspects such as clock domain crossing ratios.
• It is permitted for a Subordinate interface to accept a request that is below the QoS level indicated by the
VAxQOSACCEPT signal, but it is expected that the request might be subject to a significant delay.
While it is acceptable for a Subordinate to delay a request that has a lower priority than the QoS
acceptance level, it is recommended that such a transaction is not delayed indefinitely.
There are several reasons for a lower-priority transaction to be issued on the interface, for example:
• A delay between a change in the QoS acceptance value and the ability of the component to adapt to that
change.
• A requirement to make progress on a transaction that is Head-of-line blocking a higher priority request.
• A requirement to make progress on a transaction for reasons of starvation prevention.
The QoS_Accept property as shown in Table A4.20 is used to define whether an interface includes the QoS accept
indicator signals.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
87


Chapter A4. Request attributes
A4.8. QoS signaling
Table A4.20: QoS_Accept property
QoS_Accept
Default
Description
True
The interface includes VAWQOSACCEPT and
VARQOSACCEPT signals.
False
Y
The interface does not include VAWQOSACCEPT
or VARQOSACCEPT signals.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
88
