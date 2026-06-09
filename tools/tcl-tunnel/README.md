# Tcl Tunnel (Vivado Tcl Forwarding Service)

本项目提供一个仅本机可访问的 Python 服务：

- 接收 curl 或其他 HTTP 客户端提交的 Tcl 命令。
- 在持久化 Vivado Tcl 会话中执行命令并同步返回结果。
- 支持会话新建、复用、列表、关闭。
- 同一 session 的多次请求共享同一终端上下文。

服务默认监听 127.0.0.1，不对外网开放。

## 环境要求

- Windows 或 Linux
- Python 3.12+
- 已安装 Vivado，且命令行可调用 `vivado`（Linux/macOS）或 `vivado.bat`（Windows）

会话启动命令：

- **Linux/macOS**: `vivado -mode tcl`
- **Windows**: `%SystemRoot%\\system32\\cmd.exe /k vivado.bat -mode tcl`

## 安装依赖

```powershell
uv sync
```

若你不使用 uv，也可使用 pip：

```powershell
pip install -e .
```

## 启动服务

```powershell
uv run uvicorn main:app --host 127.0.0.1 --port 8000
```

或：

```powershell
uv run python main.py
```

## API 概览

### 1) 创建会话

- 方法: `POST /sessions`
- 成功: `201`

示例：

```powershell
curl -s -X POST http://127.0.0.1:8000/sessions
```

响应示例：

```json
{
  "session_id": "8ce11f4f2f8646f4a5c88a4b3c08c2ce",
  "created_at": "2026-04-27T09:30:00.123456Z"
}
```

### 2) 在会话中执行 Tcl 命令

- 方法: `POST /sessions/{session_id}/execute`
- 成功: `200`
- 请求体字段:
  - `command`: string，必填
  - `timeout_seconds`: number，可选，默认 60

示例：

```powershell
curl -s -X POST http://127.0.0.1:8000/sessions/8ce11f4f2f8646f4a5c88a4b3c08c2ce/execute \
  -H "Content-Type: application/json" \
  -d "{\"command\":\"puts [version]\",\"timeout_seconds\":30}"
```

响应示例：

```json
{
  "session_id": "8ce11f4f2f8646f4a5c88a4b3c08c2ce",
  "output": "Vivado v2023.2 ...",
  "timeout_seconds": 30,
  "executed_at": "2026-04-27T09:31:00.654321Z"
}
```

### 3) 列出会话

- 方法: `GET /sessions`
- 成功: `200`

示例：

```powershell
curl -s http://127.0.0.1:8000/sessions
```

响应示例：

```json
{
  "sessions": [
    {
      "session_id": "8ce11f4f2f8646f4a5c88a4b3c08c2ce",
      "is_alive": true,
      "is_busy": false,
      "last_active_at": "2026-04-27T09:31:00.654321Z"
    }
  ]
}
```

### 4) 关闭会话

- 方法: `DELETE /sessions/{session_id}`
- 成功: `204`

示例：

```powershell
curl -i -X DELETE http://127.0.0.1:8000/sessions/8ce11f4f2f8646f4a5c88a4b3c08c2ce
```

## 错误码约定

- `404`: 会话不存在
- `409`: 会话冲突（同一会话并发执行，触发单会话互斥）
- `504`: 命令执行超时
- `500`: Vivado 进程异常或会话进程异常

## 生命周期与回收策略

- 同一 session 内部请求串行执行，避免 stdin 交叉写入。
- 每次执行命令会注入唯一结束标记，读取到标记后返回结果，不依赖提示符。
- 空闲 30 分钟自动回收会话。
- 服务退出时强制回收全部会话。

## 会话复用验证示例

以下示例用于验证“同一会话跨请求共享同一终端状态”。

1. 创建会话并记录 `session_id`。
2. 第一条命令在 Tcl 中设置变量。
3. 第二条命令读取变量，返回应为同一值。

```powershell
# 1) 创建会话
$resp = curl -s -X POST http://127.0.0.1:8000/sessions | ConvertFrom-Json
$sid = $resp.session_id

# 2) 写变量
curl -s -X POST http://127.0.0.1:8000/sessions/$sid/execute `
  -H "Content-Type: application/json" `
  -d '{"command":"set tunnel_var hello_vivado"}'

# 3) 读变量
curl -s -X POST http://127.0.0.1:8000/sessions/$sid/execute `
  -H "Content-Type: application/json" `
  -d '{"command":"puts $tunnel_var"}'
```

若输出包含 `hello_vivado`，说明会话复用生效。

## 冒烟验证流程

推荐顺序：

1. `POST /sessions` 创建会话。
2. 连续两次 `POST /sessions/{id}/execute`。
3. `GET /sessions` 确认会话状态。
4. `DELETE /sessions/{id}` 关闭会话。

## 并发验证建议

- 两个不同会话并发执行命令，结果应互不污染。
- 同一会话并发执行请求，后来的并发请求应收到 `409`（会话忙）。

## 自动回收验证建议

测试时可临时把代码中的空闲阈值改小（如 30 秒）：

1. 创建会话。
2. 等待超过阈值。
3. 再执行命令，预期 `404`。

## Tcl 命令示例来源

可参考项目中的 [tcl常用命令.md](tcl常用命令.md) 获取常见 Vivado Tcl 命令。
