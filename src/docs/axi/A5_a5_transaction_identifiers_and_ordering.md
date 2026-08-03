# A5 Transaction identifiers and ordering

Chapter A5
Transaction identifiers and ordering
This chapter describes transaction identifiers and how they can be used to control the ordering of transactions.
It contains the following sections:
• A5.1 Transaction identifiers
• A5.2 Unique ID indicator
• A5.3 Request ordering
• A5.4 Interconnect use of transaction identifiers
• A5.5 Write data and response ordering
• A5.6 Read data ordering
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
89


Chapter A5. Transaction identifiers and ordering
A5.1. Transaction identifiers
A5.1 Transaction identifiers
The AXI protocol includes a transaction identifier (AXI ID). A Manager can use the AXI ID to identify
transactions that must be returned in order.
All transactions with a given AXI ID value must remain ordered, but there is no restriction on the ordering of
transactions with different ID values. A single physical port can support out-of-order transactions by acting as
several logical ports, each handling its transactions in order.
By using AXI IDs, a Manager can issue transactions without waiting for earlier transactions to complete. This can
improve system performance because it enables parallel processing of transactions.
A5.1.1
Transaction ID signals
The read and write request, read data, and write response channels include a transaction ID signal.
Table A5.1: ID signals
Name
Width
Default
Description
AWID
ID_W_WIDTH
All zeros
Transaction identifier used for the ordering of write requests.
BID
ID_W_WIDTH
All zeros
Transaction identifier used for the ordering of write responses.
ARID
ID_R_WIDTH
All zeros
Transaction identifier used for the ordering of read requests.
RID
ID_R_WIDTH
All zeros
Transaction identifier used for the ordering of read data.
The ID width properties are described in Table A5.2.
Table A5.2: ID width properties
Name
Values
Default
Description
ID_W_WIDTH
0..32
-
ID width on write channels in bits, applies to AWID and
BID.
ID_R_WIDTH
0..32
-
ID width on read channels in bits, applies to ARID and
RID.
If a width property is zero, the associated signal is not present.
A Manager that does not support reordering of its requests and responses, or has only one outstanding transaction,
can omit the ID signals from its interface. An attached Subordinate must have its AxID inputs tied LOW.
A Subordinate that does not reorder requests or responses does not need to use ID values.
If a Subordinate does not include ID signals, it cannot be connected to a Manager that does have ID signals,
because the Manager requires BID and RID to be reflected from AWID and ARID.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
90


Chapter A5. Transaction identifiers and ordering
A5.2. Unique ID indicator
A5.2 Unique ID indicator
The unique ID indicator is an optional flag that indicates when a request on the read or write address channels is
using an AXI identifier that is unique for in-flight transactions. A corresponding signal is also on the read and
write response channels to indicate that a transaction is using a unique ID.
The unique ID indicator can be used downstream of the AXI Manager to determine when a request needs to be
ordered with respect to other requests from that Manager. Requests that do not require ordering might not require
tracking in downstream components.
The Unique_ID_Support property is used to indicate whether an interface supports unique ID indication.
Table A5.3: Unique_ID_Support property
Unique_ID_Support
Default
Description
True
Unique ID indicator signals are present on
the interface.
False
Y
Unique ID indicator signals are not present
on the interface.
When Unique_ID_Support is True, the following signals are included on the read request, read data, write request,
and write response channels.
Table A5.4: Unique ID indicator signals
Name
Width
Default
Description
AWIDUNQ,
BIDUNQ,
ARIDUNQ,
RIDUNQ
1
0b0
If asserted high, the ID for this transfer is
unique-in-flight.
The following rules apply to the unique ID indicators:
• When AWIDUNQ is asserted, there must be no outstanding write transactions from this Manager with the
same AWID value.
• A Manager must not issue a write request with the same AWID as an outstanding write transaction that had
AWIDUNQ asserted.
• If AWIDUNQ is deasserted for a request, the corresponding BIDUNQ signal must be deasserted in a single
transfer response or the Completion part of a multi-transfer response.
• If AWIDUNQ is asserted for a request, the corresponding BIDUNQ signal must be asserted in a single
transfer response or the Completion part of a multi-transfer response.
• When ARIDUNQ is asserted, there must be no outstanding read transactions from this Manager with the
same ARID value.
• A Manager must not issue a read request with the same ARID as an outstanding read transaction that had
ARIDUNQ asserted.
• If ARIDUNQ is deasserted for a request, the corresponding RIDUNQ signal must be deasserted for all
response transfers for that transaction.
• If ARIDUNQ is asserted for a request, the corresponding RIDUNQ signal must be asserted for all response
transfers for that transaction.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
91


Chapter A5. Transaction identifiers and ordering
A5.2. Unique ID indicator
• For an Atomic transaction that includes read and write responses, additional rules apply:
– If AWIDUNQ is deasserted for an Atomic request, the corresponding RIDUNQ signal must be
deasserted for all response transfers for that transaction.
– If AWIDUNQ is asserted for an Atomic request, the corresponding RIDUNQ signal must be asserted
for all response transfers for that transaction.
A transaction is outstanding from the cycle that had AxVALID asserted until the cycle when the final response
transfer is accepted by the Manager. If an interface includes BCOMP, the transaction is considered to be
outstanding until a response is received with BCOMP asserted.
An Atomic transaction is outstanding until both write and read responses are accepted by the Manager, see A6.4
Atomic transactions.
Some transaction types specify that AxIDUNQ is required to be asserted, if present. If not specified, asserting
AxIDUNQ is optional, even if there are no outstanding transactions using the same ID.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
92


Chapter A5. Transaction identifiers and ordering
A5.3. Request ordering
A5.3 Request ordering
The AXI request ordering model is based on the use of the transaction identifier, which is signaled on ARID or
AWID.
Transaction requests on the same channel, with the same ID and destination are guaranteed to remain in order.
Transaction responses with the same ID are returned in the same order as the requests were issued.
The ordering model does not give any ordering guarantees between:
• Transactions from different Managers
• Read and write transactions
• Transactions with different IDs
• Transactions to different Peripheral regions
• Transactions to different Memory locations
If a Manager requires ordering between transactions that have no ordering guarantee, the Manager must wait to
receive a response to the first transaction before issuing the second transaction.
A5.3.1
Memory locations and Peripheral regions
The address map in AMBA is made up of Memory locations and Peripheral regions.
A Memory location has all of the following properties:
• A read of a byte from a Memory location returns the last value that was written to that byte location.
• A write to a byte of a Memory location updates the value at that location to a new value that is obtained by a
subsequent read of that location.
• Reading or writing to a Memory location has no side-effects on any other Memory location.
• Observation guarantees for Memory are given for each location.
• The size of a Memory location is equal to the single-copy atomicity size for that component.
A Peripheral region has all of the following properties:
• A read from an address in a Peripheral region does not necessarily return the last value that was written to
that address.
• A write to a byte address in a Peripheral region does not necessarily update the value at that address to a new
value that is obtained by subsequent reads.
• Accessing an address within a Peripheral region might have side-effects on other addresses within that region.
• Observation guarantees for Peripherals are given per region.
• The size of a Peripheral region is IMPLEMENTATION DEFINED but it must be contained within a single
Subordinate component.
A transaction can be to one or more address locations. The locations are determined by AxADDR and any relevant
qualifiers such as the address space.
• Ordering guarantees are given only between accesses to the same Memory location or Peripheral region.
• A transaction to a Peripheral region must be entirely contained within that region.
• A transaction that spans multiple Memory locations has multiple ordering guarantees.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
93


Chapter A5. Transaction identifiers and ordering
A5.3. Request ordering
A5.3.2
Device and Normal requests
Transactions can be either of type Device or Normal.
Device
A read or write where the request has AxCACHE[1] deasserted.
Device transactions can be used to access Peripheral regions or Memory locations.
Normal
A read or write where the request has AxCACHE[1] asserted.
Normal transactions are used to access Memory locations and are not expected to be used to access Peripheral
regions.
A Normal access to a Peripheral region must complete in a protocol compliant manner, but the result is
IMPLEMENTATION DEFINED.
A5.3.3
Observation and completion definitions
For accesses to Peripheral regions, a Device read or write access DRW1 is observed by a Device read or write
access DRW2, when DRW1 arrives at the Subordinate component before DRW2.
For accesses to Memory locations, all of the following apply:
• A write W1 is observed by a write W2, if W2 takes effect after W1.
• A read R1 is observed by a write W2, if R1 returns data from a write W3, when W2 is after W3.
• A write W1 is observed by a read R2, if R2 returns data from either W1 or from write W3, when W3 is after
W1.
Read R1 or write W1 can be of type Device or Normal.
The definitions of write and read completions are:
Write completion response
The cycle when the associated BRESP handshake is given, when BVALID, BREADY and BCOMP (if present)
are asserted.
Read completion response
The cycle when the last associated RDATA handshake is given, when RVALID, RLAST and RREADY are
asserted.
A5.3.4
Manager ordering guarantees
There are three types of ordering model guarantees:
• Observability guarantees before a completion response is received.
• Observability guarantees from a completion response.
• Response ordering guarantees.
Observability guarantees before a completion response is received
All of the following guarantees apply to transactions from the same Manager using the same ID:
• A Device write DW1 is guaranteed to arrive at the destination before Device write DW2, where DW2 is
issued after DW1 and to the same Peripheral region.
• A Device read DR1 is guaranteed to arrive at the destination before Device read DR2, where DR2 is issued
after DR1 and to the same Peripheral region.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
94


Chapter A5. Transaction identifiers and ordering
A5.3. Request ordering
• A write W1 is guaranteed to be observed by a write W2, where W2 is issued after W1 and both have the
same cacheability and Memory location.
• A write W1 that has been observed by a read R2 is guaranteed to be observed by a read R3, where R3 is
issued after R2 and have the same cacheability and Memory location.
Observability guarantees from a completion response
The guarantees from a completion response are as follows:
• For a read request, the completion response guarantees that it is observable to a subsequent read or write
request from any Manager.
• For a Non-bufferable write request, the completion response guarantees that it is observable to a subsequent
read or write request from any Manager.
• For a Bufferable write request, the completion response can be sent from an intermediate point. It does not
guarantee that the write has completed at the endpoint but does guarantee observability, depending on the
Domain of the request:
– Non-shareable: observable to the issuing Manager only.
– Shareable: observable to all other Managers in the Shareable Domain.
– System: observable to all other Managers.
For more information on Domains, see A8.3 Cache coherency and Domains.
Response ordering guarantees
Transaction responses have all the following ordering guarantees:
• A read R1 is guaranteed to receive a response before the response to a read R2, where R2 is issued from the
same Manager after R1 with the same ID.
• A write W1 is guaranteed to receive a response before the response to a write W2, where W2 is issued from
the same Manager after W1 with the same ID.
A5.3.5
Subordinate ordering requirements
To meet the Manager ordering guarantees, Subordinate interfaces must meet the following requirements.
Peripheral locations
For Peripheral locations, the execution order of transactions to Peripheral locations is IMPLEMENTATION
DEFINED. This execution order is typically expected to match the arrival order but that is not a requirement.
Memory locations
For transactions with the same cacheability and Memory location:
• A write W1 must be ordered before a write W2 with the same ID, where W2 is received after W1 is received.
• A write W1 must be ordered before a write W2, where W2 is received after the completion response for W1
is given.
• A write W1 must be ordered before a read R2, where R2 is received after the completion response for W1 is
given.
• A read R1 must be ordered before a write W2, where W2 is received after the completion response for R1 is
given.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
95


Chapter A5. Transaction identifiers and ordering
A5.3. Request ordering
Response ordering requirements
• The response to read R1 must be returned before the response to a read R2, where R2 is received after R1
with the same ID.
• The response to write W1 must be returned before the response to a write W2, where W2 is received after
W1 with the same ID.
A5.3.6
Interconnect ordering requirements
An interconnect component has the following attributes:
• A request is received on one port and is either issued on a different port or responded to.
• A response is received on one port and is either issued on a different port or consumed.
When the interconnect issues requests or responses, it must adhere to the following requirements:
• A read R1 request must be issued before a read R2 request, where R2 is received after R1, with the same ID
and to the same or overlapping locations.
• A write W1 request must be issued before a write W2 request, where W2 is received after W1, with the same
ID, to the same or overlapping locations.
• A Device read DR1 request must be issued before a Device read DR2 request, where DR2 is received after
DR1, with the same ID and to the same Peripheral region.
• A Device write DW1 request must be issued before a Device write DW2 request, where DW2 is received
after DW1, with the same ID and to the same Peripheral region.
• A read R1 response must be issued before a read R2 response, where R2 is received after R1, with the same
ID.
• A write W1 response must be issued before a write W2 response, where W2 is received after W1, with the
same ID.
When the interconnect is acting as a Subordinate component, it must also adhere to the Subordinate requirements.
Any manipulation of the AXI ID values that are associated with a transaction must ensure that the ordering
requirements of the original ID values are maintained.
A5.3.7
Response before the endpoint
To improve system performance, it is possible for an intermediate component to issue a response to some
transactions. This action is known as an early response. The intermediate component issuing an early response
must ensure that visibility and ordering guarantees are met.
Early read response
For Normal read transactions, an intermediate component can respond with read data from a local memory if it is
up to date with respect to all earlier writes to the same or overlapping address. In this case, the request is not
required to propagate beyond the intermediate component.
An intermediate component must observe ID ordering rules, which means a read response can only be sent if all
earlier reads with the same ID have already had a response.
Early write response
For Bufferable write transactions (AWCACHE[0] is asserted), an intermediate component can send an early write
response for transactions that have no downstream observers. If the intermediate component sends an early write
response, the intermediate component can store a local copy of the data, but must propagate the transaction
downstream, before discarding that data.
An intermediate component must observe ID ordering rules, which means a write response can only be sent if all
earlier writes with the same ID have already had a response.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
96


Chapter A5. Transaction identifiers and ordering
A5.3. Request ordering
After sending an early write response, the component must be responsible for ordering and observability of that
transaction until the write has been propagated downstream, and a write response is received. During the period
between sending the early write response and receiving a response from downstream, the component must ensure
that:
• If an early write response was given for a Normal transaction, all subsequent transactions to the same or
overlapping Memory locations are ordered after the write that has had an early response.
• If an early write response was given for a Device transaction, then all subsequent transactions to the same
Peripheral region are ordered after the write that has had an early response.
When giving an early write response for a Device Bufferable transaction, the intermediate component is expected
to propagate the write transaction without dependency on other transactions. The intermediate component cannot
wait for another read or write to arrive before propagating a previous Device write.
A5.3.8
Ordering between requests with different memory types
There are no ordering requirements between Cacheable requests and Device or Non-cacheable Normal requests.
Responses must be in order for transactions with the same AXI ID, irrespective of cacheability.
Ordering requirements between Device and Normal Non-cacheable requests depends on the
Device_Normal_Independence property.
Table A5.5: Device_Normal_Independence property
Device_Normal_Independence
Default
Description
True
A Device request is permitted to overtake, or be overtaken by, a
Normal Non-cacheable request with the same ID to the same
location.
False
Y
Device and Normal Non-cacheable requests with the same ID, to
the same location must be observed in issue order.
Guidance for connecting Manager and Subordinate interfaces with different values of
Device_Normal_Independence is shown in Table A5.6.
Table A5.6: Device_Normal_Independence interoperability
Subordinate: False
Subordinate: True
Manager: False
Compatible.
Incompatible.
The Subordinate might not meet the ordering
requirements of the Manager.
Manager: True
Compatible.
The Subordinate might enforce stricter
ordering than required.
Compatible.
A5.3.9
Ordered write observation
To improve compatibility with interface protocols that support a different ordering model, a Subordinate interface
can give stronger ordering guarantees for write transactions, known as Ordered Write Observation.
The Ordered_Write_Observation property is used to define whether an interface has Ordered Write Observation.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
97


Chapter A5. Transaction identifiers and ordering
A5.3. Request ordering
Table A5.7: Ordered_Write_Observation property
Ordered_Write_Observation
Default
Description
True
The interface exhibits Ordered Write Observation.
False
Y
The interface does not exhibit Ordered Write Observation.
An interface that exhibits Ordered Write Observation gives guarantees for write transactions that are not dependent
on the destination or address:
• A write W1 is guaranteed to be observed by a write W2, where W2 is issued after W1, from the same
Manager, with the same ID.
When using Ordered Write Observation, a Manager can issue multiple write requests without waiting for write
responses, and they are observed in issue order. This can result in improved performance when using the
Producer-Consumer ordering model.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
98


Chapter A5. Transaction identifiers and ordering
A5.4. Interconnect use of transaction identifiers
A5.4 Interconnect use of transaction identifiers
When a Manager is connected to an interconnect, the interconnect appends additional bits to the AWID and ARID
identifiers that are unique to that Manager port. This has two effects:
• Managers do not have to know what ID values are used by other Managers because the interconnect makes
the ID values used by each Manager unique by appending the Manager number to the original identifier.
• The ID identifier at a Subordinate interface is wider than the ID identifier at a Manager interface.
For write responses, the interconnect uses the additional bits of the BID identifier to determine which Manager
port the write response is destined for. The interconnect removes these bits of the BID identifier before passing the
BID value to the correct Manager port.
For read data, the interconnect uses the additional bits of the RID identifier to determine which Manager port the
read data is destined for. The interconnect removes these bits of the RID identifier before passing the RID value to
the correct Manager port.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
99


Chapter A5. Transaction identifiers and ordering
A5.5. Write data and response ordering
A5.5 Write data and response ordering
A Manager must issue write data in the same order that it issues the transaction requests.
When using credited transport, this rule applies to each Resource Plane. Therefore, it is permitted to send data out
of order with respect to requests if they are using different Resource Planes. Interleaving data transfers for
different transactions is permitted if they are on different Resource Planes. See A2.4.2 Resource Planes for more
information on Resource Planes.
Figure A5.1 shows an example of write data ordering and interleaving when using two Resource Planes, it shows:
• Data for the transaction with ID1 is permitted to be issued before data for ID0 as they are using different RPs.
• Data transfers for ID1 can be interleaved between transfers for ID0 or ID2, as they are using different RPs.
0
1
2
3
4
5
6
7
8
9
10
ACLK
AWVALID
AWID[1:0]
ID0
ID1
ID2
AWRP[1:0]
RP0
RP1 RP0
WVALID
WRP[1:0]
RP1 RP0 RP1 RP0 RP0 RP1
Figure A5.1: Example of a write data ordering with two Resource Planes
A Subordinate must ensure that the BID value of a write response matches the AWID value of the request to which
it is responding.
An interconnect must ensure that write responses from a sequence of transactions with the same AWID value
targeting different Subordinates are received by the Manager in request order.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
100


Chapter A5. Transaction identifiers and ordering
A5.6. Read data ordering
A5.6 Read data ordering
The Subordinate must ensure that the RID value of any returned data matches the ARID value of the request to
which it is responding.
The interconnect must ensure that read data from a sequence of transactions with the same ARID value targeting
different Subordinates are received by the Manager in request order.
The read data reordering depth is the maximum number of accepted requests for which a Subordinate might send
read data. A Subordinate that sends read data in the same order as the requests were received has a read data
reordering depth of one.
The read data reordering depth is a static value that can be specified by the designer of the Subordinate.
There is no mechanism for a Manager to dynamically determine the read data reordering depth of a Subordinate.
A5.6.1
Read data interleaving
AXI ordering permits read data transfers with different ID values to be interleaved. This applies to all transactions
that can have multiple read data transfers, including Atomic transactions.
Some AXI Manager and interconnect components can be more efficiently designed if it is determined at
design-time whether the attached Subordinate interface will interleave read data from different transactions.
The property Read_Interleaving_Disabled is used to indicate whether an interface supports the interleaving of read
data transfers from different transactions.
Table A5.8: Read_Interleaving_Disabled property
Read_Interleaving_Disabled
Default
Description
True
A Manager interface is not capable of receiving read data that is
interleaved.
A Subordinate interface is guaranteed not to interleave read data.
False
Y
A Manager interface is capable of receiving read data that is
interleaved.
A Subordinate interface might interleave data from read
transactions with different ARID values.
For some interfaces, this property can be used as a configuration control, for others it is a capability indicator. All
Managers that issue transactions with different IDs must be designed to accept interleaved data. Managers might
use the configuration option to disable interleaving as an optimization when the attached Subordinate supports the
disabling of interleaving.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
101


Chapter A5. Transaction identifiers and ordering
A5.6. Read data ordering
A5.6.2
Read data chunking
The read data chunking option enables a Subordinate interface to reorder read data within a transaction using a
128b granule. The start address might be used as a hint to determine which chunk to send first, but the Subordinate
is permitted to return chunks of data in any order.
The property Read_Data_Chunking is used to indicate whether an interface supports the return of read data in
reorderable chunks.
Table A5.9: Read_Data_Chunking property
Read_Data_Chunking
Default
Description
True
Read data chunking is supported.
False
Y
Read data chunking is not supported, no chunking signals are
present.
A5.6.2.1
Read data chunking signaling
When read data chunking is supported, the following signals as shown in Table A5.10 are added to the read request
and data channel.
Table A5.10: Read data chunking signals
Name
Width
Default
Description
ARCHUNKEN
1
0b0
If asserted in a read request, the Subordinate can
send read data in 128b chunks.
RCHUNKV
1
0b0
Asserted high to indicate that RCHUNKNUM and
RCHUNKSTRB are valid. It must be the same for
every response of the transaction.
RCHUNKNUM
RCHUNKNUM_WIDTH
All zeros
Indicates the chunk number being transferred.
Chunks are numbered incrementally from zero,
according to the data width and base address of
the transaction.
RCHUNKSTRB
RCHUNKSTRB_WIDTH
All ones
Indicates the read data chunks that are valid for
this transfer.
Each bit corresponds to 128 bits of data. The least
significant bit of RCHUNKSTRB corresponds to
the least significant 128 bits of RDATA.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
102


Chapter A5. Transaction identifiers and ordering
A5.6. Read data ordering
The RCHUNKNUM_WIDTH property defines the width of the RCHUNKNUM signal.
Table A5.11: RCHUNKNUM_WIDTH property
Name
Values
Default
Description
RCHUNKNUM_WIDTH
0, 1, 5, 6, 7, 8
0
Width of RCHUNKNUM in bits.
Must be 0 if Read_Data_Chunking == False else
0 or 1 if DATA_WIDTH < 128
8 if DATA_WIDTH == 128
7 if DATA_WIDTH == 256
6 if DATA_WIDTH == 512
5 if DATA_WIDTH == 1024
The RCHUNKSTRB_WIDTH property defines the width of the RCHUNKSTRB signal.
Table A5.12: RCHUNKSTRB_WIDTH property
Name
Values
Default
Description
RCHUNKSTRB_WIDTH
0, 1, 2, 4, 8
0
Width of RCHUNKSTRB in bits.
Must be 0 if Read_Data_Chunking == False else
0 or 1 if DATA_WIDTH < 256
2 if DATA_WIDTH == 256
4 if DATA_WIDTH == 512
8 if DATA_WIDTH == 1024
Interfaces with a small DATA_WIDTH can include RCHUNKNUM and RCHUNKSTRB signals as 1-bit wide
or omit them from the interface. When using interface protection, the RCHUNKCHK signal covers both of these
signals, so RCHUNKNUM and RCHUNKSTRB must be the same width for connected components.
It is recommended that RCHUNKNUM and RCHUNKSTRB are omitted if not required by the interface.
A5.6.2.2
Read data chunking protocol rules
In the read data chunking protocol, all the following rules apply:
• ARCHUNKEN must only be asserted for transactions with the following attributes:
– Size is equal to the data channel width, or Length is one transfer.
– Size is 128 bits or larger.
– Addr is aligned to 16 bytes.
– Burst is INCR or WRAP.
– Opcode is ReadNoSnoop, ReadOnce, ReadOnceCleanInvalid, or ReadOnceMakeInvalid.
• The ID value must be unique-in-flight, which means:
– ARCHUNKEN can only be asserted if there are no outstanding read transactions using the same ARID
value.
– The Manager must not issue a request on the read channel with the same ARID as an outstanding
request that had ARCHUNKEN asserted.
– If present on the interface, ARIDUNQ must be asserted if ARCHUNKEN is asserted.
• If ARCHUNKEN is deasserted, RCHUNKV must be deasserted for all response transfers of the transaction.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
103


Chapter A5. Transaction identifiers and ordering
A5.6. Read data ordering
• If ARCHUNKEN is asserted, RCHUNKV can be asserted for response transfers of the transaction.
• RCHUNKV must be the same for every response transfer of a transaction.
• When RVALID and RCHUNKV are asserted, RCHUNKNUM must be between zero and ARLEN.
• When RVALID and RCHUNKV are asserted, RCHUNKSTRB must not be zero.
• When RVALID and RCHUNKV are asserted, RLAST must only be asserted for the final response transfer
of the transaction, irrespective of RCHUNKNUM and RCHUNKSTRB.
• When RVALID is asserted and RCHUNKV is deasserted, RCHUNKNUM and RCHUNKSTRB can take
any value.
The number of data chunks transferred must be consistent with ARLEN and ARSIZE, so the number of bytes
transferred in a transaction is the same whether chunking is enabled or not. Note that when using read data
chunking, a transaction might have more read data transfers than indicated by ARLEN.
For unaligned transactions, chunks at addresses lower than ARADDR are not transferred and must have
RCHUNKSTRB deasserted.
A5.6.2.3
Interoperability
If a Manager supports read data chunking, then downstream interconnect and Subordinates can reduce their
buffering if they also support chunking. An interconnect which connects to components with a mixture of
chunking support can drive ARCHUNKEN and RCHUNKV according to the capabilities of the attached
components.
When connecting interfaces with different values for the Read_Data_Chunking property, the following rules apply
as shown in Table A5.13.
Table A5.13: Read_Data_Chunking interoperability
Subordinate: False
Subordinate: True
Manager: False
ARCHUNKEN is not present.
Subordinate ARCHUNKEN input is tied
low.
RCHUNKV is not present.
Subordinate RCHUNKV output is
unconnected.
RCHUNKNUM is not present.
Subordinate RCHUNKNUM output is
unconnected.
RCHUNKSTRB is not present.
Subordinate RCHUNKSTRB output is
unconnected.
Full data transfers are sent in natural order.
Full data transfers are sent in natural order.
Manager: True
Manager ARCHUNKEN output is
unconnected.
Chunking signals are connected.
Manager RCHUNKV input is tied low.
Read data can be reordered and sent in
chunks.
Manager RCHUNKNUM input is tied.
Manager RCHUNKSTRB input is tied.
Full data transfers are sent in natural order.
A5.6.2.4
Chunking examples
In these examples, each row in the figure represents a transfer and the shaded cells indicate bytes that are not
transferred.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
104


Chapter A5. Transaction identifiers and ordering
A5.6. Read data ordering
Figure A5.2 shows a transaction on a 256-bit width read data channel where:
• Addr is 0x00.
• Length is 2 transfers.
• Size is 256 bits.
• Burst is INCR.
RCHUNKNUM = 1; RCHUNKSTRB = 0b01; RLAST = 0
RCHUNKNUM = 0; RCHUNKSTRB = 0b10; RLAST = 0
RCHUNKNUM = 1; RCHUNKSTRB = 0b10; RLAST = 0
RCHUNKNUM = 0; RCHUNKSTRB = 0b01; RLAST = 1
1st transfer
2nd transfer
3rd transfer
4th transfer
127              0
0x20
0x00
RDATA
255           128
0x10
0x30
Figure A5.2: Example of read data returned in 128-bit chunks
Figure A5.3 shows a transaction on a 256-bit width read data channel, where:
• Addr is 0x10.
• Length is 2 transfers.
• Size is 256 bits.
• Burst is INCR.
RCHUNKNUM = 0; RCHUNKSTRB = 0b10; RLAST = 0
RCHUNKNUM = 1; RCHUNKSTRB = 0b11; RLAST = 1
1st transfer
2nd transfer
127              0
0x20
RDATA
255           128
0x10
0x30
Figure A5.3: Example with an unaligned address and a mixture of 128-bit and 256-bit chunks
Figure A5.4 shows a transaction on a 128-bit width read data channel, where:
• Addr is 0x10.
• Length is 4 transfers.
• Size is 128 bits.
• Burst is WRAP.
• RCHUNKSTRB is not present.
The Subordinate uses the start address as a hint and sends the chunk at 0x10 first.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
105


Chapter A5. Transaction identifiers and ordering
A5.6. Read data ordering
RCHUNKNUM = 1; RLAST = 0
RCHUNKNUM = 3; RLAST = 0
RCHUNKNUM = 0; RLAST = 0
RCHUNKNUM = 2; RLAST = 1
1st transfer
2nd transfer
3rd transfer
4th transfer
127              0
0x10
0x30
0x00
0x20
RDATA
Figure A5.4: Example of a wrapping transaction
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
106
