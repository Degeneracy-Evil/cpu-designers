# B4 Revisions

Chapter B4
Revisions
This appendix describes the technical changes between released issues of this specification.
It contains the following sections:
• B4.1 Differences between Issue H.c and Issue J
• B4.2 Differences between Issue J and Issue K
• B4.3 Differences between Issue K and Issue L
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
306


Chapter B4. Revisions
B4.1. Differences between Issue H.c and Issue J
B4.1 Differences between Issue H.c and Issue J
Feature
Change
Detail
AXI3, AXI4, AXI4-Lite
interfaces
Removal
AXI3, AXI4, and AXI4-Lite content is removed from the specification.
These interface types are not recommended for new designs and have
been superseded by the AXI5 interface. Removed content can be
accessed by downloading earlier versions of this specification.
ACE and ACE5
interfaces
Removal
ACE and ACE5 content is removed from the specification. AMBA CHI
is recommended for fully coherent agents and is actively supported.
ACE5-Lite,
ACE5-LiteDVM,
ACE5-LiteACP, and
AXI5-Lite interfaces
Update
ACE5-Lite, ACE5-LiteDVM, ACE5-LiteACP, and AXI5-Lite interfaces
are described through constraints on property values and signal
presence.
AXI5 interface
New feature
All optional features in this specification are now applicable to AXI5
class interfaces. AXI5 is expected to be used for general-purpose
interfaces.
Caching shareable lines
New feature
Support for storing shareable lines in a system cache.
Cache stashing
New feature
There is an additional Basic option for cache stashing to support
interfaces which use only a sub-set of the cache stashing protocol.
Invalidate hint
New feature
InvalidateHint transaction, which can be used by an agent when it is
finished working with a data set and that data might be allocated in a
downstream cache.
WriteDeferrable
transaction
New feature
A 64-byte atomic store operation that might not be accepted by the
Subordinate.
Realm Management
Extension (RME)
New feature
Enhanced memory protection.
DVM v9.2
New feature
New messages to support the Armv9.2 architecture.
Untranslated transactions
New feature
Version 3 adds support for mixing translated and untranslated
transactions.
New feature
UnstashTranslation transaction, used as a deallocation hint for an
address translation cache.
Page-based Hardware
Attributes (PBHA)
New feature
4-bit descriptors associated with a translation table entry that can be
annotated onto a transaction request.
Subsystem Identifier
New feature
An additional identifier that can be added to transaction requests to
indicate from which subsystem they originate.
Subordinate busy
New feature
Response signal that indicates the level of activity of a Subordinate.
Unique ID indicator
Clarification
Added rules for the Unique ID Indicator and Atomic transactions that
include read and write responses.
Correction
BIDUNQ is not required to follow AWIDUNQ for non-Completion
write responses such as Persist and MTE Match.
Memory Tagging
Extension (MTE)
Clarification
A WritePtlCMO or WriteFullCMO with AWTAGOP Transfer must be
Non-shareable. This is because a WriteUnique with AWTAGOP of
Transfer is not permitted.
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
307


Chapter B4. Revisions
B4.1. Differences between Issue H.c and Issue J
Table B4.1 – Continued from previous page
Feature
Change
Detail
Clarification
Transactions that carry MTE tags must not cross a cache line boundary.
Additional
requirement
Read transactions with the MTE opcode of Fetch must be Regular.
Enhancement
The text describing MTE and Poison is enhanced with additional
guidance.
Prefetch transaction
Clarification
A Prefetch request must not be used to signal that a line can be fetched
into a managed or visible cache.
Wakeup signals
Clarification
It is permitted for Wakeup signals to be driven from a glitch-free OR
tree if that implementation is safe for asynchronous sampling.
Multi-copy atomicity
Update
The requirements for multi-copy atomicity are updated for the Armv8
architecture.
Exclusive accesses
Update
New signals are added to the rules for an exclusive sequence.
Clarification
The requirements for AxCACHE in an exclusive access have been
redefined to be easier to understand.
Read response
Clarification
For read responses where data is not required to be valid, the Manager
might still sample the RDATA value so the Subordinate should not rely
on the response to hide sensitive data.
Interface parity
Enhancement
The description regarding how to handle missing signals in CHK groups
is enhanced to cover the case where either the input or output is missing.
Signal matrix
Correction
The ARDOMAIN and AWDOMAIN entries in the signal matrix are
corrected to be dependent on the Shareable_Transactions property and
marked as Configurable rather than Mandatory.
Cache stashing
Correction
"AWSTASHLPIDEN must be driven to all zeros when
AWSTASHLPIDEN is deasserted"
is corrected to:
"When AWSTASHLPIDEN is LOW, AWSTASHLPID is invalid and must
be zero"
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
308


Chapter B4. Revisions
B4.2. Differences between Issue J and Issue K
B4.2 Differences between Issue J and Issue K
Feature
Change
Detail
Memory Encryption
Contexts (MEC)
New feature
The Memory Encryption Contexts (MEC) feature is added to the Realm
Management Extension (RME).
MPAM extension
Enhancement
A new configuration option is defined for MPAM to support a wider
PartID field.
MTE extension
Enhancement
A new configuration option is defined for MTE to support components
which transport tags but do not support the Match operation.
Fixed_Burst_Disable
Enhancement
A new property is defined that allows components to not support a Burst
type of FIXED.
Cache_Line_Size
Enhancement
A new property is defined to capture the cache line size of an interface.
WriteNoSnoopFull
Transaction
Enhancement
A new WriteNoSnoopFull_Transaction property is defined to enable an
interface to support WriteNoSnoopFull without having to support all
transactions related to caching shareable lines.
Write channel
dependency
Clarification
It is clarified that a Subordinate must not block acceptance of data-less
write requests due to transactions with leading write data.
Length attribute
Clarification
It is clarified that Size x Length defines that maximum number of bytes
in a transaction rather than the actual number in all cases.
Transaction equations
Correction
The Data_Bytes variable is corrected to be DATA_WIDTH/8.
Transaction pseudocode
Clarification
Variable names changed to align with earlier sections.
Ordering between
Device and Normal
Non-cacheable
Enhancement
A property Device_Normal_Independence is added to control whether
Device and Normal Non-cacheable requests are required to be ordered
against each other.
CACHE_Present
Clarification
It is clarified that the CACHE_Present property determines whether
AxCACHE signals are present on an interface.
Cache stash property
Correction
In the paragraph text and Table A8.19, the Cache_Stash_Transactions
property was incorrectly referred to as Stash_Transactions.
Max_Transaction_Bytes
Clarification
Clarification on the meaning of the Max_Transaction_Bytes property.
Write data strobes
Clarification
Clarification of the rules for WSTRB.
Read data interleaving
Clarification
It is clarified that read data transfers in Atomic transactions can be
interleaved.
Modifiable transactions
Clarification
It is clarified that AxNSE must not be modified, along with AxPROT.
Exclusive accesses
Clarification
It is clarified that AWATOP must not be Match for exclusive writes.
PREFETCHED response
Change
The recommendation for PREFETCHED response is changed to be:
within a cache line, the PREFETCHED response is used for all data
transfers or no data transfers. This aligns better with the CHI
DataSource response.
Caching shareable lines
Clarification
It is clarified that clean evictions of Shareable lines must not be written
back to memory.
Clarification
In Table A8.8, CacheStash* is replaced with StashOnce*.
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
309


Chapter B4. Revisions
B4.2. Differences between Issue J and Issue K
Table B4.2 – Continued from previous page
Feature
Change
Detail
Memory Tagging
Clarification
A footnote is added to Table A12.13 to clarify that a WriteNoSnoop
with tag Match must not be Exclusive.
Correction
In Table A12.12, the value for Tags match is corrected to be 0b11, not
0b10.
User Loopback signaling
Clarification
Clarification of the rules for LOOP_x_WIDTH properties.
MMUFLOW_Present
property default
Correction
The default value for MMUFLOW_Present is corrected to be False to
make it compatible with the default for the Untranslated_Transactions
property.
StashTranslation and
UnstashTranslation
Enhancement
StashTranslation and UnstashTranslation are enhanced to enable the
stash or unstash of Granule Protection Table entries.
DVM messages
Clarification
It is clarified that the AC and CR channels are ordered.
Correction
The mapping for the 2nd part of a PICI message was incorrect in Table
A15.22. ACADDR[11:4] should be PA[11:4].
Poison
Correction
The width of WPOISON and RPOISON is corrected to be
ceil(DATA_WIDTH/64) rather than DATA_WIDTH/64.
Interface parity for
CRTRACE
Correction
In Table A16.4, the enable signal for CRTRACECHK was indicated as
ACVALID when it should be CRVALID.
Loopback check signal
width
Change
In Table A16.4, the width of check signals for Loopback signals is
changed from 1 to ceil(LOOP_x_WIDTH) to cover cases where the
maximum recommendation of 8 for loopback width is exceeded.
ACE5-LiteDVM
interface
Correction
The list of signals no longer supported in ACE5-LiteDVM is corrected
to ACSNOOP, ACPROT and CRRESP.
Correction
DVM_Message_Support must be Receiver for ACE5-LiteDVM
interfaces. Therefore, the snoop channels are mandatory rather than
optional.
BROADCAST* signals
Correction
In the signal matrix Table B2.2, the BROADCAST* signal presence was
listed as dependent on a Broadcast_Signals property which was not
defined. Presence conditions for these signals have now been removed.
Parity check signal
matrix
Clarification
A matrix of parity check signals vs interface type is added for clarity.
Read Interleaving
Disabled and AXI5-Lite
Correction
Read_Interleaving_Disabled was incorrectly constrained to True for
AXI5-Lite interfaces, it should be False.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
310


Chapter B4. Revisions
B4.3. Differences between Issue K and Issue L
B4.3 Differences between Issue K and Issue L
Feature
Change
Detail
Credited transport
New feature
New credited transport option for all channels.
Arm Compression
Technology
New feature
Added support for Arm Compression Technology.
Protection attributes
New feature
New options for signaling physical address space and other protection
attributes.
RME - Granular Data
Isolation
New feature
Added support for the GDI extension to RME.
Reset
Clarification
It is clarified that all signals that are required to be deasserted during
reset must wait until at least the rising ACLK edge after ARESETn is
HIGH.
Memory Encryption
Contexts (MEC)
Correction
In Table B2.4, the MECID_WIDTH row has been corrected to say
values can be 0,16 (two values) rather than 0..16 (range).
Clarification
It is clarified that the constraint for zero MECID only applies to requests
where MECID is applicable.
Clarification
Removed misleading paragraph regarding mismatched widths of
AxMECID.
Untranslated
Transactions
Correction
The default value for AWMMUVALID and ARMMUVALID is
corrected to be 0b1 rather than 0b0.
Correction
When the AxMMUVALID signals were added to the specification, it
was expected that translated and untranslated transactions would use
different AXI ID values, but these rules were missing from the
specification.
New feature
New v4 option for Untranslated Transactions supports address
translation with GDI and PCIe XT mode.
Transaction address
calculation
Correction
The expression to determine the address states for a wrap transaction
has been corrected to:
Address_N = Aligned_Addr + ((N - 1) * Size) -
(Size * Length)
Wrapping bursts
New feature
New property Wrap_CLS_Modifiable, used to determine whether
WRAP transactions must be cache line sized and Modifiable.
Exclusive accesses
Clarification
It is clarified that mismatched attributes do not always cause a failure.
Atomic Transactions
Clarification
It is clarified that Atomic transactions must update the entire written
location atomically.
Clarification
AtomicCompare transactions count as a Regular Transaction, even
though the address might not be aligned to Size.
Clarification
Clarification of ID rules for Atomic transactions.
Memory Tagging
Extension (MTE)
Clarification
If is clarified that transactions that carry tags must be physically
addressed.
Continued on next page
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
311


Chapter B4. Revisions
B4.3. Differences between Issue K and Issue L
Table B4.3 – Continued from previous page
Feature
Change
Detail
Cache line sized
transactions
Change
The following Opcodes can now be Non-modifiable or Modifiable:
WriteZero, WriteNoSnoopFull, WritePtlCMO, WriteFullCMO.
Caching Shareable lines
Correction
In Table A8.8, the entry for a Non-shareable CleanShared CMO has a
footnote added that it must hit a Shareable Dirty line if RME_Support is
True.
Enhancement
Added a statement regarding Outer Cacheable mode in attached CPUs.
Cache maintenance
operations
Clarification
It is clarified that if the AxDOMAIN signals are missing, a CMO is
assumed to be Non-shareable.
Correction
In the example of a Non-shareable WriteFullCMO with CleanInvalid,
all in-line and peer caches must be cleaned and invalidated because the
CMO is considered to be shareable.
New feature
New cache maintenance operation, CleanInvalidStorage.
DVM Messages
Correction
In the ASID field section, the statement “For a 16-bit ASID agent
sending a message to an 8-bit VMID agent” has been corrected to “For a
16-bit ASID agent sending a message to an 8-bit ASID agent".
Clarification
The use of the Range field in DVM TLBI messages is clarified.
Clarification
It is clarified that the range calculation uses the Translation Granule size
in bytes, derived from TG.
DVM Complete
transaction
Clarification
When DATA_WIDTH is 1024 and Max_Transaction_Bytes is 64 bytes,
it is not possible that a DVM Complete can have ARSIZE equal to data
channel width. It is clarified that for a DVM Complete, ARSIZE must
be equal to the data channel width or Max_Transaction_Bytes if that is
smaller than the data width.
DVM connection
Clarification
It is clarified that there might be a race between the assertion of
SYSCOACK and ACVALID.
AWCACHE meanings
Correction
The meaning of the Bufferable bit (AWCACHE[0]) is corrected to say
that the write response indicates that the data has reached its final
destination only if AWCACHE[3:2] are both deasserted.
ACE-LiteACP cache line
size
Clarification
It is clarified that the constraints on ACE5-LiteACP interfaces include a
cache line size of 64 bytes.
Trace signals
Clarification
Added recommendation that a component that provides a response to a
transaction with the Trace signal deasserted in the request provides a
response with the Trace signal deasserted.
Loopback signals
Clarification
It is clarified that Loopback signals can be used on only read or only
write channels.
Cache line sized and
Regular
Clarification
ReadNoSnoop with MTE Fetch is added to the list of Opcodes that must
be cache line sized and Regular.
ID constraints
Clarification
It is clarified that transactions with unique ID constraints are only
constrained against other transactions on the same channels.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
312
