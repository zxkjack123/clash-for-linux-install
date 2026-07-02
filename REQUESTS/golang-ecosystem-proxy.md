# 需求：Go 生态系统代理支持

**提出者:** agent-task-runner 项目
**日期:** 2026-07-02
**优先级:** 中

---

## 问题描述

当前 Go 编译器 (`go build`、`go test`、`go mod download`) 无法正常运行，因为关键域名被墙：

```
proxy.golang.org → EOF
golang.org       → 502/EOF  
sum.golang.org   → EOF
```

Go 下载模块时分两步：先向 `golang.org` 发 HTTPS 解析 import path，再通过 `proxy.golang.org` 下载 zip。两步在无代理环境均失败。

---

## 需求 1：mixin.yaml 添加 Go 域名代理规则

**文件:** `resources/mixin.yaml`，在 `rules:` 块中添加：

```yaml
  # Go ecosystem (force PROXY)
  - DOMAIN-SUFFIX,golang.org,PROXY
  - DOMAIN,proxy.golang.org,PROXY
  - DOMAIN,sum.golang.org,PROXY
  - DOMAIN,go.dev,PROXY
  - DOMAIN-SUFFIX,godoc.org,PROXY
```

## 需求 2：Go 环境变量脚本

**文件:** 新建 `script/go-env.sh`

```bash
#!/bin/bash
# 使用前: source script/go-env.sh
if ! curl -s --connect-timeout 3 https://golang.org/ >/dev/null 2>&1; then
    export GOPROXY='https://goproxy.cn,direct'
fi
echo "Go proxy: GOPROXY=$GOPROXY"
```

## 验证

```bash
clashctl mixin -e                           # 应用规则
curl -x http://127.0.0.1:7890 -I https://golang.org/  # 应返回 200
source script/go-env.sh && go mod download               # 应成功下载模块
```

## 关联项目

- `/home/gw/opt/agent-task-runner` — Python PM→Worker→Reviewer 循环
- `/home/gw/opt/agent-orchestrator-management` — Go 控制面
