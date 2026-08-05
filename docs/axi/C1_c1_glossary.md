# C1 Glossary

Chapter C1
Glossary
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
314


Chapter C1. Glossary
Aligned
A data item stored at an address that is divisible by the highest power of 2 that divides into its size in bytes.
Aligned halfwords, words and doublewords therefore have addresses that are divisible by 2, 4 and 8 respectively.
An aligned access is one where the address of the access is aligned to the size of each element of the access.
At approximately the same time
Two events occur at approximately the same time if a remote observer might not be able to determine the order in
which they occurred.
Barrier
An operation that forces a defined ordering of other actions.
Big-endian memory
Means that the most significant byte (MSB) of the data is stored in the memory location with the lowest address.
Blocking
Describes an operation that prevents following actions from continuing until the operation completes.
Branch prediction
Is where a processor selects a future execution path to fetch along. For example, after a branch instruction, the
processor can choose to speculatively fetch either the instruction following the branch or the instruction at the
branch target.
Byte
An 8-bit data item.
Cache
Any cache, buffer, or other storage structure in a caching Manager that can hold a copy of the data value for a
particular address location.
Cache hit
A memory access that can be processed at high speed because the data it addresses is already in the cache.
Cache line
The basic unit of storage in a cache. Its size in words is always a power of two. A cache line must be aligned to the
size of the cache line.
Cache miss
A memory access that cannot be processed at high speed because the data it addresses is not in the cache.
ceil()
A function that returns the lowest integer value that is equal to or greater than the input to the function.
Coherent
Data accesses from a set of observers to a memory location are coherent accesses to that memory location by the
members of the set of observers are consistent with there being a single total order of all writes to that memory
location by all members of the set of observers.
Component
A distinct functional unit that has at least one AMBA interface. Component can be used as a general term for
Manager, Subordinate, peripheral, and interconnect components.
Deprecated
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
315


Chapter C1. Glossary
Something that is present in the specification for backwards compatibility. Whenever possible you must avoid
using deprecated features. These features might not be present in future versions of the specification.
Downstream
An AXI transaction operates between a Manager component and one or more Subordinate components, and can
pass through one or more intermediate components. At any intermediate component, for a given transaction,
downstream means between that component and a destination Subordinate component, and includes the
destination Subordinate component.
Downstream and upstream are defined relative to the transaction as a whole, not relative to individual data flows
within the transaction.
Downstream cache
A downstream cache is defined from the perspective of an initiating Manager. A downstream cache for a Manager
is one that it accesses using the fundamental AXI transaction channels. An initiating Manager can allocate cache
lines into a downstream cache.
Endianness
An aspect of the system memory mapping.
Full coherency
A fully coherent Manager can share data with other Managers and allocate that data in its local caches; it can
snoop and be snooped.
I/O coherency
An I/O coherent Manager can share data with other Managers but cannot allocate that data in its local caches; it
can snoop but not be snooped.
IMPLEMENTATION DEFINED
Means that the behavior is not defined by this specification, but must be defined and documented by individual
implementations.
in a timely manner
The protocol cannot define an absolute time within which something must occur. However, in a sufficiently idle
system, it will make progress and complete without requiring any explicit action.
Initiating Manager
A Manager that issues a transaction that starts a sequence of events. When describing a sequence of transactions,
the term initiating Manager distinguishes the Manager that triggers the sequence of events from any snooped
Manager that is accessed as a result of the action of the initiating Manager.
Initiating Manager is a temporal definition, meaning it applies at particular points in time, and typically is used
when describing sequences of events. A Manager that is an initiating Manager for one sequence of events can be a
snooped Manager for another sequence of events.
Interconnect component
A component with more than one AMBA interface that connects one or more Manager components to one or more
Subordinate components.
An interconnect component can be used to group together either:
• A set of Managers so that they appear as a single Manager interface.
• A set of Subordinates so that they appear as a single Subordinate interface.
Little-endian memory
Means that the least significant byte (LSB) of the data is stored in the memory location with the lowest address.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
316


Chapter C1. Glossary
Load
The action of a Manager component reading the value held at a particular address location. For a processor, a load
occurs as the result of executing a particular instruction. Whether the load results in the Manager issuing a read
transaction depends on whether the accessed cache line is held in the local cache.
Local cache
A local cache is defined from the perspective of an initiating Manager. A local cache is one that is internal to the
Manager. Any access to the local cache is performed within the Manager.
Main memory
The memory that holds the data value of an address location when no cached copies of that location exist. For any
location, main memory can be out of date with respect to the cached copies of the location, but main memory is
updated with the most recent data value when no cached copies exist.
Main memory can be referred to as memory when the context makes the intended meaning clear.
Manager
An agent that initiates transactions.
Manager component
A component that initiates transactions.
It is possible that a single component can act as both a Manager component and as a Subordinate component.
For example, a Direct Memory Access (DMA) component can be a Manager component when it is initiating
transactions to move data, and a Subordinate component when it is being programmed.
Memory Encryption Contexts (MEC)
Memory Encryption Contexts are configurations of encryption that are associated with areas of memory, assigned
by the MMU.
MEC is an extension to the Arm Realm Management Extension (RME). The RME system architecture requires that
the Realm, Secure, and Root Physical Address Spaces (PAS) are encrypted. The encryption key or encryption
context, used with each of these PASs is global within that PAS. For example, for the Realm PAS, all Realm
memory uses the same encryption context. With MEC this concept is broadened, and for the Realm PAS
specifically, each Realm is allowed to have a unique encryption context. This provides additional defense in depth
to the isolation already provided in RME. MECIDs are identifying tags that are associated with different Memory
Encryption Contexts.
Memory Management Unit (MMU)
Provides detailed control of the part of a memory system that provides address translation. Most of the control is
provided using translation tables that are held in memory, and define the attributes of different regions of the
physical memory map.
Memory Subordinate component
A Memory Subordinate component, or Memory Subordinate, is a Subordinate component with the following
properties:
• A read of a byte from a Memory Subordinate returns the last value written to that byte location.
• A write to a byte location in a Memory Subordinate updates the value at that location to a new value that is
obtained by subsequent reads.
• Reading a location multiple times has no side-effects on any other byte location.
• Reading or writing one byte location has no side-effects on any other byte location.
Observer
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
317


Chapter C1. Glossary
A processor or other Manager component, such as a peripheral device, that can generate reads from or writes to
memory.
Page-based Hardware Attributes (PBHA)
Page Based Hardware Attributes (PBHA) is an optional, implementation defined feature. It allows software to set
up to 4 bits in the translation tables, which are then propagated though the memory system with transactions, and
can be used in the system to control system components. The meaning of the bits is specific to the system design.
Peer cache
A peer cache is defined from the perspective of an initiating Manager. A peer cache for that Manager is one that is
accessed using snoop channels. An initiating Manager cannot allocate cache lines into a peer cache.
Peripheral Subordinate component
A Peripheral Subordinate component is also described as a Peripheral Subordinate. A Peripheral Subordinate
typically has an IMPLEMENTATION DEFINED method of access that is described in the data sheet for the
component. Any access that is not defined as permitted might cause the Peripheral Subordinate to fail, but must
complete in a protocol-correct manner to prevent system deadlock. The protocol does not require continued
correct operation of the peripheral.
In the context of the descriptions in this specification, Peripheral Subordinate is synonymous with peripheral,
peripheral component, peripheral device, and device.
PoS
Point of Serialization. The point through which all transactions to a given address must pass and the order in
which the transactions are processed is determined.
Prefetching
Prefetching refers to speculatively fetching instructions or data from the memory system. In particular, instruction
prefetching is the process of fetching instructions from memory before the instructions that precede them, in
simple sequential execution of the program, have finished executing. Prefetching an instruction does not mean that
the instruction has to be executed.
In this specification, references to instruction or data fetching apply also to prefetching, unless the context
explicitly indicates otherwise.
RAZ/WI, Read-As-Zero, Writes Ignored
Hardware must implement the field as Read-as-Zero, and must ignore writes to the field. Software can rely on the
field reading as all 0s, and on writes being ignored. This description can apply to a single bit that reads as 0, or to a
field that reads as all 0s.
Realm Management Extensions (RME)
The Realm Management Extension (RME) is an extension to the Armv9 A-profile architecture. RME is one
component of the Arm Confidential Compute Architecture (Arm CCA). Together with the other components of the
Arm CCA, RME enables support for dynamic, attestable and trusted execution environments (Realms) to be run
on an Arm PE. RME adds two additional Security states (Root and Realm) and two physical address spaces (Root
and Realm), and provides hardware-based isolation that allows execution contexts to run in different Security
states and share resources in the system.
Snoop filter
A precise snoop filter that is able to track precisely the cache lines that might be allocated within a Manager.
Snooped cache
A hardware-coherent cache on a snooped Manager. That is, it is a hardware-coherent cache that receives snoop
transactions.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
318


Chapter C1. Glossary
The term snooped cache is used in preference to the term snooped Manager when the sequence of events being
described only involves the cache and does not involve any actions or events on the associated Manager.
Snooped Manager
A caching Manager that receives snoop transactions.
Snooped Manager is a temporal definition, meaning it applies at particular points in time, and typically is used
when describing sequences of events. A Manager that is a snooped Manager for one sequence of events can be an
initiating Manager for another sequence of events.
Speculative read
A transaction that a Manager issues when it might not need the transaction to be performed because it already has
a copy of the accessed cache line in its local cache. Typically, a Manager issues a speculative read in parallel with
a local cache lookup. This gives lower latency than looking in the local cache first, and then issuing a read
transaction only if the required cache line is not found in the local cache.
Store
The action of a Manager component changing the value held at a particular address location. For a processor, a
store occurs as the result of executing a particular instruction. Whether the store results in the Manager issuing a
read or write transaction depends on whether the accessed cache line is held in the local cache, and if it is in the
local cache, the state it is in.
Subordinate
An agent that receives and responds to requests.
Subordinate component
A component that receives transactions and responds to them.
It is possible that a single component can act as both a Subordinate component and as a Manager component. For
example, a Direct Memory Access (DMA) component can be a Subordinate component when it is being
programmed and a Manager component when it is initiating transactions to move data.
System Memory Management Unit (SMMU)
A system-level MMU. That is, a system component that provides address translation from one address space to
another. An SMMU provides one or more of:
• virtual address (VA) to physical address (PA) translation.
• VA to intermediate physical address (IPA) translation.
• IPA to PA translation.
When using the Realm Management Extension (RME), an SMMU can also perform the Granule Protection Check.
Transaction
An AXI Manager initiates an AXI transaction to communicate with an AXI Subordinate. Typically, the transaction
requires information to be exchanged between the Manager and Subordinate on multiple channels. The complete
set of required information exchanges form the AXI transaction.
Translation Lookaside Buffer (TLB)
A memory structure containing the results of translation table walks. TLBs help to reduce the average cost of a
memory access.
Translation table
A table held in memory that defines the properties of memory areas of various sizes from 1KB.
Translation table walk
The process of doing a full translation table lookup.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
319


Chapter C1. Glossary
Unaligned
An unaligned access is an access where the address of the access is not aligned to the size of an element of the
access.
Unaligned memory accesses
Are memory accesses that are not, or might not be, appropriately halfword-aligned, word-aligned, or
doubleword-aligned.
UNPREDICTABLE
In the AMBA AXI Architecture means that the behavior cannot be relied upon.
UNPREDICTABLE behavior must not be documented or promoted as having a defined effect.
Upstream
An AXI transaction operates between a Manager component and one or more Subordinate components, and can
pass through one or more intermediate components. At any intermediate component, for a given transaction,
upstream means between that component and the originating Manager component, and includes the originating
Manager component.
Downstream and upstream are defined relative to the transaction as a whole, not relative to individual data flows
within the transaction.
Write-Back cache
A cache in which when a cache hit occurs on a store access, the data is only written to the cache. Data in the cache
can therefore be more up-to-date than data in main memory. Any such data is written back to main memory when
the cache line is cleaned or re-allocated. Another common term for a Write-Back cache is a copy-back cache.
Write-Through cache
A cache in which when a cache hit occurs on a store access, the data is written both to the cache and to main
memory. This is normally done via a write buffer to avoid slowing down the processor.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
320
