# B3 Summary of ID constraints

Chapter B3
Summary of ID constraints
This appendix is a summary of ID usage constraints in this document.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
304


Chapter B3. Summary of ID constraints
Must use an ID that is unique in-flight on the same channels:
• Atomic transactions
• Prefetch transactions
• WriteZero transactions
• WriteDeferrable transactions
• InvalidateHint transactions
• Read transactions with data chunking enabled
• Transactions which transport MTE tags
• UnstashTranslation transactions
• ACT transactions
Must not use the same ID for in-flight transactions on the same channels:
• DVM Complete and non-DVM Complete transactions
• StashOnce and non-StashOnce transactions
• Translated and untranslated transactions
• StashTranslation and non-StashTranslation transactions
Must use the same ID:
• Multiple outstanding requests that require ordering between them.
• Transactions in an exclusive access pair.
ARM IHI 0022
Issue L
Copyright © 2003-2025 Arm Limited or its affiliates. All rights reserved.
Non-confidential
305
