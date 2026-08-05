# A11 Other write transactions

Chapter A11
Other write transactions
This chapter describes additional write transactions supported in the AXI protocol.
It contains the following sections:
• A11.1 WriteZero Transaction
• A11.2 WriteDeferrable Transaction
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
182


Chapter A11. Other write transactions
A11.1. WriteZero Transaction
A11.1 WriteZero Transaction
Many writes in a system, particularly from a CPU, have data set to zero. For example, while initializing or
allocating memory. These writes with a zero value consume write data bandwidth and interconnect power that can
be saved by using a data-less request.
The WriteZero transaction is used to write zero values to a cache line sized data location. The transaction consists
of a write request and write response but has no associated write data transfer. It is functionally equivalent to a
regular write to the same location with fully populated data lanes where all data has a value of zero.
The WriteZero_Transaction property is used to indicate whether an interface supports the WriteZero transaction.
Table A11.1: WriteZero_Transaction property
WriteZero_Transaction
Default
Description
True
WriteZero is supported.
False
Y
WriteZero is not supported.
The rules for a WriteZero transaction are:
• A WriteZero request indicates that the data at the locations indicated by address, size, and length attributes
must be set to zero.
• A WriteZero transaction consists of a request on the AW channel and a single response on the B channel.
• A WriteZero transaction is cache line sized and Regular, see A3.1.8 Regular transactions
• AWSNOOP must be 0b0111 or 0b00111.
• AWLOCK must be 0b0, not exclusive access.
• AWTAGOP must be Invalid.
• AWID must be unique-in-flight, which means:
– A WriteZero transaction can only be issued if there are no outstanding write transactions using the same
AWID value.
– A Manager must not issue a request on the write channel with the same AWID as an outstanding
WriteZero transaction.
– If present, AWIDUNQ must be asserted for a WriteZero transaction.
• AWDOMAIN can take any value. If the Domain is Shareable, a WriteZero acts as a WriteUniqueFull with
zero as data.
• A Manager that issues WriteZero requests cannot be connected to a Subordinate that does not support
WriteZero.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
183


Chapter A11. Other write transactions
A11.2. WriteDeferrable Transaction
A11.2 WriteDeferrable Transaction
In enterprise systems, accelerators are commonly used that are accessed across chip-to-chip connections using a
64-byte atomic store operation. These store operations are performed to shared queues within the accelerator. In
some cases, it is possible that the store will not be accepted because the queue is full but might be accepted if
retried later. This type of transaction is known as a WriteDeferrable.
PCIe Gen5 includes support for a deferrable write through the Deferrable Memory Write (DMWr) transaction.
This requires a write response, so the DMWr is a non-posted Write. It is expected that a WriteDeferrable
transaction in AXI translates to a PCIe DMWr transaction.
A11.2.1
WriteDeferrable transaction support
The WriteDeferrable_Transaction property is used to indicate whether an interface supports the WriteDeferrable
transaction.
Table A11.2: WriteDeferrable_Transaction property
WriteDeferrable_Transaction
Default
Description
True
WriteDeferrable is supported.
False
Y
WriteDeferrable is not supported.
A Manager that issues WriteDeferrable requests cannot be connected to a Subordinate that does not support
WriteDeferrable.
A11.2.2
WriteDeferrable signaling
When the WriteDeferrable_Transaction property is True, AWSNOOP and BRESP must be wide enough to
accommodate additional encodings:
• AWSNOOP_WIDTH must be 5.
• BRESP_WIDTH must be 3.
A WriteDeferrable transaction consists of a request, 64-bytes of write data and a write response.
The rules for a WriteDeferrable transaction are:
• AWSNOOP is 0b10000.
• AWDOMAIN is 0b11 (System shareable).
• AWCACHE is Device or Normal Non-cacheable.
• Legal combinations of Length x Size are:
– 1 x 64-bytes
– 2 x 32-bytes
– 4 x 16-bytes
– 8 x 8-bytes
– 16 x 4-bytes
• All bits of WSTRB must be set within the 64-byte container.
• AWADDR is aligned to 64-bytes.
• AWBURST is INCR.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
184


Chapter A11. Other write transactions
A11.2. WriteDeferrable Transaction
• AWLOCK is deasserted, not exclusive access.
• AWATOP is Non-atomic transaction.
• AWTAGOP is Invalid.
• The ID is unique-in-flight for all transactions, which means:
– A WriteDeferrable transaction can only be issued if there are no outstanding transactions on the write
channels with the same ID value.
– A Manager must not issue a request on the write channels with the same ID as an outstanding
WriteDeferrable transaction.
– If present, AWIDUNQ must be asserted for a WriteDeferrable transaction.
• A WriteDeferrable transaction must be treated as 64-byte atomic, therefore:
– It must only be to locations which have a single-copy atomicity size of 64-bytes or greater.
– The request must not be split or merged with other transactions.
A11.2.3
Response to a WriteDeferrable request
Table A11.3 shows the meanings for the response to a WriteDeferrable request.
Table A11.3: WriteDeferrable response meanings
BRESP[2:0]
Response
Indication
0b000
OKAY
The write was accepted by a Subordinate that supports
WriteDeferrable transactions and was successful.
0b001
EXOKAY
Not a permitted response to WriteDeferrable.
0b010
SLVERR
Write has reached an end point but has been unsuccessful.
0b011
DECERR
Write has not reached a point where data can be written.
0b100
DEFER
Write was unsuccessful because it cannot be serviced at
this time but might be successful if resent later. The
location is not updated. This response is only permitted
for a WriteDeferrable transaction.
0b101
TRANSFAULT
Write was terminated because of a translation fault which
might be resolved by a PRI request. This response is only
permitted if AWMMUFLOW is PRI.
0b110
RESERVED
–
0b111
UNSUPPORTED
Write was unsuccessful because the transaction type is
not supported by the target. The location is not updated.
This response is only permitted for a WriteDeferrable
transaction.
If an interconnect detects that a WriteDeferrable is targeting a Subordinate that does not support WriteDeferrable
transactions, it must not propagate the request.
In this case, it is expected that an UNSUPPORTED response is sent, but SLVERR or DECERR are also permitted.
A Subordinate interface that can recognize a WriteDeferrable but cannot process it, has the
WriteDeferrable_Transaction property True but is expected to respond with UNSUPPORTED.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
185
