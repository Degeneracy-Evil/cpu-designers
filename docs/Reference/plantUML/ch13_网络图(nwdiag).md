# 网络图(nwdiag)

网络图是计算机或电信网络的直观表示。它说明了网络组件（包括服务器、路由器、交换机、集线器和
设备）的排列和互连。网络图是网络工程师和管理员了解、设置和排除网络故障的宝贵工具。
nwdiag 由Takeshi Komiya 开发，为快速绘制网络图提供了一个精简的平台。我们对Takeshi 开发的这
一创新工具表示感谢！
由于其直观的语法，nwdiag 已无缝集成到PlantUML 中。这里展示的示例受到了Takeshi 所记录示例
的启发。
13.1
简单图示
13.1.1
定义一个网络

@startuml
nwdiag {
network dmz {
address = "210.x.x.x/24"
}
}
@enduml
13.1.2
定义网络中的一些元素或服务器

@startuml
nwdiag {
network dmz {
address = "210.x.x.x/24"
web01 [address = "210.x.x.1"];
web02 [address = "210.x.x.2"];
}
}
@enduml
13.1.3
完整的例子

@startuml
nwdiag {
network dmz {
address = "210.x.x.x/24"
web01 [address = "210.x.x.1"];
web02 [address = "210.x.x.2"];
}
network internal {
address = "172.x.x.x/24";

13.2
定义多个地址
13
使用NWDIAG 的网络图
web01 [address = "172.x.x.1"];
web02 [address = "172.x.x.2"];
db01;
db02;
}
}
@enduml
定义多个地址

@startuml
nwdiag {
network dmz {
address = "210.x.x.x/24"
// set multiple addresses (using comma)
web01 [address = "210.x.x.1, 210.x.x.20"];
web02 [address = "210.x.x.2"];
}
network internal {
address = "172.x.x.x/24";
web01 [address = "172.x.x.1"];
web02 [address = "172.x.x.2"];
db01;
db02;
}
}
@enduml

13.3
群节点
13
使用NWDIAG 的网络图
群节点
13.3.1
在网络定义中定义组

@startuml
nwdiag {
network Sample_front {
address = "192.168.10.0/24";
// define group
group web {
web01 [address = ".1"];
web02 [address = ".2"];
}
}
network Sample_back {
address = "192.168.20.0/24";
web01 [address = ".1"];
web02 [address = ".2"];
db01 [address = ".101"];
db02 [address = ".102"];
// define network using defined nodes
group db {
db01;
db02;
}
}
}
@enduml
13.3.2
在网络定义之外定义组

@startuml
nwdiag {
// define group outside of network definitions
group {
color = "#FFAAAA";
web01;
web02;
db01;
}
network dmz {

群节点
13
使用NWDIAG 的网络图
web01;
web02;
}
network internal {
web01;
web02;
db01;
db02;
}
}
@enduml
13.3.3
在同一个网络上定义不同的一些组
13.3.4
一个定义了两个组的例子

@startuml
nwdiag {
group {
color = "#FFaaaa";
web01;
db01;
}
group {
color = "#aaaaFF";
web02;
db02;
}
network dmz {
address = "210.x.x.x/24"
web01 [address = "210.x.x.1"];
web02 [address = "210.x.x.2"];
}
network internal {
address = "172.x.x.x/24";
web01 [address = "172.x.x.1"];
web02 [address = "172.x.x.2"];
db01 ;
db02 ;
}
}
@enduml

群节点
13
使用NWDIAG 的网络图
[Ref. QA-12663]
13.3.5
定义了三个组的例子

@startuml
nwdiag {
group {
color = "#FFaaaa";
web01;
db01;
}
group {
color = "#aaFFaa";
web02;
db02;
}
group {
color = "#aaaaFF";
web03;
db03;
}
network dmz {
web01;
web02;
web03;
}
network internal {
web01;
db01 ;
web02;
db02 ;
web03;
db03;
}
}
@enduml

13.4
拓展语法(适用于组或者网络)
13
使用NWDIAG 的网络图
[Ref. QA-13138]
拓展语法(适用于组或者网络)
13.4.1
网络
用于网络或者网络的组成部分，你可以添加或者修改:
• 地址(使用, 来分隔);
• 颜色;
• 描述;
• 形状.

@startuml
nwdiag {
network Sample_front {
address = "192.168.10.0/24"
color = "red"
// define group
group web {
web01 [address = ".1, .2", shape = "node"]
web02 [address = ".2, .3"]
}
}
network Sample_back {
address = "192.168.20.0/24"
color = "palegreen"
web01 [address = ".1"]
web02 [address = ".2"]
db01 [address = ".101", shape = database ]
db02 [address = ".102"]
// define network using defined nodes
group db {
db01;
db02;
}
}
}
@enduml

拓展语法(适用于组或者网络)
13
使用NWDIAG 的网络图
13.4.2
组
对于组，你可以添加或修改:
• 颜色;
• 描述.

@startuml
nwdiag {
group {
color = "#CCFFCC";
description = "Long group description";
web01;
web02;
db01;
}
network dmz {
web01;
web02;
}
network internal {
web01;
web02;
db01 [address = ".101", shape = database];
}
}
@enduml

13.5
Using Sprites
13
使用NWDIAG 的网络图
[Ref. QA-12056]
Using Sprites
You can use all sprites (icons) from the Standard Library or any other library.
Use the notation <$sprite> to use a sprite, \n to make a new line, or any other Creole syntax.

@startuml
!include <office/Servers/application_server>
!include <office/Servers/database_server>
nwdiag {
network dmz {
address = "210.x.x.x/24"
// set multiple addresses (using comma)
web01 [address = "210.x.x.1, 210.x.x.20",
description = "<$application_server>\n web01"]
web02 [address = "210.x.x.2",
description = "<$application_server>\n web02"];
}
network internal {
address = "172.x.x.x/24";
web01 [address = "172.x.x.1"];
web02 [address = "172.x.x.2"];
db01 [address = "172.x.x.100",
description = "<$database_server>\n db01"];
db02 [address = "172.x.x.101",
description = "<$database_server>\n db02"];
}
}
@enduml

13.6
Using OpenIconic
13
使用NWDIAG 的网络图
[Ref. QA-11862]
Using OpenIconic
You can also use the icons from OpenIconic in network or node descriptions.
Use the notation <&icon> to make an icon, <&icon*n> to multiply the size by a factor n, and \n to make
a newline:

@startuml
nwdiag {
group nightly {
color = "#FFAAAA";
description = "<&clock> Restarted nightly <&clock>";
web02;
db01;
}
network dmz {
address = "210.x.x.x/24"
user [description = "<&person*4.5>\n user1"];
// set multiple addresses (using comma)
web01 [address = "210.x.x.1, 210.x.x.20",
description = "<&cog*4>\nweb01"]
web02 [address = "210.x.x.2",
description = "<&cog*4>\nweb02"];
}
network internal {
address = "172.x.x.x/24";
web01 [address = "172.x.x.1"];
web02 [address = "172.x.x.2"];
db01 [address = "172.x.x.100",
description = "<&spreadsheet*4>\n db01"];
db02 [address = "172.x.x.101",
description = "<&spreadsheet*4>\n db02"];
ptr
[address = "172.x.x.110",
description = "<&print*4>\n ptr01"];
}
}
@enduml

13.7
Same nodes on more than two networks
13
使用NWDIAG 的网络图
Same nodes on more than two networks
You can use same nodes on different networks (more than two networks); nwdiag use in this case ’jump
line’ over networks.

@startuml
nwdiag {
// define group at outside network definitions
group {
color = "#7777FF";
web01;
web02;
db01;
}
network dmz {
color = "pink"
web01;
web02;
}
network internal {
web01;
web02;
db01 [shape = database ];
}
network internal2 {
color = "LightBlue";
web01;
web02;
db01;
}
}

13.8
Peer networks
13
使用NWDIAG 的网络图
@enduml
Peer networks
Peer networks are simple connections between two nodes, for which we don’t use a horizontal ”busbar”
network

@startuml
nwdiag {
inet [shape = cloud];
inet -- router;
network {
router;
web01;
web02;
}
}
@enduml
13.9
Peer networks and group
13.9.1
Without group

@startuml
nwdiag {
internet [ shape = cloud];

Peer networks and group
13
使用NWDIAG 的网络图
internet -- router;
network proxy {
router;
app;
}
network default {
app;
db;
}
}
@enduml
13.9.2
Group on first

@startuml
nwdiag {
internet [ shape = cloud];
internet -- router;
group {
color = "pink";
app;
db;
}
network proxy {
router;
app;
}
network default {
app;
db;
}
}

Peer networks and group
13
使用NWDIAG 的网络图
@enduml
13.9.3
Group on second

@startuml
nwdiag {
internet [ shape = cloud];
internet -- router;
network proxy {
router;
app;
}
group {
color = "pink";
app;
db;
}
network default {
app;
db;
}
}
@enduml

Peer networks and group
13
使用NWDIAG 的网络图
13.9.4
Group on third

@startuml
nwdiag {
internet [ shape = cloud];
internet -- router;
network proxy {
router;
app;
}
network default {
app;
db;
}
group {
color = "pink";
app;
db;
}
}
@enduml

13.10
Add title, caption, header, footer or legend on network diagram
13
使用NWDIAG 的网络图
[Ref. Issue#408 and QA-12655]
Add title, caption, header, footer or legend on network diagram

@startuml
header some header
footer some footer
title My title
nwdiag {
network inet {
web01 [shape = cloud]
}
}
legend
The legend
end legend
caption This is caption
@enduml

13.11
With or without shadow
13
使用NWDIAG 的网络图
[Ref. QA-11303 and Common commands]
With or without shadow
13.11.1
With shadow (by default)

@startuml
nwdiag {
network nw {
server;
internet;
}
internet [shape = cloud];
}
@enduml
13.11.2
Without shadow

@startuml
<style>
root {
shadowing 0
}
</style>
nwdiag {
network nw {
server;
internet;
}
internet [shape = cloud];
}
@enduml

13.12
Change width of the networks
13
使用NWDIAG 的网络图
[Ref. QA-14516]
Change width of the networks
You can change the width of the networks, especially in order to have the same full width for only some
or all networks.
Here are some examples, with all the possibilities.
13.12.1
First example
• without

@startuml
nwdiag {
network NETWORK_BASE {
dev_A [address = "dev_A" ]
dev_B [address = "dev_B" ]
}
network IntNET1 {
dev_B [address = "dev_B1" ]
dev_M [address = "dev_M1" ]
}
network IntNET2 {
dev_B [address = "dev_B2" ]
dev_M [address = "dev_M2" ]
}
}
@enduml
• only the first

@startuml
nwdiag {
network NETWORK_BASE {
width = full

Change width of the networks
13
使用NWDIAG 的网络图
dev_A [address = "dev_A" ]
dev_B [address = "dev_B" ]
}
network IntNET1 {
dev_B [address = "dev_B1" ]
dev_M [address = "dev_M1" ]
}
network IntNET2 {
dev_B [address = "dev_B2" ]
dev_M [address = "dev_M2" ]
}
}
@enduml
• the first and the second

@startuml
nwdiag {
network NETWORK_BASE {
width = full
dev_A [address = "dev_A" ]
dev_B [address = "dev_B" ]
}
network IntNET1 {
width = full
dev_B [address = "dev_B1" ]
dev_M [address = "dev_M1" ]
}
network IntNET2 {
dev_B [address = "dev_B2" ]
dev_M [address = "dev_M2" ]
}
}
@enduml

Change width of the networks
13
使用NWDIAG 的网络图
• all the network (with same full width)

@startuml
nwdiag {
network NETWORK_BASE {
width = full
dev_A [address = "dev_A" ]
dev_B [address = "dev_B" ]
}
network IntNET1 {
width = full
dev_B [address = "dev_B1" ]
dev_M [address = "dev_M1" ]
}
network IntNET2 {
width = full
dev_B [address = "dev_B2" ]
dev_M [address = "dev_M2" ]
}
}
@enduml
13.12.2
Second example
• without

Change width of the networks
13
使用NWDIAG 的网络图

@startuml
nwdiag {
e1
network n1 {
e1
e2
e3
}
network n2 {
e3
e4
e5
}
network n3 {
e2
e6
}
}
@enduml
• only the first

@startuml
nwdiag {
e1
network n1 {
width = full
e1
e2
e3
}
network n2 {
e3
e4

Change width of the networks
13
使用NWDIAG 的网络图
e5
}
network n3 {
e2
e6
}
}
@enduml
• the first and the second

@startuml
nwdiag {
e1
network n1 {
width = full
e1
e2
e3
}
network n2 {
width = full
e3
e4
e5
}
network n3 {
e2
e6
}
}
@enduml

Change width of the networks
13
使用NWDIAG 的网络图
• all the network (with same full width)

@startuml
nwdiag {
e1
network n1 {
width = full
e1
e2
e3
}
network n2 {
width = full
e3
e4
e5
}
network n3 {
width = full
e2
e6
}
}
@enduml

13.13
Other internal networks
13
使用NWDIAG 的网络图
Other internal networks
You can define other internal networks (TCP/IP, USB, SERIAL,...).
• Without address or type

@startuml
nwdiag {
network LAN1 {
a [address = "a1"];
}
network LAN2 {
a [address = "a2"];
switch;
}
switch -- equip;
equip -- printer;
}
@enduml

Other internal networks
13
使用NWDIAG 的网络图
• With address or type

@startuml
nwdiag {
network LAN1 {
a [address = "a1"];
}
network LAN2 {
a [address = "a2"];
switch [address = "s2"];
}
switch -- equip;
equip [address = "e3"];
equip -- printer;
printer [address = "USB"];
}
@enduml

13.14
Using (global) style
13
使用NWDIAG 的网络图
[Ref. QA-12824]
Using (global) style
13.14.1
Without style (by default)

@startuml
nwdiag {
network DMZ {
address = "y.x.x.x/24"
web01 [address = "y.x.x.1"];
web02 [address = "y.x.x.2"];
}
network Internal {
web01;
web02;
db01 [address = "w.w.w.z", shape = database];
}
group {
description = "long group label";
web01;
web02;
db01;
}
}
@enduml

Using (global) style
13
使用NWDIAG 的网络图
13.14.2
With style
You can use style to change rendering of elements.

@startuml
<style>
nwdiagDiagram {
network {
BackGroundColor green
LineColor red
LineThickness 1.0
FontSize 18
FontColor navy
}
server {
BackGroundColor pink
LineColor yellow
LineThickness 1.0
' FontXXX only for description or label
FontSize 18
FontColor #blue
}
arrow {
' FontXXX only for address
FontSize 17
FontColor #red
FontName Monospaced
LineColor black
}
group {
BackGroundColor cadetblue
LineColor black
LineThickness 2.0
FontSize 11
FontStyle bold
Margin 5
Padding 5
}
}
</style>
nwdiag {

13.15
Appendix: Test of all shapes on Network diagram (nwdiag)
13
使用NWDIAG 的网络图
network DMZ {
address = "y.x.x.x/24"
web01 [address = "y.x.x.1"];
web02 [address = "y.x.x.2"];
}
network Internal {
web01;
web02;
db01 [address = "w.w.w.z", shape = database];
}
group {
description = "long group label";
web01;
web02;
db01;
}
}
@enduml
[Ref. QA-14479]
Appendix: Test of all shapes on Network diagram (nwdiag)

@startuml
nwdiag {
network Network {
Actor
[shape = actor]
Agent
[shape = agent]
Artifact
[shape = artifact]
Boundary
[shape = boundary]
Card
[shape = card]
Cloud
[shape = cloud]
Collections [shape = collections]
Component
[shape = component]
}
}
@enduml

Appendix: Test of all shapes on Network diagram (nwdiag)
13
使用NWDIAG 的网络图

@startuml
nwdiag {
network Network {
Control
[shape = control]
Database
[shape = database]
Entity
[shape = entity]
File
[shape = file]
Folder
[shape = folder]
Frame
[shape = frame]
Hexagon
[shape = hexagon]
Interface
[shape = interface]
}
}
@enduml

@startuml
nwdiag {
network Network {
Label
[shape = label]
Node
[shape = node]
Package
[shape = package]
Person
[shape = person]
Queue
[shape = queue]
Stack
[shape = stack]
Rectangle
[shape = rectangle]
Storage
[shape = storage]
Usecase
[shape = usecase]
}
}
@enduml
TODO: FIXME ￿ol￿￿￿olli￿level￿0￿￿Overlap of label for folder￿olli￿￿￿olli￿level￿0￿￿Hexagon shape is miss-
ing￿olli￿￿￿ol￿￿

Appendix: Test of all shapes on Network diagram (nwdiag)
13
使用NWDIAG 的网络图

@startuml
nwdiag {
network Network {
Folder [shape = folder]
Hexagon [shape = hexagon]
}
}
@enduml

@startuml
nwdiag {
network Network {
Folder [shape = folder, description = "Test, long long label\nTest, long long label"]
Hexagon [shape = hexagon, description = "Test, long long label\nTest, long long label"]
}
}
@enduml
TODO: FIXME