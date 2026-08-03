# A14 Interface clock and power gating

Chapter A14
Interface clock and power gating
This chapter describes stopping and starting interfaces for the purposes of clock and power control.
It contains the following sections:
• A14.1 Interface gating with Valid-Ready transport
• A14.2 Interface gating with credited transport
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
222


Chapter A14. Interface clock and power gating
A14.1. Interface gating with Valid-Ready transport
A14.1 Interface gating with Valid-Ready transport
When using a Valid-Ready transport, wake-up signals can be used to indicate when there is activity associated with
the interface.
Table A14.1: Wake-up signals
Name
Width
Default
Description
AWAKEUP
1
-
Manager output, asserted HIGH to indicate there
might be activity on the read and write request
channels.
ACWAKEUP
1
-
Subordinate output, asserted HIGH to indicate
there might be activity on the snoop request
channel.
The signals can be routed to a clock controller or similar component to enable power and clocks to the connected
components.
The wake-up signals are synchronous and must also be suitable for sampling asynchronously in a different clock
domain. This requires the wake-up signals to be glitch-free, which can be achieved by for example being
generated directly from a register, or from a glitch-free OR tree.
The wake-up signals must be asserted to guarantee that a transaction can be accepted, but once the transaction is in
progress the assertion or deassertion of the wake-up signal is IMPLEMENTATION DEFINED.
It is recommended, but not required that a wake-up signal is deasserted when no further transactions are required.
The Wakeup_Signals property is used to indicate whether a component includes wake-up signaling.
Table A14.2: Wakeup_Signals property
Wakeup_Signals
Default
Description
True
AWAKEUP is present. ACWAKEUP is present if
the interface has an AC channel.
False
Y
No wake-up signals are present.
Wakeup signals can only be used with Valid-Ready transport, which implies the following:
• When AXI_Transport is Credited, Wakeup_Signals must be False.
A14.1.1
AWAKEUP rules and recommendations
AWAKEUP is an output signal from a Manager interface and is asserted at the start of a transaction to indicate
that there is a transaction to be processed. It has the following rules:
• It is recommended that AWAKEUP is asserted at least one cycle before the assertion of ARVALID,
AWVALID, or WVALID to prevent the acceptance of a transaction request being delayed.
• It is permitted for AWAKEUP to be asserted at any point before or after the assertion of ARVALID,
AWVALID, or WVALID.
• A Subordinate is permitted to wait for AWAKEUP to be asserted before asserting ARREADY, AWREADY,
or WREADY.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
223


Chapter A14. Interface clock and power gating
A14.1. Interface gating with Valid-Ready transport
• If AWAKEUP is asserted in a cycle where AWVALID is asserted and AWREADY is deasserted, then
AWAKEUP must remain asserted until AWREADY is asserted.
• If AWAKEUP is asserted in a cycle when ARVALID is asserted and ARREADY is deasserted, then
AWAKEUP must remain asserted until ARREADY is asserted.
• After the ARVALID, ARREADY handshake, or the AWVALID, AWREADY handshake, the interconnect
must remain active until the transaction has completed.
• It is permitted, but not recommended, to assert AWAKEUP then deassert it without a transaction taking
place.
There is no requirement relating to the assertion of AWAKEUP relative to WVALID. However, for components
that can assert WVALID before AWVALID, the assertion of AWAKEUP at least one cycle before WVALID can
prevent the acceptance of a new transaction being delayed.
If a Subordinate has an AWAKEUP input but the attached Manager does not have an AWAKEUP output, then
either:
• Tie AWAKEUP high, however this might prevent the Subordinate interface from using low power states.
• Derive AWAKEUP from AxVALID and SYSCOREQ/ACK. This method allows the Subordinate to enter
low power states, but it may introduce latency while the clock is enabled.
A14.1.2
AWAKEUP and Coherency Connection signaling
If wake-up and Coherency Connection signals are both present on an interface, there are additional considerations.
• It is required that the AWAKEUP signal is asserted to guarantee progress of a transition on the Coherency
Connection signaling.
• It is permitted for AWAKEUP to be asserted at any point before or after the assertion of SYSCOREQ.
However, it is required to be asserted to guarantee the corresponding assertion of SYSCOACK. When
AWAKEUP is asserted with SYSCOREQ asserted and SYSCOACK deasserted, it must remain asserted
until SYSCOACK is asserted.
• It is permitted for AWAKEUP to be asserted at any point before or after the deassertion of SYSCOREQ.
However, it is required to be asserted to guarantee the corresponding deassertion of SYSCOACK. When
AWAKEUP is asserted with SYSCOREQ deasserted and SYSCOACK asserted, it must remain asserted
until SYSCOACK is deasserted.
See A15.6 Coherency Connection signaling for more details.
A14.1.3
ACWAKEUP rules and recommendations
ACWAKEUP is an output signal from a Subordinate interface, usually on an interconnect, and is asserted at the
start of a DVM message transaction to indicate that there is a transaction to be processed. It has the following rules:
• It is recommended that ACWAKEUP is asserted at least one cycle before the assertion of ACVALID to
prevent the acceptance of a DVM request being delayed.
• ACWAKEUP must remain asserted until the associated ACVALID / ACREADY handshake to ensure
progress of the DVM transaction.
• After the ACVALID / ACREADY handshake, the Manager must remain active until the DVM transaction
has completed.
• It is permitted for ACWAKEUP to be asserted at any point before or after the assertion of ACVALID.
• It is permitted, but not recommended, to assert ACWAKEUP and then deassert it without ACVALID being
asserted.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
224


Chapter A14. Interface clock and power gating
A14.2. Interface gating with credited transport
A14.2 Interface gating with credited transport
When using credited transport, an interface can include control signals to determine when channel receivers can
give credits. This can be used to clock or power gate interfaces when they are idle.
The property Credit_Control is used to indicate whether credit control signals are included on an interface. If
credit control signals are not included, the interface is assumed to be running when not in reset.
Credits are implicitly returned during the STOP state and on exit from the STOP state all credits are with the
receiver. Transmitters are not required to explicitly return all credits to the receiver before it stops.
Table A14.3: Credit_Control property
Credit_Control
Default
Description
False
Y
Credit control signals are not included.
Credit exchange starts from reset and does not stop.
Implicit_Return_Uni
Credit control signals are included. Credits are implicitly returned to
the receiver when exiting the STOP state. Control is unidirectional
because only a Manager can initiate the move to ACTIVATE or
DEACTIVATE.
The following rules apply to the Credit_Control property:
• Credit_Control must be False if the AXI_Transport property is Ready.
• Connected interfaces must have the same value for Credit_Control.
Table A14.4 shows the signals that are included when Credit_Control is Implicit_Return_Uni.
Table A14.4: Credit control signals
Name
Width
Default
Description
ACTIVATEREQ
1
0b1
Activation / deactivation request from a Manager.
ACTIVATEACK
1
0b1
Activation / deactivation acknowledge from a Subordinate.
ASKSTOP
1
0b0
Asserted HIGH to indicate that the Subordinate wants the
Manager to stop the interface.
Figure A14.1 shows connected AXI5 interfaces using credit control signaling.
Figure A14.1: AXI5 interfaces using credit control signaling
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
225


Chapter A14. Interface clock and power gating
A14.2. Interface gating with credited transport
A14.2.1
Channel states
When using credit control, an interface can be in one of four states: STOP, ACTIVATE, RUN, DEACTIVATE.
• RUN and STOP are stable states. An interface can remain in this state for an indefinite period.
• DEACTIVATE and ACTIVATE are transient states. It is expected that an interface moves to the next stable
state in a relatively short period.
Figure A14.2: Interface states
A14.2.1.1
STOP state
• There are no outstanding transactions, the interface is idle and can be clock gated or powered down.
• Managers and Subordinates have no credits and cannot send any transfers or credits.
• The Subordinate might receive credits after entering this state if there is a race between credits and
ACTIVATEREQ deassertion, they must be discarded.
• If the Manager wants to start a transaction, it can assert ACTIVATEREQ.
• When ACTIVATEREQ is asserted, the interface moves into the ACTIVATE state.
A14.2.1.2
ACTIVATE state
• This is a transient state, and the interface is expected to transition to RUN within a relatively short period.
• When the Subordinate is ready to start, it asserts ACTIVATEACK and starts to send credits.
• The Manager might receive credits due to a potential race between ACTIVATEACK and credit signals,
these can be used to send transfers.
• When ACTIVATEACK is asserted, the interface moves into the RUN state.
A14.2.1.3
RUN state
• The Manager and Subordinate can send credits and transfers.
• If the Manager wants to stop the interface and there are no outstanding transactions, it can stop sending
credits and deassert ACTIVATEREQ.
• If the Subordinate wants the interface to stop, it can assert ASKSTOP.
• When ACTIVATEREQ is deasserted, the interface moves into the DEACTIVATE state.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
226


Chapter A14. Interface clock and power gating
A14.2. Interface gating with credited transport
A14.2.1.4
DEACTIVATE state
• This is a transient state, and the interface is expected to transition to STOP within a relatively short period.
• The Manager must not send transfers or credits.
• The Subordinate will have no transfers to send because all outstanding transactions must be complete.
• The Subordinate stops sending credits and deasserts ACTIVATEACK.
• When ACTIVATEACK is deasserted, the interface moves into the STOP state.
A14.2.2
Stop request signal, ASKSTOP
The Manager controls the move from RUN to DEACTIVATE, but the Subordinate can use the ASKSTOP signal
to ask the Manager to initiate the move to DEACTIVATE. This might be because the Subordinate is idle or
because it is required to reconfigure or reset when all outstanding transactions are complete.
The following rules apply to ASKSTOP:
• ASKSTOP can only be HIGH when ACTIVATEACK is HIGH, that means in the RUN or DEACTIVATE
states.
• If ASKSTOP is asserted, it must remain HIGH until ACTIVATEACK is LOW.
• ASKSTOP must be LOW when ACTIVATEACK is LOW.
• When ASKSTOP is HIGH, the Manager must deassert ACTIVATEREQ when there are no outstanding
transactions.
• It is recommended that the Manager does not issue any new transaction requests when ASKSTOP is HIGH.
A14.2.3
Credit control signal rules
The following rules apply to the credit control signals:
• When ACTIVATEREQ is LOW there must be no outstanding transactions and the Manager must not send
transfers.
• When ACTIVATEREQ is LOW or ACTIVATEACK is LOW, the Manager must not send credits.
• When ACTIVATEACK is LOW, the Subordinate must not send transfers or credits.
• ACTIVATEREQ, ACTIVATEACK and ASKSTOP must be LOW during reset.
A14.2.4
Pipelining channels
It can sometimes be required to add pipeline stages to channels to meet timing between interfaces. The following
rules and notes apply:
• Register pipeline stages can be added to VALID, CRDT or CRDTSH paths of any channel independently.
• The Manager must not receive any credits in the STOP state.
– If credit signals from the Subordinate have a longer transport delay than ACTIVATEACK, there must
be a delay between sending the last credits and deasserting ACTIVATEACK.
• If credit signals from the Manager have a longer transport delay than ACTIVATEREQ, the Subordinate
might receive credits in the STOP state. These credits must be discarded.
• If ACTIVATEACK has a longer transport delay than credit signals, the Manager might receive and use
credits in the ACTIVATE state.
• ASKSTOP must be pipelined the same as ACTIVATEACK so the rules regarding ASKSTOP can be
applied on both sides of the connection.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
227


Chapter A14. Interface clock and power gating
A14.2. Interface gating with credited transport
• When registering the VALID signals, the logic must ensure that associated payload signals remain aligned to
VALID and the PENDING signals are HIGH in the cycle before VALID is HIGH.
A14.2.5
Clock and power gating
When an interface is in the STOP state, the transport logic can be clock or power gated. The following rules apply:
• Transfers will not be sent or received.
• Credits will not be sent.
• If credits are received, they are discarded.
A Subordinate interface can use the ACTIVATEREQ input to activate its clocks or power, therefore:
• ACTIVATEREQ must be glitch free and suitable for sampling in a different clock domain.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
228


Chapter A14. Interface clock and power gating
A14.3. Sequence diagram
A14.3 Sequence diagram
Figure A14.3 shows the sequence diagram for credit control in an AXI5 interface.
Manager
Manager
Subordinate
Subordinate
Manager wants start
ACTIVATEREQ high
ACTIVATE
ACTIVATEACK high
RUN
par
AR, AW, W credits sent
AR, AW, W transfers sent
B, R credits sent
B, R transfers sent
No outstanding transactions
Manager wants to stop
ACTIVATEREQ low
DEACTIVATE
ACTIVATEACK low
STOP
Figure A14.3: Sequence diagram of an AXI5 connection using credit control signaling
The following behavior is not shown in the sequence diagram:
• A Manager might receive credits in the DEACTIVATE state due to the opposite direction race.
• A Manager might receive credits in the ACTIVATE state due to pipelining, these can be used immediately.
• Due to pipelining, a Subordinate might receive credits during the STOP state, which must be discarded.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
229


Chapter A14. Interface clock and power gating
A14.4. Example waveform
A14.4 Example waveform
An example interface control waveform is included to demonstrate a common case but does not indicate all
permitted behavior. Not all signals are shown, for example PENDING signals must be included on all credited
channels.
A14.4.1
Transmitting one read transaction
In this example, the Manager sends one read request, waits for the two data transfers then stops the interface.
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
11
12
13
14
30
29
30
31
32
33
34
ACLK
State
STOP
ACTIVATE
RUN
DEACT
STOP
ACTIVATEREQ
ACTIVATEACK
ASKSTOP
ARCRDT
ARVALID
RCRDT
RVALID
at least N cycles
Figure A14.4: Starting and stopping an interface after one read transaction
Cycle 0
The link is inactive, both interfaces are in STOP.
Cycle 2
The Manager has a request to send, so asserts ACTIVATEREQ to wake the Subordinate.
Cycle 4
The Subordinate asserts ACTIVATEACK. It sends a credit by asserting ARCRDT.
Cycle 5
The Manager sends a transfer on AR and the Subordinate sends another AR credit.
Cycle 6
The Manager starts sending credits on the R channel.
Cycle 10, 12
The Subordinate sends two read data transfers and the transaction is complete.
Cycle 13
The Subordinate wants the interface to stop so asserts ASKSTOP.
Cycle 29
There are no outstanding transactions so the Manager deasserts ACTIVATEREQ.
Cycle 31
The Subordinate deasserts ACTIVATEACK and ASKSTOP and moves into STOP. This must be at least N
cycles after the Subordinate sent a credit, where N is the maximum number of cycles that any credit signal is
delayed by pipelining.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
230
