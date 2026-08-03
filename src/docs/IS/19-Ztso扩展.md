## 第19章 "Ztso"全存储排序扩展，版本1.0

本章定义了RISC-V全存储排序（RVTSO）内存一致性模型的"Ztso"扩展。RVTSO定义为相对于RVWMO（在第18.1节中定义）的增量。

**评论：**_Ztso扩展旨在促进最初为x86或SPARC架构编写的代码的移植，这两种架构默认都使用TSO。它还支持固有地提供RVTSO行为并希望向软件公开这一事实的实现。_

RVTSO对RVWMO进行以下调整：

- 所有加载操作的行为如同它们具有acquire-RCpc注解

- 所有存储操作的行为如同它们具有release-RCpc注解

- 所有AMO的行为如同它们同时具有acquire-RCsc和release-RCsc注解

**评论：**_这些规则使除规则4-7之外的所有PPO规则变得冗余。它们还使任何未同时设置PW和SR的非I/O fence变得冗余。最后，它们还意味着没有任何内存操作会在任一方向上被重新排序越过AMO。_

**评论：**_在RVTSO上下文中，与RVWMO一样，存储排序注解由PPO规则5-7简洁且完整地定义。在这两种内存模型中，是第18.1.4.1节允许hart将值从其存储缓冲区转发到后续（按程序顺序）的加载——也就是说，存储可以在对其他hart可见之前在本地转发。_

此外，如果实现了Ztso扩展，则V扩展和Zve系列扩展中的向量内存指令在指令级别遵循RVTSO。Ztso扩展不会加强指令内元素访问的排序。

尽管Ztso没有向ISA添加新指令，但假定RVTSO编写的代码在不支持Ztso的实现上不会正确运行。编译为仅在Ztso下运行的二进制文件应通过二进制文件中的标志来指示这一点，以便不实现Ztso的平台可以简单地拒绝运行它们。

The RISC-V Instruction Set Manual, Volume I | © RISC-V International

20.1. Pseudocode for instruction semantics | Page 97
