# 思维导图(MindMap)

在PlantUML 中，MindMap 图表是头脑风暴、组织想法和项目规划的有效工具。MindMap 图表或
思维导图是信息的可视化表示，其中的中心思想分支成相关主题，形成一个概念的蜘蛛网。PlantUML
以其简单、基于文本的语法为创建这些图表提供了便利，从而可以高效地组织复杂的想法并将其可视化。
使用PlantUML 绘制MindMaps 尤为有利，因为它可以与其他工具和系统集成。这种集成简化了将思维
导图纳入大型项目文档的过程。PlantUML 基于文本的方法还能轻松修改和控制思维导图的版本，使其
成为协作式头脑风暴和创意开发的动态工具。
PlantUML 中的思维导图可用于各种目的，从勾勒项目结构到头脑风暴产品功能或业务战略。思维导图
的分层和直观布局有助于识别不同想法和概念之间的关系，从而更容易纵观全局，找出需要进一步探索
的领域。这使得PlantUML 成为项目经理、开发人员和业务分析人员的宝贵工具，他们需要用这种方法
直观地组织复杂信息，并以简洁明了的方式呈现出来。
17.1
OrgMode 语法
同时兼容OrgMode 语法。
@startmindmap
* Debian
** Ubuntu
*** Linux Mint
*** Kubuntu
*** Lubuntu
*** KDE Neon
** LMDE
** SolydXK
** SteamOS
** Raspbian with a very long name
*** <s>Raspmbc</s> => OSMC
*** <s>Raspyfi</s> => Volumio
@endmindmap
17.2
Markdown 语法
同时兼容Markdown 语法。
@startmindmap

17.3
运算符
17
MINDMAP
* root node
* some first level node
* second level node
* another second level node
* another first level node
@endmindmap
运算符
你可以使用下面的运算符来决定图形方向。
@startmindmap
+ OS
++ Ubuntu
+++ Linux Mint
+++ Kubuntu
+++ Lubuntu
+++ KDE Neon
++ LMDE
++ SolydXK
++ SteamOS
++ Raspbian
-- Windows 95
-- Windows 98
-- Windows NT
--- Windows 8
--- Windows 10
@endmindmap

17.4
多行表示
17
MINDMAP
多行表示
你可以用: 和; 包围文字，来表示多行文本.
@startmindmap
* Class Templates
**:Example 1
<code>
template <typename T>
class cname{
void f1()<U+003B>
...
}
</code>
;
**:Example 2
<code>
other template <typename T>
class cname{
...
</code>
;
@endmindmap
@startmindmap
+ root
**:right_1.1
right_1.2;
++ right_2
left side
-- left_1
-- left_2
**:left_3.1
left_3.2;
@endmindmap

17.5
Multiroot Mindmap
17
MINDMAP
Multiroot Mindmap
You can create multiroot mindmap, as:
@startmindmap
* Root 1
** Foo
** Bar
* Root 2
** Lorem
** Ipsum
@endmindmap
[Ref. QH-773]
17.6
Colors
It is possible to change node color.
17.6.1
With inline color
• OrgMode syntax mindmap
@startmindmap
*[#Orange] Colors
**[#lightgreen] Green
**[#FFBBCC] Rose
**[#lightblue] Blue
@endmindmap

Colors
17
MINDMAP
• Arithmetic notation syntax mindmap
@startmindmap
+[#Orange] Colors
++[#lightgreen] Green
++[#FFBBCC] Rose
--[#lightblue] Blue
@endmindmap
• Markdown syntax mindmap
@startmindmap
*[#Orange] root node
*[#lightgreen] some first level node
*[#FFBBCC] second level node
*[#lightblue] another second level node
*[#lightgreen] another first level node
@endmindmap
17.6.2
With style color
• OrgMode syntax mindmap
@startmindmap
<style>
mindmapDiagram {
.green {
BackgroundColor lightgreen
}
.rose {
BackgroundColor #FFBBCC
}

Colors
17
MINDMAP
.your_style_name {
BackgroundColor lightblue
}
}
</style>
* Colors
** Green <<green>>
** Rose <<rose>>
** Blue <<your_style_name>>
@endmindmap
• Arithmetic notation syntax mindmap
@startmindmap
<style>
mindmapDiagram {
.green {
BackgroundColor lightgreen
}
.rose {
BackgroundColor #FFBBCC
}
.your_style_name {
BackgroundColor lightblue
}
}
</style>
+ Colors
++ Green <<green>>
++ Rose <<rose>>
-- Blue <<your_style_name>>
@endmindmap
• Markdown syntax mindmap
@startmindmap
<style>
mindmapDiagram {
.green {
BackgroundColor lightgreen
}
.rose {

17.7
移除方框
17
MINDMAP
BackgroundColor #FFBBCC
}
.your_style_name {
BackgroundColor lightblue
}
}
</style>
* root node
* some first level node <<green>>
* second level node <<rose>>
* another second level node <<your_style_name>>
* another first level node <<green>>
@endmindmap
• Apply style to a branch
@startmindmap
<style>
mindmapDiagram {
.myStyle * {
BackgroundColor lightgreen
}
}
</style>
+ root
++ b1 <<myStyle>>
+++ b11
+++ b12
++ b2
@endmindmap
[Ref. GA-920]
移除方框
你可以用下划线移除方框图。
@startmindmap
* root node
** some first level node
***_ second level node

17.8
改变图形方向
17
MINDMAP
***_ another second level node
***_ foo
***_ bar
***_ foobar
** another first level node
@endmindmap
@startmindmap
*_ root node
**_ some first level node
***_ second level node
***_ another second level node
***_ foo
***_ bar
***_ foobar
**_ another first level node
@endmindmap
@startmindmap
+ root node
++ some first level node
+++_ second level node
+++_ another second level node
+++_ foo
+++_ bar
+++_ foobar
++_ another first level node
-- some first right level node
--_ another first right level node
@endmindmap
改变图形方向
你可以同时使用图形的左右两侧。
@startmindmap

17.9
Change (whole) diagram orientation
17
MINDMAP
* count
** 100
*** 101
*** 102
** 200
left side
** A
*** AA
*** AB
** B
@endmindmap
Change (whole) diagram orientation
You can change (whole) diagram orientation with:
• left to right direction (by default)
• top to bottom direction
• right to left direction
• bottom to top direction (not yet implemented/issue then use workaround)
17.9.1
Left to right direction (by default)
@startmindmap
* 1
** 2
*** 4
*** 5
** 3
*** 6
*** 7
@endmindmap

Change (whole) diagram orientation
17
MINDMAP
17.9.2
Top to bottom direction
@startmindmap
top to bottom direction
* 1
** 2
*** 4
*** 5
** 3
*** 6
*** 7
@endmindmap
17.9.3
Right to left direction
@startmindmap
right to left direction
* 1
** 2
*** 4
*** 5
** 3
*** 6
*** 7
@endmindmap
17.9.4
Bottom to top direction
@startmindmap
top to bottom direction
left side
* 1
** 2
*** 4
*** 5
** 3

17.10
完整示例
17
MINDMAP
*** 6
*** 7
@endmindmap
[Ref. QH-1413]
完整示例
@startmindmap
caption figure 1
title My super title
* <&flag>Debian
** <&globe>Ubuntu
*** Linux Mint
*** Kubuntu
*** Lubuntu
*** KDE Neon
** <&graph>LMDE
** <&pulse>SolydXK
** <&people>SteamOS
** <&star>Raspbian with a very long name
*** <s>Raspmbc</s> => OSMC
*** <s>Raspyfi</s> => Volumio
header
My super header
endheader
center footer My super footer
legend right
Short
legend
endlegend
@endmindmap

17.11
改变风格
17
MINDMAP
改变风格
17.11.1
节点、深度
@startmindmap
<style>
mindmapDiagram {
node {
BackgroundColor lightGreen
}
:depth(1) {
BackGroundColor white
}
}
</style>
* Linux
** NixOS
** Debian
*** Ubuntu
**** Linux Mint
**** Kubuntu
**** Lubuntu
**** KDE Neon
@endmindmap

17.12
Word Wrap
17
MINDMAP
17.11.2
无盒
@startmindmap
<style>
mindmapDiagram {
node {
BackgroundColor lightGreen
}
boxless {
FontColor darkgreen
}
}
</style>
* Linux
** NixOS
** Debian
***_ Ubuntu
**** Linux Mint
**** Kubuntu
**** Lubuntu
**** KDE Neon
@endmindmap
Word Wrap
使用MaximumWidth 设置，你可以控制自动换字。使用的单位是像素。
@startmindmap
<style>
node {

17.13
Creole on Mindmap diagram
17
MINDMAP
Padding 12
Margin 3
HorizontalAlignment center
LineColor blue
LineThickness 3.0
BackgroundColor gold
RoundCorner 40
MaximumWidth 100
}
rootNode {
LineStyle 8.0;3.0
LineColor red
BackgroundColor white
LineThickness 1.0
RoundCorner 0
Shadowing 0.0
}
leafNode {
LineColor gold
RoundCorner 0
Padding 3
}
arrow {
LineStyle 4
LineThickness 0.5
LineColor green
}
</style>
* Hi =)
** sometimes i have node in wich i want to write a long text
*** this results in really huge diagram
**** of course, i can explicit split with a\nnew line
**** but it could be cool if PlantUML was able to split long lines, maybe with an option
@endmindmap
Creole on Mindmap diagram
You can use Creole or HTML Creole on Mindmap:
@startmindmap
* Creole on Mindmap

Creole on Mindmap diagram
17
MINDMAP
left side
**:==Creole
This is **bold**
This is //italics//
This is ""monospaced""
This is --stricken-out--
This is __underlined__
This is ~~wave-underlined~~
--test Unicode and icons--
This is <U+221E> long
This is a <&code> icon
Use image : <img:https://plantuml.com/logo3.png>
;
**: <b>HTML Creole
This is <b>bold</b>
This is <i>italics</i>
This is <font:monospaced>monospaced</font>
This is <s>stroked</s>
This is <u>underlined</u>
This is <w>waved</w>
This is <s:green>stroked</s>
This is <u:red>underlined</u>
This is <w:#0000FF>waved</w>
-- other examples --
This is <color:blue>Blue</color>
This is <back:orange>Orange background</back>
This is <size:20>big</size>
;
right side
**:==Creole line
You can have horizontal line
----
Or double line
====
Or strong line
____
Or dotted line
..My title..
Or dotted title
//and title... //
==Title==
Or double-line title
--Another title--
Or single-line title
Enjoy!;
**:==Creole list item
**test list 1**
* Bullet list
* Second item
** Sub item
*** Sub sub item
* Third item
----
**test list 2**
# Numbered list
# Second item
## Sub item
## Another sub item

Creole on Mindmap diagram
17
MINDMAP
# Third item
;
@endmindmap
[Ref. QA-17838]