# B1 Signal list

Chapter B1
Signal list
This appendix lists all the signals described within this specification. Some channels and signals are optional, so
are not included on every interface. Each signal name contains a hyperlink to the section in which the signal is
defined.
Parity check signals are not included in this chapter but are listed in A16.2.3 Parity check signals.
Signals are grouped based on channel and category as described in the following sections:
• B1.1 Write channels
• B1.2 Read channels
• B1.3 Snoop channels
• B1.4 Interface level signals
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
274


Chapter B1. Signal list
B1.1. Write channels
B1.1 Write channels
The write channels are used to transfer requests, data, and responses for write transactions and some other
data-less transactions.
B1.1.1
Write request channel
The write request channel carries all the required address and control information for transactions that use the
write channels. Signals on this channel have the prefix AW.
Table B1.1: Write request channel signals
Name
Width
Source
Description
AWVALID
1
Manager
Valid indicator
AWREADY
1
Subordinate
Ready indicator
AWPENDING
1
Manager
Pending indicator
AWCRDT
Num_RP_AWW
Subordinate
Credit grant
AWCRDTSH
1
Subordinate
Shared credit grant
AWRP
clog2(Num_RP_AWW)
Manager
Resource Plane indicator
AWSHAREDCRD
1
Manager
Shared credit indicator
AWID
ID_W_WIDTH
Manager
Transaction identifier for a write request
AWADDR
ADDR_WIDTH
Manager
Transaction address
AWREGION
4
Manager
Region identifier
AWLEN
8
Manager
Transaction length
AWSIZE
3
Manager
Transaction size
AWBURST
2
Manager
Burst attribute
AWLOCK
1
Manager
Exclusive access indicator
AWCACHE
4
Manager
Memory attributes
AWPROT
3
Manager
Protection attributes
AWNSE
1
Manager
Non-secure extension bit for RME
AWPAS
PAS_WIDTH
Manager
Physical Address Space
AWINST
1
Manager
Data or instruction request indicator
AWPRIV
1
Manager
Privileged request indicator
AWQOS
4
Manager
QoS identifier
AWUSER
USER_REQ_WIDTH
Manager
User-defined extension to a request
AWDOMAIN
2
Manager
Shareability domain of a request
AWSNOOP
AWSNOOP_WIDTH
Manager
Write request opcode
AWSTASHNID
11
Manager
Stash Node ID
AWSTASHNIDEN
1
Manager
Stash Node ID enable
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
275


Chapter B1. Signal list
B1.1. Write channels
Table B1.1 – Continued from previous page
Name
Width
Source
Description
AWSTASHLPID
5
Manager
Stash Logical Processor ID
AWSTASHLPIDEN
1
Manager
Stash Logical Processor ID enable
AWTRACE
1
Manager
Trace signal
AWLOOP
LOOP_W_WIDTH
Manager
Loopback signals on the write channels
AWMMUVALID
1
Manager
MMU signal qualifier
AWMMUSECSID
SECSID_WIDTH
Manager
Secure Stream ID
AWMMUSID
SID_WIDTH
Manager
StreamID
AWMMUSSIDV
1
Manager
SubstreamID valid
AWMMUSSID
SSID_WIDTH
Manager
SubstreamID
AWMMUATST
1
Manager
Address translated indicator
AWMMUFLOW
2
Manager
SMMU flow type
AWMMUPASUNKNOWN
1
Manager
PAS unknown indicator
AWMMUPM
1
Manager
Protected Mode indicator
AWPBHA
4
Manager
Page-based Hardware Attributes
AWMECID
MECID_WIDTH
Manager
Memory Encryption Context identifier
AWNSAID
4
Manager
Non-secure Access ID
AWSUBSYSID
SUBSYSID_WIDTH
Manager
Subsystem ID
AWATOP
6
Manager
Atomic transaction opcode
AWMPAM
MPAM_WIDTH
Manager
MPAM information with a request
AWIDUNQ
1
Manager
Unique ID indicator
AWCMO
AWCMO_WIDTH
Manager
CMO type
AWTAGOP
2
Manager
Memory Tag operation for write requests
AWACT
ACT_W_WIDTH
Manager
ACT payload
AWACTV
1
Manager
ACT valid indicator
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
276


Chapter B1. Signal list
B1.1. Write channels
B1.1.2
Write data channel
The write data channel carries write data and control information from a Manager to a Subordinate. Signals on this
channel have the prefix W.
Table B1.2: Write data channel signals
Name
Width
Source
Description
WVALID
1
Manager
Valid indicator
WREADY
1
Subordinate
Ready indicator
WPENDING
1
Manager
Pending indicator
WCRDT
Num_RP_AWW
Subordinate
Credit grant
WCRDTSH
1
Subordinate
Shared credit grant
WRP
clog2(Num_RP_AWW)
Manager
Resource Plane indicator for the W channel
WSHAREDCRD
1
Manager
Shared credit indicator
WDATA
DATA_WIDTH
Manager
Write data
WSTRB
DATA_WIDTH / 8
Manager
Write data strobes
WTAG
ceil(DATA_WIDTH/128)*4
Manager
Memory Tag
WTAGUPDATE
ceil(DATA_WIDTH/128)
Manager
Memory Tag update
WLAST
1
Manager
Last write data
WUSER
USER_DATA_WIDTH
Manager
User-defined extension to write data
WPOISON
ceil(DATA_WIDTH / 64)
Manager
Poison indicator
WTRACE
1
Manager
Trace signal
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
277


Chapter B1. Signal list
B1.1. Write channels
B1.1.3
Write response channel
The write response channel carries responses from Subordinate to Manager for transactions using the write data
channels. Signals on this channel have the prefix B.
Table B1.3: Write response channel signals
Name
Width
Source
Description
BVALID
1
Subordinate
Valid indicator
BREADY
1
Manager
Ready indicator
BPENDING
1
Subordinate
Pending indicator
BCRDT
1
Manager
Credit grant
BID
ID_W_WIDTH
Subordinate
Transaction identifier for a write response
BIDUNQ
1
Subordinate
Unique ID indicator
BRESP
BRESP_WIDTH
Subordinate
Write response
BCOMP
1
Subordinate
Completion response indicator
BPERSIST
1
Subordinate
Persist response
BTAGMATCH
2
Subordinate
Memory Tag Match response
BUSER
USER_RESP_WIDTH
Subordinate
User-defined extension to a write response
BTRACE
1
Subordinate
Trace signal
BLOOP
LOOP_W_WIDTH
Subordinate
Loopback signal on the write response channel
BBUSY
2
Subordinate
Busy indicator
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
278


Chapter B1. Signal list
B1.2. Read channels
B1.2 Read channels
The read channels are used to transfer requests, data, and responses for read transactions, cache maintenance
operations, and DVM Complete messages.
B1.2.1
Read request channel
The read request channel carries all the required address and control information for transactions that use the read
channels. Signals on this channel have the prefix AR.
Table B1.4: Read request channel signals
Name
Width
Source
Description
ARVALID
1
Manager
Valid indicator
ARREADY
1
Subordinate
Ready indicator
ARPENDING
1
Manager
Pending indicator
ARCRDT
Num_RP_AR
Subordinate
Credit grant
ARCRDTSH
1
Subordinate
Shared credit grant
ARRP
clog2(Num_RP_AR)
Manager
Resource Plane indicator
ARSHAREDCRD
1
Manager
Shared credit indicator
ARID
ID_R_WIDTH
Manager
Transaction identifier for a read request
ARADDR
ADDR_WIDTH
Manager
Transaction address
ARREGION
4
Manager
Region identifier
ARLEN
8
Manager
Transaction length
ARSIZE
3
Manager
Transaction size
ARBURST
2
Manager
Burst attribute
ARLOCK
1
Manager
Exclusive access indicator
ARCACHE
4
Manager
Memory attributes
ARPROT
3
Manager
Protection attributes
ARNSE
1
Manager
Non-secure extension bit for RME
ARPAS
PAS_WIDTH
Manager
Physical Address Space
ARINST
1
Manager
Data or instruction request indicator
ARPRIV
1
Manager
Privileged request indicator
ARQOS
4
Manager
QoS identifier
ARUSER
USER_REQ_WIDTH
Manager
User-defined extension to a request
ARDOMAIN
2
Manager
Shareability domain of a request
ARSNOOP
ARSNOOP_WIDTH
Manager
Read request opcode
ARTRACE
1
Manager
Trace signal
ARLOOP
LOOP_R_WIDTH
Manager
Loopback signal on the read request channel
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
279


Chapter B1. Signal list
B1.2. Read channels
Table B1.4 – Continued from previous page
Name
Width
Source
Description
ARMMUVALID
1
Manager
MMU signal qualifier
ARMMUSECSID
SECSID_WIDTH
Manager
Secure Stream ID
ARMMUSID
SID_WIDTH
Manager
StreamID
ARMMUSSIDV
1
Manager
SubstreamID valid
ARMMUSSID
SSID_WIDTH
Manager
SubstreamID
ARMMUATST
1
Manager
Address translated indicator
ARMMUFLOW
2
Manager
SMMU flow type
ARMMUPASUNKNOWN
1
Manager
PAS unknown indicator
ARMMUPM
1
Manager
Protected Mode indicator
ARPBHA
4
Manager
Page-based Hardware Attributes
ARMECID
MECID_WIDTH
Manager
Memory Encryption Context identifier
ARNSAID
4
Manager
Non-secure Access ID
ARSUBSYSID
SUBSYSID_WIDTH
Manager
Subsystem ID
ARMPAM
MPAM_WIDTH
Manager
MPAM information with a request
ARCHUNKEN
1
Manager
Read data chunking enable
ARIDUNQ
1
Manager
Unique ID indicator
ARTAGOP
2
Manager
Memory Tag operation for read requests
ARACT
ACT_R_WIDTH
Manager
ACT payload
ARACTV
1
Manager
ACT valid indicator
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
280


Chapter B1. Signal list
B1.2. Read channels
B1.2.2
Read data channel
The read data channel carries read data and responses from a Subordinate to a Manager. Signals on this channel
have the prefix R.
Table B1.5: Read data channel signals
Name
Width
Source
Description
RVALID
1
Subordinate
Valid indicator
RREADY
1
Manager
Ready indicator
RPENDING
1
Subordinate
Pending indicator
RCRDT
1
Manager
Credit grant
RID
ID_R_WIDTH
Subordinate
Transaction identifier for read data
RIDUNQ
1
Subordinate
Unique ID indicator
RDATA
DATA_WIDTH
Subordinate
Read data
RTAG
ceil(DATA_WIDTH/128)*4
Subordinate
Memory Tag
RRESP
RRESP_WIDTH
Subordinate
Read response
RLAST
1
Subordinate
Last read data
RUSER
USER_DATA_WIDTH +
USER_RESP_WIDTH
Subordinate
User-defined extension to read data and
response
RPOISON
ceil(DATA_WIDTH / 64)
Subordinate
Poison indicator
RTRACE
1
Subordinate
Trace signal
RLOOP
LOOP_R_WIDTH
Subordinate
Loopback signal on the read data channel
RCHUNKV
1
Subordinate
Read data chunking valid
RCHUNKNUM
RCHUNKNUM_WIDTH
Subordinate
Read data chunk number
RCHUNKSTRB
RCHUNKSTRB_WIDTH
Subordinate
Read data chunk strobe
RBUSY
2
Subordinate
Busy indicator
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
281


Chapter B1. Signal list
B1.3. Snoop channels
B1.3 Snoop channels
In this specification, the snoop channels are only used to transport DVM messages.
B1.3.1
Snoop request channel
The snoop request channel carries address and control information for DVM message requests. Signals on this
channel have the prefix AC.
Table B1.6: Snoop request channel signals
Name
Width
Source
Description
ACVALID
1
Subordinate
Valid indicator
ACREADY
1
Manager
Ready indicator
ACPENDING
1
Subordinate
Pending indicator
ACCRDT
1
Manager
Credit grant
ACADDR
ADDR_WIDTH
Subordinate
DVM message payload
ACVMIDEXT
4
Subordinate
VMID extension for DVM messages
ACTRACE
1
Subordinate
Trace signal
B1.3.2
Snoop response channel
The snoop response channel carries responses to DVM messages. Signals on this channel have the prefix CR.
Table B1.7: Snoop response channel signals
Name
Width
Source
Description
CRVALID
1
Manager
Valid indicator
CRREADY
1
Subordinate
Ready indicator
CRPENDING
1
Manager
Pending indicator
CRCRDT
1
Subordinate
Credit grant
CRTRACE
1
Manager
Trace signal
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
282


Chapter B1. Signal list
B1.4. Interface level signals
B1.4 Interface level signals
Interface level signals are non-channel signals. There can be up to one set of each per interface.
B1.4.1
Clock and reset signals
All signals on an interface are synchronous to a global clock and are reset using a global reset signal.
Table B1.8: Clock and reset signals
Name
Width
Source
Description
ACLK
1
External
Global clock signal
ARESETn
1
External
Global reset signal
B1.4.2
Credit control signals
Credit control signals are used with a credited link layer, to determine when channel receivers can give credits and
therefore when transmitters can send transfers.
Table B1.9: Credit control signals
Name
Width
Source
Description
ACTIVATEREQ
1
Manager
Activation request
ACTIVATEACK
1
Subordinate
Activation acknowledge
ASKSTOP
1
Subordinate
Stop request
ACTIVATEREQD
1
Subordinate
Activation request for snoop channels
ACTIVATEACKD
1
Manager
Activation acknowledge for snoop channels
ASKSTOPD
1
Manager
Stop request for snoop channels
B1.4.3
Wakeup signals
The wake-up signals are used to indicate that there is activity associated with the interface.
Table B1.10: Wake-up signals
Name
Width
Source
Description
AWAKEUP
1
Manager
Wake-up signal associated with read and write channels
ACWAKEUP
1
Subordinate
Wake-up signal associated with snoop channels
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
283


Chapter B1. Signal list
B1.4. Interface level signals
B1.4.4
QoS Accept signals
QoS Accept signals can be used by a Subordinate interface to indicate the minimum QoS value of requests that it
accepts.
Table B1.11: QoS Accept signals
Name
Width
Source
Description
VAWQOSACCEPT
4
Subordinate
QoS acceptance level for write requests
VARQOSACCEPT
4
Subordinate
QoS acceptance level for read requests
B1.4.5
Coherency Connection signals
The coherency connection signals are used by a Manager to control whether it receives DVM messages on the AC
channel.
Table B1.12: Coherency connection signals
Name
Width
Source
Description
SYSCOREQ
1
Manager
Coherency connect request
SYSCOACK
1
Subordinate
Coherency connect acknowledge
B1.4.6
Interface control signals
The interface control signals are static inputs to a Manager interface that can be used to configure interface
behavior.
Table B1.13: Interface control signals
Name
Width
Source
Description
BROADCASTATOMIC
1
Tie-off
Control input for Atomic transactions
BROADCASTSHAREABLE
1
Tie-off
Control input for Shareable transactions
BROADCASTCACHEMAINT
1
Tie-off
Control input for cache maintenance operations
BROADCASTCMOPOPA
1
Tie-off
Control input for the CleanInvalidPoPA CMO
BROADCASTPERSIST
1
Tie-off
Control input for CleanSharedPersist and CleanSharedDeepPersist
BROADCASTSTORAGE
1
Tie-off
Control input for CleanInvalidStorage CMO
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
284
