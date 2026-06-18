# 实体关系图(ER)

基于信息工程符号。
这是对现有类图的一个扩展。这个扩展增加了：
• 信息工程符号的额外关系。
• 一个映射到类图的entity 别名class 。
• 一个额外的可见性修改器* ，用于识别强制属性。
除此之外，绘制图表的语法与类图相同。类图的所有其他特征也被支持。
See also Chen Entity Relationship Diagrams.
[Ref. GH-31]
20.1
信息工程关系
类型
符号
零或一
|o--
正好一个
||--
零或多
}o--
一个或多个
}|--
例子

@startuml
Entity01 }|..|| Entity02
Entity03 }o..o| Entity04
Entity05 ||--o{ Entity06
Entity07 |o--|| Entity08
@enduml
20.2
实体

@startuml
entity Entity01 {
* identifying_attribute
--
* mandatory_attribute
optional_attribute
}
@enduml
同样，这也是正常的类图语法（除了使用entity ，而不是class ）。你可以在类图中做的任何事情都
可以在这里完成。

20.3
完整的例子
20
实体关系图
* 可见性修饰符可以用来识别强制属性。在修饰符之后可以使用空格，以避免与克里奥尔语的黑体字冲
突。

@startuml
entity Entity01 {
optional attribute
**optional bold attribute**
* **mandatory bold attribute**
}
@enduml
完整的例子

@startuml
' hide the spot
hide circle
' avoid problems with angled crows feet
skinparam linetype ortho
entity "Entity01" as e01 {
*e1_id : number <<generated>>
--
*name : text
description : text
}
entity "Entity02" as e02 {
*e2_id : number <<generated>>
--
*e1_id : number <<FK>>
other_details : text
}
entity "Entity03" as e03 {
*e3_id : number <<generated>>
--
e1_id : number <<FK>>
other_details : text
}
e01 ||..o{ e02
e01 |o..o{ e03
@enduml

完整的例子
20
实体关系图
目前，当鱼尾纹与实体成一定角度绘制时，鱼尾纹看起来不是很好。这可以通过使用linetype ortho
skinparam 来避免。