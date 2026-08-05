# A2 AXI transport

Chapter A2
AXI transport
AXI uses channels to transport request, data and response transfers between components.
This chapter describes the AXI transport with options for either a VALID-READY handshake or credited channels.
It contains the following sections:
• A2.1 Clock and reset
• A2.2 AXI transport options
• A2.3 Valid-Ready transport
• A2.4 Credited transport
• A2.5 Pipelining and register stages
• A2.6 AXI transactions and transfers
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
26


Chapter A2. AXI transport
A2.1. Clock and reset
A2.1 Clock and reset
This section describes the requirements for implementing the AXI global clock and reset signals ACLK and
ARESETn.
A2.1.1
Clock
Each AXI interface has a single clock signal, ACLK. All input signals are sampled on the rising edge of ACLK.
All output signal changes can only occur after the rising edge of ACLK.
There must be no combinatorial paths between input and output signals on an interface.
A2.1.2
Reset
The AXI protocol uses a single active-LOW reset signal, ARESETn. The reset signal can be asserted
asynchronously, but deassertion can only be synchronous with a rising edge of ACLK.
Signals that are required to be deasserted during reset must remain deasserted at least until the rising ACLK edge
after ARESETn is HIGH. The earliest point these signals can be asserted is at a rising ACLK edge after
ARESETn is HIGH.
Other signals can take any value during reset.
For example, for VALID, this is point b in Figure A2.1.
ACLK
ARESETn
VALID
a
b
Figure A2.1: Exit from reset
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
27


Chapter A2. AXI transport
A2.2. AXI transport options
A2.2 AXI transport options
Two options are available for AXI transport:
• Ready, where every channel includes VALID and READY signals. The transmitter asserts VALID when it
has a transfer to send. A transfer occurs when VALID and READY are both HIGH.
• Credited, where every channel includes VALID and CRDT signals. The receiver uses CRDT signals to give
credits to the transmitter. The transmitter can assert VALID to send a transfer if it has an appropriate credit.
This transport is good for high frequency operation and enables the use of Resource Planes on a link.
All AXI channels on an interface use the same type of transport, Table A2.1 shows how this is configured using the
AXI_Transport property.
Table A2.1: AXI_Transport property
AXI_Transport
Default
Description
Credited
AXI channels use CRDT flow control signals.
Ready
Y
AXI channels use READY flow control signals.
The following rules apply to transport configuration:
• Connected Manager and Subordinate interfaces must have the same value for the AXI_Transport property.
• Credited transport can be used with AXI5 interfaces only.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
28


Chapter A2. AXI transport
A2.3. Valid-Ready transport
A2.3 Valid-Ready transport
When using a Valid-Ready transport, all AXI channels use the same VALID-READY handshake process to
transfer address, data, and control information. This two-way flow control mechanism means both the Manager
and Subordinate can control the rate that the information moves between Manager and Subordinate. The
transmitter generates the VALID signal to indicate when the address, data, or control information is available. The
receiver generates the READY signal to indicate that it can accept the information. Transfer occurs only when
both the VALID and READY signals are HIGH.
VALID signals must be LOW during reset.
Figure A2.2, Figure A2.3 and Figure A2.4 show examples of the handshake process.
The transmitter presents information after edge 1 and asserts the VALID signal as shown in Figure A2.2. The
receiver asserts the READY signal after edge 2. The transmitter must keep its information stable until the transfer
occurs at edge 3, when this assertion is recognized.
0
1
2
3
4
ACLK
INFORMATION
VALID
READY
Figure A2.2: VALID before READY handshake
A transmitter is not permitted to wait until READY is asserted before asserting VALID.
When VALID is asserted, it must remain asserted until the handshake occurs, at a rising clock edge when VALID
and READY are both asserted.
In Figure A2.3, the receiver asserts READY after edge 1, before the address, data, or control information is valid.
This assertion indicates that it can accept the information. The transmitter presents the information and asserts
VALID after edge 2, then the transfer occurs at edge 3, when this assertion is recognized. In this case, transfer
occurs in a single cycle.
0
1
2
3
4
ACLK
INFORMATION
VALID
READY
Figure A2.3: READY before VALID handshake
A receiver is permitted to wait for VALID to be asserted before asserting the corresponding READY.
If READY is asserted, it is permitted to deassert READY before VALID is asserted.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
29


Chapter A2. AXI transport
A2.3. Valid-Ready transport
In Figure A2.4, both the transmitter and receiver happen to indicate that they can transfer the address, data, or
control information after edge 1. In this case, the transfer occurs at the rising clock edge when the assertion of
both VALID and READY can be recognized. These assertions mean that the transfer occurs at edge 2.
0
1
2
3
4
ACLK
INFORMATION
VALID
READY
Figure A2.4: VALID with READY handshake
The default state of READY signals can be either HIGH or LOW.
For request channels, it is recommended to use HIGH as the default state to minimize latency. In that case, the
Subordinate must be able to accept any valid request that is presented to it.
A2.3.1
Valid-Ready signals
Table A2.2 shows the VALID and READY signals. VALID signals are present whether using Valid-Ready
transport or credited transport.
Table A2.2: Valid and Ready signals
Name
Width
Default
Description
AWVALID
1
-
Asserted high to indicate that the signals on the AW channel are valid.
AWREADY
1
-
Asserted high to indicate that a transfer on the AW channel can be accepted.
WVALID
1
-
Asserted high to indicate that the signals on the W channel are valid.
WREADY
1
-
Asserted high to indicate that a transfer on the W channel can be accepted.
BVALID
1
-
Asserted high to indicate that the signals on the B channel are valid.
BREADY
1
-
Asserted high to indicate that a transfer on the B channel can be accepted.
ARVALID
1
-
Asserted high to indicate that the signals on the AR channel are valid.
ARREADY
1
-
Asserted high to indicate that a transfer on the AR channel can be accepted.
RVALID
1
-
Asserted high to indicate that the signals on the R channel are valid.
RREADY
1
-
Asserted high to indicate that a transfer on the R channel can be accepted.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
30


Chapter A2. AXI transport
A2.3. Valid-Ready transport
A2.3.2
Dependencies between channel handshake signals
There are dependencies between channels for write, read, and snoop transactions. These are described in the
sections below and include dependency diagrams, where:
• Single-headed arrows point to signals that can be asserted before or after the signal at the start of the arrow.
• Double-headed arrows point to signals that must be asserted only after assertion of the signal at the start of
the arrow.
A2.3.2.1
Write transaction dependencies
For transactions on the write channels, Figure A2.5 shows the handshake signal dependencies. The rules are:
• The Manager must not wait for the Subordinate to assert AWREADY or WREADY before asserting
AWVALID or WVALID. This applies to every write data transfer in a transaction.
• The Subordinate can wait for AWVALID or WVALID, or both, before asserting AWREADY.
• The Subordinate can assert AWREADY before AWVALID or WVALID, or both, are asserted.
• The Subordinate can wait for AWVALID or WVALID, or both, before asserting WREADY.
• The Subordinate can assert WREADY before AWVALID or WVALID, or both, are asserted.
• The Subordinate must wait for AWVALID, AWREADY, WVALID, and WREADY to be asserted before
asserting BVALID.
• The Subordinate must wait for the last write data transfer before asserting BVALID. The last write data
transfer has WLAST asserted, see A3.2.1 Write data channel (W).
• The Subordinate must not wait for the Manager to assert BREADY before asserting BVALID.
• The Manager can wait for BVALID before asserting BREADY.
• The Manager can assert BREADY before BVALID is asserted.
WREADY
AWVALID
AWREADY
WVALID
BVALID
BREADY
Figure A2.5: Write transaction handshake dependencies
For transactions on the write channels that do not include data, WVALID and WREADY are not included in the
dependencies.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
31


Chapter A2. AXI transport
A2.3. Valid-Ready transport
A2.3.2.2
Read transaction dependencies
For transactions on the read channels, Figure A2.6 shows the handshake signal dependencies. The rules are:
• The Manager must not wait for the Subordinate to assert ARREADY before asserting ARVALID.
• The Subordinate can wait for ARVALID to be asserted before it asserts ARREADY.
• The Subordinate can assert ARREADY before ARVALID is asserted.
• The Subordinate must wait for both ARVALID and ARREADY to be asserted before it asserts RVALID to
indicate that valid data is available.
• The Subordinate must not wait for the Manager to assert RREADY before asserting RVALID.
• The Manager can wait for RVALID to be asserted before it asserts RREADY.
• The Manager can assert RREADY before RVALID is asserted.
ARREADY
RREADY
ARVALID
RVALID
Figure A2.6: Read transaction handshake dependencies
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
32


Chapter A2. AXI transport
A2.4. Credited transport
A2.4 Credited transport
When the AXI_Transport property is Credited, AXI channels use a credited transport.
Table A2.3 shows a list of all signals that can be added to a channel when credited transport is used. Signal names
are the base name, when instantiated each includes a prefix to indicate which channel they belong.
A channel has a transmitter (Tx) and a receiver (Rx).
Table A2.3: Credited channel signals
Name
Width
Source
Presence
Description
VALID
1
Tx
-
When asserted HIGH, there is one
transfer from Tx to Rx.
PENDING
1
Tx
AXI_Transport == Credited
Asserted HIGH to indicate that a
transfer might occur in the following
cycle. See A2.4.4 Transfer-level
clock gating.
RP
clog2(Num_RP)
Tx
Num_RP > 1
Encoded indicator of the Resource
Plane number for a transfer. See
A2.4.2 Resource Planes.
SHAREDCRD
1
Tx
Shared_Credits == True
Asserted HIGH to indicate that the
transfer is using a shared credit.
See A2.4.3 Shared credits.
CRDT
Num_RP
Rx
AXI_Transport == Credited
Asserted HIGH to give one credit on
the respective resource plane.
CRDTSH
1
Rx
Shared_Credits == True
Asserted HIGH to give one shared
credit. See A2.4.3 Shared credits.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
33


Chapter A2. AXI transport
A2.4. Credited transport
A2.4.1
Credited flow control
The following rules apply to a credited channel:
• During reset the channel transmitter has no credits, the receiver has all available credits. All CRDT and
CRDTSH signals must be LOW.
• Each cycle that CRDT or CRDTSH is asserted gives one credit per bit asserted, to the channel transmitter.
• The channel transmitter uses a credit each cycle that VALID is asserted.
• VALID must not be asserted when the channel transmitter has zero credits.
• The minimum number of credits that the receiver can give is 1 per resource plane.
• The maximum number of credits that the receiver can give is 15 per resource plane and 15 shared credits.
There must not be combinatorial paths between credit signals and other signals on a channel in either direction.
This restriction has the following consequences:
• A credit cannot be used for a transfer in the same cycle that it is given.
• A credit cannot be given in the same cycle that it is used by a transfer.
An example of transfers on a channel is shown in Figure A2.7. In this example, the receiver has two credits
available.
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
ARESETn
CRDT
VALID
a
b
d
c
e
Figure A2.7: Example Transfers
Cycle 0
At reset the Tx has no credits.
Cycle 3
One credit is given by the Rx.
Cycle 4
The Tx uses the credit for a transfer. Another credit is given by the Rx.
Cycle 5
The Tx uses the second credit for a transfer.
Cycle 7
The credit used in cycle 4 is given back to the Tx.
Cycle 8
The Tx uses the credit for a transfer.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
34


Chapter A2. AXI transport
A2.4. Credited transport
A2.4.2
Resource Planes
Resource Planes (RP) are used to enable independence between traffic sharing a channel. This could be to avoid
deadlock scenarios or to improve quality-of-service. Each RP has dedicated credits so it is possible to give credits
for one RP, allowing it to make progress when another RP is blocked waiting for credit.
• Transfers using different Resource Planes must not block one another between transmitter and receiver.
If transfers remain on separate Resource Planes across multiple links, then the non-blocking guarantee can be
extended.
The parameter Num_RP specifies how many RPs are supported on a channel.
The RP signal indicates the Resource Plane number for each transfer, from 0 to Num_RP-1.
The width of RP is clog2(Num_RP). For example, if Num_RP is 5 the width of RP is 3. If Num_RP is 1, there is
no RP signal.
Credits are given per Resource Plane. The CRDT signal has one bit per Resource Plane, therefore the receiver can
give up to one credit per RP per cycle. The number of credits for each RP is permitted to be different.
• The transmitter can issue a transfer on a specific RP only if it has at least one credit for that RP.
• The receiver must be able to give at least one dedicated credit per RP supported.
• The AR, AW and W channels can have multiple RPs.
• The AW and W transfers in the same transaction must use the same RP number.
There are no ordering guarantees between transfers using different RPs. This means:
• A Manager must not issue a request transfer that has the same ID as an outstanding transaction on the same
channel but a different RP.
• A Manager can interleave write data transfers for different transactions if they are using different RPs. See
A5.5 Write data and response ordering.
The B and R channels have one RP.
Table A2.5 shows the properties that define the number of RPs.
Table A2.5: Resource plane number properties
Name
Values
Default
Description
Num_RP_AWW
1-8
1
Number of resource planes on the AW and W channels.
Num_RP_AR
1-8
1
Number of resource planes on the AR channel.
Connected interfaces can be configured to have a different number of RPs, but a Manager must not require the use
of more RPs than can be provided by the attached Subordinate.
If the AXI_Transport property is Ready: Num_RP_AWW and Num_RP_AR must be 1.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
35


Chapter A2. AXI transport
A2.4. Credited transport
A2.4.3
Shared credits
Any channel that includes multiple RPs can optionally include shared credits to improve buffer utilization when
throughput varies on different RPs. A receiver supporting shared credits can allocate its buffers between those
dedicated to one RP and those for any RP.
Table A2.6 shows the properties that define whether shared credits are supported.
Table A2.6: Shared credit properties
Name
Values
Default
Description
Shared_Credits_AW
True,
False
False
If True, Shared credits are supported on the AW channel and
the AWCRDTSH and AWSHAREDCRD signals are included.
Shared_Credits_W
True,
False
False
If True, Shared credits are supported on the W channel and the
WCRDTSH and WSHAREDCRD signals are included.
Shared_Credits_AR
True,
False
False
If True, Shared credits are supported on the AR channel and
the ARCRDTSH and ARSHAREDCRD signals are included.
The following rules apply:
• If the AXI_Transport property is Ready: Shared_Credits_AW, Shared_Credits_W and Shared_Credits_AR
must be False.
• If Num_RP_AWW is 1: Shared_Credits_AW and Shared_Credits_W must be False.
• If Num_RP_AR is 1: Shared_Credits_AR must be False.
• The CRDTSH signal is asserted by the receiver to give one shared credit to the transmitter. CRDTSH can be
asserted without asserting CRDT.
• A transmitter can use a shared credit to send a transfer on any RP.
• A receiver must give independence guarantees between RPs, whether the transmitter is using a shared or
dedicated credit.
• The SHAREDCRD signal is asserted by the transmitter alongside VALID to indicate that the transfer is
using a shared credit.
It is recommended that a transmitter uses a dedicated rather than shared credit for a transfer if it has both. This is
because shared credits are more flexible so could be retained for a transfer that does not have a dedicated credit.
The compatibility between Manager and Subordinate interfaces according to the values of the Shared_Credits
properties is shown in Table A2.7.
Table A2.7: Shared credits compatibility
Shared_Credits
Subordinate: False
Subordinate: True
Manager: False
Compatible.
Compatible.
SHAREDCRD inputs tied LOW, CRDTSH
outputs unconnected.
Functional, but available shared credits are
unused.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
36


Chapter A2. AXI transport
A2.4. Credited transport
Manager: True
Compatible.
SHAREDCRD outputs unconnected,
CRDTSH inputs tied LOW.
Manager does not receive any shared credits.
Compatible.
An example of the use of a channel with 3 Resource Planes and shared credits is shown in Figure A2.8.
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
CRDT[0]
CRDT[1]
CRDT[2]
CRDTSH
VALID
SHAREDCRD
RP[1:0]
RP1
RP2 RP2
RP0
Dedicated RP0 credit count
0
0
1
1
1
1
1
1
1
0
1
Dedicated RP1 credit count
0
0
1
0
1
1
1
1
1
1
1
Dedicated RP2 credit count
0
0
1
1
1
1
0
0
1
1
1
Shared credit count
0
0
1
1
1
1
1
0
1
1
2
Figure A2.8: Example of a channel with 3 Resource Planes
Cycle 0
The Transmitter has no credits.
Cycle 1
The Receiver gives one credit for each RP and one shared credit.
Cycle 2
The Transmitter sends a transfer on RP1 using a dedicated credit.
Cycle 3
The Receiver gives a dedicated credit back to the Transmitter for RP1.
Cycle 5
The Transmitter sends a transfer on RP2 using a dedicated credit.
Cycle 6
The Transmitter sends a transfer on RP2 using a shared credit, as no dedicated credits are available.
Cycle 7
The Receiver gives a shared credit, and a dedicated credit for RP2 back to the Transmitter.
Cycle 8
The Transmitter sends a transfer on RP0 using a dedicated credit
Cycle 9
The Receiver gives a dedicated credit back to the Transmitter for RP0, along with an additional
shared credit.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
37


Chapter A2. AXI transport
A2.4. Credited transport
A2.4.4
Transfer-level clock gating
The PENDING signal associated with a channel is guaranteed to be asserted the cycle before a transfer is sent, so
can be used to gate the clock of the receiver circuitry.
The following rules apply:
• There is one PENDING signal per channel.
• It is required that PENDING is asserted in the cycle before VALID is asserted.
• When PENDING is deasserted, it is required that VALID is deasserted in the next cycle.
• When PENDING is asserted, it is permitted but not required that VALID is asserted in the next cycle.
The PENDING signal is independent of credits and credit control. For example, a transmitter is permitted to do
any of the following:
• Keep PENDING permanently asserted, including during reset. It might do this if it is unable to determine in
advance when a transfer is to be sent.
• Assert PENDING when it does not have a credit.
• Assert and then deassert PENDING without sending a transfer.
An example of the use of PENDING is shown in Figure A2.9.
ACLK
PENDING
VALID
Figure A2.9: Example usage of the PENDING signal
See A14.2 Interface gating with credited transport for information regarding gating of interfaces using credited
channels.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
38


Chapter A2. AXI transport
A2.4. Credited transport
A2.4.5
Credited transport signals
Table A2.9 shows the signals that can be included when AXI_Transport is Credited. Each channel also has a
VALID signal, as shown in Table A2.2.
Table A2.9: Signals when using credited transport
Name
Width
Default
Description
AWPENDING
1
0b1
Asserted HIGH to indicate that a transfer might
occur in the following cycle.
AWCRDT
Num_RP_AWW
All zeros
Asserted HIGH to give one AW credit on the
respective RP.
AWCRDTSH
1
0b0
Asserted HIGH to give one shared AW credit,
supports up to one shared credit per cycle.
AWRP
clog2(Num_RP_AWW)
All zeros
Encoded indicator of the Resource Plane number
for an AW transfer.
AWSHAREDCRD
1
0b0
Asserted HIGH to indicate that an AW transfer is
using a shared credit.
WPENDING
1
0b1
Asserted HIGH to indicate that a transfer might
occur in the following cycle.
WCRDT
Num_RP_AWW
All zeros
Asserted HIGH to give one W credit on the
respective RP.
WCRDTSH
1
0b0
Asserted HIGH to give one shared W credit,
supports up to one shared credit per cycle.
WRP
clog2(Num_RP_AWW)
All zeros
Encoded indicator of the Resource Plane number
for a W transfer.
WSHAREDCRD
1
0b0
Asserted HIGH to indicate that a W transfer is
using a shared credit.
BPENDING
1
0b1
Asserted HIGH to indicate that a transfer might
occur in the following cycle.
BCRDT
1
0b0
Asserted HIGH to give one B credit.
ARPENDING
1
0b1
Asserted HIGH to indicate that a transfer might
occur in the following cycle.
ARCRDT
Num_RP_AR
All zeros
Asserted HIGH to give one AR credit on the
respective RP.
ARCRDTSH
1
0b0
Asserted HIGH to give one shared AR credit,
supports up to one shared credit per cycle.
ARRP
clog2(Num_RP_AR)
All zeros
Encoded indicator of the Resource Plane number
for an AR transfer.
ARSHAREDCRD
1
0b0
Asserted HIGH to indicate that an AR transfer is
using a shared credit.
RPENDING
1
0b1
Asserted HIGH to indicate that a transfer might
occur in the following cycle.
RCRDT
1
0b0
Asserted HIGH to give one R credit.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
39


Chapter A2. AXI transport
A2.5. Pipelining and register stages
A2.5 Pipelining and register stages
Each AXI channel transfers information in only one direction, and the architecture does not require any fixed
relationship between the channels. This means that a register stage can be inserted at any point in any channel at
the cost of an additional cycle of latency.
These qualities make the following possible:
• Trade-off between cycles of latency and maximum frequency of operation.
• Direct, fast connection between a processor and high-performance memory, while using simple register
slices to isolate longer paths to less performance critical peripherals.
The following rules apply to the registering of channels:
• There can be any number of register stages on VALID, READY, and CRDT paths between components.
• Different channels can have a different number of register stages, depending on their timing requirements.
• VALID signals must be pipelined by the same number of cycles as the payload signals of that channel
including RP and SHAREDCRD signals, if present.
• PENDING signals must retain the relationship that they are HIGH in the cycle before VALID is HIGH.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
40


Chapter A2. AXI transport
A2.6. AXI transactions and transfers
A2.6 AXI transactions and transfers
The AXI protocol requires the following relationships to be maintained:
• A write response must always follow the last write transfer in a write transaction.
• Read data and responses must always follow the read request.
• When a Manager issues a write request, it must be able to provide all write data for that transaction, without
dependency on other transactions from that Manager.
• When a Manager has issued a write request and all write data, it must be able to accept all responses for that
transaction, without dependency on other transactions from that Manager.
• When a Manager has issued a read request, it must be able to accept all read data for that transaction, without
dependency on other transactions from that Manager.
– Note that a Manager can rely on read data returning in order from transactions that use the same ID, so
the Manager only needs enough storage for read data from transactions with different IDs.
• A Manager is permitted to wait for one transaction to complete before issuing another transaction request.
• A Subordinate is permitted to wait for one transaction to complete before accepting another request, giving
credits or sending transfers for another transaction.
• A Subordinate must not block acceptance of data-less write requests due to transactions with leading write
data.
The protocol does not define any other relationship between the channels.
The lack of relationship means, for example, that the write data can appear at an interface before the write request
for the transaction. This can occur if the write request channel contains more register stages than the write data
channel. Similarly, the write data might appear in the same cycle as the request.
When the interconnect is required to determine the destination address space or Subordinate space, it must realign
the request and write data. This realignment is required to assure that the write data is signaled as being valid only
to the Subordinate for which it is destined.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
41
