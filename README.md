# CPU Designers



## 项目结构说明

```txt
example是老师给的课程资料
dev是我们的开发目录
```

## 本项目基础git使用

```bash
# 初始化
git checkout -b <your name> # 创建你自己的branch

# 然后你进行coding...
git add . # 添加文件到暂存区
git commit -m "<这里写你本次代码的摘要>" # commit 修改

# 推送
git checkout <your name> # 确保你现在在自己的分支中
git push origin <your name> # 推送你的开发到你自己的远程分支进行存档
git checkout main # 切换回main
git push origin main # 向main分支进行推送，这会自动的发送一个pr请求，等待管理员手动合并
```

