# 静态门禁（Static Gates）

本仓库大量逻辑以 Shell 脚本形式存在（安装、诊断、网络测试、订阅刷新等）。为了尽量在**提交之前**发现“会卡住 / 会误退 / 会污染 JSON 输出”的高风险点，我们提供一组轻量的静态门禁脚本。

## 一键运行

在仓库根目录：

- `bash script/run_static_gates.sh`

该脚本会以 strict 模式依次执行以下门禁：

1. `script/audit_curl_blocks.py`：curl 归并块审计（多行 `\` 续行归并）
2. `script/audit_errexit_arith.py`：`set -e` 下 `((var++)) / ((var--))` 陷阱审计
3. `script/audit_json_stdout_purity.py`：JSON 模式 stdout 纯 JSON 污染源审计

通过条件：所有审计器 `high=0`（strict 模式下遇到 high 会退出非 0）。

## 门禁 1：curl 归并块审计

脚本：`script/audit_curl_blocks.py`

重点检查：

- **缺少总超时**：`--max-time/-m` 或 `timeout N curl` 包裹
- **缺少 connect-timeout**：不是致命，但能显著降低 DNS/TCP 卡住的体感
- webhook/通知 POST：无超时属于高风险（容易卡死主流程）
- `curl | jq` 在 `pipefail` 下无 guard：可能导致脚本非预期退出

## 门禁 2：errexit + 算术命令陷阱

脚本：`script/audit_errexit_arith.py`

在 bash 中，算术命令 `(( expr ))` 的退出码是：

- `expr != 0` → exit 0
- `expr == 0` → exit 1

因此在 `set -e` 时，下面的写法可能在计数从 0 开始时“突然把脚本干掉”：

- `((var++))`
- `((var--))`

建议替代写法（示例）：

- `((++var))` / `((--var))`
- `var=$((var+1))`
- 或者显式 guard（例如 `((var++)) || true`，但更推荐改写表达式）

## 门禁 3：JSON 模式 stdout 纯 JSON

脚本：`script/audit_json_stdout_purity.py`

约束目标：

- **JSON 模式**下 stdout 只能输出 JSON（方便上层 `| jq` / `python -m json.tool` / 监控采集）
- 人类可读日志必须走 stderr

该审计器会尝试识别常见的 JSON 模式结构（如 `--json` 或 `MODE=text/json`），并在 JSON 分支里发现 `echo/printf` 写 stdout 且内容不像 JSON 时给出告警。

## 常见处理策略

- 缺 `--max-time`：补齐 `--connect-timeout` + `--max-time`（或使用 `timeout N curl ...`）
- `curl | jq`：在管道末尾添加 fallback（如 `|| true` / `|| echo '{...}'`）并确保 JSON 模式不污染 stdout
- JSON 污染：把人类日志 `>&2`，或像 `script/clash_diagnose.sh` 一样在 JSON 模式下把 stdout 切到 stderr，再用独立 FD 输出 JSON

> 备注：这些门禁是“启发式静态检查”，不会完全解析 Shell，但目标是**低误报 + 抓住高风险坑**。
