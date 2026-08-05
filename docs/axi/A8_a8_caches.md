# A8 Caches

Chapter A8
Caches
This chapter describes caching in the AXI protocol.
It contains the following sections:
• A8.1 Caching in AXI
• A8.2 Cache line size
• A8.3 Cache coherency and Domains
• A8.4 I/O coherency
• A8.5 Caching Shareable lines
• A8.6 Prefetch transaction
• A8.7 Cache Stashing
• A8.8 Deallocating read transactions
• A8.9 Invalidate hint
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
131


Chapter A8. Caches
A8.1. Caching in AXI
A8.1 Caching in AXI
In this specification, the term cache is used for any storage structure, including caches, buffers, or other
intermediate storage elements. Data can be cached at various points in a system. An example topology is shown
in Figure A8.1. In the example, there is a system cache which is visible to all agents, local Shareable caches which
are visible to all coherent agents and local Non-shareable caches which are visible to a single agent.
Fully coherent agents use hardware coherency with data snooping to keep their caches coherent. These will
typically use an AMBA CHI interface [5].
I/O coherent agents can share data with fully coherent agents but any data that is cached locally to them must be
manually maintained to ensure coherency.
Non-coherent agents must use manual cache maintenance on any data that is shared with other agents and cached
locally.
Fully coherent agent
Fully coherent agent
I/O coherent agent
Shareable cache
Shareable cache
Non-shareable 
cache
Coherent interconnect and cache
Non-coherent interconnect
System cache
Memory
CHI
Non-coherent agent
CHI
CHI
CHI
AXI
AXI
AXI
AXI
AXI
AXI
Figure A8.1: Example system topology showing possible cache locations and type
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
132


Chapter A8. Caches
A8.2. Cache line size
A8.2 Cache line size
A cache line is defined as a cached copy of sequentially byte addressed memory locations, with the first address
aligned to the total size of the cache line. A system which employs cache sharing must have a common cache line
size. Some transactions only operate on entire cache lines and must be cache line sized.
The cache line size is fixed at design time and defined using the Cache_Line_Size property.
Name
Values
Default
Description
Cache_Line_Size
16, 32, 64, 128, 256, 512, 1024, 2048
64
Cache line size in bytes.
For any interfaces carrying cache line sized transactions, the data width must be wide enough to transport a cache
line using 16 transfers or fewer.
To be compatible with AMBA CHI, cache line size must be 64 bytes.
Opcodes where the transaction must be cache line sized and Regular are shown in Table A8.2. For more
information on Regular transactions, see A3.1.8 Regular transactions.
Table A8.2: Opcodes which must be cache line sized and Regular
Transactions on the read channels
Transactions on the write channels
ReadShared
WriteNoSnoopFull
ReadClean
WriteUniqueFull
CleanShared
WriteBackFull
CleanInvalid
WriteEvictFull
MakeInvalid
CMO
CleanSharedPersist
WriteZero
ReadNoSnoop with MTE Fetch
WriteUniqueFullStash
WriteFullCMO
StashOnceShared
StashOnceUnique
Prefetch
InvalidateHint
Cache line sized transactions have the following constraints:
• Size x Length must be equal to the cache line size.
• Transactions with write data must have all byte strobes asserted within the cache line container.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
133


Chapter A8. Caches
A8.3. Cache coherency and Domains
A8.3 Cache coherency and Domains
When multiple Managers share data, writes from those Managers must be coherent. This means writes to the same
address location by two Managers are observable in the same order by all participating Managers.
If a system contains caches, measures must be taken to ensure that cached values do not become stale.
In AMBA, this can be achieved in three ways:
• Using Non-cacheable transactions.
• Software coherency with manual cache maintenance.
• Hardware coherency with snooping and automatic cache maintenance.
AXI supports these by attributing a Domain to every address location, this can be System, Non-shareable or
Shareable. There must be a consistent definition of:
• Which address locations are in each Domain.
• Which Domain an address location is attributed.
A8.3.1
System Domain
Address locations in the System Domain must be visible to all Managers that are able to access them. This is
achieved by ensuring that all System Domain requests are Non-cacheable and therefore not stored in any local
caches. Using the System Domain makes coherency simple but is generally not high performance.
Requests to Device type memory are required to use the System Domain.
A8.3.2
Non-shareable Domain
Address locations in the Non-shareable Domain are not required to be visible to other Managers. Transactions to
Non-shareable locations do not need to trigger hardware coherency mechanisms to ensure visibility.
If Non-shareable data is to be shared between Managers, then transactions known as Cache Maintenance
Operations (CMOs) must be issued to clean and invalidate the data from any local caches before it is read.
See Chapter A9 Cache maintenance for more details.
Data sharing using CMOs is known as software coherency and can be an efficient approach if the sharing behavior
between Managers is known. For example, if there are predictable data sets that are written by one agent then read
by another. The main disadvantage of this approach is that it relies on software being correct. Coherency bugs in
software can be easy to introduce and difficult to debug.
To avoid a loss of coherency, there are some rules when caching Non-shareable lines:
• The eviction and write-back of Clean Non-shareable data is not permitted. This is to avoid a Clean line from
overwriting a Dirty line in a downstream cache that was written by another Manager.
• The passing of Dirty data on a read of a Non-shareable line from one cache to another is not permitted. The
line must be passed as Clean and responsibility for writing back the line remains with the downstream cache.
This avoids a subsequent write-back of the line from overwriting a later update from another Manager.
A8.3.3
Shareable Domain
Address locations in the Shareable Domain must be visible to all other Managers that also have those locations
marked as Shareable. Requests with the Shareable attribute must snoop local caches and lookup in caches that
might contain Shareable data from other Managers.
There are two reasons why an AXI component may need to support the Shareable Domain: to enable I/O
coherency and to support the movement of Shareable cache lines between upstream and downstream caches.
These cases are covered in A8.4 I/O coherency and A8.5 Caching Shareable lines.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
134


Chapter A8. Caches
A8.3. Cache coherency and Domains
Requests in the Shareable domain can use a Burst type of INCR or WRAP, not FIXED.
A8.3.4
Domain signaling
Domain signaling is optional, if an interface does not have Domain signaling then Non-cacheable requests are
assumed to be in the System Domain and Cacheable requests are assumed to be in the Non-shareable Domain.
If a component is required to support the Shareable Domain, it must include the Domain signaling.
The Shareable_Transactions property is used to describe whether an interface supports the Shareable Domain and
therefore has Domain signaling.
Table A8.3: Shareable_Transactions property
Shareable_Transactions
Default
Description
True
Shareable domain supported, AxDOMAIN
signals are on the interface.
False
Y
Shareable domain not supported,
AxDOMAIN signals are not on the
interface.
When Shareable_Transactions is True, the following signals are included on the interface.
Table A8.4: AxDOMAIN signals
Name
Width
Default
Description
AWDOMAIN,
ARDOMAIN
2
-
Shareability domain of a request.
Shareable_Transactions is encoded on the AxDOMAIN signals as shown in Table A8.5.
Table A8.5: AxDOMAIN encodings
AxDOMAIN
Label
Meaning
0b00
Non-shareable
Non-shareable domain
0b01
Shareable
Shareable domain
0b10
Shareable
Shareable domain
0b11
System
System domain
If AxDOMAIN signals are not present:
• Non-cacheable requests are assumed to be in the System domain.
• Cacheable requests are assumed to be in the Shareable domain.
In previous versions of this specification, AxDOMAIN values of 0b01 and 0b10 indicated Inner Shareable and
Outer Shareable respectively. In this version, it is recommended that 0b10 is used to indicate the Shareable
domain.
Guidance for connecting Manager and Subordinate interfaces with different values of Shareable_Transactions is
shown in Table A8.6.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
135


Chapter A8. Caches
A8.3. Cache coherency and Domains
Table A8.6: Shareable_Transactions interoperability
Subordinate: False
Subordinate: True
Manager: False
Compatible.
Compatible if logic is added to generate default
AxDOMAIN values from AxCACHE.
Manager: True
Compatible.
AxDOMAIN outputs are unconnected.
Compatible.
A8.3.5
Domain consistency
An address location can be marked as Shareable for one agent and Non-shareable for another. To avoid a loss of
coherency, data cached as Non-shareable must be made visible using CMOs before being accessed by an agent
that has the location marked as Shareable.
A8.3.6
Domains and memory types
The combination of Domain and memory type determines which caches must be accessed to complete the
transactions.
Legal combinations of memory type and Domain are shown in Table A8.7. The table also indicates which caches
must be accessed when processing a request.
• Peer caches are those which are accessed using snoop requests, this requires a coherent protocol such as
AMBA CHI [5].
• Inline caches are those which requests pass through while progressing towards memory.
Table A8.7: Legal combinations of memory type and Domain
Memory type
Domain
Caches accessed
Device
(AxCACHE[3:1] == 0b000)
System
None
Normal Non-cacheable
(AxCACHE[3:1] == 0b001)
Non-shareable
None
Shareable
Peer caches
System (recommended)
None
Normal Cacheable
(AxCACHE[3:2] != 0b00)
Non-shareable
Inline caches
Shareable
Inline and peer caches
Note that Normal Non-cacheable Shareable is permitted but not expected. Some implementations might not look
up in peer caches for Non-cacheable accesses.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
136


Chapter A8. Caches
A8.4. I/O coherency
A8.4 I/O coherency
An I/O coherent Manager can read and write data in the Sharable Domain through use of a coherent interconnect
but it cannot be snooped, so it must not cache Shareable data. AXI does not support data snooping, so the coherent
interconnect will typically be based on the AMBA CHI protocol [5] with AXI interfaces for connecting I/O
coherent Managers.
Fully coherent 
agent
Fully coherent 
agent
I/O coherent agent
Shareable cache
Shareable cache
Coherent interconnect and cache
CHI
CHI
CHI
CHI
AXI
AXI
Figure A8.2: Example use of I/O coherency
When an I/O coherent Manager issues a Shareable read request, the coherent interconnect tries to find the data by
snooping appropriate coherent caches and checking Shareable lines within its caches. If the data cannot be found,
a request is sent downstream towards memory. When the data is returned, it must not be cached by the I/O
coherent Manager because the data can become stale.
When an I/O coherent Manager issues a Shareable write request (WriteUniquePtl or WriteUniqueFull), the
coherent interconnect issues clean and invalidation requests to the coherent caches to ensure that there are no local
copies. It then writes the data into a cache or towards memory. For a partial cache line write, any Dirty data found
in coherent caches can be merged with the write.
The Shareable_Cache_Support property must be False for an I/O coherent interface.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
137


Chapter A8. Caches
A8.5. Caching Shareable lines
A8.5 Caching Shareable lines
An AXI-based cache that is downstream of a coherent interconnect has the option to store Shareable lines in
addition to Non-shareable cache lines. This has the advantages that:
• Clean evictions of Shareable lines can be cached but must not be written back to memory.
• Dirty data from Shareable lines can be passed to upstream Shareable caches.
To enable this, additional Opcodes and responses are required. The cache must also track which lines are Shareable
if it also stores lines from the Non-shareable Domain. In this case, a valid cache line can have one of four states:
• Clean
• Dirty
• Shareable Clean
• Shareable Dirty
The rules regarding which Opcodes can hit which cache lines are shown in Table A8.8.
Table A8.8: Rules for caching Shareable lines
Opcode
Domain
Cache state
Clean
Dirty
Shareable
Clean
Shareable
Dirty
Read*
Non-shareable
Permitted to hit
Permitted to hit
Must not hit
Permitted to hit1
Shareable
Permitted to hit
Must hit
Permitted to hit
Must hit2
Write*
Non-shareable
Must hit
Must hit
Must not hit
Permitted to hit1
Shareable
Must hit
Must hit
Must hit
Must hit
CleanShared*
Non-shareable
Permitted to hit
Must hit
Permitted to hit
Permitted to hit3
Shareable
Permitted to hit
Must hit
Permitted to hit
Must hit
CleanInvalid* / MakeInvalid
Non-shareable
Must hit
Must hit
Permitted to hit3
Permitted to hit3
Shareable
Must hit
Must hit
Must hit
Must hit
InvalidateHint / Prefetch
Non-shareable
Permitted to hit
Permitted to hit
Permitted to hit
Permitted to hit
Shareable
Permitted to hit
Permitted to hit
Permitted to hit
Permitted to hit
StashOnce*
Non-shareable
Permitted to hit
Permitted to hit
Must not hit
Permitted to hit
Shareable
Permitted to hit
Permitted to hit
Permitted to hit
Permitted to hit
∗Includes all variants of the Opcode.
1 The line must no longer be marked as Shareable.
2 Dirty data can be provided upstream if the request was ReadShared.
3 Must hit if RME_Support is True.
If Outer Cacheable mode is used by attached CPUs, transactions marked in the page tables as Inner
Non-cacheable, Outer Cacheable will not use shareable read and write transactions and it is not expected that
cache lines will be allocated as Shareable.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
138


Chapter A8. Caches
A8.5. Caching Shareable lines
A8.5.1
Opcodes to support reading and writing full cache lines
The following Opcodes can be used to read and write full cache lines of data.
Transactions using these Opcodes must be Modifiable, cache line sized and Regular. See A4.2.2 Modifiable
transactions, A8.2 Cache line size and A3.1.8 Regular transactions.
For write transactions all write strobes must be asserted.
ReadClean
A full cache line read from a Shareable location, where the data is likely to be allocated in an upstream cache. The
read data must be Clean.
This Opcode can be used if the Shareable_Cache_Support and Shareable_Transactions properties are both True.
ReadShared
A full cache line read from a Shareable location, where the data is likely to be allocated in an upstream cache. The
read data can be Clean or Dirty. If the data is Dirty, the line must be allocated upstream, and the response for all
transfers of read data must be OKAYDIRTY instead of OKAY.
This Opcode can be used if the Shareable_Cache_Support and Shareable_Transactions properties are both True.
WriteNoSnoopFull
A Non-shareable write of a full cache line where the data is Dirty and not allocated upstream.
An upstream cache can issue a WriteNoSnoopFull transaction when it evicts a Non-shareable Dirty cache line or
when streaming write data which is cache line sized. If a downstream cache receives a WriteNoSnoopFull request,
it can allocate the line knowing that the line is not allocated upstream.
This Opcode can be used if the WriteNoSnoopFull_Transaction or Shareable_Cache_Support property is True.
Table A8.9: WriteNoSnoopFull_Transaction property
WriteNoSnoopFull_Transaction
Default
Description
True
WriteNoSnoopFull is supported.
False
Y
WriteNoSnoopFull is not supported unless
Shareable_Cache_Support is True.
WriteUniqueFull
A Shareable write of a full cache line where the data is Dirty but was not allocated upstream. This transaction is
used by an I/O coherent Manager to write to a cache line that might be stored in a cache within the coherent
domain. A system cache can allocate the line as Shareable Dirty.
This Opcode can be used if the Shareable_Transactions property is True.
WriteBackFull
A WriteBackFull transaction can be used when a Shareable Dirty line is evicted from a coherent cache. This
transaction enables a system cache to allocate the line as Shareable Dirty.
This Opcode can be used if the Shareable_Cache_Support and Shareable_Transactions properties are both True.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
139


Chapter A8. Caches
A8.5. Caching Shareable lines
WriteEvictFull
A WriteEvictFull transaction can be used when a Shareable Clean line is evicted from a coherent cache. This
transaction enables a system cache to allocate the line as Shareable Clean.
A Shareable Clean line must not be exposed to any agents outside of the Shareable Domain because the line might
become stale within caches in the Shareable Domain. For the same reason, data from a WriteEvictFull must not
update memory.
This Opcode can be used if the Shareable_Cache_Support and Shareable_Transactions properties are both True.
A8.5.2
Configuration of Shareable cache support
The Shareable_Cache_Support property is used to indicate whether an interface supports the additional transaction
Opcodes required for the storage of coherent cache lines.
Table A8.10: Shareable_Cache_Support property
Shareable_Cache_Support
Default
Description
True
Additional Opcodes for Shareable cache
lines are supported.
False
Y
Additional Opcodes for Shareable cache
lines are not supported.
The compatibility between Manager and Subordinate interfaces according to the values of the
Shareable_Cache_Support property is shown in Table A8.11.
Table A8.11: Shareable_Cache_Support compatibility
Shareable_Cache_Support
Subordinate: False
Subordinate: True
Manager: False
Compatible.
Compatible.
Manager: True
Incompatible.
Alternative Opcodes must be used.
Compatible.
Shareable requests can also be controlled at reset-time using an optional Manager input signal,
BROADCASTSHAREABLE.
Table A8.12: BROADCASTSHAREABLE signal
Name
Width
Default
Description
BROADCASTSHAREABLE
1
0b1
Manager tie-off input, used to control the issuing of
Shareable transactions from an interface.
When BROADCASTSHAREABLE is present and deasserted, all transactions are converted to Non-shareable
equivalents before they are sent, as shown in Table A8.13.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
140


Chapter A8. Caches
A8.5. Caching Shareable lines
Table A8.13: Opcode alternatives
Opcode
BROADCASTSHAREABLE is LOW
WriteUniquePtl
WriteNoSnoop
WriteUniqueFull
WriteNoSnoop or WriteNoSnoopFull
WriteBackFull
WriteNoSnoop or WriteNoSnoopFull
WriteEvictFull
- (request must be dropped)
CMO (Shareable)
CMO (Non-shareable)
WriteUniquePtlStash
WriteNoSnoop
WriteUniqueFullStash
WriteNoSnoop or WriteNoSnoopFull
WritePtlCMO (Shareable)
WritePtlCMO (Non-shareable)
StashOnceShared (Shareable)
StashOnceShared (Non-shareable)
StashOnceUnique (Shareable)
StashOnceUnique (Non-shareable)
Prefetch (Shareable)
Prefetch (Non-shareable)
ReadOnce
ReadNoSnoop
ReadShared
ReadNoSnoop
ReadClean
ReadNoSnoop
ReadOnceCleanInvalid
ReadNoSnoop
ReadOnceMakeInvalid
ReadNoSnoop
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
141


Chapter A8. Caches
A8.6. Prefetch transaction
A8.6 Prefetch transaction
When a Manager has indication that it might need data for an address but does not want to commit to reading it yet,
it can send a Prefetch request to the system that it might be advantageous to prepare the location for reading. This
request to the system can cause the allocation of data into a downstream cache or from off-chip memory before the
Manager makes the actual read request.
The Prefetch request is not required to be ordered with respect to other requests such as CMOs, therefore a
Prefetch must not be used to signal that a line can be fetched into a managed or visible cache.
The PREFETCHED response to a read request indicates that the transaction has hit upon prefetched data. The
Manager can use this as part of a heuristic to determine if it continues issuing Prefetch requests.
In AMBA CHI [5], the equivalent of a Prefetch request is PrefetchTgt which can be issued alongside a coherent
request to the same address. The PrefetchTgt can bypass any coherency checks and cause the memory controller to
prefetch the data in case the coherent request does not find the data in any shared caches. If the memory controller
uses an AXI interface, the CHI PrefetchTgt request can be converted to an AXI Prefetch.
A8.6.1
Rules for the prefetch transaction
A Prefetch is a data-less transaction, the rules are:
• The Prefetch transaction consists of a request on the AW channel and a single response transfer on the B
channel, there is no data transfer.
• A Prefetch request is signaled using the AWSNOOP Opcode of 0b01111.
• A Prefetch request must be cache line sized with the following constraints:
– The transaction is Regular, see A3.1.8 Regular transactions.
– AWCACHE[1] is asserted, that is a Normal transaction.
– AWDOMAIN is Non-shareable or Shareable.
– AWLOCK is deasserted, not exclusive access.
• The ID value must be unique-in-flight, which means:
– A Prefetch request can only be issued if there are no outstanding write transactions using the same
AWID.
– The Manager must not issue a request on the write channel with the same AWID as an outstanding
Prefetch request.
– If present on the interface, AWIDUNQ must be asserted for Prefetch transactions.
• The Manager may or may not follow a Prefetch request with a non-Prefetch request to the same address.
• A Subordinate interface at any level can chose to propagate or respond to a Prefetch request.
• It is permitted to respond to a Prefetch request with OKAY, DECERR, SLVERR, or TRANSFAULT (only if
AWMMUFLOW is PRI).
• An OKAY response can be sent irrespective of whether the Subordinate acts on the Prefetch request.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
142


Chapter A8. Caches
A8.6. Prefetch transaction
The Prefetch_Transaction property is used to indicate whether a component supports the Prefetch Opcode as
shown in Table A8.14.
Table A8.14: Prefetch_Transaction property
Prefetch_Transaction
Default
Description
True
Prefetch is supported.
False
Y
Prefetch is not supported.
A8.6.2
Response for prefetched data
If a read request hits on data which has been prepared due to a previous Prefetch request, the Subordinate may
return a PREFETCHED response. This can be used by the Manager to determine the success rate of its Prefetch
requests.
The PREFETCHED response has the following rules and recommendations:
• The PREFETCHED response is signaled using RRESP encoding of 0b100.
• When Prefetch_Transaction is True, RRESP_WIDTH must be 3 to enable the signaling of the
PREFETCHED response.
• PREFETCHED indicates that read data is valid and has come from a prefetched source.
• PREFETCHED can be used for a response to the following Opcodes:
– ReadNoSnoop
– ReadOnce
– ReadClean
– ReadShared
– ReadOnceCleanInvalid
– ReadOnceMakeInvalid
• A PREFETCHED response cannot be sent for an exclusive read.
• It is recommended that within a cache line, the PREFETCHED response is used for all data transfers or no
data transfers. If a transaction spans cache lines, there can be a mixture of PREFETCHED and other
responses for each cache line accessed.
• A PREFETCHED response can only be sent if the Prefetch_Transaction property is True for the interface.
• A PREFETCHED response can be sent to a Manager even if the Manager has not sent a Prefetch request to
that location. For example, if a Manager happens to read data which was prefetched by another Manager.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
143


Chapter A8. Caches
A8.7. Cache Stashing
A8.7 Cache Stashing
Cache stashing enables one component to indicate that data should be placed in another cache in the system. This
technique can be used to ensure that data is located close to its point of use, potentially improving the performance
of the overall system. The AXI protocol supports cache stashing requests with or without a stash target identifier.
Cache stashing is a hint. A cache, or system component can choose to ignore the stash part of a request.
I/O coherent AXI Managers can request that data is stashed in fully coherent Managers with AMBA CHI
interfaces [5].
A8.7.1
Stash transaction Opcodes
There are four Opcodes that can be used for cache stashing.
WriteUniquePtlStash
Write to a Shareable location with an indication that the data should be allocated into a cache. Any number of
bytes within the cache line can be written, including all bytes or zero bytes.
WriteUniqueFullStash
Write a full cache line of data to a Shareable location with an indication that the data should be allocated into a
cache. The transaction must be cache line sized and Regular. All write strobes must be asserted.
StashOnceShared
A data-less transaction which indicates that a cache line should be fetched into a particular cache. Other copies of
the line are not required to be invalidated.
StashOnceUnique
A data-less transaction which indicates that a cache line should be fetched into a particular cache. It is
recommended that all other copies are invalidated.
A StashOnceUnique transaction can cause the invalidation of a cached copy of a cache line and care must be taken
to ensure that such transactions do not interfere with exclusive access sequences.
For an interface that supports the Untranslated Transactions feature, an extra stash transaction is supported. The
StashTranslation transaction is used to indicate to a System Memory Management Unit (SMMU) that a translation
should be obtained for the address that is supplied with the StashTranslation transaction. See A13.9
StashTranslation Opcode.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
144


Chapter A8. Caches
A8.7. Cache Stashing
A8.7.2
Stash transaction signaling
Stash requests are signaled on the write request channel and have a single response transfer on the write response
channel. Write with stash transactions also include write data.
A stash request has constraints on Domain, Size, and Length shown in Table A8.15. Cache stash transactions are
not permitted to cross a cache line boundary.
Table A8.15: Domain, Size, and Length constraints for stash requests
Opcode
AWSNOOP
Domain
Size, Length
WriteUniquePtlStash
0b1000
Shareable
Cache size or smaller
WriteUniqueFullStash
0b1001
Shareable
Cache line sized and Regular
StashOnceShared
0b1100
Non-shareable, Shareable
Cache line sized and Regular
StashOnceUnique
0b1101
Non-shareable, Shareable
Cache line sized and Regular
The following constraints also apply to all stash request Opcodes:
• AWCACHE[1] is 0b1 (Modifiable)
• AWLOCK is 0b0 (not exclusive access)
• AWTAGOP is 0b00 (Invalid)
• AWATOP is 0b000000 (Non-atomic operation)
A8.7.3
Stash request Domain
The Domain of a stash request determines which caches are checked for the cache line and how the line should be
fetched and stored.
A stash request to a Shareable location implies that the line can be stored in a peer or inline cache. If the stash
request causes a cache to issue a downstream request, it should be Shareable if possible. Writes with stash must
always be to a Shareable location.
A stash request to a Non-shareable location implies that the line can be stored in an inline cache. If the stash
request causes a cache to issue a downstream request, it must be Non-shareable. StashOnceShared and
StashOnceUnique Opcodes can be to Shareable or Non-shareable locations.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
145


Chapter A8. Caches
A8.7. Cache Stashing
A8.7.4
Stash target identifiers
A stash request can optionally include target identifiers to indicate a specific cache that is preferred for the data to
be stored. This specification does not define the precise details of this identification mechanism. It is expected that
any agent that is performing a stash operation knows the identifier to use for a given stash transaction.
This specification defines two levels of identification:
• A Node ID (NID) to identify the physical interface that the cache stash should be sent to.
• A Logical Processor ID (LPID) to identify a functional unit that is associated with that physical interface.
For example, a stash transaction can specify a processor cluster interface and specific cache within that cluster.
The signals used to indicate stash targets are shown in Table A8.16.
Table A8.16: Signals used to indicate stash targets
Name
Width
Default
Description
AWSTASHNID
11
0x000
Node Identifier of the target for a stash operation.
AWSTASHNIDEN
1
0b0
HIGH to indicate that the AWSTASHNID signal is valid.
AWSTASHLPID
5
0x00
Logical Processor Identifier within the target for a stash
operation.
AWSTASHLPIDEN
1
0b0
HIGH to indicate that the AWSTASHLPID signal is valid.
The NID and LPID signals are optional on an interface, controlled using the STASHNID_Present and
STASHLPID_Present properties, respectively.
Table A8.17: STASHNID_Present property
STASHNID_Present
Default
Description
True
AWSTASHNID and AWSTASHNIDEN are present.
False
Y
AWSTASHNID and AWSTASHNIDEN are not present.
Table A8.18: STASHLPID_Present property
STASHLPID_Present
Default
Description
True
AWSTASHLPID and AWSTASHLPIDEN are present.
False
Y
AWSTASHLPID and AWSTASHLPIDEN are not present.
Each stash target identifier has an enable signal so NID and LPID can be controlled independently.
• For stash transactions, any combination of target enables is permitted.
• For non-stash transactions, AWSTASHLPIDEN and AWSTASHNIDEN must be LOW.
• When AWSTASHNIDEN is LOW, AWSTASHNID is invalid and must be zero.
• When AWSTASHLPIDEN is LOW, AWSTASHLPID is invalid and must be zero.
• It is permitted, but not recommended to send a stash transaction with a stash target that indicates a
component that does not support cache stashing. The indication of a stash target within a stash transaction
does not affect which components are permitted to access and cache a given cache line.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
146


Chapter A8. Caches
A8.7. Cache Stashing
For WriteUniquePtlStash and WriteUniqueFullStash requests without a target, the following is recommended:
• If the interconnect can determine that the line is held in a single cache before the write occurs, then stash the
cache line back to that cache.
• If the cache line is not held in any cache before the write occurs, then stash the cache line in a shared system
cache.
For StashOnceShared and StashOnceUnique requests without a target:
• If the interconnect can determine that the cache line is not in any cache, then it is recommended to stash the
cache line in a shared system cache.
• A component can use this to prefetch a cache line to a downstream cache for its own use.
A8.7.5
Transaction ID for stash transactions
There are no constraints on the use of AXI ID values for WriteUniquePtlStash and WriteUniqueFullStash
transactions.
StashOnceShared and StashOnceUnique can be referred to as StashOnce transactions.
StashOnce transactions must not use the same AXI ID values that are used by non-StashOnce transactions on the
write channels that are outstanding at the same time. This rule ensures that there are no ordering constraints
between StashOnce transactions and other transactions. Therefore, a component that discards a StashOnce request
can give an immediate response without checking ID ordering requirements.
StashOnce transactions and non-StashOnce transactions are permitted to use the same AXI ID value, provided that
the same ID value is not used by both a StashOnce transaction and a non-StashOnce at the same time.
There can be multiple outstanding StashOnce transactions with the same ID.
There can be multiple outstanding non-StashOnce transactions with the same ID.
The use of a unique ID value for a StashOnce transaction ensures that these transactions can be given an
immediate response if they are not supported.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
147


Chapter A8. Caches
A8.7. Cache Stashing
A8.7.6
Support for stash transactions
The Cache_Stash_Transactions property is used to indicate whether an interface supports cache stashing, as shown
in Table A8.19.
Table A8.19: Cache_Stash_Transactions property
Cache_Stash_Transactions
Default
Description
True
All cache stashing Opcodes are supported. There may or
may not be a stash target.
Basic
Only the StashOnceShared Opcode is supported. A stash
target is not permitted, STASHLPID_Present and
STASHNID_Present must be False.
False
Y
Cache stashing is not supported and associated signals are
omitted.
When Cache_Stash_Transactions is False, STASHNID_Present and STASHLPID_Present must both be False.
The compatibility between Manager and Subordinate interfaces according to the values of the
Cache_Stash_Transactions property is shown in Table A8.20.
Table A8.20: Stash transactions compatibility
Cache_Stash_Transactions
Subordinate: False
Subordinate: Basic
Subordinate: True
Manager: False
Compatible.
Compatible.
Compatible.
Manager: Basic
Incompatible, action
must be taken.
Compatible.
Compatible.
Manager: True
Incompatible, action
must be taken.
Incompatible, action
must be taken.
Compatible.
If a Manager issues stash requests to a target that does not support them, action can be taken in the Manager or
interconnect as shown in Table A8.21.
Table A8.21: Action needed if the target does not support stash transactions
Stash transaction
Action
WriteUniquePtlStash
Convert to WriteUniquePtl.
WriteUniqueFullStash
Convert to WriteUniqueFull.
StashOnceShared
Do not propagate and give an immediate response.
StashOnceUnique
Do not propagate and give an immediate response.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
148


Chapter A8. Caches
A8.8. Deallocating read transactions
A8.8 Deallocating read transactions
Deallocating read transactions can be used when a Manager requires data which is not likely to be used again by
any Manager. A cache can use this as a hint to evict the line and make the resource available for other data.
The DeAllocation_Transactions property is used to indicate whether a component supports deallocating
transactions as shown in Table A8.22.
Interoperability between a component that issues deallocating transactions and a component that does not support
them can be performed by converting the Opcode to ReadOnce.
Table A8.22: DeAllocation_Transactions property
DeAllocation_Transactions
Default
Description
True
Deallocating transactions are supported.
False
Y
Deallocating transactions are not supported.
A8.8.1
Deallocating read Opcodes
This specification defines two deallocating transaction Opcodes on the read request channel:
ReadOnceCleanInvalid (ROCI)
This request reads a snapshot of the current value of the cache line. It is recommended, but not required that any
cached copy of the cache line is deallocated. If a Dirty copy of the cache line exists, and the cache line is
deallocated, then the Dirty copy must be written back to main memory.
ReadOnceCleanInvalid is signaled using an ARSNOOP value of 0b0100.
ReadOnceMakeInvalid (ROMI)
This request reads a snapshot of the current value of the cache line. It is recommended, but not required that any
cached copy of the cache line is deallocated. It is permitted, but not required that a Dirty copy of the cache line is
discarded. The Dirty copy of the cache line does not need to be written back to main memory.
ReadOnceMakeInvalid is signaled using an ARSNOOP value of 0b0101.
A8.8.2
Rules and recommendations
Deallocating transactions are only permitted to access one cache line at a time and are not permitted to cross a
cache line boundary. Size must be cache line sized or smaller.
A ROMI request to part of a cache line can result in the invalidation of the entire cache line. Some
implementations might not support the deallocation behavior for transactions that are less than a cache line and
instead convert the transaction to ReadOnce in such cases.
ROCI and ROMI are only supported in the Shareable Domain, so the Shareable_Transactions property must be
True if DeAllocation_Transactions is True.
For a ROMI transaction, it is required that the invalidation of the cache line is committed before the return of the
first item of read data for the transaction. The invalidation of the cache line is not required to have completed at
this point. However, it must be ensured that any later write transaction from any agent that starts after this point, is
guaranteed not to be invalidated by this transaction.
The following considerations apply to the use of deallocating transactions:
• Caution is needed when deallocating transactions are issued to the same cache line that other agents are
using for exclusive accesses. This is because the deallocation can cause an exclusive sequence to fail.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
149


Chapter A8. Caches
A8.8. Deallocating read transactions
• Apart from the interaction with exclusive accesses, the ROCI transaction only provides a hint for
deallocation of a cache line and has no other impact on the correctness of a system.
• The use of the ROMI transaction can cause the loss of a Dirty cache line. The use of this transaction must be
strictly limited to scenarios when it is known that it is safe to do so.
• Deallocating transactions do not guarantee that a cache line will be cleaned or invalidated, so cannot be used
to ensure that data is visible to all observers.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
150


Chapter A8. Caches
A8.9. Invalidate hint
A8.9 Invalidate hint
The InvalidateHint transaction is a data-less deallocation hint. It can be used when a Manager has finished working
with a data set and that data might be allocated in a downstream cache. An InvalidateHint request informs the
cache that the line is no longer required and can be invalidated. A write-back of the line is permitted but not
required.
InvalidateHint is not required to be executed for functional correctness, so can be terminated at any point in the
system by responding with BRESP of OKAY.
Care is needed when using an InvalidateHint transaction to avoid exposure of previously overwritten values. This
can be achieved either by:
• Ensuring that a clean operation following a scrubbing write ensures that the write has been propagated
sufficiently far that it is not removed by the Invalidate Hint transaction.
• Ensuring the use of the InvalidateHint transaction is limited to address ranges that will not contain sensitive
information.
A8.9.1
Invalidate Hint signaling
InvalidateHint is a data-less transaction using AW and B channels.
The following constraints apply to an InvalidateHint request:
• AWSNOOP is 0b10010.
– AWSNOOP must be 5b wide if the InvalidateHint_Transaction property is True.
• AWDOMAIN can be Non-shareable or Shareable.
• AWBURST is INCR.
• AWSIZE and AWLEN must be cache line sized and Regular.
• AWCACHE is Normal Cacheable.
• AWID is unique-in-flight, which means:
– An InvalidateHint request can only be issued if there are no outstanding transactions on the write
channels using the same ID value.
– A Manager must not issue a request on the write channels with the same ID as an outstanding
InvalidateHint transaction.
– If present, AWIDUNQ must be asserted for an InvalidateHint request.
• AWLOCK is deasserted, not an exclusive access.
• AWTAGOP is Invalid.
• AWATOP is Non-atomic operation.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
151


Chapter A8. Caches
A8.9. Invalidate hint
A8.9.2
Invalidate Hint support
The InvalidateHint_Transaction property is used to indicate whether an interface supports the InvalidateHint
transaction, as shown in Table A8.23.
Table A8.23: InvalidateHint_Transaction property
InvalidateHint_Transaction
Default
Description
True
InvalidateHint is supported.
False
Y
InvalidateHint is not supported.
The compatibility between Manager and Subordinate interfaces according to the values of the
InvalidateHint_Transaction property is shown in Table A8.24.
Table A8.24: InvalidateHint_Transaction compatibility
InvalidateHint_Transaction
Subordinate: False
Subordinate: True
Manager: False
Compatible.
Compatible.
Manager: True
Not compatible.
An adapter that responds OKAY to
InvalidateHint could be used to
make it compatible.
Compatible.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
152
