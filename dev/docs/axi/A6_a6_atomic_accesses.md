# A6 Atomic accesses

Chapter A6
Atomic accesses
This chapter describes single-copy and multi-copy atomicity and how to perform exclusive accesses and atomic
transactions.
It contains the following sections:
• A6.1 Single-copy atomicity size
• A6.2 Multi-copy write atomicity
• A6.3 Exclusive accesses
• A6.4 Atomic transactions
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
107


Chapter A6. Atomic accesses
A6.1. Single-copy atomicity size
A6.1 Single-copy atomicity size
The single-copy atomicity size is the minimum number of bytes that a transaction updates atomically. The AXI
protocol requires a transaction that is larger than the single-copy atomicity size to update memory in blocks of at
least the single-copy atomicity size.
Atomicity does not define the exact instant when the data is updated. What must be ensured is that no Manager can
ever observe a partially updated form of the atomic data. For example, in many systems, data structures such as
linked lists are made up of 32-bit atomic elements. An atomic update of one of these elements requires that the
entire 32-bit value is updated at the same time. It is not acceptable for any Manager to observe an update of only
16 bits at one time, and then the update of the other 16 bits later.
More complex systems require support for larger atomic elements, in particular 64-bit atomic elements, so that
Managers can communicate using data structures that are based on these larger atomic elements.
The single-copy atomicity sizes that are supported in a system are important because all the components involved
in a given communication must support the required size of atomic element. If two Managers are communicating
through an interconnect and a single Subordinate, then all the components involved must ensure that transactions
of the required size are treated atomically.
The AXI protocol does not require a specific single-copy atomicity size and systems can be designed to support
different single-copy atomicity sizes.
In AXI the term single-copy atomic group describes a group of components that can communicate at a particular
atomicity. For example, Figure A6.1 shows a system in which:
• The CPU, DSP, DRAM controller, DMA controller, peripherals, SRAM memory and associated interconnect,
are in a 32-bit single-copy atomic group.
• The CPU, DSP, DRAM controller, and associated interconnect are also in a 64-bit single-copy atomic group.
32-bit single-copy atomic group
64-bit single-copy atomic group
CPU
Interconnect
DSP
DMA
Controller
DRAM
Controller
SRAM
UART
Timer
GPIO
Interconnect
Figure A6.1: Example system with different single-copy atomic groups
A transaction never has an atomicity guarantee greater than the alignment of its start address. For example, a
transaction in a 64-bit single-copy atomic group that is not aligned to an 8-byte boundary does not have any 64-bit
single-copy atomic guarantee.
Byte strobes associated with a transaction do not affect the single-copy atomicity size.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
108


Chapter A6. Atomic accesses
A6.2. Multi-copy write atomicity
A6.2 Multi-copy write atomicity
A system is defined as being multi-copy atomic if:
• Writes to the same location are observed in the same order by all agents.
• A write to a location that is observable by an agent, is observable by all agents.
To specify that a system provides multi-copy atomicity, a Multi_Copy_Atomicity property is defined.
Table A6.1: Multi_Copy_Atomicity property
Multi_Copy_Atomicity
Default
Description
True
Multi_Copy_Atomicity is supported.
False
Y
Multi_Copy_Atomicity is not supported.
Multi-copy atomicity can be ensured by:
• Using a single Point of Serialization (PoS) for a given address, so that all accesses to the same location are
ordered. This must ensure that all coherent cached copies of a location are invalidated before the new value
of the location is made visible to any agents.
• Avoiding the use of forwarding buffers that are upstream of any agents. This prevents a buffered write of a
location becoming visible to some agents before it is visible to all agents.
It is required that the Multi_Copy_Atomicity property is True for Issue G and later of this specification.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
109


Chapter A6. Atomic accesses
A6.3. Exclusive accesses
A6.3 Exclusive accesses
The exclusive access mechanism can provide semaphore-type operations without requiring the connection to
remain dedicated to a particular Manager during the operation.
The AxLOCK signals are used to indicate an exclusive access, and the BRESP and RRESP signals indicate the
success or failure of the exclusive access write or read respectively.
Table A6.2: AxLOCK signals
Name
Width
Default
Description
AWLOCK,
ARLOCK
1
0b0
Asserted high to indicate that an exclusive access is
required.
The Exclusive_Accesses property is used to define whether a Manager issues exclusive accesses or whether a
Subordinate supports them:
Table A6.3: Exclusive_Accesses property
Exclusive_Accesses
Default
Description
True
Y
Exclusive accesses are supported. AWLOCK and
ARLOCK are present on the interface.
False
Exclusive accesses are not supported. AWLOCK and
ARLOCK are not present on the interface.
Table A6.4 provides guidance that applies when connecting Manager and Subordinate components with different
property values:
Table A6.4: Exclusive Accesses Interoperability
Subordinate: False
Subordinate: True
Manager: False
Compatible.
Compatible.
AWLOCK and ARLOCK are tied
LOW.
Manager: True
Not compatible.
Exclusive accesses will continually fail,
but the interface will not deadlock.
Compatible.
A6.3.1
Exclusive access sequence
The mechanism of an exclusive access sequence is:
1. A Manager issues an exclusive read request from an address.
2. At some later time, the Manager attempts to complete the exclusive operation by issuing an exclusive write
request to the same address, with an AWID that matches the ARID used for the exclusive read.
3. This exclusive write access is signaled as either:
• Successful, if no other Manager has written to that location since the exclusive read access. In this case,
the exclusive write updates memory.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
110


Chapter A6. Atomic accesses
A6.3. Exclusive accesses
• Failed, if another Manager has written to that location since the exclusive read access. In this case, the
memory location is not updated.
A Manager might not complete the write portion of an exclusive operation. The exclusive access monitoring
hardware monitors only one address for each transaction ID. If a Manager does not complete the write portion of
an exclusive operation, a subsequent exclusive read by that Manager using the same transaction ID changes the
address that is being monitored for exclusive accesses.
A6.3.2
Exclusive access from the perspective of the Manager
A Manager starts an exclusive operation by performing an exclusive read. If the transaction is successful, the
Subordinate returns the EXOKAY response, indicating that the Subordinate recorded the address to be monitored
for exclusive accesses.
If the Manager attempts an exclusive read from a Subordinate that does not support exclusive accesses, the
Subordinate returns the OKAY response instead of the EXOKAY response. In this case, the read data is valid, but
the location is not being monitored for exclusivity.
The Manager can treat the OKAY response as an error condition indicating that the exclusive access is not
supported. It is recommended that the Manager does not perform the write portion of this exclusive operation.
At some time after the exclusive read, the Manager tries an exclusive write to the same location. If the contents of
the addressed location have not been updated since the exclusive read, the exclusive write operation succeeds. The
Subordinate returns the EXOKAY response, and updates the memory location.
If the contents of the addressed location have been updated since the exclusive read, the exclusive write attempt
fails, and the Subordinate returns the OKAY response instead of the EXOKAY response. The exclusive write
attempt does not update the memory location.
A Manager might not complete the write portion of an exclusive operation. If this happens, the Subordinate
continues to monitor the address for exclusive accesses until another exclusive read starts a new exclusive access
sequence.
A Manager must not start the write part of an exclusive access sequence until the read part is complete.
A6.3.3
Exclusive access restrictions
The following restrictions apply to exclusive accesses:
• The address of an exclusive access must be aligned to the total number of bytes in the transaction, that is, the
product of Size and Length.
• The number of bytes to be transferred in an exclusive access transaction must be a power-of-2, that is, 1, 2, 4,
8, 16, 32, 64, or 128 bytes.
• The Length of an exclusive access must not exceed 16 transfers.
• The Domain must not be Shareable, see A8.3.3 Shareable Domain.
• The Opcode must be ReadExclusive or WriteExclusive. See Chapter A7 Request Opcodes.
• AWTAGOP must not be Match, see A12.2 Memory Tagging Extension (MTE).
Failure to observe these restrictions causes UNPREDICTABLE behavior.
For an exclusive sequence to be successful, the AxCACHE values must be appropriate to ensure that the read and
write requests reach the exclusive access monitor.
The minimum number of bytes to be monitored during an exclusive operation is the product of Size and Length.
The Subordinate can monitor a larger number of bytes, up to 128, which is the maximum number of bytes in an
exclusive access. However, this can result in a successful exclusive access being indicated as failing because a
neighboring byte was updated.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
111


Chapter A6. Atomic accesses
A6.3. Exclusive accesses
If any of the signals shown in Table A6.5 are different between the read and write requests in an exclusive
sequence, the exclusive write might fail even if the location has not been updated by another agent.
Table A6.5: Signals that should be the same in an exclusive sequence
AxID
AxADDR
AxREGION
AxSUBSYSID
AxDOMAIN
AxLEN
AxSIZE
AxBURST
AxLOCK
AxCACHE[1:0]
AxPROT
AxNSE
AxPAS
AxINST
AxPRIV
AxSNOOP
AxMMUVALID
AxMMUATST
AxMMUFLOW
AxMMUPASUNKNOWN
AxMMUPM
AxMMUSECSID
AxMMUSID
AxMMUSSID
AxMMUSSIDV
A6.3.4
Exclusive access from the perspective of the Subordinate
A Subordinate that supports exclusive access must have monitor hardware. It is recommended that such a
Subordinate has a monitor unit for each exclusive-capable Manager ID that can access it.
When a Subordinate receives an exclusive read request, it records the address and ARID value of any exclusive
read operation. Then it monitors that location until either a write occurs to that location or until another exclusive
read with the same ARID value resets the monitor to a different address.
If the Subordinate can successfully process the exclusive read, it responds with EXOKAY for every read data
transfer.
If the Subordinate cannot process the exclusive read, it responds with a response which is not EXOKAY. An
exclusive read can have more than one response transfers. It is not permitted to have a mix of OKAY and
EXOKAY responses for a single transaction.
When the Subordinate receives an exclusive write with a given AWID value, the monitor checks to see if that
address is being monitored for exclusive access with that AWID. If it is, then this indicates that no write has
occurred to that location since the exclusive read access, and the exclusive write proceeds, completing the
exclusive access. The Subordinate returns the EXOKAY response to the Manager and updates the addressed
memory location.
If the address is not being monitored with the same AWID value at the time of an exclusive write, this indicates
one of the following:
• The location has been updated since the exclusive read access.
• The monitor has been reset to another location.
• The Manager did not issue an exclusive read with the same attributes as the exclusive write.
If the monitor deems the sequence to have failed, the exclusive write must not update the addressed location, and
the Subordinate must return the OKAY response instead of the EXOKAY response.
If a Subordinate that does not support exclusive accesses receives an exclusive write, it responds with an OKAY
response and the location is updated.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
112


Chapter A6. Atomic accesses
A6.4. Atomic transactions
A6.4 Atomic transactions
Atomic transactions perform more than just a single access and have an operation that is associated with the
transaction. Atomic transactions enable sending the operation to the data, permitting the operation to be performed
closer to where the data is located. Atomic transactions are suited to situations where the data is located a
significant distance from the agent that must perform the operation.
Compared with using exclusive accesses, this approach reduces the amount of time during which the data must be
made inaccessible to other agents in the system.
Atomic transactions update the entire written location atomically, irrespective of the single-copy atomicity size of
the component.
A6.4.1
Overview
In an atomic transaction, the Manager sends an address, control information, and outbound data. The Subordinate
sends inbound data (except for AtomicStore) and a response. This specification supports four forms of Atomic
transaction:
AtomicStore
• The Manager sends a single data value with an address and the atomic operation to be performed.
• The Subordinate performs the operation using the sent data and value at the addressed location as operands.
• The result is stored in the address location.
• A single response is given without data.
• Outbound data size is 1, 2, 4, or 8 bytes.
AtomicLoad
• The Manager sends a single data value with an address and the atomic operation to be performed.
• The Subordinate returns the original data value at the addressed location.
• The Subordinate performs the operation using the sent data and value at the addressed location as operands.
• The result is stored in the address location.
• Outbound data size is 1, 2, 4, or 8 bytes.
• Inbound data size is the same as the outbound data size.
AtomicSwap
• The Manager sends a single data value with an address.
• The Subordinate swaps the value at the addressed location with the data value that is supplied in the
transaction.
• The Subordinate returns the original data value at the addressed location.
• Outbound data size is 1, 2, 4, or 8 bytes.
• Inbound data size is the same as the outbound data size.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
113


Chapter A6. Atomic accesses
A6.4. Atomic transactions
AtomicCompare
• The Manager sends two data values, the compare value and the swap value, to the addressed location. The
compare and swap values are of equal size.
• The Subordinate checks the data value at the addressed location against the compare value:
– If the values match, the swap value is written to the addressed location.
– If the values do not match, the swap value is not written to the addressed location.
• The Subordinate returns the original data value at the addressed location.
• Outbound data size is 2, 4, 8, 16, or 32 bytes.
• Inbound data size is half of the outbound data size because the outbound data contains both compare and
swap values, whereas the inbound data has only the original data value.
A6.4.2
Atomic transaction operations
This specification supports eight different operations that can be used with AtomicStore and AtomicLoad
transactions as shown in Table A6.6.
Table A6.6: Atomic transaction operators
Operator
Description
ADD
The value in memory is added to the sent data and the result stored in memory.
CLR
Every set bit in the sent data clears the corresponding bit of the data in memory.
EOR
Bitwise exclusive OR of the sent data and value in memory.
SET
Every set bit in the sent data sets the corresponding bit of the data in memory.
SMAX
The value stored in memory is the maximum of the existing value and sent data.
This operation assumes signed data.
SMIN
The value stored in memory is the minimum of the existing value and sent data.
This operation assumes signed data.
UMAX
The value stored in memory is the maximum of the existing value and sent data.
This operation assumes unsigned data.
UMIN
The value stored in memory is the minimum of the existing value and sent data.
This operation assumes unsigned data.
A6.4.3
Atomic transactions attributes
The rules for atomic transactions are as follows:
• AWLEN and AWSIZE specify the number of bytes of write data in the transaction. For AtomicCompare,
the number of bytes must include both the compare and swap values.
• If AWLEN indicates a transaction length greater than one, AWSIZE is required to be the full data channel
width.
• Write strobes that are not within the data window, as specified by AWADDR and AWSIZE, must be
deasserted.
• Write strobes within the data window must be asserted.
• All atomic transactions are considered to be Regular.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
114


Chapter A6. Atomic accesses
A6.4. Atomic transactions
For AtomicStore, AtomicLoad, and AtomicSwap
• The write data is 1, 2, 4, or 8 bytes and read data is 1, 2, 4, or 8 bytes respectively.
• AWADDR must be aligned to the total write data size.
• AWBURST must be INCR.
For AtomicCompare
• The write data is 2, 4, 8, 16, or 32 bytes and read data is 1, 2, 4, 8, or 16 bytes.
• AWADDR must be aligned to half the total write data size.
• If AWADDR points to the lower half of the transaction:
– The compare value is sent first. The compare value is in the lower bytes of a single-transfer transaction,
or in the first transfers of a multi-transfer transaction.
– AWBURST must be INCR.
• If AWADDR points to the upper half of the transaction:
– The swap value is sent first. The swap value is in the lower bytes of a single-transfer transaction, or in
the first transfers of a multi-transfer transaction.
– AWBURST must be WRAP.
• There are relaxations to the usual rules for transactions of type WRAP:
– A Length of 1 is permitted.
– AWADDR is not required to be aligned to the transfer size.
– The property Wrap_CLS_Modifiable does not affect AtomicCompare. See A3.1.4 Wrapping address
(WRAP) for more information.
Examples of AtomicCompare transactions with a 64-bit data channel are shown in Figure A6.2.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
115


Chapter A6. Atomic accesses
A6.4. Atomic transactions
0
1
2
3
4
5
6
7
C
S
-
-
-
-
-
-
AWADDR
AWSIZE
AWLEN
0x00
0x01
0x04
0x06
0x00
0x04
0x00
0x08
0
0
0
0
0
0
1
1
1st Transfer 
2nd Transfer 
1st Transfer 
2nd Transfer 
1 (2B)
1 (2B)
2 (4B)
2 (4B)
3 (8B)
3 (8B)
3 (8B)
3 (8B)
S
C
-
-
-
-
-
-
-
-
-
-
C
C
S
S
-
-
-
-
S
S
C
C
C C
C
C
S
S
S
S
S S
S
S
C
C
C
C
C C
C
C
C
C
C
C
S S
S
S
S
S
S
S
S S
S
S
S
S
S
S
C C
C
C
C
C
C
C
AWBURST
INCR
WRAP
INCR
WRAP
INCR
WRAP
INCR
WRAP
Figure A6.2: Examples showing the location of the Compare and Swap values for an AtomicCompare
Note that the compare and swap values are sent in a different order in the last two examples.
A6.4.4
ID use for Atomic transactions
A single AXI ID is used for an Atomic transaction. The same AXI ID is used for the request, write response, and
the read data. This requirement means that the Manager must only use ID values that can be signaled on both
AWID and RID signals.
The ID must be unique-in-flight for Atomic transactions, which means:
• An AtomicStore request can only be issued if there are no outstanding transactions on the write channels
using the same ID value.
• A Manager must not issue a request on the write channel with the same ID value as an outstanding
AtomicStore request.
• An AtomicLoad, AtomicSwap or AtomicCompare request can only be issued if there are no outstanding
transactions on the read or write channels using the same ID value.
• A Manager must not issue a request on the read or write channels with the same ID value as an outstanding
AtomicLoad, AtomicSwap or AtomicCompare request.
• For Atomic transactions that use the read data channel, if the interface includes Unique ID signaling then
RIDUNQ must be asserted if AWIDUNQ was asserted. See A5.2 Unique ID indicator for more details.
These rules ensure there are no ordering requirements between Atomic transactions and other transactions.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
116


Chapter A6. Atomic accesses
A6.4. Atomic transactions
A6.4.5
Request attribute restrictions for Atomic transactions
For Atomic transactions, the following restrictions apply for request attributes:
• AWCACHE and AWDOMAIN are permitted to be any combination valid for the interface type. See Table
A8.7.
• AWSNOOP must be set to all zeros. If AWSNOOP has any other value, AWATOP must be all zeros.
• AWLOCK must be deasserted, not exclusive access.
A6.4.6
Atomic transaction signaling
To support Atomic transactions AWATOP is added to an interface.
Table A6.7: AWATOP signal
Name
Width
Default
Description
AWATOP
6
0x00
Indicates the type and endianness of an
atomic transaction.
The encodings for AWATOP are shown in Table A6.8 and Table A6.9.
Table A6.8: AWATOP encodings
AWATOP[5:0]
Description
0b000000
Non-atomic operation
0b01exxx
AtomicStore
0b10exxx
AtomicLoad
0b110000
AtomicSwap
0b110001
AtomicCompare
For AtomicStore and AtomicLoad transactions AWATOP[3] indicates the endianness that is required for the
atomic operation:
• When deasserted, this bit indicates that the operation is little-endian.
• When asserted, this bit indicates that the operation is big-endian.
The value of AWATOP[3] applies to arithmetic operations only and is ignored for bitwise logical operations.
For AtomicStore and AtomicLoad transactions, Table A6.9 shows the encodings for the operations on the
lower-order AWATOP[2:0] signals.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
117


Chapter A6. Atomic accesses
A6.4. Atomic transactions
Table A6.9: Lower order AWATOP[2:0] encodings
AWATOP[2:0]
Operation
Description
0b000
ADD
Add
0b001
CLR
Bit clear
0b010
EOR
Exclusive OR
0b011
SET
Bit set
0b100
SMAX
Signed maximum
0b101
SMIN
Signed minimum
0b110
UMAX
Unsigned maximum
0b111
UMIN
Unsigned minimum
A6.4.7
Transaction structure
For AtomicLoad, AtomicSwap, and AtomicCompare transactions, the transaction structure is as follows:
• The request is issued on the AW channel.
• The associated transaction data is sent on the W channel.
• The number of write data transfers required on the W channel is determined by the AWLEN signal.
• The relative timing of the Atomic transaction request and the Atomic transaction write data is not specified.
• The Subordinate returns the original data value using the R channel.
• The number of read data transfers is determined from both AWLEN and the AWATOP signals. For the
AtomicCompare operation, if AWLEN indicates a transaction length greater than 1, then the number of read
data transfers is half that specified by AWLEN.
• A Subordinate is permitted to wait for all write data before sending read data. A Manager must be able to
send all write data without receiving any read data.
• A Subordinate is permitted to send all read data before accepting any write data. A Manager must be able to
accept all read data without any write data being accepted.
• A single write response is returned on the B channel. The write response must be given by the Subordinate
only after it has received all write data transfers and the result of the atomic transaction is observable.
The transfers involved in AtomicLoad, AtomicSwap, and AtomicCompare transactions are shown in Figure A6.3.
sent data
Subordinate
AW
W
B
R
Manager
AtomicLoad
sent data
response
sent data
original data
Figure A6.3: AtomicLoad, AtomicSwap, or AtomicCompare transaction
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
118


Chapter A6. Atomic accesses
A6.4. Atomic transactions
For AtomicStore transactions, the transaction structure is as follows:
• The request is issued on the AW channel.
• The associated transaction data is sent on the W channel.
• The number of write data transfers required on the W channel is determined by the AWLEN signal.
• The relative timing of the Atomic transaction request and the Atomic transaction write data is not specified.
• A single write response is returned on the B channel. The write response must be given only by the
Subordinate after it has received all write data transfers and the result of the atomic transaction is observable.
The transfers involved in AtomicStore transactions are shown in Figure A6.4.
sent data
Subordinate
AW
W
B
Manager
AtomicStore
sent data
response
Figure A6.4: AtomicStore transaction
A6.4.8
Response signaling
The write response to an Atomic transaction indicates that the transaction is visible to all required observers.
Atomic transactions that include a read response are visible to all required observers from the point of receiving
the first item of read data.
A Manager is permitted to use either a read or write response as an indication that a transaction is visible to all
required observers.
There is no concept of an error that is associated with the operation, such as overflow. An operation is fully
specified for all input combinations.
For transactions, such as AtomicCompare, where there are multiple outcomes for the transaction, no indication is
provided on the outcome of the transaction. To determine if a Compare and Swap instruction has updated the
memory location, it is necessary to inspect the original data value that is returned as part of the transaction.
It is permitted to give an error response to an Atomic transaction when the transaction reaches a component that
does not support Atomic transactions.
For AtomicLoad, AtomicSwap, and AtomicCompare transactions:
• A Subordinate must send the correct number of read data transfers, even if the write response is DECERR or
SLVERR.
• A Manager might ignore the write response and only use the response that comes with read data.
• If there is an error with the write part of the transaction, it is highly recommended that a DECERR or
SLVERR response is signaled on the read and write responses, so it is not missed by the Manager.
• If there is an error on the write but not on the read, a Manager ignoring the write response must read the
location again to determine whether it was updated.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
119


Chapter A6. Atomic accesses
A6.4. Atomic transactions
A6.4.9
Atomic transaction dependencies
For AtomicLoad, AtomicSwap, and AtomicCompare transactions, Figure A6.5 shows the following Atomic
transaction handshake signal dependencies:
• The Manager must not wait for the Subordinate to assert AWREADY or WREADY before asserting
AWVALID or WVALID.
• The Subordinate can wait for AWVALID or WVALID, or both, before asserting AWREADY.
• The Subordinate can assert AWREADY before AWVALID or WVALID, or both, are asserted.
• The Subordinate can wait for AWVALID or WVALID, or both, before asserting WREADY.
• The Subordinate can assert WREADY before AWVALID or WVALID, or both, are asserted.
• The Subordinate must wait for AWVALID, AWREADY, WVALID, and WREADY to be asserted before
asserting BVALID.
• The Subordinate must also wait for WLAST to be asserted before asserting BVALID because the write
response BRESP, must be signaled only after the last data transfer of a write transaction.
• The Subordinate must not wait for the Manager to assert BREADY before asserting BVALID.
• The Manager can wait for BVALID before asserting BREADY.
• The Manager can assert BREADY before BVALID is asserted.
• The Subordinate must wait for both AWVALID and AWREADY to be asserted before it asserts RVALID to
indicate that valid data is available.
• The Subordinate must not wait for the Manager to assert RREADY before asserting RVALID.
• The Manager can wait for RVALID to be asserted before it asserts RREADY.
• The Manager can assert RREADY before RVALID is asserted.
• The Manager must not wait for the Subordinate to assert RVALID before asserting WVALID.
• The Subordinate can wait for WVALID to be asserted, for all write data transfers, before it asserts RVALID.
• The Manager can assert WVALID before RVALID is asserted.
In the dependency diagram that Figure A6.5 shows:
• A single-headed arrow points to a signal that can be asserted before or after the signal at the start of the arrow.
• A double-headed arrow points to a signal that must be asserted only after assertion of the signal at the start of
the arrow.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
120


Chapter A6. Atomic accesses
A6.4. Atomic transactions
AWREADY
AWVALID
WVALID
BVALID
BREADY
WREADY
RVALID
RREADY
Figure A6.5: Atomic transaction handshake dependencies
A6.4.10
Support for Atomic transactions
The Atomic_Transactions property is used to indicate whether a component supports Atomic transactions.
Table A6.10: Atomic_Transactions property
Atomic_Transactions
Default
Description
True
Atomic Transactions are supported.
False
Y
Atomic Transactions are not supported.
In some implementations this will be a fixed interface attribute, other implementations might enable the
design-time setting of the property.
If a Subordinate or interconnect component declares that it supports Atomic transactions, then it must support all
operation types, sizes, and endianness.
Manager support
A Manager component that supports Atomic transactions can also include a mechanism to suppress the generation
of Atomic transactions to ensure compatibility in systems where Atomic transactions are not supported.
An optional BROADCASTATOMIC pin is specified. When present and deasserted, Atomic transactions are not
issued by the Manager.
Table A6.11: BROADCASTATOMIC tie-off input
Name
Width
Default
Description
BROADCASTATOMIC
1
0b1
Manager tie-off input, used to control the issuing of
Atomic transactions from an interface.
Subordinate support
It is optional for a Subordinate component to support Atomic transactions.
If a Subordinate component only supports Atomic transactions for particular memory types, or for particular
address regions, then the Subordinate must give an appropriate error response for the Atomic transactions that it
does not support.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
121


Chapter A6. Atomic accesses
A6.4. Atomic transactions
Interconnect support
It is optional for an interconnect to support Atomic transactions.
If an interconnect does not support Atomic transactions, all attached Manager components must be configured to
not generate Atomic transactions.
Atomic transactions can be supported at any point within an interconnect that supports them, including passing
Atomic transactions downstream to Subordinate components.
Atomic transactions are not required to be supported for every address location. If Atomic transactions are not
supported for a given address location, then an appropriate error response can be given for the transaction.
See A3.3 Transaction response.
For Device transactions, the Atomic transaction must be passed to the endpoint Subordinate. If the Subordinate is
configured to indicate that it does not support Atomic transactions, then the interconnect must give an error
response for the transaction. An Atomic transaction must not be passed to a component that does not support
Atomic transactions.
For Cacheable transactions, the interconnect can either:
• Perform the atomic operation within the interconnect. This method requires that the interconnect performs
the appropriate read, write, and snoop transactions to complete the operation.
• If the appropriate endpoint Subordinate is configured to indicate that it does support atomic operations, then
the interconnect can pass the atomic operation to the Subordinate.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
122
