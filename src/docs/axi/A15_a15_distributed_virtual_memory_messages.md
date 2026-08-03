# A15 Distributed Virtual Memory messages

Chapter A15
Distributed Virtual Memory messages
This chapter describes how AXI supports distributed system MMUs using Distributed Virtual Memory (DVM)
messages to maintain all MMUs in a virtual memory system.
It contains the following sections:
• A15.1 Introduction to DVM transactions
• A15.2 Support for DVM messages
• A15.3 DVM messages
• A15.4 Transporting DVM messages
• A15.5 DVM Sync and Complete
• A15.6 Coherency Connection signaling
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
231


Chapter A15. Distributed Virtual Memory messages
A15.1. Introduction to DVM transactions
A15.1 Introduction to DVM transactions
DVM transactions are an optional feature used to pass messages that support the maintenance of a virtual memory
system. There are two types of DVM transactions: DVM message and DVM Complete.
A DVM message supports the following operations:
• TLB Invalidate
• Branch Predictor Invalidate
• Physical Instruction Cache Invalidate
• Virtual Instruction Cache Invalidate
• Synchronization
• Hint
DVM message requests are sent from a Subordinate interface, usually on an interconnect, to a Manager interface
using the snoop request (AC) channel.
DVM message responses are sent from a Manager to Subordinate interface using the snoop response (CR) channel.
A DVM Complete transaction is issued on the read request channel (AR) in response to a DVM Synchronization
(Sync) message, to indicate that all required operations and any associated transactions have completed.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
232


Chapter A15. Distributed Virtual Memory messages
A15.2. Support for DVM messages
A15.2 Support for DVM messages
The DVM_Message_Support property is used to indicate if an interface supports DVM messages.
Table A15.1: DVM_Message_Support property
DVM_Message_Support
Default
Description
Receiver
DVM message and Synchronization transactions are
supported from Subordinate to Manager interfaces on the
AC/CR channels. DVM Complete transactions are
supported from Manager to Subordinate interfaces on the
AR/R channels.
False
Y
DVM message transactions are not supported.
Note that the Bidirectional option for DVM_Message_Support in previous issues of this specification is deprecated
in this specification.
DVM Complete messages require that ARDOMAIN is set to Shareable. Therefore, when
DVM_Message_Support is Receiver the Shareable_Transactions property must be True.
DVM messages were introduced in the Armv7 architecture and were extended in Armv8, Armv8.1, Armv8.4, and
Armv9.2 architectures. It is essential that interfaces initiating and receiving DVM messages support the same
architecture versions.
The following properties define the version that is supported by an interface:
• DVM_v8
• DVM_v8.1
• DVM_v8.4
• DVM_v9.2
Each property can take the values: True or False. If a property is not declared, then it is considered False.
In Table A15.2 there is an indication of which message versions are supported, depending on the property values.
A component that supports DVM messages from a specific version must also support earlier architecture versions.
Table A15.2: DVM message versions
DVM property
Architecture support
DVM_v9.2
DVM_v8.4
DVM_v8.1
DVM_v8
Armv9.2
Armv8.4
Armv8.1
Armv8
Armv7
True
True or False
True or False
True or False
Y
Y
Y
Y
Y
False
True
True or False
True or False
-
Y
Y
Y
Y
False
False
True
True or False
-
-
Y
Y
Y
False
False
False
True
-
-
-
Y
Y
False
False
False
False
-
-
-
-
Y
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
233


Chapter A15. Distributed Virtual Memory messages
A15.3. DVM messages
A15.3 DVM messages
The following DVM messages are supported by the protocol:
• TLB Invalidate
• Branch Predictor Invalidate
• Physical Instruction Cache Invalidate
• Virtual Instruction Cache Invalidate
• Synchronization
• Hint
DVM transactions only operate on read-only structures, such as Instruction cache, Branch Predictor, and TLB, and
therefore only invalidation operations are required. The concept of cleaning does not apply to a read-only structure.
This means that it is functionally correct to invalidate more entries than the DVM message requires, although the
extra invalidations can affect performance.
A15.3.1
DVM message fields
The fields in DVM messages are shown in Table A15.3.
Table A15.3: DVM message fields
Name
Width
Description
VA
32-57
Virtual Address or Intermediate Physical Address (IPA).
PA
32-52
Physical Address
ASID
8 or 16
Address Space ID
ASIDV
1
Asserted HIGH to indicate that the ASID field is valid.
When deasserted, ASID must be zero.
VMID
8 or 16
Virtual Machine ID
VMIDV
1
Asserted HIGH to indicate that the VMID field is valid.
When deasserted, VMID must be zero.
DVMType
3
DVM message type:
0b000
TLB Invalidate (TLBI)
0b001
Branch Predictor Invalidate (BPI)
0b010
Physical Instruction Cache Invalidate (PICI)
0b011
Virtual Instruction Cache Invalidate (VICI)
0b100
Synchronization (Sync)
0b101
Reserved
0b110
Hint
0b111
Reserved
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
234


Chapter A15. Distributed Virtual Memory messages
A15.3. DVM messages
Table A15.3 – Continued from previous page
Name
Width
Description
Exception
2
Indicates the Exception level that the transaction applies to:
0b00
Hypervisor and all Guest OS
0b01
EL3
0b10
Guest OS
0b11
Hypervisor
Security
2
Indicates which Security state the invalidation applies to.
See Table A15.6 for encodings.
Leaf
1
Indicates whether only leaf entries are invalidated:
0b0
Invalidate all associated translations.
0b1
Invalidate Leaf Entry only.
Stage
2
Indicates which stages are invalidated:
0b00
Armv7: Stage of invalidation varies with invalidation type.
Armv8 and later: Stage 1 and Stage 2 invalidation.
0b01
Stage 1 only invalidation.
0b10
Stage 2 only invalidation.
0b11
GPT
Num
5
Used as a constant multiplication factor in the range calculation.
All binary values are valid.
Scale
2
Used as a constant in address range exponent calculation.
All binary values are valid.
TTL
2
Hint of Translation Table Level (TTL) which includes the addresses to be
invalidated. See Table A15.4 and Table A15.5 for details.
TG
2
Translation Granule (TG).
For TLB Invalidations by range, TG indicates the granule size:
0b00
Reserved.
0b01
4KB
0b10
16KB
0b11
64KB
For non-range TLB Invalidations, TG and TTL indicate the table level hint, see
Table A15.5.
VI
16
Virtual Index, used for PICI messages.
VIV
2
Virtual Index Valid:
0b00
Virtual Index not valid
0b01
Reserved
0b10
Reserved
0b11
Virtual Index valid
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
235


Chapter A15. Distributed Virtual Memory messages
A15.3. DVM messages
Table A15.3 – Continued from previous page
Name
Width
Description
IS
4
Invalidation Size encoding for GPT TLBI by PA operations:
0b0000
4KB
0b0001
16KB
0b0010
64KB
0b0011
2MB
0b0100
32MB
0b0101
512MB
0b0110
1GB
0b0111
16GB
0b1000
64GB
0b1001
512GB
0b1010-
0b1111
Reserved
Addr
1
Indicates if the message includes an address.
0b0
No address information.
0b1
Address included, this is a two-part message.
Range
1
Asserted HIGH to indicate that the 2nd part indicates an address range.
Completion
1
Asserted HIGH to indicate that a Completion message is required.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
236


Chapter A15. Distributed Virtual Memory messages
A15.3. DVM messages
TLB Invalidate level hint
For TLB Invalidations by address range, the TTL field indicates which level of translation table walk holds the leaf
entry for the address being invalidated. The encodings are shown in Table A15.4.
Table A15.4: Leaf entry hint for range-based TLB Invalidations
TTL
Meaning
0b00
No level hint information.
0b01
The leaf entry is on level 1 of the translation table walk.
0b10
The leaf entry is on level 2 of the translation table walk.
0b11
The leaf entry is on level 3 of the translation table walk.
For TLB Invalidations by non-range address, the TTL and TG fields indicate which level of translation table walk
holds the leaf entry for the address being invalidated. The encodings are shown in Table A15.5.
Table A15.5: Leaf entry hint for non-range TLB Invalidations
TG
TTL
Meaning
0b00
0b00
No level hint
0b01
Reserved
0b10
Reserved
0b11
Reserved
0b01
0b00
No level hint
0b01
The leaf entry is on level 1 of the translation table walk.
0b10
The leaf entry is on level 2 of the translation table walk.
0b11
The leaf entry is on level 3 of the translation table walk.
0b10
0b00
No level hint
0b01
No level hint
0b10
The leaf entry is on level 2 of the translation table walk.
0b11
The leaf entry is on level 3 of the translation table walk.
0b11
0b00
No level hint
0b01
The leaf entry is on level 1 of the translation table walk.
0b10
The leaf entry is on level 2 of the translation table walk.
0b11
The leaf entry is on level 3 of the translation table walk.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
237


Chapter A15. Distributed Virtual Memory messages
A15.3. DVM messages
Security field
The Security field has different meanings depending on the DVM Type, as shown in Table A15.6.
Table A15.6: Security field encodings per DVM Type
Security
TLBI
BPI
PICI All
PICI by PA
VICI
0b00
Realm
Secure and
Non-secure
Root, Realm,
Secure, and
Non-secure
Root
Secure and
Non-secure
0b01
Non-secure
address from a
Secure context
Reserved
Realm and
Non-secure
Realm
Reserved
0b10
Secure
Reserved
Secure and
Non-secure
Secure
Secure
0b11
Non-secure
Reserved
Non-secure
Non-secure
Non-secure
ASID field
The ASID field contains an 8-bit or 16-bit Address Space ID.
• Armv7 supports only an 8-bit ASID.
• Armv8 and above support both 8-bit and 16-bit ASID.
It cannot be determined from a DVM message whether the message uses an 8-bit or 16-bit ASID. All 8-bit ASID
messages are required to set the ASID[15:8] bits to zero.
It is expected that most systems will use a single ASID size across the entire system, either 8-bit ASID or 16-bit
ASID.
In a system that contains a mix of 8-bit ASID and 16-bit ASID components, it is expected that all maintenance is
done by an agent that uses 16-bit ASID. This ensures that the agent can perform maintenance on both the 8-bit
ASID and 16-bit ASID components.
The interoperability requirements are:
• For an 8-bit ASID agent sending a message to a 16-bit ASID agent, a message appears as a 16-bit ASID with
the upper 8 bits set to zero.
• For a 16-bit ASID agent sending a message to an 8-bit ASID agent:
– If the upper 8 bits are zero, the message was received correctly.
– If the upper 8 bits are non-zero, then over-invalidation will occur, since the 8-bit ASID agent ignores the
upper 8 bits.
VMID field
The VMID field contains an 8-bit or 16-bit Virtual Machine ID.
• Armv7 and Armv8 support only 8-bit VMIDs.
• Armv8.1 and above support both 8-bit and 16-bit VMIDs.
It cannot be determined from a DVM message whether the message uses an 8-bit or 16-bit VMID. All 8-bit VMID
messages are required to set the VMID[15:8] field to zero.
It is expected that most systems use a single VMID size across the entire system, either 8-bit VMID or 16-bit
VMID.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
238


Chapter A15. Distributed Virtual Memory messages
A15.3. DVM messages
In a system that contains a mix of 8-bit VMID and 16-bit VMID components, it is expected that all maintenance is
done by an agent that uses 16-bit VMID. This ensures that the agent can perform maintenance on both the 8-bit
VMID and 16-bit VMID components.
The interoperability requirements are:
• For an 8-bit VMID agent sending a message to a 16-bit VMID agent, a message appears as a 16-bit VMID
with the upper 8 bits set to zero.
• For a 16-bit VMID agent sending a message to an 8-bit VMID agent:
– If the upper 8 bits are zero, the message was received correctly.
– If the upper 8 bits are nonzero, then over-invalidation will occur, since the 8-bit VMID agent ignores the
upper 8 bits.
When Armv8.1 and above is supported, ACVMIDEXT is included on the AC channel to transport the upper byte
of 16-bit VMIDs. See A15.4 Transporting DVM messages for more details.
A15.3.2
TLB Invalidate messages
This section details the TLB Invalidate (TLBI) message.
For a TLBI message some fields have a fixed value, as shown in Table A15.7.
Table A15.7: Fixed field values for a TLBI message
Name
Value
Meaning
DVMType
0b000
TLB Invalidate opcode.
Completion
0b0
Completion not required.
The entries on which the TLBI must operate depends on the fields in the message. All supported TLBI operations
are shown in Table A15.8.
The Arm column indicates the minimum Arm architecture version required to support the message.
The field to signal mappings for TLBI messages are detailed in Table A15.20.
Table A15.8: TLBI messages
Operation
Arm
Exception
Security
VMIDV
ASIDV
Leaf
Stage
Addr
EL3 TLBI all
v8
0b01
0b10
0b0
0b0
0b0
0b00
0b0
EL3 TLBI by VA
v8
0b01
0b10
0b0
0b0
0b0
0b00
0b1
EL3 TLBI by VA, Leaf only
v8
0b01
0b10
0b0
0b0
0b1
0b00
0b1
Secure Guest OS TLBI by Non-secure IPA
v8.4
0b10
0b01
0b1
0b0
0b0
0b10
0b1
Secure Guest OS TLBI by Non-secure IPA,
Leaf only
v8.4
0b10
0b01
0b1
0b0
0b1
0b10
0b1
Secure TLBI all
v7
0b10
0b10
0b0
0b0
0b0
0b00
0b0
Secure TLBI by VA
v7
0b10
0b10
0b0
0b0
0b0
0b00
0b1
Secure TLBI by VA, Leaf only
v8
0b10
0b10
0b0
0b0
0b1
0b00
0b1
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
239


Chapter A15. Distributed Virtual Memory messages
A15.3. DVM messages
Table A15.8 – Continued from previous page
Operation
Arm
Exception
Security
VMIDV
ASIDV
Leaf
Stage
Addr
Secure TLBI by ASID
v7
0b10
0b10
0b0
0b1
0b0
0b00
0b0
Secure TLBI by ASID and VA
v7
0b10
0b10
0b0
0b1
0b0
0b00
0b1
Secure TLBI by ASID and VA, Leaf only
v8
0b10
0b10
0b0
0b1
0b1
0b00
0b1
Secure Guest OS TLBI all
v8.4
0b10
0b10
0b1
0b0
0b0
0b00
0b0
Secure Guest OS TLBI by VA
v8.4
0b10
0b10
0b1
0b0
0b0
0b00
0b1
Secure Guest OS TLBI all, Stage 1 only
v8.4
0b10
0b10
0b1
0b0
0b0
0b01
0b0
Secure Guest OS TLBI by Secure IPA
v8.4
0b10
0b10
0b1
0b0
0b0
0b10
0b1
Secure Guest OS TLBI by VA, Leaf only
v8.4
0b10
0b10
0b1
0b0
0b1
0b00
0b1
Secure Guest OS TLBI by Secure IPA,
Leaf only
v8.4
0b10
0b10
0b1
0b0
0b1
0b10
0b1
Secure Guest OS TLBI by ASID
v8.4
0b10
0b10
0b1
0b1
0b0
0b00
0b0
Secure Guest OS TLBI by ASID and VA
v8.4
0b10
0b10
0b1
0b1
0b0
0b00
0b1
Secure Guest OS TLBI by ASID and VA,
Leaf only
v8.4
0b10
0b10
0b1
0b1
0b1
0b00
0b1
All OS TLBI all
v7
0b10
0b11
0b0
0b0
0b0
0b00
0b0
Guest OS TLBI all, Stage 1 and 2
v7
0b10
0b11
0b1
0b0
0b0
0b00
0b0
Guest OS TLBI by VA
v7
0b10
0b11
0b1
0b0
0b0
0b00
0b1
Guest OS TLBI all, Stage 1 only
v8
0b10
0b11
0b1
0b0
0b0
0b01
0b0
Guest OS TLBI by IPA
v8
0b10
0b11
0b1
0b0
0b0
0b10
0b1
Guest OS TLBI by VA, Leaf only
v8
0b10
0b11
0b1
0b0
0b1
0b00
0b1
Guest OS TLBI by IPA, Leaf only
v8
0b10
0b11
0b1
0b0
0b1
0b10
0b1
Guest OS TLBI by ASID
v7
0b10
0b11
0b1
0b1
0b0
0b00
0b0
Guest OS TLBI by ASID and VA
v7
0b10
0b11
0b1
0b1
0b0
0b00
0b1
Guest OS TLBI by ASID and VA, Leaf
only
v8
0b10
0b11
0b1
0b1
0b1
0b00
0b1
Secure Hypervisor TLBI all
v8.4
0b11
0b10
0b0
0b0
0b0
0b00
0b0
Secure Hypervisor TLBI by VA
v8.4
0b11
0b10
0b0
0b0
0b0
0b00
0b1
Secure Hypervisor TLBI by VA, Leaf only
v8.4
0b11
0b10
0b0
0b0
0b1
0b00
0b1
Secure Hypervisor TLBI by ASID
v8.4
0b11
0b10
0b0
0b1
0b0
0b00
0b0
Secure Hypervisor TLBI by ASID and VA
v8.4
0b11
0b10
0b0
0b1
0b0
0b00
0b1
Secure Hypervisor TLBI by ASID and VA,
Leaf only
v8.4
0b11
0b10
0b0
0b1
0b1
0b00
0b1
Hypervisor TLBI all
v7
0b11
0b11
0b0
0b0
0b0
0b00
0b0
Hypervisor TLBI by VA
v7
0b11
0b11
0b0
0b0
0b0
0b00
0b1
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
240


Chapter A15. Distributed Virtual Memory messages
A15.3. DVM messages
Table A15.8 – Continued from previous page
Operation
Arm
Exception
Security
VMIDV
ASIDV
Leaf
Stage
Addr
Hypervisor TLBI by VA, Leaf only
v8
0b11
0b11
0b0
0b0
0b1
0b00
0b1
Hypervisor TLBI by ASID
v8.1
0b11
0b11
0b0
0b1
0b0
0b00
0b0
Hypervisor TLBI by ASID and VA
v8.1
0b11
0b11
0b0
0b1
0b0
0b00
0b1
Hypervisor TLBI by ASID and VA, Leaf
only
v8.1
0b11
0b11
0b0
0b1
0b1
0b00
0b1
Realm TLBI all
v9.2
0b10
0b00
0b0
0b0
0b0
0b00
0b0
Realm Guest OS TLBI all, Stage 1 only
v9.2
0b10
0b00
0b1
0b0
0b0
0b01
0b0
Realm Guest OS TLBI all, Stage 1 and 2
v9.2
0b10
0b00
0b1
0b0
0b0
0b00
0b0
Realm Guest OS TLBI by VA
v9.2
0b10
0b00
0b1
0b0
0b0
0b00
0b1
Realm Guest OS TLBI by VA, Leaf only
v9.2
0b10
0b00
0b1
0b0
0b1
0b00
0b1
Realm Guest OS TLBI by ASID
v9.2
0b10
0b00
0b1
0b1
0b0
0b00
0b0
Realm Guest OS TLBI by ASID and VA
v9.2
0b10
0b00
0b1
0b1
0b0
0b00
0b1
Realm Guest OS TLBI by ASID and VA,
Leaf only
v9.2
0b10
0b00
0b1
0b1
0b1
0b00
0b1
Realm Guest OS TLBI by IPA
v9.2
0b10
0b00
0b1
0b0
0b0
0b10
0b1
Realm Guest OS TLBI by IPA, Leaf only
v9.2
0b10
0b00
0b1
0b0
0b1
0b10
0b1
Realm Hypervisor TLBI all
v9.2
0b11
0b00
0b0
0b0
0b0
0b00
0b0
Realm Hypervisor TLBI by VA
v9.2
0b11
0b00
0b0
0b0
0b0
0b00
0b1
Realm Hypervisor TLBI by VA, Leaf only
v9.2
0b11
0b00
0b0
0b0
0b1
0b00
0b1
Realm Hypervisor TLBI by ASID
v9.2
0b11
0b00
0b0
0b1
0b0
0b00
0b0
Realm Hypervisor TLBI by ASID and VA
v9.2
0b11
0b00
0b0
0b1
0b0
0b00
0b1
Realm Hypervisor TLBI by ASID and VA,
Leaf only
v9.2
0b11
0b00
0b0
0b1
0b1
0b00
0b1
GPT TLBI by PA
v9.2
0b01
0b10
0b0
0b0
0b0
0b11
0b1
GPT TLBI by PA, Leaf only
v9.2
0b01
0b10
0b0
0b0
0b1
0b11
0b1
GPT TLBI all
v9.2
0b01
0b10
0b0
0b0
0b0
0b11
0b0
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
241


Chapter A15. Distributed Virtual Memory messages
A15.3. DVM messages
Range field
The Range field indicates that an invalidation operates on a range of addresses.
Range can be 0b1 for messages where both of the following apply:
• Arm is v8.4 or later.
• The Addr bit is 0b1, so the message includes an address.
Range based TLB Invalidate by IPA or VA
When the Range field is 0b1 for a TLBI by VA or IPA, the address range to invalidate is calculated using the
following formula:
BaseAddr ≤AddressRange < BaseAddr+
�
(Num + 1) × 2(5×Scale+1) × Translation_Granule_Size
�
Where:
• Translation_Granule_Size in bytes is determined from the TG value provided in the message. See Table
A15.3 for encodings.
• Scale is provided in the message, it can take any value from 0-3.
• Num is provided in the message, it can take any value from 0-31.
• BaseAddr is the base address of the range, based on TG:
– 4K: BaseAddr is VA[MaxVA:12].
– 16K: BaseAddr is VA[MaxVA:14], VA[13:12] must be zero.
– 64K: BaseAddr is VA[MaxVA:16], VA[15:12] must be zero.
A TLBI by Range is a 2-part message with field mappings described in Table A15.20.
GPT TLB Invalidate
Granule Protection Table (GPT) TLBI by PA operations perform range-based invalidation and invalidate TLB
entries starting from the PA, within the range as specified in the Invalidation Size (IS) field. See Table A15.3 for
encodings.
If the PA is not aligned to the IS value, no TLB entries are required to be invalidated.
The IS field is applicable only in GPT TLBI by PA operations.
• A GPT TLBI all message is signaled using a 1-part message with the Range field set to 0b0.
• A GPT TLBI by PA message is signaled using a 2-part message with the Range field set to 0b1.
The field to signal mappings for GPT TLBI messages are shown in Table A15.20.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
242


Chapter A15. Distributed Virtual Memory messages
A15.3. DVM messages
A15.3.3
Branch Predictor Invalidate messages
The Branch Predictor Invalidate (BPI) message is used to invalidate virtual addresses from branch predictors.
A BPI message is signaled using a 1-part or 2-part message with field to signal mappings detailed in Table A15.21.
The fixed field values for a BPI message are shown in Table A15.9.
Table A15.9: Fixed field values for a BPI message
Name
Value
Meaning
DVMType
0b001
Branch Predictor Invalidate opcode
Completion
0b0
Completion not required
Range
0b0
Address is not a range
VMIDV
0b0
VMID field not valid
ASIDV
0b0
ASID field not valid
Exception
0b00
Hypervisor and all Guest OS
Security
0b00
Secure and Non-secure
Leaf
0b0
Leaf information is N/A
Stage
0b00
Stage information is N/A
All supported BPI operations are shown in Table A15.10.
The Arm column indicates the minimum Arm architecture version required to support the message.
Table A15.10: BPI messages
Operation
Arm
Addr
Branch Predictor Invalidate all
v7
0b0
Branch Predictor Invalidate by VA
v7
0b1
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
243


Chapter A15. Distributed Virtual Memory messages
A15.3. DVM messages
A15.3.4
Instruction cache invalidations
Instruction caches can use either a physical address or a virtual address to tag the data they contain. A system
might contain a mixture of both forms of cache.
The DVM protocol includes instruction cache invalidation operations that use physical addresses and operations
that use virtual addresses. A component that receives DVM messages must support both forms of message,
independent of the style of instruction cache implemented. It might be necessary to over-invalidate in the case
where a message is received in a format that is not native to the cache type.
Physical Instruction Cache Invalidate
This section lists the Physical Instruction Cache Invalidate (PICI) operations that the DVM message supports.
This message type is also used for Instruction Caches which are Virtually Indexed Physically Tagged (VIPT).
A PICI message is signaled using a 1-part or 2-part message with field to signal mappings detailed in Table
A15.22. The fixed field values for a PICI message are shown in Table A15.11.
Table A15.11: Fixed field values for a PICI message
Name
Value
Meaning
DVMType
0b010
Physical Instruction Cache Invalidate opcode
Completion
0b0
Completion not required
Range
0b0
Address is not a range
Exception
0b00
Hypervisor and all Guest OS
Leaf
0b0
Leaf information is N/A
Stage
0b00
Stage information is N/A
All supported PICI operations are shown in Table A15.12.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
244


Chapter A15. Distributed Virtual Memory messages
A15.3. DVM messages
Table A15.12: PICI messages
Operation
Arm
Security
VIV
Addr
PICI all Root, Realm, Secure and Non-secure
v9.2
0b00
0b00
0b0
PICI by PA without Virtual Index, Root only
v9.2
0b00
0b00
0b1
PICI by PA with Virtual Index, Root only
v9.2
0b00
0b11
0b1
PICI all Realm and Non-secure
v9.2
0b01
0b00
0b0
PICI by PA without Virtual Index, Realm only
v9.2
0b01
0b00
0b1
PICI by PA with Virtual Index, Realm only
v9.2
0b01
0b11
0b1
PICI all Secure and Non-secure
v7
0b10
0b00
0b0
PICI by PA without Virtual Index, Secure only
v7
0b10
0b00
0b1
PICI by PA with Virtual Index, Secure only
v7
0b10
0b11
0b1
PICI all, Non-secure only
v7
0b11
0b00
0b0
PICI by PA without Virtual Index, Non-secure only
v7
0b11
0b00
0b1
PICI by PA with Virtual Index, Non-secure only
v7
0b11
0b11
0b1
When the Virtual Index Valid (VIV) field is 0b11, then VI[27:12] is used as part of the Physical Address.
Note that in previous issues of this specification, a PICI all with Security value of 0b10 was incorrectly labeled as
Secure only when it should have been Secure and Non-secure.
Virtual Instruction Cache Invalidate
This section lists the Virtual Instruction Cache Invalidate (VICI) operations that the DVM message supports.
A VICI message is signaled using a 1-part or 2-part message with field to signal mappings detailed in Table
A15.22.
The fixed field values for a VICI message are shown in Table A15.13.
Table A15.13: Fixed field values for a VICI message
Name
Value
Meaning
DVMType
0b011
Virtual Instruction Cache Invalidate opcode
Completion
0b0
Completion not required
Range
0b0
Address is not a range
Leaf
0b0
Leaf information is N/A
Stage
0b00
Stage information is N/A
All supported VICI operations are shown in Table A15.14.
The Arm column indicates the minimum Arm architecture version required to support the message.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
245


Chapter A15. Distributed Virtual Memory messages
A15.3. DVM messages
Table A15.14: VICI messages
Operation
Arm
Exception
Security
VMIDV
ASIDV
Addr
Hypervisor and all Guest OS VICI all, Secure and Non-secure
v7
0b00
0b00
0b0
0b0
0b0
Hypervisor and all Guest OS VICI all, Non-secure only
v7
0b00
0b11
0b0
0b0
0b0
All Guest OS VICI by ASID and VA, Secure only
v7
0b10
0b10
0b0
0b1
0b1
All Guest OS VICI by VMID, Secure only
v8.4
0b10
0b10
0b1
0b0
0b0
All Guest OS VICI by ASID, VA and VMID, Secure only
v8.4
0b10
0b10
0b1
0b1
0b1
All Guest OS VICI by VMID, Non-secure only
v7
0b10
0b11
0b1
0b0
0b0
All Guest OS VICI by ASID, VA and VMID, Non-secure only
v7
0b10
0b11
0b1
0b1
0b1
Hypervisor VICI by VA, Non-secure only
v7
0b11
0b11
0b0
0b0
0b1
Hypervisor VICI by ASID and VA, Non-secure only
v8.1
0b11
0b11
0b0
0b1
0b1
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
246


Chapter A15. Distributed Virtual Memory messages
A15.3. DVM messages
A15.3.5
Synchronization message
A Synchronization (Sync) message is used when the requester needs to know when all previous invalidations are
complete. For more information on how to use the Sync message, see A15.5 DVM Sync and Complete.
A Sync message is signaled using a 1-part message with field to signal mappings detailed in Table A15.21.
The fixed field values for a Sync message are shown in Table A15.15.
Table A15.15: Fixed field values for a Sync message
Name
Value
Meaning
DVMType
0b100
Sync opcode
Completion
0b1
Completion required
ASIDV
0b0
No ASID information
VMIDV
0b0
No VMID information
Addr
0b0
No address information
Range
0b0
No address range
Exception
0b00
Exception information is N/A
Security
0b00
Security information is N/A
Leaf
0b0
Leaf information is N/A
Stage
0b00
Stage information is N/A
A15.3.6
Hint message
A reserved message address space is provided for future Hint messages.
The fixed field values for a Hint message are shown in Table A15.16.
Table A15.16: Fixed field values for a Hint message
Name
Value
Meaning
DVMType
0b110
Hint opcode
Completion
0b0
Completion not required
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
247


Chapter A15. Distributed Virtual Memory messages
A15.4. Transporting DVM messages
A15.4 Transporting DVM messages
To transport DVM messages, two channels are added to an interface:
• Snoop request channel, used to transfer DVM message requests. Signals on this channel have the prefix AC.
• Snoop response channel, used to transfer DVM message responses. Signals on this channel have the prefix
CR.
A DVM message transaction consists of one request transfer on the snoop request channel and one response on the
snoop response channel. There can be one or two transactions per message, the Addr field in the first request
indicates if another transaction is required.
DVM messages that do not include an address are sent using one transaction.
DVM messages that include an address are sent using two transactions.
An interconnect is usually used to replicate and distribute DVM message requests to participating Manager
components. Managers can use the Coherency Connection signaling to opt into receiving messages at runtime, see
A15.6 Coherency Connection signaling.
Flows for one-part and two-part messages are shown in Figure A15.1.
AC
CR
Interconnect
(Subordinate Interface)
Receiving 
Manager
AC
CR
Interconnect
(Subordinate Interface)
Receiving 
Manager
DVM request
(1 part)
response
DVM request
(2nd part)
DVM request
(1st part)
response
to 2nd part
response
to 1st part
Figure A15.1: DVM message flows
The following rules apply to two-part DVM messages:
• The requests are always sent as successive transfers, with no other message requests between them.
• A component issuing a two-part DVM message must be able to issue the second part of the message without
requiring a response to the first part of the message.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
248


Chapter A15. Distributed Virtual Memory messages
A15.4. Transporting DVM messages
A15.4.1
Signaling for DVM messages
Snoop channels for DVM messages use the same transport as the other AXI channels as determined by the
AXI_Transport property. See A2.2 AXI transport options for more details on transport.
DVM message requests use the snoop request channel from a Subordinate to a Manager interface. Table A15.17
shows the signals that can be included in the snoop request channel.
Table A15.17: Snoop request channel
Name
Width
Source
Presence
Description
ACVALID
1
Subordinate
DVM_Message_Support
DVM message request valid
indicator.
ACREADY
1
Manager
DVM_Message_Support and
AXI_Transport == Ready
DVM message request ready
indicator.
ACPENDING
1
Subordinate
DVM_Message_Support and
AXI_Transport == Credited
Pending signal for the AC
channel.
ACCRDT
1
Manager
DVM_Message_Support and
AXI_Transport == Credited
Asserted high to give one
DVM message request
credit.
ACADDR
ADDR_WIDTH
Subordinate
DVM_Message_Support
Used to carry the payload
for DVM message requests.
ACVMIDEXT
4
Subordinate
DVM_Message_Support and
(DVM_v8.1 or DVM_v8.4 or
DVM_v9.2)
Extension to support 16-bit
VMID in DVM messages.
ACTRACE
1
Subordinate
DVM_Message_Support and
Trace_Signals
Trace signal for the AC
channel.
The response to a DVM request is transported on the snoop response channel from a Manager to a Subordinate
interface. Table A15.18 shows the signals that can be included in the snoop response channel.
Table A15.18: Snoop response channel
Name
Width
Source
Presence
Description
CRVALID
1
Manager
DVM_Message_Support
DVM message response
valid indicator.
CRREADY
1
Subordinate
DVM_Message_Support and
AXI_Transport == Ready
DVM message response
ready indicator.
CRPENDING
1
Manager
DVM_Message_Support and
AXI_Transport == Credited
Pending signal for the CR
channel.
CRCRDT
1
Subordinate
DVM_Message_Support and
AXI_Transport == Credited
Asserted high to give one
DVM message response
credit.
CRTRACE
1
Manager
DVM_Message_Support and
Trace_Signals
Trace signal for the CR
channel.
A DVM response acknowledges that the request has been received but does not indicate the success or failure of a
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
249


Chapter A15. Distributed Virtual Memory messages
A15.4. Transporting DVM messages
DVM message. Reordering is not supported on the AC or CR channels, so responses are returned in the same
order as the AC requests were issued.
The ACTRACE and CRTRACE signals act the same as trace signals on other channels, see A12.3 Trace signals
for more information.
A15.4.2
Snoop channels using Valid-Ready transport
When using a Valid-Ready transport, the following rules apply:
• ACVALID must only be asserted by a Subordinate when there is valid address and control information.
• When asserted, ACVALID must remain asserted until the rising clock edge after the Manager asserts the
ACREADY signal.
• CRVALID is asserted to indicate that the Manager has acknowledged the DVM message.
• When asserted, CRVALID must remain asserted until the rising clock edge after the Subordinate asserts the
CRREADY signal.
The rules for dependencies between the snoop request and response channels are listed below and illustrated in
Figure A15.2.
• The Subordinate must not wait for the Manager to assert ACREADY before asserting ACVALID.
• The Manager can wait for ACVALID to be asserted before it asserts ACREADY.
• The Manager can assert ACREADY before ACVALID is asserted.
• The Manager must wait for both ACVALID and ACREADY to be asserted before it asserts CRVALID to
indicate that a valid response is available.
• The Manager must not wait for the Subordinate to assert CRREADY before asserting CRVALID.
• The Subordinate can wait for CRVALID to be asserted before it asserts CRREADY.
• The Subordinate can assert CRREADY before CRVALID is asserted.
ACREADY
CRREADY
ACVALID
CRVALID
Figure A15.2: Snoop transaction handshake dependencies
A15.4.3
Snoop channels using credited transport
When using credited transport, the rules of A2.4 Credited transport and A2.4.4 Transfer-level clock gating apply
to the snoop channels. In addition:
• The Manager must wait for a DVM message request before sending a DVM message response.
• Multiple Resource Planes and shared credits are not supported on the snoop channels.
A15.4.4
Address widths in DVM messages
The property ADDR_WIDTH is used to specify the width of ARADDR, AWADDR, and ACADDR. This sets the
physical address width used by an interface.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
250


Chapter A15. Distributed Virtual Memory messages
A15.4. Transporting DVM messages
The ACADDR signal is also used to transport the Virtual Address (VA), so the required VA width also sets a
minimum constraint on ADDR_WIDTH. Table A15.19 shows some common VA widths and the minimum
ADDR_WIDTH required.
Table A15.19: Common VA widths and minimum ADDR_WIDTH
VA width
Minimum
ADDR_WIDTH
32
32
41
40
49
44
53
48
57
48
VA widths greater than 57-bits are not supported.
If the PA width exceeds the VA width, then virtual address operations might receive additional address information
in a DVM message. In this case, any additional address information must be ignored and operations performed
using only the supported address bits.
If a component supports a larger VA width than its PA width, the component must take appropriate action
regarding the additional physical address bits. See A3.1.5 Transfer address for more details on mismatched
address widths.
A15.4.5
Mapping message fields to signals
The fields in DVM messages are transported using bits of the ACADDR and ACVMIDEXT signals.
There are different mappings for each message type, shown in the tables below. The bit position allocation might
appear irregular but is used to ease the translation between implementations with different address widths.
For Hint messages, the Completion (0b0) and DVMType (0b110) fields are at ACADDR[15] and
ACADDR[14:12] respectively, other mappings are IMPLEMENTATION DEFINED.
The mappings for TLB Invalidate messages are shown in Table A15.20.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
251


Chapter A15. Distributed Virtual Memory messages
A15.4. Transporting DVM messages
Table A15.20: Field mappings for TLB Invalidate messages
Signal
TLBI 1-part
TLBI 1st of
2-part
TLBI 2nd
part by VA
or IPA
TLBI 2nd
part by range
GPT TLBI
1st part
GPT TLBI
2nd part
ACADDR[51]
0b0
0b0
0b0
0b0
0b0
PA[51]
ACADDR[50]
0b0
0b0
0b0
0b0
0b0
PA[50]
ACADDR[49]
0b0
0b0
0b0
0b0
0b0
PA[49]
ACADDR[48]
0b0
0b0
0b0
0b0
0b0
PA[48]
ACADDR[47]
0b0
VA[56]
VA[52]
VA[52]
0b0
PA[47]
ACADDR[46]
0b0
VA[55]
VA[51]
VA[51]
0b0
PA[46]
ACADDR[45]
0b0
VA[54]
VA[50]
VA[50]
0b0
PA[45]
ACADDR[44]
0b0
VA[53]
VA[49]
VA[49]
0b0
PA[44]
ACADDR[43]
VMID[15]
VA[48]
VA[44]
VA[44]
0b0
PA[43]
ACADDR[42]
VMID[14]
VA[47]
VA[43]
VA[43]
0b0
PA[42]
ACADDR[41]
VMID[13]
VA[46]
VA[42]
VA[42]
0b0
PA[41]
ACADDR[40]
VMID[12]
VA[45]
VA[41]
VA[41]
0b0
PA[40]
ACADDR[39]
ASID[15]
ASID[15]
VA[39]
VA[39]
0b0
PA[39]
ACADDR[38]
ASID[14]
ASID[14]
VA[38]
VA[38]
0b0
PA[38]
ACADDR[37]
ASID[13]
ASID[13]
VA[37]
VA[37]
0b0
PA[37]
ACADDR[36]
ASID[12]
ASID[12]
VA[36]
VA[36]
0b0
PA[36]
ACADDR[35]
ASID[11]
ASID[11]
VA[35]
VA[35]
0b0
PA[35]
ACADDR[34]
ASID[10]
ASID[10]
VA[34]
VA[34]
0b0
PA[34]
ACADDR[33]
ASID[9]
ASID[9]
VA[33]
VA[33]
0b0
PA[33]
ACADDR[32]
ASID[8]
ASID[8]
VA[32]
VA[32]
0b0
PA[32]
ACADDR[31]
VMID[7]
VMID[7]
VA[31]
VA[31]
0b0
PA[31]
ACADDR[30]
VMID[6]
VMID[6]
VA[30]
VA[30]
0b0
PA[30]
ACADDR[29]
VMID[5]
VMID[5]
VA[29]
VA[29]
0b0
PA[29]
ACADDR[28]
VMID[4]
VMID[4]
VA[28]
VA[28]
0b0
PA[28]
ACADDR[27]
VMID[3]
VMID[3]
VA[27]
VA[27]
0b0
PA[27]
ACADDR[26]
VMID[2]
VMID[2]
VA[26]
VA[26]
0b0
PA[26]
ACADDR[25]
VMID[1]
VMID[1]
VA[25]
VA[25]
0b0
PA[25]
ACADDR[24]
VMID[0]
VMID[0]
VA[24]
VA[24]
0b0
PA[24]
ACADDR[23]
ASID[7]
ASID[7]
VA[23]
VA[23]
0b0
PA[23]
ACADDR[22]
ASID[6]
ASID[6]
VA[22]
VA[22]
0b0
PA[22]
ACADDR[21]
ASID[5]
ASID[5]
VA[21]
VA[21]
0b0
PA[21]
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
252


Chapter A15. Distributed Virtual Memory messages
A15.4. Transporting DVM messages
Table A15.20 – Continued from previous page
Signal
TLBI 1-part
TLBI 1st of
2-part
TLBI 2nd
part by VA
or IPA
TLBI 2nd
part by range
GPT TLBI
1st part
GPT TLBI
2nd part
ACADDR[20]
ASID[4]
ASID[4]
VA[20]
VA[20]
0b0
PA[20]
ACADDR[19]
ASID[3]
ASID[3]
VA[19]
VA[19]
0b0
PA[19]
ACADDR[18]
ASID[2]
ASID[2]
VA[18]
VA[18]
0b0
PA[18]
ACADDR[17]
ASID[1]
ASID[1]
VA[17]
VA[17]
0b0
PA[17]
ACADDR[16]
ASID[0]
ASID[0]
VA[16]
VA[16]
0b0
PA[16]
ACADDR[15]
0b0
(Completion)
0b0
(Completion)
VA[15]
VA[15]
0b0
(Completion)
PA[15]
ACADDR[14]
0b0
(DVMType[2])
0b0
(DVMType[2])
VA[14]
VA[14]
0b0
(DVMType[2])
PA[14]
ACADDR[13]
0b0
(DVMType[1])
0b0
(DVMType[1])
VA[13]
VA[13]
0b0
(DVMType[1])
PA[13]
ACADDR[12]
0b0
(DVMType[0])
0b0
(DVMType[0])
VA[12]
VA[12]
0b0
(DVMType[0])
PA[12]
ACADDR[11]
Exception[1]
Exception[1]
TG[1]
TG[1]
Exception[1]
IS[3]
ACADDR[10]
Exception[0]
Exception[0]
TG[0]
TG[0]
Exception[0]
IS[2]
ACADDR[9]
Security[1]
Security[1]
TTL[1]
TTL[1]
Security[1]
IS[1]
ACADDR[8]
Security[0]
Security[0]
TTL[0]
TTL[0]
Security[0]
IS[0]
ACADDR[7]
0b0 (Range)
Range
0b0
Scale[1]
Range
0b0
ACADDR[6]
VMIDV
VMIDV
0b0
Scale[0]
0b0
(VMIDV)
0b0
ACADDR[5]
ASIDV
ASIDV
0b0
Num[4]
0b0 (ASIDV)
0b0
ACADDR[4]
0b0
Leaf
0b0
Num[3]
Leaf
0b0
ACADDR[3]
Stage[1]
Stage[1]
VA[40]
VA[40]
Stage[1]
0b0
ACADDR[2]
Stage[0]
Stage[0]
0b0
Num[2]
Stage[0]
0b0
ACADDR[1]
0b0
0b0
0b0
Num[1]
0b0
0b0
ACADDR[0]
0b0 (Addr)
0b1 (Addr)
0b0
Num[0]
Addr
0b0
ACVMIDEXT[3]
VMID[11]
VMID[11]
VMID[15]
VMID[15]
0b0
0b0
ACVMIDEXT[2]
VMID[10]
VMID[10]
VMID[14]
VMID[14]
0b0
0b0
ACVMIDEXT[1]
VMID[9]
VMID[9]
VMID[13]
VMID[13]
0b0
0b0
ACVMIDEXT[0]
VMID[8]
VMID[8]
VMID[12]
VMID[12]
0b0
0b0
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
253


Chapter A15. Distributed Virtual Memory messages
A15.4. Transporting DVM messages
The mappings for Branch Predictor Invalidate and Sync messages are shown in Table A15.21.
Table A15.21: Field mappings for BPI and Sync messages
Signal
BPI all or Sync
BPI by VA 1st part
BPI by VA 2nd part
ACADDR[51]
0b0
0b0
0b0
ACADDR[50]
0b0
0b0
0b0
ACADDR[49]
0b0
0b0
0b0
ACADDR[48]
0b0
0b0
0b0
ACADDR[47]
0b0
VA[56]
VA[52]
ACADDR[46]
0b0
VA[55]
VA[51]
ACADDR[45]
0b0
VA[54]
VA[50]
ACADDR[44]
0b0
VA[53]
VA[49]
ACADDR[43]
0b0
VA[48]
VA[44]
ACADDR[42]
0b0
VA[47]
VA[43]
ACADDR[41]
0b0
VA[46]
VA[42]
ACADDR[40]
0b0
VA[45]
VA[41]
ACADDR[39]
0b0
0b0
VA[39]
ACADDR[38]
0b0
0b0
VA[38]
ACADDR[37]
0b0
0b0
VA[37]
ACADDR[36]
0b0
0b0
VA[36]
ACADDR[35]
0b0
0b0
VA[35]
ACADDR[34]
0b0
0b0
VA[34]
ACADDR[33]
0b0
0b0
VA[33]
ACADDR[32]
0b0
0b0
VA[32]
ACADDR[31]
0b0
0b0
VA[31]
ACADDR[30]
0b0
0b0
VA[30]
ACADDR[29]
0b0
0b0
VA[29]
ACADDR[28]
0b0
0b0
VA[28]
ACADDR[27]
0b0
0b0
VA[27]
ACADDR[26]
0b0
0b0
VA[26]
ACADDR[25]
0b0
0b0
VA[25]
ACADDR[24]
0b0
0b0
VA[24]
ACADDR[23]
0b0
0b0
VA[23]
ACADDR[22]
0b0
0b0
VA[22]
ACADDR[21]
0b0
0b0
VA[21]
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
254


Chapter A15. Distributed Virtual Memory messages
A15.4. Transporting DVM messages
Table A15.21 – Continued from previous page
Signal
BPI all or Sync
BPI by VA 1st part
BPI by VA 2nd part
ACADDR[20]
0b0
0b0
VA[20]
ACADDR[19]
0b0
0b0
VA[19]
ACADDR[18]
0b0
0b0
VA[18]
ACADDR[17]
0b0
0b0
VA[17]
ACADDR[16]
0b0
0b0
VA[16]
ACADDR[15]
Completion
0b0 (Completion)
VA[15]
ACADDR[14]
DVMType[2]
0b0 (DVMType[2])
VA[14]
ACADDR[13]
DVMType[1]
0b0 (DVMType[1])
VA[13]
ACADDR[12]
DVMType[0]
0b1 (DVMType[0])
VA[12]
ACADDR[11]
0b0 (Exception[1])
0b0 (Exception[1])
VA[11]
ACADDR[10]
0b0 (Exception[0])
0b0 (Exception[0])
VA[10]
ACADDR[9]
0b0 (Security[1])
0b0 (Security[1])
VA[9]
ACADDR[8]
0b0 (Security[0])
0b0 (Security[0])
VA[8]
ACADDR[7]
0b0 (Range)
0b0 (Range)
VA[7]
ACADDR[6]
0b0 (VMIDV)
0b0 (VMIDV)
VA[6]
ACADDR[5]
0b0 (ASIDV)
0b0 (ASIDV)
VA[5]
ACADDR[4]
0b0 (Leaf)
0b0 (Leaf)
VA[4]
ACADDR[3]
0b0 (Stage[1])
0b0 (Stage[1])
VA[40]
ACADDR[2]
0b0 (Stage[0])
0b0 (Stage[0])
0b0
ACADDR[1]
0b0
0b0
0b0
ACADDR[0]
0b0 (Addr)
0b1 (Addr)
0b0
ACVMIDEXT[3]
0b0
0b0
0b0
ACVMIDEXT[2]
0b0
0b0
0b0
ACVMIDEXT[1]
0b0
0b0
0b0
ACVMIDEXT[0]
0b0
0b0
0b0
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
255


Chapter A15. Distributed Virtual Memory messages
A15.4. Transporting DVM messages
The mappings for Instruction Cache Invalidation messages are shown in Table A15.22.
Table A15.22: Field mappings for VICI and PICI messages
Signal
VICI all
VICI by VA 1st
part
VICI by VA 2nd
part
PICI 1st part
PICI 2nd part
ACADDR[51]
0b0
0b0
0b0
0b0
PA[51]
ACADDR[50]
0b0
0b0
0b0
0b0
PA[50]
ACADDR[49]
0b0
0b0
0b0
0b0
PA[49]
ACADDR[48]
0b0
0b0
0b0
0b0
PA[48]
ACADDR[47]
0b0
VA[56]
VA[52]
0b0
PA[47]
ACADDR[46]
0b0
VA[55]
VA[51]
0b0
PA[46]
ACADDR[45]
0b0
VA[54]
VA[50]
0b0
PA[45]
ACADDR[44]
0b0
VA[53]
VA[49]
0b0
PA[44]
ACADDR[43]
VMID[15]
VA[48]
VA[44]
0b0
PA[43]
ACADDR[42]
VMID[14]
VA[47]
VA[43]
0b0
PA[42]
ACADDR[41]
VMID[13]
VA[46]
VA[42]
0b0
PA[41]
ACADDR[40]
VMID[12]
VA[45]
VA[41]
0b0
PA[40]
ACADDR[39]
ASID[15]
ASID[15]
VA[39]
0b0
PA[39]
ACADDR[38]
ASID[14]
ASID[14]
VA[38]
0b0
PA[38]
ACADDR[37]
ASID[13]
ASID[13]
VA[37]
0b0
PA[37]
ACADDR[36]
ASID[12]
ASID[12]
VA[36]
0b0
PA[36]
ACADDR[35]
ASID[11]
ASID[11]
VA[35]
0b0
PA[35]
ACADDR[34]
ASID[10]
ASID[10]
VA[34]
0b0
PA[34]
ACADDR[33]
ASID[9]
ASID[9]
VA[33]
0b0
PA[33]
ACADDR[32]
ASID[8]
ASID[8]
VA[32]
0b0
PA[32]
ACADDR[31]
VMID[7]
VMID[7]
VA[31]
VI[27]
PA[31]
ACADDR[30]
VMID[6]
VMID[6]
VA[30]
VI[26]
PA[30]
ACADDR[29]
VMID[5]
VMID[5]
VA[29]
VI[25]
PA[29]
ACADDR[28]
VMID[4]
VMID[4]
VA[28]
VI[24]
PA[28]
ACADDR[27]
VMID[3]
VMID[3]
VA[27]
VI[23]
PA[27]
ACADDR[26]
VMID[2]
VMID[2]
VA[26]
VI[22]
PA[26]
ACADDR[25]
VMID[1]
VMID[1]
VA[25]
VI[21]
PA[25]
ACADDR[24]
VMID[0]
VMID[0]
VA[24]
VI[20]
PA[24]
ACADDR[23]
ASID[7]
ASID[7]
VA[23]
VI[19]
PA[23]
ACADDR[22]
ASID[6]
ASID[6]
VA[22]
VI[18]
PA[22]
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
256


Chapter A15. Distributed Virtual Memory messages
A15.4. Transporting DVM messages
Table A15.22 – Continued from previous page
Signal
VICI all
VICI by VA 1st
part
VICI by VA 2nd
part
PICI 1st part
PICI 2nd part
ACADDR[21]
ASID[5]
ASID[5]
VA[21]
VI[17]
PA[21]
ACADDR[20]
ASID[4]
ASID[4]
VA[20]
VI[16]
PA[20]
ACADDR[19]
ASID[3]
ASID[3]
VA[19]
VI[15]
PA[19]
ACADDR[18]
ASID[2]
ASID[2]
VA[18]
VI[14]
PA[18]
ACADDR[17]
ASID[1]
ASID[1]
VA[17]
VI[13]
PA[17]
ACADDR[16]
ASID[0]
ASID[0]
VA[16]
VI[12]
PA[16]
ACADDR[15]
0b0
(Completion)
0b0
(Completion)
VA[15]
0b0
(Completion)
PA[15]
ACADDR[14]
0b0
(DVMType[2])
0b0
(DVMType[2])
VA[14]
0b0
(DVMType[2])
PA[14]
ACADDR[13]
0b1
(DVMType[1])
0b1
(DVMType[1])
VA[13]
0b1
(DVMType[1])
PA[13]
ACADDR[12]
0b1
(DVMType[0])
0b1
(DVMType[0])
VA[12]
0b0
(DVMType[0])
PA[12]
ACADDR[11]
Exception[1]
Exception[1]
VA[11]
0b0
(Exception[1])
PA[11]
ACADDR[10]
Exception[0]
Exception[0]
VA[10]
0b0
(Exception[0])
PA[10]
ACADDR[9]
Security[1]
Security[1]
VA[9]
Security[1]
PA[9]
ACADDR[8]
Security[0]
Security[0]
VA[8]
Security[0]
PA[8]
ACADDR[7]
0b0 (Range)
0b0 (Range)
VA[7]
0b0 (Range)
PA[7]
ACADDR[6]
VMIDV
VMIDV
VA[6]
VIV[1]
PA[6]
ACADDR[5]
ASIDV
ASIDV
VA[5]
VIV[0]
PA[5]
ACADDR[4]
0b0 (Leaf)
0b0 (Leaf)
VA[4]
0b0
PA[4]
ACADDR[3]
0b0 (Stage[1])
0b0 (Stage[1])
VA[40]
0b0
0b0
ACADDR[2]
0b0 (Stage[0])
0b0 (Stage[0])
0b0
0b0
0b0
ACADDR[1]
0b0
0b0
0b0
0b0
0b0
ACADDR[0]
0b0 (Addr)
0b1 (Addr)
0b0
Addr
0b0
ACVMIDEXT[3]
VMID[11]
VMID[11]
VMID[15]
0b0
0b0
ACVMIDEXT[2]
VMID[10]
VMID[10]
VMID[14]
0b0
0b0
ACVMIDEXT[1]
VMID[9]
VMID[9]
VMID[13]
0b0
0b0
ACVMIDEXT[0]
VMID[8]
VMID[8]
VMID[12]
0b0
0b0
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
257


Chapter A15. Distributed Virtual Memory messages
A15.5. DVM Sync and Complete
A15.5 DVM Sync and Complete
A DVM Sync message is used when the requester needs to know when all previous invalidations are complete.
A DVM Complete request is sent when a component has received a DVM Sync message and all preceding
invalidation operations are complete. The following rules apply in determining when an operation is complete:
TLB Invalidate
Complete when a Manager can no longer use an invalidated translation and all previous transactions
that could have used an invalidated translation are complete.
Branch Predictor Invalidate
Complete when cached copies of predicted instruction fetches have been invalidated and can no longer
be accessed by the associated Manager. The invalidated cached copies might be from any virtual
address or from a specified virtual address.
Instruction Cache Invalidate
Complete when cached instructions have been invalidated and can no longer be accessed by the
associated Manager.
The synchronization flow between an interconnect and one receiving Manager is shown in Figure A15.3.
The process is:
1. The Manager acknowledges receipt of the DVM Sync message using the snoop response (CR) channel. This
response must not be dependent on the forward progress of any transactions on the AR or AW channels.
2. The Manager must issue a DVM Complete request on the AR channel when it has completed all the
necessary actions. This must be after the handshake of the associated DVM Sync on the snoop request
channel of the same Manager. The Manager must send a DVM Complete in a timely manner, even if it
continues to receive more DVM invalidation operations and more DVM Sync messages.
3. The interconnect component responds to the DVM Complete request using the read data (R) channel of the
component that issued the DVM Complete. Read data is not valid in this response.
Interconnect
(Subordinate Interface)
Receiving 
Manager
DVM Sync request
response
DVM Complete request
response
AC
CR
AR
R
Figure A15.3: DVM Synchronization flow
Every DVM Sync message must have one corresponding DVM Complete request.
A DVM Complete request can only be sent if there is a corresponding DVM Sync message.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
258


Chapter A15. Distributed Virtual Memory messages
A15.5. DVM Sync and Complete
A DVM Complete request is signaled on the AR channel, Table A15.23 shows the constraints on other AR channel
signals if they are present.
Table A15.23: DVM Complete request constraints
Signal
Constraint
ARSNOOP
Must be 0b1110.
ARADDR
Must be zero.
ARID
Must be different from that of any outstanding, non-DVM
Complete transaction on the read channels.
ARBURST
Must be INCR (0b01).
ARLEN
Must be 1 transfer (0x00).
ARSIZE
Must be equal to the data channel width or
Max_Transaction_Bytes if that is smaller than the data width.
ARDOMAIN
Must be Shareable (0b01 or 0b10).
ARCACHE
Must be Modifiable, Non-cacheable (0b0010).
ARCHUNKEN
Must be 0b0.
ARMMUVALID
Must be 0b0. If not present, ARMMUVALID is assumed to be
0b0 for a DVM Complete request.
ARMMUATST
Must be 0b0.
ARMMUFLOW
Must be 0b00.
ARTAGOP
Must be 0b00.
ARLOCK
Must be 0b0.
When using credited transport, a DVM Complete message can use any value for ARRP, but all DVM Complete
messages on an interface must use the same RP.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
259


Chapter A15. Distributed Virtual Memory messages
A15.6. Coherency Connection signaling
A15.6 Coherency Connection signaling
DVM message requests are transferred from a Subordinate to a Manager interface, which is the opposite direction
to other requests. A Manager which is idle might be powered down and unable to accept any DVM requests.
Coherency Connection signaling can be used to enable a Manager to control whether it receives DVM message
requests.
The Coherency_Connection_Signals property is used to indicate whether a component supports the Coherency
Connection signals.
Table A15.24: Coherency_Connection_Signals property
Coherency_Connection_Signals
Default
Description
True
Coherency Connection signaling is supported.
False
Y
Coherency Connection signaling is not supported.
When Coherency_Connection_Signals is True, the following signals are included on an interface.
Table A15.25: Coherency Connection signals
Name
Width
Default
Description
SYSCOREQ
1
-
Output from a Manager, asserted HIGH to request
that it receives DVM messages on the AC channel.
SYSCOACK
1
-
Output from a Subordinate, asserted HIGH to
acknowledge that the attached Manager might
receive DVM messages on the AC channel.
Coherency Connection signals do not have default values, so connected interfaces must both support or not
support Coherency Connection signaling.
The Coherency Connection signals use a four-phase scheme which can safely cross clock domains.
Disconnecting from DVM messages is typically used before entering a low-power state in which DVM requests
cannot be processed.
A15.6.1
Coherency Connection Handshake
SYSCOREQ and SYSCOACK must be deasserted when ARESETn is asserted. When not in reset, the following
requests are permitted:
• A Manager requests to receive DVM messages by asserting SYSCOREQ HIGH. The interconnect indicates
that DVM messages are enabled by asserting SYSCOACK HIGH.
• The Manager requests to stop receiving DVM messages by deasserting SYSCOREQ LOW. The interconnect
indicates that DVM messages is disabled by deasserting SYSCOACK LOW.
The handshake timing is shown in Figure A15.4.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
260


Chapter A15. Distributed Virtual Memory messages
A15.6. Coherency Connection signaling
ACLK
ARESETn
SYSCOREQ
SYSCOACK
Disabled
Connect
Enabled
Disconnect
Disabled
a
c
b
d
Figure A15.4: Coherency Connection handshake timing
The connection signaling obeys the four-phase handshake rules:
• A Manager can only change SYSCOREQ when SYSCOACK is at the same level.
• A Subordinate can only change SYSCOACK when SYSCOREQ is at the opposite level.
The rules for Managers and Subordinate components in each state are shown in Table A15.26.
Table A15.26: Coherency Connection signaling states
State
SYSCOREQ
SYSCOACK
Rules
Disabled
0
0
Manager:
• Must not fetch and use DVM-managed translation table
data to perform translations.
• Asserts SYSCOREQ if it needs to perform DVM-managed
translations.
Subordinate:
• Must not issue any DVM message requests.
• Must not issue any DVM Sync requests, these are assumed
to complete immediately.
Connect
1
0
Manager:
• Must not fetch and use DVM-managed translation table
data to perform translations.
• Must be able to receive and respond to DVM message
requests.
• Waiting for SYSCOACK to be asserted before using
DVM-managed translations.
Subordinate:
• Asserts SYSCOACK when it has enabled DVM messages
to the attached Manager.
Enabled
1
1
Manager:
• Can fetch and use DVM-managed translation table data.
• Must be able to receive and respond to DVM message
requests.
• Deasserts SYSCOREQ if it has finished using
DVM-managed translation table data and wants to enter a
low power state. Any transaction using previously fetched
data must have been completed.
Subordinate:
• Can send DVM messages to the attached Manager.
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
261


Chapter A15. Distributed Virtual Memory messages
A15.6. Coherency Connection signaling
Table A15.26 – Continued from previous page
State
SYSCOREQ
SYSCOACK
Rules
Disconnect
0
1
Manager:
• Must not fetch or use any DVM-managed translation table
data.
• Must be able to receive and respond to DVM message
requests.
• Waiting for SYSCOACK to be deasserted before disabling
DVM-managed logic.
Subordinate:
• Must wait for all outstanding DVM messages to receive a
response before deasserting SYSCOACK.
• Must stop issuing DVM messages in a timely manner.
• Must issue the second part of a 2-part DVM message if the
first part has already been issued.
Note that a Subordinate is not permitted to send DVM messages in the Connect state, but a Manager must be able
to receive DVM messages in the Connect state. This is because there might be a race between the assertion of
SYSCOACK and ACVALID.
If an interconnect has sent a DVM Sync message that requires a DVM Complete message on the AR channel, then
the interconnect is permitted to deassert SYSCOACK before the DVM Complete request is received. The Manager
is required to send the DVM Complete request on the AR channel, even when DVM messages are disabled.
Transitions on the Coherency Connection signals might rely on AWAKEUP being asserted, see A14.1.2
AWAKEUP and Coherency Connection signaling for details.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
262


Chapter A15. Distributed Virtual Memory messages
A15.7. Snoop channels credit control
A15.7 Snoop channels credit control
When using credited transport, the snoop channels can include control signals to determine when channel receivers
can give credits. This can be used to clock or power gate snoop channels when they are idle.
The following rules apply:
• Credit control is independent of the other channels on the interface. For example, the DVM channels can be
in RUN when other channels are in STOP.
• All of the rules in A14.2 Interface gating with credited transport apply to the DVM credit control signals, but
the Manager and Subordinate terms are swapped.
• A DVM transaction is considered to be complete when the response is received on CR. For a DVM Sync, the
DVM channels can be stopped once the CR response is received. The Manager must start the main channels
to send a DVM Complete request on the AR channel.
• Credit control is independent of the coherency connection state. For example, DVM messages might be
enabled by setting SYSCOREQ and SYSCOACK HIGH, but the AC and CR channels remain in STOP
until a DVM message needs to be sent.
Table A15.27 shows the signals that are included when DVM_Message_Support is Receiver and Credit_Control is
Implicit_Return_Uni.
Table A15.27: Credit control signals
Name
Width
Default
Description
ACTIVATEREQD
1
0b1
Activation / deactivation request from a Subordinate for the
snoop channels.
ACTIVATEACKD
1
0b1
Activation / deactivation acknowledge from a Manager for the
snoop channels.
ASKSTOPD
1
0b0
Asserted HIGH to indicate that the Manager wants the
Subordinate to stop the snoop channels.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
263
