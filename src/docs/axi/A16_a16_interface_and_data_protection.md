# A16 Interface and data protection

Chapter A16
Interface and data protection
This chapter specifies schemes for the protection of data and interfaces using poison and parity signaling.
It contains the following sections:
• A16.1 Data protection using Poison
• A16.2 Parity protection for data and interface signals
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
264


Chapter A16. Interface and data protection
A16.1. Data protection using Poison
A16.1 Data protection using Poison
Poison signaling is used to indicate that a set of data bytes has been previously corrupted. Passing the Poison
signaling alongside the data permits any future user of the data to be notified that the data might be corrupt. Poison
signaling is supported at the granularity of 1 bit for every 64 bits of data.
Table A16.1: Poison signals
Name
Width
Default
Description
WPOISON,
RPOISON
ceil(DATA_WIDTH / 64)
-
Asserted high to indicate that the data in this transfer
is corrupted. There is one bit per 64-bits of data.
The presence of Poison signals is configured using the Poison property.
Table A16.2: Poison property
Poison
Default
Description
True
Poison signaling is supported.
False
Y
Poison signaling is not supported.
The validity of the Poison signaling is identical to the validity of the associated data.
Poison signaling is independent of error response signaling:
• It is permitted to signal an error with no Poison violation.
• It is permitted to signal a Poison violation without signaling an error response.
A 64-bit granule is defined as an 8-byte address range that is aligned to an 8-byte boundary.
Where the transaction size, as indicated by AxSIZE, is less than 64-bits then it is permitted for the Poison bit to be
different on each data transfer. In this situation the receiving component must examine all data transfers to
determine if the 64-bit granule is poisoned.
Poison bits can be set for data lanes that are invalid for a transfer. For example, a 64-bit transfer on a 128-bit
channel can have both Poison bits set.
For implications of Poison with MTE Tags, see A12.2.10 MTE and Poison.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
265


Chapter A16. Interface and data protection
A16.2. Parity protection for data and interface signals
A16.2 Parity protection for data and interface signals
For safety-critical applications it is necessary to detect and possibly correct, transient and functional errors on
individual wires within an SoC.
An error in a system component can propagate and cause multiple errors within connected components. Error
detection and correction (EDC) is required to operate end-to-end, covering all logic and wires from source to
destination.
One way to implement end-to-end protection, is to employ customized EDC schemes in components and
implement a simple error detection scheme between components. Between these components there is no logic and
single bit errors do not propagate to multi-bit errors. This section describes a parity scheme for detecting single-bit
errors on the AMBA interface between components. Multi-bit errors can be detected if they occur in different
parity signal groups. Figure A16.1 shows locations where parity can be used in AMBA.
Source
Destination
Short distance wiring
Long distance wiring 
and routing logic
Parity generation
Parity check and 
EDC generation
EDC check and 
Parity generation
Parity check
AMBA
Parity
AMBA
Parity
Interconnect
EDC code
Figure A16.1: Parity use in AMBA
A16.2.1
Configuration of parity protection
The protection scheme employed on an interface is defined by the property Check_Type.
Table A16.3: Check_Type property
Check_Type
Default
Description
Odd_Parity_Byte_All
Odd parity checking included for all signals. Each bit of
the parity signal generally covers up to 8 bits. However, a
parity bit can cover more than 8 bits if the configuration
requires it.
Odd_Parity_Byte_Data
Odd parity checking included for data signals with names
that end in DATA. Each bit of the parity signal covers
exactly 8 bits.
False
Y
No checking signals on the interface.
A16.2.2
Error detection behavior
This specification is not prescriptive regarding component or system behavior when a parity error is detected.
Depending on the system and affected signals, a flipped bit can have a wide range of effects. It might be harmless,
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
266


Chapter A16. Interface and data protection
A16.2. Parity protection for data and interface signals
cause performance issues, data corruption, security violations, or deadlock. The transaction response is
independent of parity error detection.
When an error is detected, the receiver can do any of the following:
• Terminate or propagate the transaction. Termination might or might not be protocol compliant.
• Correct the parity check signal or propagate the signal in error.
• Update its memory or leave untouched. The location might be marked as poisoned.
• Signal an error response through other means, for example with an interrupt.
A16.2.3
Parity check signals
The parity check signals are listed in Table A16.4. They have the following attributes and rules:
• Odd parity is used.
Odd parity means that check signals are added to groups of signals on the interface and driven such that
there is always an odd number of asserted bits in that group.
• Parity signals covering data and payload are defined such that in most cases there are no more than 8 bits per
group.
This limitation assumes that there is a maximum of 3 logic levels available in the timing budget for
generating each parity bit.
• Parity signals covering critical control signals, which are likely to have a smaller timing budget available, are
defined with a single odd parity bit. This single odd parity bit is the inversion of the original critical control
signal.
• Check signals are synchronous to ACLK and must be driven correctly in every cycle that the signal in the
Check enable column is HIGH, see Table A16.4.
• Control signals have ARESETn as the Check enable.
– If the check signal for a control signal is wider than 1 bit, check bit [n] corresponds to bit [n] in the
control signal.
• Payload signals have xVALID as the Check enable.
– If the check signal for a payload signal is wider than 1 bit:
* Where a check signal covers multiple signals, parity is calculated by concatenating the signals in the
order they are listed in Table A16.4, with the first signal listed at the LSB.
* Check bit [n] corresponds to bits [(8n+7):8n] in the payload, with the following exceptions:
· WTAGCHK[n] is the parity of {WTAGUPDATE[n],WTAG[4n+3:4n]}.
· RTAGCHK[n] is the parity of RTAG[4n+3:4n].
* If the payload is not an integer number of bytes, the most significant bit of the check signal covers
fewer than 8-bits in the most significant portion of the payload.
• Parity signals must be driven appropriately to all the bits in the associated payload, irrespective of whether
those bits are actively used in the transfer. For example, all bits of WDATACHK must be driven correctly
when WVALID is asserted, even if some byte lanes are not being used.
• If none of the signals covered by a check signal are present on an interface, then the check signal is omitted
from the interface.
The following rules apply for CHK signals which cover multiple signals where one or more of the inputs or
outputs are missing:
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
267


Chapter A16. Interface and data protection
A16.2. Parity protection for data and interface signals
• If there is a missing signal output, the value is assumed to be the default for that signal. Signals with a
non-zero default must be considered when calculating parity, for example BCOMP which has a default value
of 0b1.
• If there is an output signal with no corresponding input, the missing input cannot be assumed to take a fixed
value. Therefore, the CHK signal cannot be used reliably.
• It is recommended that input signals that are part of a CHK group are either all present or all not present.
Table A16.4: Parity check signals
Name
Signals covered
Width
Check enable
AWVALIDCHK
AWVALID
1
ARESETn
AWREADYCHK
AWREADY
1
ARESETn
AWPENDINGCHK
AWPENDING
1
ARESETn
AWCRDTCHK
AWCRDT
Num_RP_AWW
ARESETn
AWCRDTSHCHK
AWCRDTSH
1
ARESETn
AWRPCHK
AWRP
1
AWVALID
AWSHAREDCRDCHK
AWSHAREDCRD
1
AWVALID
AWIDCHK
AWID
AWIDUNQ
ceil((ID_W_WIDTH +
int(Unique_ID_Support))/8)
AWVALID
AWADDRCHK
AWADDR
ceil(ADDR_WIDTH/8)
AWVALID
AWLENCHK
AWLEN
1
AWVALID
AWCTLCHK0
AWSIZE
AWBURST
AWLOCK
AWPROT
AWNSE
1
AWVALID
AWCTLCHK1
AWREGION
AWCACHE
AWQOS
1
AWVALID
AWCTLCHK2
AWDOMAIN
AWSNOOP
1
AWVALID
AWCTLCHK3
AWATOP
AWCMO
AWTAGOP
1
AWVALID
AWPASCHK
AWPAS
1
AWVALID
AWINSTPRIVCHK
AWINST
AWPRIV
1
AWVALID
AWUSERCHK
AWUSER
ceil(USER_REQ_WIDTH/8)
AWVALID
AWSTASHNIDCHK
AWSTASHNID
AWSTASHNIDEN
1
AWVALID
AWSTASHLPIDCHK
AWSTASHLPID
AWSTASHLPIDEN
1
AWVALID
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
268


Chapter A16. Interface and data protection
A16.2. Parity protection for data and interface signals
Table A16.4 – Continued from previous page
Name
Signals covered
Width
Check enable
AWTRACECHK
AWTRACE
1
AWVALID
AWLOOPCHK
AWLOOP
ceil(LOOP_W_WIDTH/8)
AWVALID
AWMMUCHK
AWMMUATST
AWMMUFLOW
AWMMUSECSID
AWMMUSSIDV
AWMMUVALID
1
AWVALID
AWMMUSIDCHK
AWMMUSID
ceil(SID_WIDTH/8)
AWVALID
AWMMUSSIDCHK
AWMMUSSID
ceil(SSID_WIDTH/8)
AWVALID
AWMMUPASUNKNOWNCHK
AWMMUPASUNKNOWN
1
AWVALID
AWMMUPMCHK
AWMMUPM
1
AWVALID
AWPBHACHK
AWPBHA
1
AWVALID
AWMECIDCHK
AWMECID
ceil(MECID_WIDTH/8)
AWVALID
AWNSAIDCHK
AWNSAID
1
AWVALID
AWMPAMCHK
AWMPAM
1
AWVALID
AWSUBSYSIDCHK
AWSUBSYSID
1
AWVALID
AWACTCHK
AWACTV
AWACT
ceil((ACT_W_WIDTH+1)/8)
AWVALID
WVALIDCHK
WVALID
1
ARESETn
WREADYCHK
WREADY
1
ARESETn
WPENDINGCHK
WPENDING
1
ARESETn
WCRDTCHK
WCRDT
Num_RP_AWW
ARESETn
WCRDTSHCHK
WCRDTSH
1
ARESETn
WRPCHK
WRP
1
WVALID
WSHAREDCRDCHK
WSHAREDCRD
1
WVALID
WDATACHK
WDATA
DATA_WIDTH/8
WVALID
WSTRBCHK
WSTRB
ceil(DATA_WIDTH/64)
WVALID
WTAGCHK
WTAG
WTAGUPDATE
ceil(DATA_WIDTH/128)
WVALID
WLASTCHK
WLAST
1
WVALID
WUSERCHK
WUSER
ceil(USER_DATA_WIDTH/8)
WVALID
WPOISONCHK
WPOISON
ceil(DATA_WIDTH/512)
WVALID
WTRACECHK
WTRACE
1
WVALID
BVALIDCHK
BVALID
1
ARESETn
BREADYCHK
BREADY
1
ARESETn
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
269


Chapter A16. Interface and data protection
A16.2. Parity protection for data and interface signals
Table A16.4 – Continued from previous page
Name
Signals covered
Width
Check enable
BPENDINGCHK
BPENDING
1
ARESETn
BCRDTCHK
BCRDT
1
ARESETn
BIDCHK
BID
BIDUNQ
ceil((ID_W_WIDTH +
int(Unique_ID_Support))/8)
BVALID
BRESPCHK
BRESP
BCOMP
BPERSIST
BTAGMATCH
BBUSY
1
BVALID
BUSERCHK
BUSER
ceil(USER_RESP_WIDTH/8)
BVALID
BTRACECHK
BTRACE
1
BVALID
BLOOPCHK
BLOOP
ceil(LOOP_W_WIDTH/8)
BVALID
ARVALIDCHK
ARVALID
1
ARESETn
ARREADYCHK
ARREADY
1
ARESETn
ARPENDINGCHK
ARPENDING
1
ARESETn
ARCRDTCHK
ARCRDT
Num_RP_AR
ARESETn
ARCRDTSHCHK
ARCRDTSH
1
ARESETn
ARRPCHK
ARRP
1
ARVALID
ARSHAREDCRDCHK
ARSHAREDCRD
1
ARVALID
ARIDCHK
ARID
ARIDUNQ
ceil((ID_R_WIDTH +
int(Unique_ID_Support))/8)
ARVALID
ARADDRCHK
ARADDR
ceil(ADDR_WIDTH/8)
ARVALID
ARLENCHK
ARLEN
1
ARVALID
ARCTLCHK0
ARSIZE
ARBURST
ARLOCK
ARPROT
ARNSE
1
ARVALID
ARCTLCHK1
ARREGION
ARCACHE
ARQOS
1
ARVALID
ARCTLCHK2
ARDOMAIN
ARSNOOP
1
ARVALID
ARCTLCHK3
ARCHUNKEN
ARTAGOP
1
ARVALID
ARPASCHK
ARPAS
1
ARVALID
ARINSTPRIVCHK
ARINST
ARPRIV
1
ARVALID
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
270


Chapter A16. Interface and data protection
A16.2. Parity protection for data and interface signals
Table A16.4 – Continued from previous page
Name
Signals covered
Width
Check enable
ARUSERCHK
ARUSER
ceil(USER_REQ_WIDTH/8)
ARVALID
ARTRACECHK
ARTRACE
1
ARVALID
ARLOOPCHK
ARLOOP
ceil(LOOP_R_WIDTH/8)
ARVALID
ARMMUCHK
ARMMUATST
ARMMUFLOW
ARMMUSECSID
ARMMUSSIDV
ARMMUVALID
1
ARVALID
ARMMUSIDCHK
ARMMUSID
ceil(SID_WIDTH/8)
ARVALID
ARMMUSSIDCHK
ARMMUSSID
ceil(SSID_WIDTH/8)
ARVALID
ARMMUPASUNKNOWNCHK
ARMMUPASUNKNOWN
1
ARVALID
ARMMUPMCHK
ARMMUPM
1
ARVALID
ARNSAIDCHK
ARNSAID
1
ARVALID
ARMPAMCHK
ARMPAM
1
ARVALID
ARPBHACHK
ARPBHA
1
ARVALID
ARMECIDCHK
ARMECID
ceil(MECID_WIDTH/8)
ARVALID
ARSUBSYSIDCHK
ARSUBSYSID
1
ARVALID
ARACTCHK
ARACTV
ARACT
ceil((ACT_R_WIDTH+1)/8)
ARVALID
RVALIDCHK
RVALID
1
ARESETn
RREADYCHK
RREADY
1
ARESETn
RPENDINGCHK
RPENDING
1
ARESETn
RCRDTCHK
RCRDT
1
ARESETn
RIDCHK
RID
RIDUNQ
ceil((ID_R_WIDTH +
int(Unique_ID_Support))/8)
RVALID
RDATACHK
RDATA
DATA_WIDTH/8
RVALID
RTAGCHK
RTAG
ceil(DATA_WIDTH/128)
RVALID
RRESPCHK
RRESP
RBUSY
1
RVALID
RLASTCHK
RLAST
1
RVALID
RCHUNKCHK
RCHUNKV
RCHUNKNUM
RCHUNKSTRB
1
RVALID
RUSERCHK
RUSER
ceil((USER_DATA_WIDTH +
USER_RESP_WIDTH)/8)
RVALID
RPOISONCHK
RPOISON
ceil(DATA_WIDTH/512)
RVALID
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
271


Chapter A16. Interface and data protection
A16.2. Parity protection for data and interface signals
Table A16.4 – Continued from previous page
Name
Signals covered
Width
Check enable
RTRACECHK
RTRACE
1
RVALID
RLOOPCHK
RLOOP
ceil(LOOP_R_WIDTH/8)
RVALID
ACVALIDCHK
ACVALID
1
ARESETn
ACREADYCHK
ACREADY
1
ARESETn
ACPENDINGCHK
ACPENDING
1
ARESETn
ACCRDTCHK
ACCRDT
1
ARESETn
ACADDRCHK
ACADDR
ceil(ADDR_WIDTH/8)
ACVALID
ACVMIDEXTCHK
ACVMIDEXT
1
ACVALID
ACTRACECHK
ACTRACE
1
ACVALID
CRVALIDCHK
CRVALID
1
ARESETn
CRREADYCHK
CRREADY
1
ARESETn
CRPENDINGCHK
CRPENDING
1
ARESETn
CRCRDTCHK
CRCRDT
1
ARESETn
CRTRACECHK
CRTRACE
1
CRVALID
VAWQOSACCEPTCHK
VAWQOSACCEPT
1
ARESETn
VARQOSACCEPTCHK
VARQOSACCEPT
1
ARESETn
AWAKEUPCHK
AWAKEUP
1
ARESETn
ACWAKEUPCHK
ACWAKEUP
1
ARESETn
ACTIVATEREQCHK
ACTIVATEREQ
1
ARESETn
ACTIVATEACKCHK
ACTIVATEACK
1
ARESETn
ASKSTOPCHK
ASKSTOP
1
ARESETn
ACTIVATEREQDCHK
ACTIVATEREQD
1
ARESETn
ACTIVATEACKDCHK
ACTIVATEACKD
1
ARESETn
ASKSTOPDCHK
ASKSTOPD
1
ARESETn
SYSCOREQCHK
SYSCOREQ
1
None
SYSCOACKCHK
SYSCOACK
1
None
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
272
