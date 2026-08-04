# 外观参数(Skinparam)

你可以使用skinparam 命令更改绘图中的颜色和字体。
示例：
skinparam backgroundColor transparent
重要：skinparam 正在逐步被汰换，请参阅问题#1464 中的评论。对于简单情况（以及为了向后兼容性），
它仍得到支持，但用户应迁移到支持更复杂场景的样式(方式)。
24.1
使用
你可以（以以下方式）使用本命令：
• 在图(diagram) 的定义中，和其他命令类似
• 在一个包含文件中
• 在一个配置文件中，提供给命令行或者ANT 任务使用。
￿blockquote￿￿You can use this command : * In the diagram definition, like any other commands, * In an
included file, * In a configuration file, provided in the command line or the ANT task. ￿blockquote￿￿
24.2
内嵌
为了避免重复(xxxx 的部分），允许内嵌（相关的）定义。
因此，如下的定义：
￿blockquote￿￿To avoid repetition, it is possible to nest definition. So the following definition : ￿blockquote￿￿
skinparam xxxxParam1 value1
skinparam xxxxParam2 value2
skinparam xxxxParam3 value3
skinparam xxxxParam4 value4
严格等价于: ￿blockquote￿￿is strictly equivalent to: ￿blockquote￿￿
skinparam xxxx {
Param1 value1
Param2 value2
Param3 value3
Param4 value4
}
24.3
黑白(Black and White)
你可以强制使用黑白输出格式，通过skinparam monochrome true 命令。￿blockquote￿￿You can force
the use of a black&white output using skinparam monochrome true command. ￿blockquote￿￿

@startuml
skinparam monochrome true
actor User
participant "First Class" as A
participant "Second Class" as B
participant "Last Class" as C
User -> A: DoWork
activate A
A -> B: Create Request
activate B

24.4
阴影
24
SKINPARAM 命令
B -> C: DoWork
activate C
C --> B: WorkDone
destroy C
B --> A: Request Created
deactivate B
A --> User: Done
deactivate A
@enduml
阴影
你可以通过使用skinparam shadowing false 命令来禁用阴影效果.

@startuml
left to right direction
skinparam shadowing<<no_shadow>> false
skinparam shadowing<<with_shadow>> true
actor User
(Glowing use case) <<with_shadow>> as guc
(Flat use case) <<no_shadow>> as fuc
User -- guc
User -- fuc
@enduml

24.5
颜色翻转(Reverse colors)
24
SKINPARAM 命令
颜色翻转(Reverse colors)
可以通过skinparam monochrome reverse 命令，强制使用黑和白的输出，在黑色背景的环境下，尤其
适用。
￿blockquote￿￿You can force the use of a black&white output using skinparam monochrome reverse
command. This can be useful for black background environment. ￿blockquote￿￿

@startuml
skinparam monochrome reverse
actor User
participant "First Class" as A
participant "Second Class" as B
participant "Last Class" as C
User -> A: DoWork
activate A
A -> B: Create Request
activate B
B -> C: DoWork
activate C
C --> B: WorkDone
destroy C
B --> A: Request Created
deactivate B
A --> User: Done
deactivate A
@enduml
24.6
颜色(Colors)
你可以使用标准颜色名称或者RGB 码
￿blockquote￿￿You can use either standard color name or RGB code. ￿blockquote￿￿

24.7
字体颜色、名称、大小(Font color, name and size)
24
SKINPARAM 命令

@startuml
colors
@enduml
transparent 只能用于图片背景
￿blockquote￿￿transparent can only be used for background of the image. ￿blockquote￿￿
字体颜色、名称、大小(Font color, name and size)
可以通过使用xxxFontColor, xxxFontSize , xxxFontName 三个参数，来修改绘图中的字体(颜色、大
小、名称）。
￿blockquote￿￿You can change the font for the drawing using xxxFontColor, xxxFontSize and xxxFontName
parameters. ￿blockquote￿￿
示例:
skinparam classFontColor red
skinparam classFontSize 10
skinparam classFontName Aapex
也可以使用skinparam defaultFontName 命令, 来修改默认的字体。
￿blockquote￿￿You can also change the default font for all fonts using skinparam defaultFontName.
￿blockquote￿￿
Example:
skinparam defaultFontName Aapex
请注意：字体名称高度依赖于操作系统，因此不要过度使用它，当你考虑到可移植性时。Helvetica and
Courier 应该是全平台可用。
￿blockquote￿￿Please note the fontname is highly system dependent, so do not over use it, if you look for
portability. Helvetica and Courier should be available on all system. ￿blockquote￿￿
还有更多的参数可用，你可以通过下面的命令打印它们：
java -jar plantuml.jar -language
￿blockquote￿￿A lot of parameters are available. You can list them using the following command: java
-jar plantuml.jar -language ￿blockquote￿￿

24.8
文本对齐(Text Alignment)
24
SKINPARAM 命令
文本对齐(Text Alignment)
通过left, right or center, 可以设置文本对齐.
也可以sequenceMessageAlign 指令赋值为direction 或reverseDirection 以便让文本对齐与箭头方
向一致。
￿blockquote￿￿Text alignment can be set up to left, right or center. You can also use direction or
reverseDirection values for sequenceMessageAlign which align text depending on arrow direction.
￿blockquote￿￿
Param name
Default value
Comment
sequenceMessageAlign
left
用于时序图中的消息(message)
sequenceReferenceAlign
center
在时序图中用于ref over

@startuml
skinparam sequenceMessageAlign center
Alice -> Bob : Hi
Alice -> Bob : This is very long
@enduml
24.9
Examples

@startuml
skinparam backgroundColor #EEEBDC
skinparam handwritten true
skinparam sequence {
ArrowColor DeepSkyBlue
ActorBorderColor DeepSkyBlue
LifeLineBorderColor blue
LifeLineBackgroundColor #A9DCDF
ParticipantBorderColor DeepSkyBlue
ParticipantBackgroundColor DodgerBlue
ParticipantFontName Impact
ParticipantFontSize 17
ParticipantFontColor #A9DCDF
ActorBackgroundColor aqua
ActorFontColor DeepSkyBlue
ActorFontSize 17
ActorFontName Aapex
}
actor User
participant "First Class" as A
participant "Second Class" as B
participant "Last Class" as C
User -> A: DoWork
activate A

Examples
24
SKINPARAM 命令
A -> B: Create Request
activate B
B -> C: DoWork
activate C
C --> B: WorkDone
destroy C
B --> A: Request Created
deactivate B
A --> User: Done
deactivate A
@enduml

@startuml
skinparam handwritten true
skinparam actor {
BorderColor black
FontName Courier
BackgroundColor<< Human >> Gold
}
skinparam usecase {
BackgroundColor DarkSeaGreen
BorderColor DarkSlateGray
BackgroundColor<< Main >> YellowGreen
BorderColor<< Main >> YellowGreen
ArrowColor Olive
}
User << Human >>
:Main Database: as MySql << Application >>
(Start) << One Shot >>
(Use the application) as (Use) << Main >>

Examples
24
SKINPARAM 命令
User -> (Start)
User --> (Use)
MySql --> (Use)
@enduml

@startuml
skinparam roundcorner 20
skinparam class {
BackgroundColor PaleGreen
ArrowColor SeaGreen
BorderColor SpringGreen
}
skinparam stereotypeCBackgroundColor YellowGreen
Class01 "1" *-- "many" Class02 : contains
Class03 o-- Class04 : aggregation
@enduml

@startuml
skinparam interface {
backgroundColor RosyBrown
borderColor orange
}
skinparam component {
FontSize 13
BackgroundColor<<Apache>> LightCoral
BorderColor<<Apache>> #FF6655
FontName Courier
BorderColor black
BackgroundColor gold
ArrowFontName Impact
ArrowColor #FF6655
ArrowFontColor #777777
}

24.10
所有skinparam 参数列表
24
SKINPARAM 命令
() "Data Access" as DA
[Web Server] << Apache >>
DA - [First Component]
[First Component] ..> () HTTP : use
HTTP - [Web Server]
@enduml

@startuml
[AA] <<static lib>>
[BB] <<shared lib>>
[CC] <<static lib>>
node node1
node node2 <<shared node>>
database Production
skinparam component {
backgroundColor<<static lib>> DarkKhaki
backgroundColor<<shared lib>> Green
}
skinparam node {
borderColor Green
backgroundColor Yellow
backgroundColor<<shared node>> Magenta
}
skinparam databaseBackgroundColor Aqua
@enduml
所有skinparam 参数列表
您可以在命令行中使用-language ，也可以使用如下命令，(通过PlantUML) 生成包含所有skinparam
参数列表的” 图表”：
• help skinparams
• skinparameters

所有skinparam 参数列表
24
SKINPARAM 命令
24.10.1
命令行：-language 命令
由于文档并不总是最新的，您可以使用此命令获得完整的参数列表：
java -jar plantuml.jar -language
24.10.2
(内置) 命令：help skinparams
从页面中，可以得到以下结果（该指令的对应代码为：CommandHelpSkinparam.java）

@startuml
help skinparams
@enduml
24.10.3
命令：皮肤参数

@startuml
skinparameters
@enduml

所有skinparam 参数列表
24
SKINPARAM 命令

所有skinparam 参数列表
24
SKINPARAM 命令
24.10.4
Ashley’s PlantUML Doc 上的所有皮肤参数(Skin Parameters)
您还可以在以下页面查看每个skinparam 参数及其显示的结果
Ashley's PlantUML Doc 中的All Skin Parameters：
• https://plantuml-documentation.readthedocs.io/en/latest/formatting/all-skin-params.html。