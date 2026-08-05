# A10 Additional request qualifiers

Chapter A10
Additional request qualifiers
This chapter describes some additional request qualifiers for the AXI protocol.
It contains the following sections:
• A10.1 Non-secure Access Identifiers (NSAID)
• A10.2 Page-based Hardware Attributes (PBHA)
• A10.3 Subsystem Identifier
• A10.4 Arm Compression Technology (ACT)
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
174


Chapter A10. Additional request qualifiers
A10.1. Non-secure Access Identifiers (NSAID)
A10.1 Non-secure Access Identifiers (NSAID)
To support the storage and processing of protected data, a set of signals can be added that enable access to
particular Non-secure memory locations to be controlled. The signals supply a Non-secure Access Identifier
(NSAID) alongside the transaction request. The NSAID can be checked to permit or deny access to a memory
location.
The NSAccess_Identifiers property is used to indicate whether a component supports these additional signals.
Table A10.1: NSAccess_Identifiers property
NSAccess_Identifiers
Default
Description
True
NSAID signaling is present on the interface.
False
Y
NSAID signaling is not present on the interface.
A10.1.1
NSAID signaling
If the NSAccess_Identifiers property is True, the following signals are added to the read and write request
channels.
Table A10.2: AxNSAID signals
Name
Width
Default
Description
AWNSAID,
ARNSAID
4
0x0
Non-secure access identifier, can be checked to
permit or deny access to a memory location.
A 4-bit NSAID value supports up to 16 unique identifiers. For each NSAID, there is a set of access permission that
is defined which determine how locations in memory are permitted to be accessed. The access permissions can be:
• No access
• Read-only access
• Write-only access
• Read/write access
The mechanism that is used to define the access permissions for each NSAID is IMPLEMENTATION DEFINED.
However, this mechanism is typically implemented using some form of Memory Protection Unit (MPU).
The following rules and recommendations apply to NSAID values:
• Requests to the Non-secure physical address space can use any NSAID value.
• Requests other address spaces must use an NSAID value of zero.
• It is permitted for transactions with different NSAID values to have access to overlapping memory locations.
• It is permitted for transactions with different NSAID values to have any combination of access permissions
for a given memory location.
• It is recommended that Managers use the default NSAID value of zero when accessing data that is not
protected, or when they do not have an assigned NSAID value.
• If a Manager is required to use a single NSAID value, then it is permitted for NSAID signals to be tied to a
fixed value.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
175


Chapter A10. Additional request qualifiers
A10.1. Non-secure Access Identifiers (NSAID)
A10.1.2
Caching and NSAID
Where caching and system coherency is performed upstream of permission checking, accesses with different
NSAID values that pass data between them must be subjected to permission checks.
The rules that are associated with NSAID use and coherency are as follows:
• When an agent caches a line of data that has been fetched using a particular NSAID value, it must ensure that
any subsequent write to main memory or any response to a snoop uses the same NSAID value. This rule
ensures that a Manager cannot move a cache line of data from one protected region to another.
• For a read request with a given NSAID value, if a snoop is used to obtain the data:
– If the NSAID value of the snoop response matches the read request, then data can be provided directly.
– If the NSAID value of the snoop response does not match the read request, then the cache line must first
be written to memory using the NSAID value obtained through the snoop response, and then read from
memory using the NSAID value of the original request. The write and subsequent read are only required
to reach a point at which permission checking has occurred.
• Snoop transactions that invalidate cached copies, such as MakeInvalid, must not be used if memory
protection is used. All such snoop transactions must be replaced with transactions that also clean the cache
line to main memory, such as CleanInvalid.
• Any interconnect-generated write to main memory that occurs as the result of a snoop must use the NSAID
value that is obtained from the snoop response.
• If a single Manager can issue transactions with multiple NSAID values, it must ensure that internal accesses
to cached copies use the NSAID value that was used to fetch the cache line initially:
– An access that has a cache line hit with the same address, but a different NSAID value, must clean and
invalidate the cache line before refetching the cache line with the appropriate NSAID value. This
process ensures that a protection check is performed.
– If it is guaranteed that the Manager never accesses the same cache line with a different NSAID value,
clean and invalidation operations are not necessary. This guarantee can be by design or be assured by
using appropriate cache maintenance operations.
• Appropriate cache maintenance must be performed when changing the access permissions for NSAID values.
It is permitted for a Manager to write to a cache line when that agent does not have write permission to the
location. It is also permitted for the updated cache line to be passed to other Managers using the same NSAID
value. However, it is not permitted for the update to propagate to main memory or to an access using a different
NSAID value.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
176


Chapter A10. Additional request qualifiers
A10.2. Page-based Hardware Attributes (PBHA)
A10.2 Page-based Hardware Attributes (PBHA)
Page-based hardware attributes (PBHA) are 4-bit descriptors associated with a translation table entry that can be
annotated onto a transaction request.
This specification describes how they can be transported but their use is IMPLEMENTATION DEFINED.
The following signals are used on the read and write request channels to transfer PBHA values.
Table A10.3: AxPBHA signals
Name
Width
Default
Description
AWPBHA,
ARPBHA
4
-
A 4b user-defined descriptor associated with a
translation table entry that can be annotated onto a
transaction request.
The PBHA_Support property is used to indicate whether an interface supports PBHA.
Table A10.4: PBHA_Support property
PBHA_Support
Default
Description
True
PBHA is supported. AWPBHA and ARPBHA are present
on the interface.
False
Y
PBHA is not supported.
A10.2.1
PBHA values
PBHA values can be added to the request during address translation and propagated through a system if they are
supported by downstream components. At the MMU, all transactions to the same page and physical address space
are likely to have the same value but accuracy of PBHA values might be degraded as they pass through the system.
Examples of where PBHA values might become inaccurate are:
• When an interconnect is combining transactions from different sources, some might have PBHA values
attached, and others might take a fixed value.
• In a downstream cache, PBHA values might not be cached along with the data in all cases.
• In the case that PBHA values in translation tables are changed, values on in-flight transactions or cached data
could become inconsistent. Appropriate TLB Invalidate or cache maintenance operations could be used to
achieve consistency.
This list is not exhaustive, designers are encouraged to document situations where PBHA can become inaccurate
within their component. A system integrator wanting to use PBHA must consider every component between the
source and target to determine the requirements of the target can be met.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
177


Chapter A10. Additional request qualifiers
A10.3. Subsystem Identifier
A10.3 Subsystem Identifier
The Subsystem Identifier (ID) is a field that can be added to transaction requests to indicate from which subsystem
they originate. The Subsystem ID can be used to qualify the transaction address and provide isolation between
parts of a system when they share memory or devices.
The signals used to transfer the Subsystem ID are shown in Table A10.5.
Table A10.5: AxSUBSYSID signals
Name
Width
Default
Description
AWSUBSYSID,
ARSUBSYSID
SUBSYSID_WIDTH
-
Subsystem identifier that indicates from which
subsystem a request originates.
The SUBSYSID_WIDTH property is used to define the width and presence of the Subsystem ID signals. If the
property is zero, the signals are not present.
Table A10.6: SUBSYSID_WIDTH property
Name
Values
Default
Description
SUBSYSID_WIDTH
0..8
0
Width of AWSUBSYSID and ARSUBSYSID in bits.
A10.3.1
Subsystem ID usage
This specification does not define the usage of Subsystem IDs.
Example implementations include:
• A Manager or group of Managers using a single Subsystem ID where they have common access rights to
shared memory or peripherals.
• An interconnect combining requests from Managers in different subsystems. In this case, the interconnect
Manager interface therefore uses different Subsystem IDs for different requests.
• Using the Subsystem ID as a look-up in a firewall or Memory Protection Unit (MPU) to isolate subsystems
for safety or security reasons.
• Requiring that all Managers within a coherent domain use the same Subsystem ID, so it can be used in snoop
filtering.
• Using Subsystem ID for performance profiling or monitoring.
• An interconnect that propagates Subsystem ID through some interfaces and not others.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
178


Chapter A10. Additional request qualifiers
A10.4. Arm Compression Technology (ACT)
A10.4 Arm Compression Technology (ACT)
Arm Compression Technology (ACT) is a block-based compression technology that allows data compression and
decompression with a minimum of state. This enables the codec hardware to be separate from the components
using the data, and a single codec to be shared between multiple agents.
When using ACT, a Manager generates loads and stores of uncompressed data that are routed by the interconnect
to the ACT codec. The ACT codec performs the compression/decompression and generates any required memory
transactions to the compressed data in memory. The codec uses information carried in the ACT payload of the
request to perform the correct compression or decompression.
This feature extends AXI5 interfaces with signals to indicate ACT transactions and carry the ACT payload
between a Manager and external codec.
The ACT_Support property determines whether an interface supports Arm Compression Technology signaling.
Table A10.7: ACT_Support property
ACT_Support
Default
Description
v1
ACT is supported, ACT signals are present.
False
Y
ACT is not supported, ACT signals are not
present.
The ACT_Support property can be True for the following interface classes:
• AXI5
When ACT_Support is v1:
• The ACT signals are present, see Table A10.9.
• WriteACT and ReadACT transactions are supported.
• The data bus width (DATA_WIDTH) must be 128b or larger.
• Untranslated_Transactions must not be False, because ACT transactions are to virtual addresses.
When connecting Manager and Subordinate interfaces, the ACT_Support property must be compatible as shown
in Table A10.8.
Table A10.8: ACT_Support property compatibility
Subordinate: False
Subordinate: v1
Manager: False
Compatible
Compatible. AxACTV inputs tied LOW.
Manager: v1
Not compatible
Compatible
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
179


Chapter A10. Additional request qualifiers
A10.4. Arm Compression Technology (ACT)
A10.4.1
ACT signaling
The following signals are required to support ACT.
Table A10.9: ACT signals
Signal
Width
Default
Description
AWACTV
1
0b0
Asserted HIGH to indicate that this is a WriteACT
request and AWACT contains a valid payload.
AWACT
ACT_W_WIDTH
All zeros
ACT payload on the write request channel.
ARACTV
1
0b0
Asserted HIGH to indicate that this is a ReadACT
request and ARACT contains a valid payload.
ARACT
ACT_R_WIDTH
All zeros
ACT payload on the read request channel.
The properties that define the width of the ACT payload are shown in Table A10.10.
Table A10.10: ACT width properties
Name
Values
Default
Description
ACT_W_WIDTH
0, 16..32
0
Width of AWACT in bits.
ACT_R_WIDTH
0, 16..32
0
Width of ARACT in bits.
The following rules apply to the ACT signal widths:
• If ACT_W_WIDTH is 0, AWACT and AWACTV are not present.
• If ACT_R_WIDTH is 0, ARACT and ARACTV are not present.
• If ACT_Support is False, ACT_W_WIDTH and ACT_R_WIDTH must be 0.
A10.4.2
ACT requests
A WriteACT request is signaled by setting AWSNOOP to 0x0 and AWACTV to 0b1.
• When AWACTV is HIGH, AWSNOOP must be 0x0.
A ReadACT request is signaled by setting ARSNOOP to 0x0 and ARACTV to 0b1.
• When ARACTV is HIGH, ARSNOOP must be 0x0.
WriteACT and ReadACT requests have the following constraints:
• Burst is INCR.
• AxCACHE is Device transaction.
• Domain is System.
• Size is the same as the data bus width if Length is greater than 1 transfer.
• AxADDR[13:0] is zero.
• For writes, all write strobes within the transaction container must be asserted.
• AxLOCK is Normal.
• TagOp is Invalid.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
180


Chapter A10. Additional request qualifiers
A10.4. Arm Compression Technology (ACT)
• ID is unique-in-flight, which means:
– An ACT read request can only be issued if there are no outstanding transactions on the read channels
with the same ID.
– An ACT write request can only be issued if there are no outstanding transactions on the write channels
with the same ID.
– A request must not be issued on the read channels with the same ID as an outstanding ACT read request.
– A request must not be issued on the write channels with the same ID as an outstanding ACT write
request.
– If present, AxIDUNQ must be asserted.
A10.4.3
Modifying ACT transactions
Transactions using ACT have a Non-modifiable memory attribute, which means there are limitations regarding
which signals can be modified as the transaction progresses through a system.
The AXI specification permits Non-modifiable transactions to have their Size and Length changed in the following
circumstances:
• If Length is greater than 16, but that is not supported by a Subordinate interface. In this case, a transaction is
split into multiple smaller transactions.
• If the transaction is transported across an interconnect link with data width smaller than that of the request.
The ACT payload associated with a transaction is specific to the Size and Length of that transaction, so an ACT
transaction must never have its Size or Length changed. This might limit the topology of subsystems transporting
ACT transactions.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
181
