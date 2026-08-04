# YAML显示效果图

YAML 格式广泛的在软件中使用.
可以使用PlantUML 可视化您的数据.
要激活此功能, 需要:
• 以关键字@startyaml 开始
• 以关键字@endyaml 结束.
@startyaml
fruit: Apple
size: Large
color:
- Red
- Green
@endyaml
12.1
复杂例子
@startyaml
doe: "a deer, a female deer"
ray: "a drop of golden sun"
pi: 3.14159
xmas: true
french-hens: 3
calling-birds:
- huey
- dewey
- louie
- fred
xmas-fifth-day:
calling-birds: four
french-hens: 3
golden-rings: 5
partridges:
count: 1
location: "a pear tree"
turtle-doves: two
@endyaml

12.2
特定的key (使用symbols 或者unicode)
12
YAML 显示效果图
特定的key (使用symbols 或者unicode)
@startyaml
@fruit: Apple
$size: Large
&color: Red
￿: Heart
‰: Per mille
@endyaml
[Ref. QA-13376]
12.3
强调
12.3.1
正常样式
@startyaml
#highlight "french-hens"
#highlight "xmas-fifth-day" / "partridges"
doe: "a deer, a female deer"
ray: "a drop of golden sun"
pi: 3.14159
xmas: true
french-hens: 3
calling-birds:
- huey
- dewey
- louie
- fred
xmas-fifth-day:
calling-birds: four
french-hens: 3
golden-rings: 5
partridges:
count: 1
location: "a pear tree"
turtle-doves: two

强调
12
YAML 显示效果图
@endyaml
12.3.2
自定义样式
@startyaml
<style>
yamlDiagram {
highlight {
BackGroundColor red
FontColor white
FontStyle italic
}
}
</style>
#highlight "french-hens"
#highlight "xmas-fifth-day" / "partridges"
doe: "a deer, a female deer"
ray: "a drop of golden sun"
pi: 3.14159
xmas: true
french-hens: 3
calling-birds:
- huey
- dewey
- louie
- fred
xmas-fifth-day:
calling-birds: four
french-hens: 3
golden-rings: 5
partridges:
count: 1
location: "a pear tree"
turtle-doves: two
@endyaml

12.4
Using different styles for highlight
12
YAML 显示效果图
[Ref. QA-13288]
Using different styles for highlight
It is possible to have different styles for different highlights.
@startyaml
<style>
.h1 {
BackGroundColor green
FontColor white
FontStyle italic
}
.h2 {
BackGroundColor red
FontColor white
FontStyle italic
}
</style>
#highlight "french-hens" <<h1>>
#highlight "xmas-fifth-day" / "partridges" <<h2>>
doe: "a deer, a female deer"
ray: "a drop of golden sun"
pi: 3.14159
xmas: true
french-hens: 3
calling-birds:
- huey
- dewey
- louie
- fred
xmas-fifth-day:
calling-birds: four
french-hens: 3
golden-rings: 5
partridges:
count: 1
location: "a pear tree"
turtle-doves: two
@endyaml

12.5
使用(global) 全局样式
12
YAML 显示效果图
[Ref. QA-15756, GH-1393]
使用(global) 全局样式
12.5.1
不带样式(默认)
@startyaml
-
name: Mark McGwire
hr:
65
avg:
0.278
-
name: Sammy Sosa
hr:
63
avg:
0.288
@endyaml
12.5.2
使用样式
您可以使用style 更改元素的显示.
@startyaml
<style>
yamlDiagram {
node {
BackGroundColor lightblue
LineColor lightblue
FontName Helvetica
FontColor red
FontSize 18
FontStyle bold
BackGroundColor Khaki
RoundCorner 0
LineThickness 2
LineStyle 10-5
separator {
LineThickness 0.5

12.6
Creole on YAML
12
YAML 显示效果图
LineColor black
LineStyle 1-5
}
}
arrow {
BackGroundColor lightblue
LineColor green
LineThickness 2
LineStyle 2-5
}
}
</style>
-
name: Mark McGwire
hr:
65
avg:
-
name: Sammy Sosa
hr:
63
avg:
@endyaml
[Ref. QA-13123]
Creole on YAML
You can use Creole or HTML Creole on YAML diagram:
@startyaml
Creole:
wave: ~~wave~~
bold: **bold**
italics: //italics//
monospaced: ""monospaced""
stricken-out: --stricken-out--
underlined: __underlined__
not-underlined: ~__not underlined__
wave-underlined: ~~wave-underlined~~
HTML Creole:
bold: <b>bold
italics: <i>italics
monospaced: <font:monospaced>monospaced
stroked: <s>stroked
underlined: <u>underlined
waved: <w>waved
green-stroked: <s:green>stroked
red-underlined: <u:red>underlined
blue-waved: <w:#0000FF>waved
Blue: <color:blue>Blue

Creole on YAML
12
YAML 显示效果图
Orange: <back:orange>Orange background
big: <size:20>big
Graphic:
OpenIconic: account-login <&account-login>
Unicode: This is <U+221E> long
Emoji: <:calendar:> Calendar
Image: <img:https://plantuml.com/logo3.png>
@endyaml