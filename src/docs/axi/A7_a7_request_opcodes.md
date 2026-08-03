# A7 Request Opcodes

Chapter A7
Request Opcodes
The request Opcode indicates the function of a request and how it must be processed by a Subordinate.
This chapter summarizes all Opcodes that are available with links in the tables to detailed descriptions of how they
work.
It contains the following sections:
• A7.1 Opcode signaling
• A7.2 AWSNOOP encodings
• A7.3 ARSNOOP encodings
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
123


Chapter A7. Request Opcodes
A7.1. Opcode signaling
A7.1 Opcode signaling
The request Opcode is communicated using the AWSNOOP and ARSNOOP signals.
Table A7.1: AxSNOOP signals
Name
Width
Default
Description
AWSNOOP
AWSNOOP_WIDTH
0x00
(WriteNoSnoop /
WriteUniquePtl /
Atomic /
WriteExclusive /
WriteACT)
Opcode for requests using the write channels.
ARSNOOP
ARSNOOP_WIDTH
0x0 (ReadNoSnoop
/ ReadOnce /
ReadExclusive /
ReadACT)
Opcode for requests using the read channels.
WriteNoSnoop, WriteUniquePtl, ReadNoSnoop and ReadOnce are default Opcodes and are used for generic
requests.
The AxSNOOP width properties are defined in Table A7.2.
Table A7.2: AxSNOOP width properties
Name
Values
Default
Description
AWSNOOP_WIDTH
0, 4, 5
4
Width of AWSNOOP in bits.
ARSNOOP_WIDTH
0, 4
4
Width of ARSNOOP in bits.
If any of the following properties are not False, AWSNOOP_WIDTH must be 5:
• WriteDeferrable_Transaction
• UnstashTranslation_Transaction
• InvalidateHint_Transaction
If any of the following properties are not False, AWSNOOP_WIDTH must be 4 or 5:
• Shareable_Cache_Support
• WriteNoSnoopFull_Transaction
• CMO_On_Write
• WriteZero_Transaction
• Cache_Stash_Transactions
• Untranslated_Transactions
• Prefetch_Transaction
If any of the following properties are not False, ARSNOOP_WIDTH must be 4:
• Shareable_Cache_Support
• DeAllocation_Transactions
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
124


Chapter A7. Request Opcodes
A7.1. Opcode signaling
• CMO_On_Read
• DVM_Message_Support
Any AxSNOOP bits not driven by an interface are assumed to be LOW.
A Manager that only uses Opcodes where AWSNOOP is LOW can set AWSNOOP_WIDTH to 0 which omits the
AWSNOOP output from its interface. An attached Subordinate must have its AWSNOOP input tied LOW.
A Manager that only uses Opcodes where ARSNOOP is LOW can set ARSNOOP_WIDTH to 0 which omits the
ARSNOOP output from its interface. An attached Subordinate must have its ARSNOOP input tied LOW.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
125


Chapter A7. Request Opcodes
A7.2. AWSNOOP encodings
A7.2 AWSNOOP encodings
The encodings for AWSNOOP are shown in Table A7.3. Some Opcodes depend on the Domain of the request.
The Enable column lists the property expression that determines whether a Manager interface is permitted to use
the Opcode and a Subordinate interface supports it.
Unlisted combinations of AWSNOOP and AWDOMAIN are illegal.
Table A7.3: AWSNOOP encodings
AWSNOOP
AWDOMAIN1
Opcode
Enable
Description
0b00000
NSH, SYS
WriteNoSnoop
-
Write to a Non-shareable or
System location.
SH
WriteUniquePtl
Shareable_Transactions
Write to a Shareable location.
NSH, SH, SYS
Atomic
Atomic_Transactions
Atomic transaction, indicated by
nonzero AWATOP signal.
NSH, SYS
WriteExclusive
Exclusive_Accesses
Exclusive write access, indicated
by AWLOCK asserted.
SYS
WriteACT
ACT_Support
ACT write access, indicated by
AWACTV asserted.
0b00001
NSH, SYS
WriteNoSnoopFull
WriteNoSnoopFull_Transaction
or Shareable_Cache_Support
Cache line sized and Regular write
to a Non-shareable location.
SH
WriteUniqueFull
Shareable_Transactions
Cache line sized and Regular write
to a Shareable location.
0b00010
-
RESERVED
-
0b00011
SH
WriteBackFull
Shareable_Transactions and
Shareable_Cache_Support
Cache line sized and Regular write
to a Shareable location. The line
was held in a coherent cache and
is Dirty.
0b00100
-
RESERVED
-
0b00101
SH
WriteEvictFull
Shareable_Transactions and
Shareable_Cache_Support
Cache line sized and Regular write
to a Shareable location. The line
was held in a coherent cache and
is Clean.
0b00110
NSH, SH
CMO
CMO_On_Write
A data-less request which
indicates that a cache maintenance
operation must be performed. The
specific operation is encoded on
the AWCMO signal. Cache line
sized and Regular.
0b00111
NSH, SH, SYS
WriteZero
WriteZero_Transaction
Cache line sized and Regular
write, where the value of every
byte is zero.
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
126


Chapter A7. Request Opcodes
A7.2. AWSNOOP encodings
Table A7.3 – Continued from previous page
AWSNOOP
AWDOMAIN1
Opcode
Enable
Description
0b01000
SH
WriteUniquePtlStash
Shareable_Transactions and
Cache_Stash_Transactions
Write to a Shareable location with
an indication that the data should
be allocated into a cache. Cache
line sized or smaller.
0b01001
SH
WriteUniqueFullStash
Shareable_Transactions and
Cache_Stash_Transactions
Cache line sized and Regular write
to a Shareable location with an
indication that the data should be
allocated into a cache.
0b01010
NSH, SH
WritePtlCMO
Write_Plus_CMO
Write where any cached copies of
the line must be cleaned and/or
invalidated according to the
AWCMO signal. Cache line sized
or smaller.
0b01011
NSH, SH
WriteFullCMO
Write_Plus_CMO
Cache line sized and Regular write
where any cached copies of the
line must be cleaned and/or
invalidated according to the
AWCMO signal.
0b01100
NSH, SH
StashOnceShared
Cache_Stash_Transactions
A data-less request which
indicates that a cache line should
be fetched into a cache. Other
copies of the line are not required
to be invalidated. Cache line sized
and Regular.
0b01101
NSH, SH
StashOnceUnique
Cache_Stash_Transactions
A data-less request which
indicates that a cache line should
be fetched into a cache. It is
recommended that all other copies
are invalidated. Cache line sized
and Regular.
0b01110
NSH, SH, SYS
StashTranslation
Untranslated_Transactions and
Cache_Stash_Transactions
A data-less request which
indicates that a translation should
be cached in an MMU.
0b01111
NSH, SH
Prefetch
Prefetch_Transaction
A data-less request which
indicates that a Manager might
read the addressed cache line at a
later time. Cache line sized and
Regular.
0b10000
SYS
WriteDeferrable
WriteDeferrable_Transaction
A 64-byte atomic write where the
Subordinate can give a DEFER or
UNSUPPORTED response.
0b10001
NSH, SH, SYS
UnstashTranslation
UnstashTranslation_Transaction
A data-less request which is a hint
that a translation is not likely to be
used again.
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
127


Chapter A7. Request Opcodes
A7.2. AWSNOOP encodings
Table A7.3 – Continued from previous page
AWSNOOP
AWDOMAIN1
Opcode
Enable
Description
0b10010
NSH, SH
InvalidateHint
InvalidateHint_Transaction
A data-less request which
indicates that a cache line is no
longer required and can be
invalidated. A write-back is
permitted but not required. Cache
line sized and Regular.
0b10011 to
0b11111
-
RESERVED
-
-
1 NSH is Non-shareable (0b00), SH is Shareable (0b01 or 0b10), SYS is System (0b11).
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
128


Chapter A7. Request Opcodes
A7.3. ARSNOOP encodings
A7.3 ARSNOOP encodings
The encodings for ARSNOOP are shown in Table A7.4. Some Opcodes depend on the Domain of the request.
The Enable column lists the property expression that determines whether a Manager interface is permitted to use
the Opcode and a Subordinate interface supports it.
Unlisted combinations of ARSNOOP and ARDOMAIN are illegal.
Table A7.4: ARSNOOP encodings
ARSNOOP
ARDOMAIN1
Opcode
Enable
Description
0b0000
NSH, SYS
ReadNoSnoop
-
Read from a Non-shareable or
System location.
SH
ReadOnce
Shareable_Transactions
Read from a Shareable location
which the Manager will not
cache.
NSH, SYS
ReadExclusive
Exclusive_Accesses
Exclusive read access, indicated
by ARLOCK asserted.
SYS
ReadACT
ACT_Support
ACT read access, indicated by
ARACTV asserted.
0b0001
SH
ReadShared
Shareable_Transactions and
Shareable_Cache_Support
Cache line sized and Regular
read from a Shareable location
which the Manager might cache.
Data can be Dirty.
0b0010
SH
ReadClean
Shareable_Transactions and
Shareable_Cache_Support
Cache line sized and Regular
read from Shareable location
which the Manager might cache.
Data must not be Dirty.
0b0011
-
RESERVED
-
-
0b0100
SH
ReadOnceCleanInvalid
Shareable_Transactions and
DeAllocation_Transactions
Read from a Shareable location
which the Manager will not
cache. Cached copies are
recommended to be cleaned and
invalidated. Cache line sized or
smaller.
0b0101
SH
ReadOnceMakeInvalid
Shareable_Transactions and
DeAllocation_Transactions
Read from a Shareable location
which the Manager will not
cache. Cached copies are
recommended to be invalidated
without a write-back. Cache line
sized or smaller.
0b0110
-
RESERVED
-
-
0b0111
-
RESERVED
-
-
0b1000
NSH, SH
CleanShared
CMO_On_Read
A request to clean all copies of a
cache line. Cache line sized and
Regular.
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
129


Chapter A7. Request Opcodes
A7.3. ARSNOOP encodings
Table A7.4 – Continued from previous page
ARSNOOP
ARDOMAIN1
Opcode
Enable
Description
0b1001
NSH, SH
CleanInvalid
CMO_On_Read
A request to clean and invalidate
all copies of a cache line. Cache
line sized and Regular.
0b1010
NSH, SH
CleanSharedPersist
CMO_On_Read and
Persist_CMO
A request to clean all copies of a
cache line. Cleaned data must
pass the Point of Persistence or
Point of Deep Persistence.
Cache line sized and Regular.
0b1011
-
RESERVED
-
-
0b1100
-
RESERVED
-
-
0b1101
NSH, SH
MakeInvalid
CMO_On_Read
A request to clean and invalidate
all copies of a cache line. Dirty
data is not required to be written
to memory. Cache line sized
and Regular.
0b1110
SH
DVM Complete
DVM_Message_Support
Indicates completion of a DVM
synchronization message.
0b1111
-
RESERVED
-
-
1 NSH is Non-shareable (0b00), SH is Shareable (0b01 or 0b10), SYS is System (0b11).
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
130
