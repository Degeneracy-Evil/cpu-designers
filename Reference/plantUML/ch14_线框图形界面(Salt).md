# 线框图形界面(Salt)

Salt 是PlantUML 的一个子项目，可帮助您设计图形界面或网页。网站线框或页面示意图或屏幕蓝图.
它在制作图形界面、示意图和蓝图方面非常有用。它有助于将概念结构与视觉设计相统一，强调功能性
而非美观性。
开发人员、设计人员和用户体验专业人员使用Wireframes 将界面元素、导航系统可视化，并促进协作。
Wireframes 是这一流程的核心，可用于各种学科。它们的保真度各不相同，从低细节草图到高细节表
现，对于原型设计和迭代设计至关重要。这一协作过程整合了从业务分析到用户研究等不同的专业知识，
确保最终设计符合业务和用户需求。
14.1
基本部件
一个窗口必须以中括号开头和结尾。接着可以这样定义:
• 按钮用[ 和]。
• 单选按钮用( 和)。
• 复选框用[ 和]。
• 用户文字域用"。
@startsalt
{
Just plain text
[This is my button]
()
Unchecked radio
(X) Checked radio
[]
Unchecked box
[X] Checked box
"Enter text here
"
^This is a droplist^
}
@endsalt
这个工具是用来讨论简单的示例窗口。
14.2
Text area
Here is an attempt to create a text area:
@startsalt
{+
This is a long
text in a textarea
.
"
"
}
@endsalt

14.3
Open, close droplist
14
SALT (WIREFRAME)
Note:
• the dot (.) to fill up vertical space;
• the last line of space ("  ") to make the area wider.
[Ref. QA-14765]
Then you can add scroll bar:
@startsalt
{SI
This is a long
text in a textarea
.
"
"
}
@endsalt
@startsalt
{S-
This is a long
text in a textarea
.
"
"
}
@endsalt
Open, close droplist
You can open a droplist, by adding values enclosed by ^, as:
@startsalt
{
^This is a closed droplist^ |
^This is an open droplist^^ item 1^^ item 2^ |
^This is another open droplist^ item 1^ item 2^
}
@endsalt
[Ref. QA-4184]

14.4
使用表格
14
SALT (WIREFRAME)
使用表格
当在输入关键词{后，会自动建立一个表格
当输入| 说明一个单元格
例子如下
@startsalt
{
Login
| "MyName
"
Password | "****
"
[Cancel] | [
OK
]
}
@endsalt
在启用关键词后，你可以使用以下字符来绘制表格中的线及列:
Symbol
Result
#
显示所有垂直水平线
!
显示所有垂直线
-
显示所有水平线
+
显示外框线
@startsalt
{+
Login
| "MyName
"
Password | "****
"
[Cancel] | [
OK
]
}
@endsalt
14.5
分组框
@startsalt
{^"我的分组框"
用户名| "MyName
"
密码| "****
"
[取消] | [确认]
}
@endsalt
[参见QA-5840]
14.6
使用分隔符
你可以使用几条横线表示分隔符

@startuml

14.7
树形外挂
14
SALT (WIREFRAME)
salt
{
Text1
..
"Some field"
==
Note on usage
~~
Another text
--
[Ok]
}
@enduml
树形外挂
使用树结构，你必须要以{T 进行起始，然后使用+ 定义层次。
@startsalt
{
{T
+ World
++ America
+++ Canada
+++ USA
++++ New York
++++ Boston
+++ Mexico
++ Europe
+++ Italy
+++ Germany
++++ Berlin
++ Africa
}
}
@endsalt
14.8
Tree table [T]
You can combine trees with tables.
@startsalt

Tree table [T]
14
SALT (WIREFRAME)
{
{T
+Region
| Population
| Age
+ World
| 7.13 billion
| 30
++ America
| 964 million
| 30
+++ Canada
| 35 million
| 30
+++ USA
| 319 million
| 30
++++ NYC
| 8 million
| 30
++++ Boston
| 617 thousand
| 30
+++ Mexico
| 117 million
| 30
++ Europe
| 601 million
| 30
+++ Italy
| 61 million
| 30
+++ Germany
| 82 million
| 30
++++ Berlin
| 3 million
| 30
++ Africa
| 1 billion
| 30
}
}
@endsalt
And add lines.
@startsalt
{
..
== with T!
{T!
+Region
| Population
| Age
+ World
| 7.13 billion
| 30
++ America
| 964 million
| 30
}
..
== with T-
{T-
+Region
| Population
| Age
+ World
| 7.13 billion
| 30
++ America
| 964 million
| 30
}
..
== with T+
{T+
+Region
| Population
| Age
+ World
| 7.13 billion
| 30
++ America
| 964 million
| 30
}
..
== with T#
{T#
+Region
| Population
| Age

14.9
Enclosing brackets [{, }]
14
SALT (WIREFRAME)
+ World
| 7.13 billion
| 30
++ America
| 964 million
| 30
}
..
}
@endsalt
[Ref. QA-1265]
Enclosing brackets [{, }]
You can define subelements by opening a new opening bracket.
@startsalt
{
Name
| "
"
Modifiers:
| { (X) public | () default | () private | () protected
[] abstract | [] final
| [] static }
Superclass:
| { "java.lang.Object " | [Browse...] }
}
@endsalt
14.10
添加选项卡
你可以通过{/ 标记增加对应的选项卡。注意：可以使用HTML 代码来增加粗体效果。
@startsalt
{+
{/ <b>General | Fullscreen | Behavior | Saving }
{
{ Open image in: | ^Smart Mode^ }
[X] Smooth images when zoomed
[X] Confirm image deletion
[ ] Show hidden images
}
[Close]
}
@endsalt

14.11
使用菜单
14
SALT (WIREFRAME)
可以定义垂直选项卡，如下:
@startsalt
{+
{/ <b>General
Fullscreen
Behavior
Saving } |
{
{ Open image in: | ^Smart Mode^ }
[X] Smooth images when zoomed
[X] Confirm image deletion
[ ] Show hidden images
[Close]
}
}
@endsalt
使用菜单
你可以使用记号{* 来添加菜单。
@startsalt
{+
{* File | Edit | Source | Refactor }
{/ General | Fullscreen | Behavior | Saving }
{
{ Open image in: | ^Smart Mode^ }
[X] Smooth images when zoomed
[X] Confirm image deletion
[ ] Show hidden images
}
[Close]
}
@endsalt
你也可以打开一个菜单：

14.12
高级表格
14
SALT (WIREFRAME)
@startsalt
{+
{* File | Edit | Source | Refactor
Refactor | New | Open File | - | Close | Close All }
{/ General | Fullscreen | Behavior | Saving }
{
{ Open image in: | ^Smart Mode^ }
[X] Smooth images when zoomed
[X] Confirm image deletion
[ ] Show hidden images
}
[Close]
}
@endsalt
*[Ref. [QA-4184](https://forum.plantuml.net/4184)]*
高级表格
对于表格有两种特殊的标记:
• * 单元格同时具备span 和left 两个属性
• . 是空白单元格
@startsalt
{#
. | Column 2 | Column 3
Row header 1 | value 1 | value 2
Row header 2 | A long cell | *
}
@endsalt
14.13
Scroll Bars [S, SI, S-]
You can use {S notation for scroll bar like in following examples:
• {S: for horizontal and vertical scrollbars
@startsalt
{S
Message
.
.
.
.
}
@endsalt

14.14
Colors
14
SALT (WIREFRAME)
• {SI : for vertical scrollbar only
@startsalt
{SI
Message
.
.
.
.
}
@endsalt
• {S- : for horizontal scrollbar only
@startsalt
{S-
Message
.
.
.
.
}
@endsalt
Colors
It is possible to change text color of widget.
@startsalt
{
<color:Blue>Just plain text
[This is my default button]
[<color:green>This is my green button]
[<color:#9a9a9a>This is my disabled button]
[]
<color:red>Unchecked box
[X] <color:green>Checked box
"Enter text here
"
^This is a droplist^
^<color:#9a9a9a>This is a disabled droplist^
^<color:red>This is a red droplist^
}
@endsalt

14.15
Creole on Salt
14
SALT (WIREFRAME)
[Ref. QA-12177]
Creole on Salt
You can use Creole or HTML Creole on salt:
@startsalt
{{^==Creole
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
}|
{^<b>HTML Creole
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
}|
{^Creole line
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

14.16
Pseudo sprite [«, »]
14
SALT (WIREFRAME)
--Another title--
Or single-line title
Enjoy!
}|
{^Creole list item
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
}|
{^Mix on salt
==<color:Blue>Just plain text
[This is my default button]
[<b><color:green>This is my green button]
[ ---<color:#9a9a9a>This is my disabled button-- ]
[]
<size:20><color:red>Unchecked box
[X] <color:green>Checked box
"//Enter text here//
"
^This is a droplist^
^<color:#9a9a9a>This is a disabled droplist^
^<b><color:red>This is a red droplist^
}}
@endsalt
Pseudo sprite [«, »]
Using << and >> you can define a pseudo-sprite or sprite-like drawing and reusing it latter.
@startsalt
{
[X] checkbox|[] checkbox
() radio | (X) radio
This is a text|[This is my button]|This is another text

14.17
OpenIconic
14
SALT (WIREFRAME)
"A field"|"Another long Field"|[A button]
<<folder
............
.XXXXX......
.X...X......
.XXXXXXXXXX.
.X........X.
.X........X.
.X........X.
.X........X.
.XXXXXXXXXX.
............
>>|<color:blue>other folder|<<folder>>
^Droplist^
}
@endsalt
[Ref. QA-5849]
OpenIconic
OpenIconic is an very nice open source icon set. Those icons have been integrated into the creole parser,
so you can use them out-of-the-box.
You can use the following syntax: <&ICON_NAME>.
@startsalt
{
Login<&person> | "MyName
"
Password<&key> | "****
"
[Cancel <&circle-x>] | [OK <&account-login>]
}
@endsalt
The complete list is available on OpenIconic Website, or you can use the following special diagram:

@startuml
listopeniconic
@enduml

14.18
Add title, header, footer, caption or legend
14
SALT (WIREFRAME)
Add title, header, footer, caption or legend
@startsalt
title My title
header some header
footer some footer
caption This is caption
legend
The legend
end legend
{+
Login
| "MyName
"
Password | "****
"
[Cancel] | [
OK
]
}
@endsalt
(See also: Common commands)

14.19
Zoom, DPI
14
SALT (WIREFRAME)
Zoom, DPI
14.19.1
Whitout zoom (by default)
@startsalt
{
<&person> Login
| "MyName
"
<&key> Password
| "****
"
[<&circle-x> Cancel ] | [ <&account-login> OK
]
}
@endsalt
14.19.2
Scale
You can use the scale command to zoom the generated image.
You can use either a number or a fraction to define the scale factor. You can also specify either width
or height (in pixel). And you can also give both width and height: the image is scaled to fit inside the
specified dimension.
@startsalt
scale 2
{
<&person> Login
| "MyName
"
<&key> Password
| "****
"
[<&circle-x> Cancel ] | [ <&account-login> OK
]
}
@endsalt
(See also: Zoom on Common commands)
14.19.3
DPI
You can also use the skinparam dpicommand to zoom the generated image.
@startsalt
skinparam dpi 200
{
<&person> Login
| "MyName
"
<&key> Password
| "****
"
[<&circle-x> Cancel ] | [ <&account-login> OK
]
}
@endsalt

14.20
Include Salt ”on activity diagram”
14
SALT (WIREFRAME)
Include Salt ”on activity diagram”
You can read the following explanation.

@startuml
(*) --> "
{{
salt
{+
<b>an example
choose one option
()one
()two
[ok]
}
}}
" as choose
choose -right-> "
{{
salt
{+
<b>please wait
operation in progress
<&clock>
[cancel]
}
}}
" as wait
wait -right-> "
{{
salt
{+
<b>success
congratulations!
[ok]
}
}}
" as success
wait -down-> "
{{
salt
{+
<b>error
failed, sorry
[ok]
}
}}
"

Include Salt ”on activity diagram”
14
SALT (WIREFRAME)
@enduml
It can also be combined with define macro.

@startuml
!unquoted procedure SALT($x)
"{{
salt
%invoke_procedure("_"+$x)
}}" as $x
!endprocedure
!procedure _choose()
{+
<b>an example
choose one option
()one
()two
[ok]
}
!endprocedure
!procedure _wait()
{+
<b>please wait
operation in progress
<&clock>
[cancel]
}
!endprocedure
!procedure _success()
{+
<b>success
congratulations!
[ok]
}
!endprocedure
!procedure _error()
{+
<b>error

14.21
Include salt ”on while condition of activity diagram”
14
SALT (WIREFRAME)
failed, sorry
[ok]
}
!endprocedure
(*) --> SALT(choose)
-right-> SALT(wait)
wait -right-> SALT(success)
wait -down-> SALT(error)
@enduml
Include salt ”on while condition of activity diagram”
You can include salt on while condition of activity diagram.

@startuml
start
while (\n{{\nsalt\n{+\nPassword | "****
"\n[Cancel] | [
OK
]}\n}}\n) is (Incorrect)
:log attempt;
:attempt_count++;
if (attempt_count > 4) then (yes)
:increase delay timer;
:wait for timer to expire;
else (no)
endif
endwhile (correct)
:log request;
:disable service;
@enduml

14.22
Include salt ”on repeat while condition of activity diagram”
14
SALT (WIREFRAME)
[Ref. QA-8547]
Include salt ”on repeat while condition of activity diagram”
You can include salt on ’repeat while’ condition of activity diagram.

@startuml
start
repeat :read data;
:generate diagrams;
repeat while (\n{{\nsalt\n{^"Next step"\n
Do you want to continue? \n[Yes]|[No]\n}\n}}\n)
stop
@enduml

14.23
Skinparam
14
SALT (WIREFRAME)
[Ref. QA-14287]
Skinparam
You can use [only] some skinparam command to change the skin of the drawing.
Some example:
@startsalt
skinparam Backgroundcolor palegreen
{+
Login
| "MyName
"
Password | "****
"
[Cancel] | [
OK
]
}
@endsalt
@startsalt
skinparam handwritten true
{+
Login
| "MyName
"
Password | "****
"
[Cancel] | [
OK
]
}
@endsalt
TODO: FIXME ￿FYI, some other skinparam does not work with salt, as:
@startsalt
skinparam defaultFontName monospaced
{+
Login
| "MyName
"
Password | "****
"
[Cancel] | [
OK
]
}
@endsalt

14.24
Style
14
SALT (WIREFRAME)
Style
You can use [only] some style command to change the skin of the drawing.
Some example:
@startsalt
<style>
saltDiagram {
BackgroundColor palegreen
}
</style>
{+
Login
| "MyName
"
Password | "****
"
[Cancel] | [
OK
]
}
@endsalt
TODO: FIXME ￿FYI, some other style does not work with salt, as:
@startsalt
<style>
saltDiagram {
Fontname Monospaced
FontSize 10
FontStyle italic
LineThickness 0.5
LineColor red
}
</style>
{+
Login
| "MyName
"
Password | "****
"
[Cancel] | [
OK
]
}
@endsalt
[Ref. QA-13460]