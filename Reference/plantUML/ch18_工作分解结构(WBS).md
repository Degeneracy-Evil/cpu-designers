# 工作分解结构(WBS)

工作分解结构图（WBS）是一种重要的项目管理工具，可将项目分解为更小、更易于管理的组成部分或
任务。它本质上是对项目团队为完成项目目标和创建所需交付成果而要开展的全部工作范围的分层分解。
PlantUML 对于创建WBS 图表特别有用。它基于文本的图表设计意味着创建和更新WBS 就像编辑
文本文档一样简单，尤其有利于管理项目生命周期内的变更。
此外，PlantUML 与其他各种工具的兼容性也增强了它在协作环境中的实用性。团队可以轻松地将WBS
图表集成到更广泛的项目文档和管理系统中。PlantUML 语法的简洁性允许快速调整，这在项目范围和
任务经常变化的动态项目环境中至关重要。因此，使用PlantUML 绘制WBS 图表，既能实现可视化分
解的清晰度，又能实现基于文本系统的灵活性和控制性，使其成为高效项目管理的宝贵资产。
18.1
OrgMode syntax
This syntax is compatible with OrgMode
@startwbs
* Business Process Modelling WBS
** Launch the project
*** Complete Stakeholder Research
*** Initial Implementation Plan
** Design phase
*** Model of AsIs Processes Completed
**** Model of AsIs Processes Completed1
**** Model of AsIs Processes Completed2
*** Measure AsIs performance metrics
*** Identify Quick Wins
** Complete innovate phase
@endwbs
18.2
Change direction
You can change direction using < and >
@startwbs
* Business Process Modelling WBS
** Launch the project
*** Complete Stakeholder Research
*** Initial Implementation Plan

18.3
Arithmetic notation
18
工作分解结构（WBS）
** Design phase
*** Model of AsIs Processes Completed
****< Model of AsIs Processes Completed1
****> Model of AsIs Processes Completed2
***< Measure AsIs performance metrics
***< Identify Quick Wins
@endwbs
Arithmetic notation
You can use the following notation to choose diagram side.
@startwbs
+ New Job
++ Decide on Job Requirements
+++ Identity gaps
+++ Review JDs
++++ Sign-Up for courses
++++ Volunteer
++++ Reading
++- Checklist
+++- Responsibilities
+++- Location
++ CV Upload Done
+++ CV Updated
++++ Spelling & Grammar
++++ Check dates
---- Skills
+++ Recruitment sites chosen
@endwbs

18.4
Multilines
18
工作分解结构（WBS）
Multilines
You can use : and ; to have multilines box, as on MindMap.
@startwbs
* <&flag> Debian
** <&globe> Ubuntu
***:Linux Mint
Open Source;
*** Kubuntu
*** ...
@endwbs
[Ref. QA-13945]
18.5
Removing box
You can use underscore _ to remove box drawing.

Removing box
18
工作分解结构（WBS）
18.5.1
Boxless on Arithmetic notation
18.5.2
Several boxless node
@startwbs
+ Project
+ Part One
+ Task 1.1
- LeftTask 1.2
+ Task 1.3
+ Part Two
+ Task 2.1
+ Task 2.2
-_ Task 2.2.1 To the left boxless
-_ Task 2.2.2 To the Left boxless
+_ Task 2.2.3 To the right boxless
@endwbs
18.5.3
All boxless node
@startwbs
+_ Project
+_ Part One
+_ Task 1.1
-_ LeftTask 1.2
+_ Task 1.3
+_ Part Two
+_ Task 2.1
+_ Task 2.2
-_ Task 2.2.1 To the left boxless
-_ Task 2.2.2 To the Left boxless
+_ Task 2.2.3 To the right boxless
@endwbs

Removing box
18
工作分解结构（WBS）
18.5.4
Boxless on OrgMode syntax
18.5.5
Several boxless node
@startwbs
* World
** America
***_ Canada
***_ Mexico
***_ USA
** Europe
***_
England
***_
Germany
***_
Spain
@endwbs
[Ref. QA-13297]
18.5.6
All boxless node
@startwbs
*_ World
**_ America
***_ Canada
***_ Mexico
***_ USA
**_ Europe
***_
England
***_
Germany
***_
Spain
@endwbs

18.6
Colors (with inline or style color)
18
工作分解结构（WBS）
[Ref. QA-13355]
Colors (with inline or style color)
It is possible to change node color:
• with inline color
@startwbs
*[#SkyBlue] this is the partner workpackage
**[#pink] this is my workpackage
** this is another workpackage
@endwbs
@startwbs
+[#SkyBlue] this is the partner workpackage
++[#pink] this is my workpackage
++ this is another workpackage
@endwbs
[Ref. QA-12374, only from v1.2020.20]
• with style color
@startwbs
<style>
wbsDiagram {
.pink {
BackgroundColor pink
}
.your_style_name {
BackgroundColor SkyBlue
}
}
</style>
* this is the partner workpackage <<your_style_name>>
** this is my workpackage <<pink>>

18.7
Using style
18
工作分解结构（WBS）
**:This is on multiple
lines; <<pink>>
** this is another workpackage
@endwbs
@startwbs
<style>
wbsDiagram {
.pink {
BackgroundColor pink
}
.your_style_name {
BackgroundColor SkyBlue
}
}
</style>
+ this is the partner workpackage <<your_style_name>>
++ this is my workpackage <<pink>>
++:This is on multiple
lines; <<pink>>
++ this is another workpackage
@endwbs
Using style
It is possible to change diagram style.
@startwbs
<style>
wbsDiagram {
// all lines (meaning connector and borders, there are no other lines in WBS) are black by default
Linecolor black
arrow {
// note that connector are actually "arrow" even if they don't look like as arrow
// This is to be consistent with other UML diagrams. Not 100% sure that it's a good idea
// So now connector are green
LineColor green
}
:depth(0) {
// will target root node
BackgroundColor White
RoundCorner 10
LineColor red
// Because we are targetting depth(0) for everything, border and connector for level 0 will be

18.8
Word Wrap
18
工作分解结构（WBS）
}
arrow {
:depth(2) {
// Targetting only connector between Mexico-Chihuahua and USA-Texas
LineColor blue
LineStyle 4
LineThickness .5
}
}
node {
:depth(2) {
LineStyle 2
LineThickness 2.5
}
}
boxless {
// will target boxless node with '_'
FontColor darkgreen
}
}
</style>
* World
** America
*** Canada
*** Mexico
**** Chihuahua
*** USA
**** Texas
***< New York
** Europe
***_
England
***_
Germany
***_
Spain
@endwbs
Word Wrap
Using MaximumWidth setting you can control automatic word wrap. Unit used is pixel.

Word Wrap
18
工作分解结构（WBS）
@startwbs
<style>
node {
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
**** but it could be cool if PlantUML was able to split long lines, maybe with an option who specify
@endwbs

18.9
Add arrows between WBS elements
18
工作分解结构（WBS）
Add arrows between WBS elements
You can add arrows between WBS elements.
Using alias with as:
@startwbs
<style>
.foo {
LineColor #00FF00;
}
</style>
* Test
** A topic
*** "common" as c1
*** "common2" as c2
** "Another topic" as t2
t2 -> c1 <<foo>>
t2 ..> c2 #blue
@endwbs
Using alias in parentheses:
@startwbs
* Test

18.10
Creole on WBS diagram
18
工作分解结构（WBS）
**(b) A topic
***(c1) common
**(t2) Another topic
t2 --> c1
b -> t2 #blue
@endwbs
[Ref. QA-16251]
Creole on WBS diagram
You can use Creole or HTML Creole on WBS:
@startwbs
* Creole on WBS
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
**:==Creole line
You can have horizontal line
----
Or double line
====
Or strong line
____
Or dotted line

Creole on WBS diagram
18
工作分解结构（WBS）
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
# Third item
;
@endwbs