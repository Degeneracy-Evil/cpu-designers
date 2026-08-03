# B2 Interface classes

Chapter B2
Interface classes
The specification part in this document describes a generic fully-featured protocol, with some features being
mandatory and others optional, based on properties. Previous issues of this specification defined a number of
interface classes for different use-cases. These can all now be described by constraining certain properties to limit
the functionality and signaling on that interface.
This chapter describes the following interface classes:
• B2.1.1 AXI5
• B2.1.2 ACE5-Lite
• B2.1.3 ACE5-LiteDVM
• B2.1.4 ACE5-LiteACP
• B2.1.5 AXI5-Lite
There are also signal and property tables with columns for each interface class:
• B2.2 Signal matrix
• B2.3 Parity check signal matrix
• B2.4 Property matrix
Note that ACE, ACE5, AXI3, AXI4, and AXI4-Lite interface classes are not described in this specification. See
[1] for more information on these interfaces.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
285


Chapter B2. Interface classes
B2.1. Summary of interface classes
B2.1 Summary of interface classes
An example of where different interface classes might be used is shown in Figure B2.1. Note that an AXI5
interface can be configured to meet all of the use-cases.
Accelerator with 
MMU
I/O coherent agent
(translated)
CPU complex
Coherent interconnect
Non-coherent interconnect
AXI5 or ACE5-LiteACP
System cache
Memory
Peripherals
Accelerator 
(untranslated)
SMMU
AXI5 or ACE5-Lite
AXI5 or ACE5-LiteDVM
CHI
AXI5 or ACE5-LiteDVM
AXI5 or ACE5-Lite
AXI5 or ACE5-Lite
AXI5 or AXI5-Lite
AXI5 or ACE5-Lite
Figure B2.1: Example system topology showing possible interface classes
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
286


Chapter B2. Interface classes
B2.1. Summary of interface classes
B2.1.1
AXI5
The AXI5 interface class is a generic interface with no property constraints.
Compared with Issue H of this specification, the following properties are now permitted to be enabled for an AXI5
interface:
• Shareable_Transactions
• CMO_On_Read
• CMO_On_Write
• Write_Plus_CMO
• WriteZero_Transaction
• Prefetch_Transaction
• Cache_Stash_Transactions
• DVM_Message_Support (Receiver only)
• DVM_v8, DVM_v8.1, DVM_v8.4, DVM_v9.2
• Coherency_Connection_Signals
• DeAllocation_Transactions
• Persist_CMO
B2.1.2
ACE5-Lite
An ACE5-Lite interface was previously needed if an AXI interface included any functionality that required
AxSNOOP signals. With this version of the specification, an AXI5 interface is recommended for new designs as it
now supports all functionality.
B2.1.3
ACE5-LiteDVM
An ACE5-LiteDVM interface was previously needed if an interface was required to send or receive DVM
messages. With this version of the specification, an AXI5 interface is recommended for new designs as it now
supports all functionality.
The most common use-case for an ACE5-LiteDVM interface is for a system MMU to receive invalidation
messages on the AC channel. The issuing of DVM messages on the AR channel is mostly done by fully coherent
CPUs, so is beyond the scope of this specification.
Note that there are some differences between the definition of ACE5-LiteDVM in this specification, compared
with Issue H [1].
In this specification, snoop data transfer and bidirectional DVM messages are not supported. Therefore, the
following signals described in earlier issues of this specification are no longer required on an ACE5-LiteDVM
interface:
• ACSNOOP, all requests on the AC channel can be assumed to be DVM messages.
• ACPROT, not required for DVM messages.
• CRRESP, not required for DVM messages.
B2.1.4
ACE5-LiteACP
ACE5-LiteACP, which is a subset of ACE5-Lite, is intended for tightly coupling accelerator components to a
processor cluster. The interface is optimized for coherent cache line accesses and is less complex than an
ACE5-Lite interface.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
287


Chapter B2. Interface classes
B2.1. Summary of interface classes
The following constraints apply to ACE5-LiteACP in order to reduce complexity.
• Data width must be 128b (DATA_WIDTH = 128).
• Size must be 128b (SIZE_Present = False).
• Length must be 1 or 4 transfers.
• Burst must be INCR (BURST_Present = False).
• Memory type must be Write-back, that is AxCACHE[1:0] is 0b11 and AxCACHE[3:2] is not 0b00.
• Cache line size must be 64.
• Some other optional features are not permitted, as Table B2.4 describes.
B2.1.5
AXI5-Lite
AXI5-Lite is a subset of AXI5 where all transactions have one data transfer. It is intended for communication with
register-based components and simple memories when bursts of data transfer are not advantageous.
The key functionality of AXI5-Lite is:
• All transactions have burst length 1.
• Supported Opcodes are WriteNoSnoop and ReadNoSnoop.
• Reordering of responses is permitted when requests have different IDs.
• All accesses are considered Device Non-bufferable.
• Exclusive accesses are not supported.
Note that the burst type is assumed to be INCR, this must be taken into account when calculating a parity value for
the AxCTLCHK0 signal.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
288


Chapter B2. Interface classes
B2.2. Signal matrix
B2.2 Signal matrix
In Table B2.2, there is a list of all signals with codes that describe the presence requirements for each interface
class. The Presence column describes the property condition used to specify the presence of the signal.
The list of codes that are used is shown in Table B2.1.
Table B2.1: Key to signals table
Code
Manager interfaces
Subordinate interfaces
Y
Mandatory
Mandatory
YM
Mandatory
Optional
YS
Optional
Mandatory
O
Optional
Optional
NS
Optional
Not present
N
Not present
Not present
Table B2.2: Summary of signal presence for each interface class
Signal
Presence
AXI5
ACE5-
Lite
ACE5-
LiteDVM
ACE5-
LiteACP
AXI5-
Lite
ACLK
-
Y
Y
Y
Y
Y
ARESETn
-
Y
Y
Y
Y
Y
AWVALID
-
Y
Y
Y
Y
Y
AWREADY
AXI_Transport == Ready
O
Y
Y
Y
Y
AWPENDING
AXI_Transport == Credited
O
N
N
N
N
AWCRDT
AXI_Transport == Credited
O
N
N
N
N
AWCRDTSH
Shared_Credits_AW == True
O
N
N
N
N
AWRP
Num_RP_AWW > 1
O
N
N
N
N
AWSHAREDCRD
Shared_Credits_AW == True
O
N
N
N
N
AWID
ID_W_WIDTH > 0
YS
YS
YS
YS
YS
AWADDR
-
Y
Y
Y
Y
Y
AWREGION
REGION_Present
O
O
O
N
N
AWLEN
LEN_Present
YS
YS
YS
YS
N
AWSIZE
SIZE_Present
YS
YS
YS
N
O
AWBURST
BURST_Present
YS
YS
YS
N
N
AWLOCK
Exclusive_Accesses
O
O
O
N
N
AWCACHE
CACHE_Present
O
O
O
O
N
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
289


Chapter B2. Interface classes
B2.2. Signal matrix
Table B2.2 – Continued from previous page
Signal
Presence
AXI5
ACE5-
Lite
ACE5-
LiteDVM
ACE5-
LiteACP
AXI5-
Lite
AWPROT
PROT_Present
O
YM
YM
YM
YM
AWNSE
RME_Support
O
O
O
N
N
AWPAS
PAS_WIDTH > 0
O
N
N
N
N
AWINST
INSTPRIV_Present
O
N
N
N
N
AWPRIV
INSTPRIV_Present
O
N
N
N
N
AWQOS
QOS_Present
O
O
O
N
N
AWUSER
USER_REQ_WIDTH > 0
O
O
O
O
O
AWDOMAIN
Shareable_Transactions
O
Y
Y
Y
N
AWSNOOP
AWSNOOP_WIDTH > 0
O
YS
YS
YS
N
AWSTASHNID
STASHNID_Present
O
O
O
O
N
AWSTASHNIDEN
STASHNID_Present
O
O
O
O
N
AWSTASHLPID
STASHLPID_Present
O
O
O
O
N
AWSTASHLPIDEN
STASHLPID_Present
O
O
O
O
N
AWTRACE
Trace_Signals
O
O
O
O
O
AWLOOP
Loopback_Signals
O
O
O
N
N
AWMMUVALID
Untranslated_Transactions == v3 or
Untranslated_Transactions == v4
O
O
N
N
N
AWMMUSECSID
SECSID_WIDTH > 0
O
O
N
N
N
AWMMUSID
SID_WIDTH > 0
O
O
N
N
N
AWMMUSSIDV
SSID_WIDTH > 0
O
O
N
N
N
AWMMUSSID
SSID_WIDTH > 0
O
O
N
N
N
AWMMUATST
MMUFLOW_Present and
(Untranslated_Transactions == v1 or
Untranslated_Transactions == True)
O
O
N
N
N
AWMMUFLOW
MMUFLOW_Present and
(Untranslated_Transactions == v2 or
Untranslated_Transactions == v3 or
Untranslated_Transactions == v4)
O
O
N
N
N
AWMMUPASUNKNOWN
Untranslated_Transactions == v4 and
RME_Support and PAS_WIDTH > 0
O
N
N
N
N
AWMMUPM
GDI_Support and
Untranslated_Transactions == v4
O
N
N
N
N
AWPBHA
PBHA_Support
O
O
O
N
N
AWMECID
MEC_Support
O
O
O
N
N
AWNSAID
NSAccess_Identifiers
O
O
O
N
N
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
290


Chapter B2. Interface classes
B2.2. Signal matrix
Table B2.2 – Continued from previous page
Signal
Presence
AXI5
ACE5-
Lite
ACE5-
LiteDVM
ACE5-
LiteACP
AXI5-
Lite
AWSUBSYSID
SUBSYSID_WIDTH > 0
O
O
O
N
O
AWATOP
Atomic_Transactions
O
O
O
N
N
AWMPAM
MPAM_Support != False
O
O
O
O
N
AWIDUNQ
Unique_ID_Support
O
O
O
O
O
AWCMO
CMO_On_Write
O
O
O
N
N
AWTAGOP
MTE_Support != False
O
O
O
N
N
AWACT
ACT_Support != False
O
N
N
N
N
AWACTV
ACT_Support != False
O
N
N
N
N
WVALID
-
Y
Y
Y
Y
Y
WREADY
AXI_Transport == Ready
O
Y
Y
Y
Y
WPENDING
AXI_Transport == Credited
O
N
N
N
N
WCRDT
AXI_Transport == Credited
O
N
N
N
N
WCRDTSH
Shared_Credits_W == True
O
N
N
N
N
WRP
Num_RP_AWW > 1
O
N
N
N
N
WSHAREDCRD
Shared_Credits_W == True
O
N
N
N
N
WDATA
-
Y
Y
Y
Y
Y
WSTRB
WSTRB_Present
YS
YS
YS
YS
YS
WTAG
MTE_Support != False
O
O
O
N
N
WTAGUPDATE
MTE_Support != False
O
O
O
N
N
WLAST
WLAST_Present
YM
YM
YM
YM
N
WUSER
USER_DATA_WIDTH > 0
O
O
O
O
O
WPOISON
Poison
O
O
O
O
O
WTRACE
Trace_Signals
O
O
O
O
O
BVALID
-
Y
Y
Y
Y
Y
BREADY
AXI_Transport == Ready
O
Y
Y
Y
Y
BPENDING
AXI_Transport == Credited
O
N
N
N
N
BCRDT
AXI_Transport == Credited
O
N
N
N
N
BID
ID_W_WIDTH > 0
YS
YS
YS
YS
YS
BIDUNQ
Unique_ID_Support
O
O
O
O
O
BRESP
BRESP_WIDTH > 0
O
O
O
O
O
BCOMP
(Persist_CMO and CMO_On_Write)
or MTE_Support == Standard
O
O
O
N
N
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
291


Chapter B2. Interface classes
B2.2. Signal matrix
Table B2.2 – Continued from previous page
Signal
Presence
AXI5
ACE5-
Lite
ACE5-
LiteDVM
ACE5-
LiteACP
AXI5-
Lite
BPERSIST
Persist_CMO and CMO_On_Write
O
O
O
N
N
BTAGMATCH
MTE_Support == Standard
O
O
N
N
N
BUSER
USER_RESP_WIDTH > 0
O
O
O
O
O
BTRACE
Trace_Signals
O
O
O
O
O
BLOOP
Loopback_Signals
O
O
O
N
N
BBUSY
Busy_Support
O
O
O
N
N
ARVALID
-
Y
Y
Y
Y
Y
ARREADY
AXI_Transport == Ready
O
Y
Y
Y
Y
ARPENDING
AXI_Transport == Credited
O
N
N
N
N
ARCRDT
AXI_Transport == Credited
O
N
N
N
N
ARCRDTSH
Shared_Credits_AR == True
O
N
N
N
N
ARRP
Num_RP_AR > 1
O
N
N
N
N
ARSHAREDCRD
Shared_Credits_AR == True
O
N
N
N
N
ARID
ID_R_WIDTH > 0
YS
YS
YS
YS
YS
ARADDR
-
Y
Y
Y
Y
Y
ARREGION
REGION_Present
O
O
O
N
N
ARLEN
LEN_Present
YS
YS
YS
YS
N
ARSIZE
SIZE_Present
YS
YS
YS
N
O
ARBURST
BURST_Present
YS
YS
YS
N
N
ARLOCK
Exclusive_Accesses
O
O
O
N
N
ARCACHE
CACHE_Present
O
O
O
O
N
ARPROT
PROT_Present
O
YM
YM
YM
YM
ARNSE
RME_Support
O
O
O
N
N
ARPAS
PAS_WIDTH > 0
O
N
N
N
N
ARINST
INSTPRIV_Present
O
N
N
N
N
ARPRIV
INSTPRIV_Present
O
N
N
N
N
ARQOS
QOS_Present
O
O
O
N
N
ARUSER
USER_REQ_WIDTH > 0
O
O
O
O
O
ARDOMAIN
Shareable_Transactions
O
Y
Y
Y
N
ARSNOOP
ARSNOOP_WIDTH > 0
O
YS
YS
O
N
ARTRACE
Trace_Signals
O
O
O
O
O
ARLOOP
Loopback_Signals
O
O
O
N
N
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
292


Chapter B2. Interface classes
B2.2. Signal matrix
Table B2.2 – Continued from previous page
Signal
Presence
AXI5
ACE5-
Lite
ACE5-
LiteDVM
ACE5-
LiteACP
AXI5-
Lite
ARMMUVALID
Untranslated_Transactions == v3 or
Untranslated_Transactions == v4
O
O
N
N
N
ARMMUSECSID
SECSID_WIDTH > 0
O
O
N
N
N
ARMMUSID
SID_WIDTH > 0
O
O
N
N
N
ARMMUSSIDV
SSID_WIDTH > 0
O
O
N
N
N
ARMMUSSID
SSID_WIDTH > 0
O
O
N
N
N
ARMMUATST
MMUFLOW_Present and
(Untranslated_Transactions == v1 or
Untranslated_Transactions == True)
O
O
N
N
N
ARMMUFLOW
MMUFLOW_Present and
(Untranslated_Transactions == v2 or
Untranslated_Transactions == v3 or
Untranslated_Transactions == v4)
O
O
N
N
N
ARMMUPASUNKNOWN
Untranslated_Transactions == v4 and
RME_Support and PAS_WIDTH > 0
O
N
N
N
N
ARMMUPM
GDI_Support and
Untranslated_Transactions == v4
O
N
N
N
N
ARPBHA
PBHA_Support
O
O
O
N
N
ARMECID
MEC_Support
O
O
O
N
N
ARNSAID
NSAccess_Identifiers
O
O
O
N
N
ARSUBSYSID
SUBSYSID_WIDTH > 0
O
O
O
N
O
ARMPAM
MPAM_Support != False
O
O
O
O
N
ARCHUNKEN
Read_Data_Chunking
O
O
O
O
N
ARIDUNQ
Unique_ID_Support
O
O
O
O
O
ARTAGOP
MTE_Support != False
O
O
O
N
N
ARACT
ACT_Support != False
O
N
N
N
N
ARACTV
ACT_Support != False
O
N
N
N
N
RVALID
-
Y
Y
Y
Y
Y
RREADY
AXI_Transport == Ready
O
Y
Y
Y
Y
RPENDING
AXI_Transport == Credited
O
N
N
N
N
RCRDT
AXI_Transport == Credited
O
N
N
N
N
RID
ID_R_WIDTH > 0
YS
YS
YS
YS
YS
RIDUNQ
Unique_ID_Support
O
O
O
O
O
RDATA
-
Y
Y
Y
Y
Y
RTAG
MTE_Support != False
O
O
O
N
N
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
293


Chapter B2. Interface classes
B2.2. Signal matrix
Table B2.2 – Continued from previous page
Signal
Presence
AXI5
ACE5-
Lite
ACE5-
LiteDVM
ACE5-
LiteACP
AXI5-
Lite
RRESP
RRESP_WIDTH > 0
O
O
O
O
O
RLAST
RLAST_Present
YS
YS
YS
YS
N
RUSER
USER_DATA_WIDTH > 0 or
USER_RESP_WIDTH > 0
O
O
O
O
O
RPOISON
Poison
O
O
O
O
O
RTRACE
Trace_Signals
O
O
O
O
O
RLOOP
Loopback_Signals
O
O
O
N
N
RCHUNKV
Read_Data_Chunking
O
O
O
O
N
RCHUNKNUM
RCHUNKNUM_WIDTH > 0
O
O
O
O
N
RCHUNKSTRB
RCHUNKSTRB_WIDTH > 0
O
O
O
O
N
RBUSY
Busy_Support
O
O
O
N
N
ACVALID
DVM_Message_Support
O
N
Y
N
N
ACREADY
DVM_Message_Support and
AXI_Transport == Ready
O
N
Y
N
N
ACPENDING
DVM_Message_Support and
AXI_Transport == Credited
O
N
N
N
N
ACCRDT
DVM_Message_Support and
AXI_Transport == Credited
O
N
N
N
N
ACADDR
DVM_Message_Support and
AXI_Transport == Credited
O
N
Y
N
N
ACVMIDEXT
DVM_Message_Support and
(DVM_v8.1 or DVM_v8.4 or
DVM_v9.2)
O
N
O
N
N
ACTRACE
DVM_Message_Support and
Trace_Signals
O
N
O
N
N
CRVALID
DVM_Message_Support
O
N
Y
N
N
CRREADY
DVM_Message_Support and
AXI_Transport == Ready
O
N
Y
N
N
CRPENDING
DVM_Message_Support and
AXI_Transport == Credited
O
N
N
N
N
CRCRDT
DVM_Message_Support and
AXI_Transport == Credited
O
N
N
N
N
CRTRACE
DVM_Message_Support and
Trace_Signals
O
N
O
N
N
AWAKEUP
Wakeup_Signals
O
O
O
O
O
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
294


Chapter B2. Interface classes
B2.2. Signal matrix
Table B2.2 – Continued from previous page
Signal
Presence
AXI5
ACE5-
Lite
ACE5-
LiteDVM
ACE5-
LiteACP
AXI5-
Lite
ACWAKEUP
Wakeup_Signals and
DVM_Message_Support
O
N
O
N
N
ACTIVATEREQ
Credit_Control ==
Implicit_Return_Uni
O
N
N
N
N
ACTIVATEACK
Credit_Control ==
Implicit_Return_Uni
O
N
N
N
N
ASKSTOP
Credit_Control ==
Implicit_Return_Uni
O
N
N
N
N
ACTIVATEREQD
DVM_Message_Support and
Credit_Control ==
Implicit_Return_Uni
O
N
N
N
N
ACTIVATEACKD
DVM_Message_Support and
Credit_Control ==
Implicit_Return_Uni
O
N
N
N
N
ASKSTOPD
DVM_Message_Support and
Credit_Control ==
Implicit_Return_Uni
O
N
N
N
N
VARQOSACCEPT
QoS_Accept
O
O
O
N
N
VAWQOSACCEPT
QoS_Accept
O
O
O
N
N
SYSCOREQ
Coherency_Connection_Signals
O
N
O
N
N
SYSCOACK
Coherency_Connection_Signals
O
N
O
N
N
BROADCASTATOMIC
-
NS
NS
NS
N
N
BROADCASTSHAREABLE
-
NS
NS
NS
NS
N
BROADCASTCACHEMAINT
-
NS
NS
NS
N
N
BROADCASTCMOPOPA
-
NS
NS
NS
N
N
BROADCASTPERSIST
-
NS
NS
NS
N
N
BROADCASTSTORAGE
-
NS
N
N
N
N
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
295


Chapter B2. Interface classes
B2.3. Parity check signal matrix
B2.3 Parity check signal matrix
Parity check signals for each interface type are shown in Table B2.3, using the codes defined in Table B2.1. Parity
check signals are described in A16.2.3 Parity check signals.
Table B2.3: Summary of check signal presence for each interface class
Signal
AXI5
ACE5-
Lite
ACE5-
LiteDVM
ACE5-
LiteACP
AXI5-
Lite
AWVALIDCHK
O
O
O
O
O
AWREADYCHK
O
O
O
O
O
AWPENDINGCHK
O
N
N
N
N
AWCRDTCHK
O
N
N
N
N
AWCRDTSHCHK
O
N
N
N
N
AWRPCHK
O
N
N
N
N
AWSHAREDCRDCHK
O
N
N
N
N
AWIDCHK
O
O
O
O
O
AWADDRCHK
O
O
O
O
O
AWLENCHK
O
O
O
O
N
AWCTLCHK0
O
O
O
O
O
AWCTLCHK1
O
O
O
O
N
AWCTLCHK2
O
O
O
O
N
AWCTLCHK3
O
O
O
N
N
AWPASCHK
O
N
N
N
N
AWINSTPRIVCHK
O
N
N
N
N
AWUSERCHK
O
O
O
O
O
AWSTASHNIDCHK
O
O
O
O
N
AWSTASHLPIDCHK
O
O
O
O
N
AWTRACECHK
O
O
O
O
O
AWLOOPCHK
O
O
O
N
N
AWMMUCHK
O
O
N
N
N
AWMMUSIDCHK
O
O
N
N
N
AWMMUSSIDCHK
O
O
N
N
N
AWMMUPASUNKNOWNCHK
O
N
N
N
N
AWMMUPMCHK
O
N
N
N
N
AWPBHACHK
O
O
O
N
N
AWNSAIDCHK
O
O
O
N
N
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
296


Chapter B2. Interface classes
B2.3. Parity check signal matrix
Table B2.3 – Continued from previous page
Signal
AXI5
ACE5-
Lite
ACE5-
LiteDVM
ACE5-
LiteACP
AXI5-
Lite
AWMPAMCHK
O
O
O
O
N
AWSUBSYSIDCHK
O
O
O
N
O
AWMECIDCHK
O
O
O
N
N
AWACTCHK
O
N
N
N
N
WVALIDCHK
O
O
O
O
O
WREADYCHK
O
O
O
O
O
WPENDINGCHK
O
N
N
N
N
WCRDTCHK
O
N
N
N
N
WCRDTSHCHK
O
N
N
N
N
WRPCHK
O
N
N
N
N
WSHAREDCRDCHK
O
N
N
N
N
WDATACHK
O
O
O
O
O
WSTRBCHK
O
O
O
O
O
WTAGCHK
O
O
O
N
N
WLASTCHK
O
O
O
O
N
WUSERCHK
O
O
O
O
O
WPOISONCHK
O
O
O
O
O
WTRACECHK
O
O
O
O
O
BVALIDCHK
O
O
O
O
O
BREADYCHK
O
O
O
O
O
BPENDINGCHK
O
N
N
N
N
BCRDTCHK
O
N
N
N
N
BIDCHK
O
O
O
O
O
BRESPCHK
O
O
O
O
O
BUSERCHK
O
O
O
O
O
BTRACECHK
O
O
O
O
O
BLOOPCHK
O
O
O
N
N
ARVALIDCHK
O
O
O
O
O
ARREADYCHK
O
O
O
O
O
ARPENDINGCHK
O
N
N
N
N
ARCRDTCHK
O
N
N
N
N
ARCRDTSHCHK
O
N
N
N
N
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
297


Chapter B2. Interface classes
B2.3. Parity check signal matrix
Table B2.3 – Continued from previous page
Signal
AXI5
ACE5-
Lite
ACE5-
LiteDVM
ACE5-
LiteACP
AXI5-
Lite
ARRPCHK
O
N
N
N
N
ARSHAREDCRDCHK
O
N
N
N
N
ARIDCHK
O
O
O
O
O
ARADDRCHK
O
O
O
O
O
ARLENCHK
O
O
O
O
N
ARCTLCHK0
O
O
O
O
O
ARCTLCHK1
O
O
O
O
N
ARCTLCHK2
O
O
O
O
N
ARCTLCHK3
O
O
O
O
N
ARPASCHK
O
N
N
N
N
ARINSTPRIVCHK
O
N
N
N
N
ARUSERCHK
O
O
O
O
O
ARTRACECHK
O
O
O
O
O
ARLOOPCHK
O
O
O
N
N
ARMMUCHK
O
O
N
N
N
ARMMUSIDCHK
O
O
N
N
N
ARMMUSSIDCHK
O
O
N
N
N
ARMMUPASUNKNOWNCHK
O
N
N
N
N
ARMMUPMCHK
O
N
N
N
N
ARNSAIDCHK
O
O
O
N
N
ARMPAMCHK
O
O
O
O
N
ARPBHACHK
O
O
O
N
N
ARSUBSYSIDCHK
O
O
O
N
O
ARMECIDCHK
O
O
O
N
N
ARACTCHK
O
N
N
N
N
RVALIDCHK
O
O
O
O
O
RREADYCHK
O
O
O
O
O
RPENDINGCHK
O
N
N
N
N
RCRDTCHK
O
N
N
N
N
RIDCHK
O
O
O
O
O
RDATACHK
O
O
O
O
O
RTAGCHK
O
O
O
N
N
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
298


Chapter B2. Interface classes
B2.3. Parity check signal matrix
Table B2.3 – Continued from previous page
Signal
AXI5
ACE5-
Lite
ACE5-
LiteDVM
ACE5-
LiteACP
AXI5-
Lite
RRESPCHK
O
O
O
O
O
RLASTCHK
O
O
O
O
N
RCHUNKCHK
O
O
O
O
N
RUSERCHK
O
O
O
O
O
RPOISONCHK
O
O
O
O
O
RTRACECHK
O
O
O
O
O
RLOOPCHK
O
O
O
N
N
ACVALIDCHK
O
N
O
N
N
ACREADYCHK
O
N
O
N
N
ACPENDINGCHK
O
N
N
N
N
ACCRDTCHK
O
N
N
N
N
ACADDRCHK
O
N
O
N
N
ACVMIDEXTCHK
O
N
O
N
N
ACTRACECHK
O
N
O
N
N
CRVALIDCHK
O
N
O
N
N
CRREADYCHK
O
N
O
N
N
CRPENDINGCHK
O
N
N
N
N
CRCRDTCHK
O
N
N
N
N
CRTRACECHK
O
N
O
N
N
VAWQOSACCEPTCHK
O
O
O
N
N
VARQOSACCEPTCHK
O
O
O
N
N
AWAKEUPCHK
O
O
O
O
O
ACWAKEUPCHK
O
N
O
N
N
ACTIVATEREQCHK
O
N
N
N
N
ACTIVATEACKCHK
O
N
N
N
N
ASKSTOPCHK
O
N
N
N
N
ACTIVATEREQDCHK
O
N
N
N
N
ACTIVATEACKDCHK
O
N
N
N
N
ASKSTOPDCHK
O
N
N
N
N
SYSCOREQCHK
O
N
O
N
N
SYSCOACKCHK
O
N
O
N
N
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
299


Chapter B2. Interface classes
B2.4. Property matrix
B2.4 Property matrix
A list of all properties is shown in Table B2.4.
The table shows the document issue in which the property was introduced and all legal values for the property.
There is a column for each interface class which shows the legal values of that property for that interface class. A
dash means there are no constraints on the property value.
Note that for User signals and User Loopback signals, the maximum width values are a recommendation rather
than a rule. See A12.5 User defined signaling and A12.4 User Loopback signaling for more information.
Table B2.4: Summary of interface property constraints
Property
Issue
Values
AXI5
ACE5-
Lite
ACE5-
LiteDVM
ACE5-
LiteACP
AXI5-
Lite
ACT_Support
L
v1, False
-
False
False
False
False
ACT_R_WIDTH
L
0, 16..32
-
0
0
0
0
ACT_W_WIDTH
L
0, 16..32
-
0
0
0
0
ADDR_WIDTH
H
1..64
-
-
-
-
-
ARSNOOP_WIDTH
J
0, 4
-
-
-
-
0
Atomic_Transactions
F
True, False
-
-
-
False
False
AWCMO_WIDTH
J
0, 2, 3
-
-
-
0
0
AWSNOOP_WIDTH
J
0, 4, 5
-
-
-
-
0
AXI_Transport
L
Ready, Credited
-
Ready
Ready
Ready
Ready
BRESP_WIDTH
J
0, 2, 3
-
-
-
-
-
BURST_Present
J
True, False
-
-
-
False
False
Busy_Support
J
True, False
-
-
-
False
False
Cache_Line_Size
K
16, 32, 64, 128, 256,
512, 1024, 2048
-
-
-
64
-
CACHE_Present
J
True, False
-
-
-
-
False
Cache_Stash_Transactions
F
True, Basic, False
-
-
-
-
False
Check_Type
F
Odd_Parity_Byte_All,
Odd_Parity_Byte_Data,
False
-
-
-
-
-
CMO_On_Read
G
True, False
-
-
-
False
False
CMO_On_Write
G
True, False
-
-
-
False
False
Coherency_Connection_Signals
F
True, False
-
False
-
False
False
Consistent_DECERR
H
True, False
-
-
-
-
True
Credit_Control
L
False,
Implicit_Return_Uni
-
False
False
False
False
DATA_WIDTH
H
8, 16, 32, 64, 128, 256,
512, 1024
-
-
-
128
-
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
300


Chapter B2. Interface classes
B2.4. Property matrix
Table B2.4 – Continued from previous page
Property
Issue
Values
AXI5
ACE5-
Lite
ACE5-
LiteDVM
ACE5-
LiteACP
AXI5-
Lite
DeAllocation_Transactions
F
True, False
-
-
-
False
False
Device_Normal_Independence
K
True, False
-
-
-
-
-
DVM_Message_Support
H
Receiver, False
-
False
Receiver
False
False
DVM_v8
E
True, False
-
False
-
False
False
DVM_v8.1
F
True, False
-
False
-
False
False
DVM_v8.4
H
True, False
-
False
-
False
False
DVM_v9.2
J
True, False
-
False
-
False
False
Exclusive_Accesses
H
True, False
-
-
-
False
False
Fixed_Burst_Disable
K
True, False
-
-
-
False
False
GDI_Support
L
True, False
-
False
False
False
False
ID_R_WIDTH
H
0..32
-
-
-
-
-
ID_W_WIDTH
H
0..32
-
-
-
-
-
INSTPRIV_Present
L
True, False
-
False
False
False
False
InvalidateHint_Transaction
J
True, False
-
-
-
False
False
LEN_Present
J
True, False
-
-
-
-
False
LOOP_R_WIDTH
H
0..8
-
-
-
0
0
LOOP_W_WIDTH
H
0..8
-
-
-
0
0
Loopback_Signals
F
True, False
-
-
-
False
False
Max_Transaction_Bytes
H
64, 128, 256, 512,
1024, 2048, 4096
-
-
-
-
-
MMUFLOW_Present
J
True, False
-
-
False
False
False
MEC_Support
K
True, False
-
-
-
False
False
MECID_WIDTH
K
0, 16
-
-
-
0
0
MPAM_Support
K
MPAM_9_1,
MPAM_12_1, False
-
-
-
-
False
MPAM_WIDTH
K
0, 11, 12, 14, 15
-
-
-
-
0
MTE_Support
K
Standard, Simplified,
Basic, False
-
-
Basic,
False
False
False
Multi_Copy_Atomicity
E
True, False
-
-
-
-
-
NSAccess_Identifiers
F
True, False
-
-
-
False
False
Num_RP_AR
L
1..8
-
1
1
1
1
Num_RP_AWW
L
1..8
-
1
1
1
1
Ordered_Write_Observation
E
True, False
-
-
-
-
-
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
301


Chapter B2. Interface classes
B2.4. Property matrix
Table B2.4 – Continued from previous page
Property
Issue
Values
AXI5
ACE5-
Lite
ACE5-
LiteDVM
ACE5-
LiteACP
AXI5-
Lite
PAS_WIDTH
L
0..3
-
0
0
0
0
PBHA_Support
J
True, False
-
-
-
False
False
PROT_Present
J
True, False
-
-
-
-
-
Persist_CMO
F
True, False
-
-
-
False
False
Poison
F
True, False
-
-
-
-
-
Prefetch_Transaction
H
True, False
-
-
-
False
False
QoS_Accept
F
True, False
-
-
-
False
False
QOS_Present
J
True, False
-
-
-
False
False
RCHUNKNUM_WIDTH
J
0, 1, 5, 6, 7, 8
-
-
-
-
0
RCHUNKSTRB_WIDTH
J
0, 1, 2, 4, 8
-
-
-
-
0
Read_Data_Chunking
G
True, False
-
-
-
-
False
Read_Interleaving_Disabled
G
True, False
-
-
-
-
False
REGION_Present
J
True, False
-
-
-
False
False
Regular_Transactions_Only
H
True, False
-
-
-
False
False
RLAST_Present
J
True, False
-
-
-
-
False
RME_Support
J
True, False
-
-
-
False
False
RRESP_WIDTH
J
0, 2, 3
-
-
-
-
-
SECSID_WIDTH
J
0, 1, 2
-
-
0
0
0
Shareable_Cache_Support
J
True, False
-
-
False
False
False
Shareable_Transactions
H
True, False
-
True
True
True
False
Shared_Credits_AR
L
True, False
-
False
False
False
False
Shared_Credits_AW
L
True, False
-
False
False
False
False
Shared_Credits_W
L
True, False
-
False
False
False
False
SID_WIDTH
H
0..32
-
-
0
0
0
SIZE_Present
J
True, False
-
-
-
False
-
SSID_WIDTH
H
0..20
-
-
0
0
0
STASHLPID_Present
J
True, False
-
-
-
-
False
STASHNID_Present
J
True, False
-
-
-
-
False
Storage_CMO
L
True, False
-
False
False
False
False
SUBSYSID_WIDTH
J
0..8
-
-
-
0
-
Trace_Signals
F
True, False
-
-
-
-
-
Unique_ID_Support
G
True, False
-
-
-
-
-
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
302


Chapter B2. Interface classes
B2.4. Property matrix
Table B2.4 – Continued from previous page
Property
Issue
Values
AXI5
ACE5-
Lite
ACE5-
LiteDVM
ACE5-
LiteACP
AXI5-
Lite
UnstashTranslation_Transaction
J
True, False
-
-
False
False
False
Untranslated_Transactions
F
v4, v3, v2, v1, True,
False
-
-
False
False
False
USER_DATA_WIDTH
H
0..DATA_WIDTH/2
-
-
-
-
-
USER_REQ_WIDTH
H
0..128
-
-
-
-
-
USER_RESP_WIDTH
H
0..16
-
-
-
-
-
Wrap_CLS_Modifiable
L
True, False
-
-
-
-
False
WLAST_Present
J
True, False
-
-
-
-
False
WSTRB_Present
J
True, False
-
-
-
-
-
Wakeup_Signals
F
True, False
-
-
-
-
-
Write_Plus_CMO
H
True, False
-
-
-
False
False
WriteDeferrable_Transaction
J
True, False
-
-
-
False
False
WriteZero_Transaction
H
True, False
-
-
-
False
False
WriteNoSnoopFull_Transaction
K
True, False
-
-
-
False
False
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
303
