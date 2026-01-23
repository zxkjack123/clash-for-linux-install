# 自动刷新 Clash 订阅

本指南介绍如何使用 `script/refresh_subscription_direct.sh` 以及随附的 systemd unit，实现免手动清理代理变量的定期订阅更新。

## 1. 手动执行

```bash
cd /path/to/clash-for-linux-install
./script/refresh_subscription_direct.sh        # 默认读取 .env 内的 CLASH_SUBSCRIPTION_URL
./script/refresh_subscription_direct.sh "https://example.com/subscribe?token=***"  # 覆盖订阅地址（示例；请勿在文档/日志中暴露真实 token）
```

> 该脚本会自动 `source .env`，然后以 `env -u https_proxy -u http_proxy ...` 的方式调用 `script/update_clash_subscription.sh`，避免因系统代理导致的 `SSL_ERROR_SYSCALL`。

## 2. 安装 systemd 定时任务 (用户级)

1. 复制 unit 文件：
   ```bash
   mkdir -p ~/.config/systemd/user
   cp systemd/clash-subscription-refresh.service ~/.config/systemd/user/
   cp systemd/clash-subscription-refresh.timer ~/.config/systemd/user/
   ```
2. 根据需要修改以下内容：
   - `WorkingDirectory`、`ExecStart`：请按你的仓库实际路径调整。
   - `OnCalendar`：默认每日 04:30 执行，可改成 `hourly`、`*-*-* 03:00:00` 等任意 systemd 时间表达式。
   - `RUN_OPTIMIZE_AFTER_REFRESH`：1 表示订阅更新后自动执行 `vpn-tools/optimize_all_network.sh`，0 表示仅刷新订阅。
   - `OPTIMIZE_DELAY`：在执行全量深度优化前等待的秒数（默认 900 秒 ≈15 分钟，给订阅/节点预热时间）。
   - `OPTIMIZE_SCRIPT`：如需自定义深度优化脚本，修改该路径。
3. 重新加载并启动：
   ```bash
   systemctl --user daemon-reload
   systemctl --user enable --now clash-subscription-refresh.timer
   ```
4. 查看状态 / 最近执行：
   ```bash
   systemctl --user status clash-subscription-refresh.timer
   journalctl --user -u clash-subscription-refresh.service -n 50
   ```

## 3. 取消或临时禁用

```bash
systemctl --user disable --now clash-subscription-refresh.timer
```

## 4. 常见问题

| 情况                                 | 解决办法                                                                            |
| ------------------------------------ | ----------------------------------------------------------------------------------- |
| `.env` 缺少 `CLASH_SUBSCRIPTION_URL` | 在 `.env` 中补充，或运行脚本时通过参数传入                                          |
| Provider 速度慢超时                  | 调整 service unit 中的 `TimeoutStartSec`，例如设置为 `10min`                        |
| 想用不同订阅                         | 建议复制 service/timer，修改 `ExecStart` 参数或 `.env` 变量                         |
| 想禁用自动深度优化                   | 将 service 文件中的 `RUN_OPTIMIZE_AFTER_REFRESH` 设为 0，或在运行脚本前导出同名变量 |
| 想缩短/拉长优化等待                  | 修改 `OPTIMIZE_DELAY`（单位秒），例如 `OPTIMIZE_DELAY=300`                          |

完成以上配置后，系统会在后台自动以无代理模式刷新订阅并重启 Mihomo/Clash，降低因缓存或网络异常导致的订阅过期风险。
