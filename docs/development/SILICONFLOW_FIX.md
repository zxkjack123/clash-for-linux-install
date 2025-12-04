# 硅基流动 API 地址修复指南

## 问题说明

在健康检查中，硅基流动API返回404错误：
```
❌ 硅基流动: 404 (90ms) [FAIL]
```

这可能是因为使用的API端点地址不正确。

## 可能的正确地址

硅基流动可能的API端点（请根据实际情况选择）：

```bash
# 选项1: 主API端点
https://api.siliconflow.cn/

# 选项2: V1 API端点
https://api.siliconflow.cn/v1

# 选项3: V1 Models端点
https://api.siliconflow.cn/v1/models

# 选项4: 健康检查端点
https://api.siliconflow.cn/health

# 选项5: 官网首页
https://siliconflow.cn/
```

## 修复方法

### 方法1: 快速修复（推荐）

如果您知道正确的API地址，可以直接修改监控脚本：

```bash
# 1. 编辑监控脚本
cd /home/gw/opt/clash-for-linux-install/vpn-tools
nano network_health_monitor.sh

# 2. 找到第107行左右的这一行：
"https://api.siliconflow.cn/|硅基流动"

# 3. 修改为正确的地址，例如：
"https://api.siliconflow.cn/v1/models|硅基流动"
# 或
"https://siliconflow.cn/|硅基流动"

# 4. 保存文件 (Ctrl+O, Enter, Ctrl+X)

# 5. 重新测试
./network_health_monitor.sh
```

### 方法2: 使用sed快速替换

如果您确定正确的地址，可以使用这个命令一键替换：

```bash
cd /home/gw/opt/clash-for-linux-install/vpn-tools

# 替换为V1端点
sed -i 's|https://api.siliconflow.cn/|https://api.siliconflow.cn/v1|g' network_health_monitor.sh

# 或替换为官网
sed -i 's|https://api.siliconflow.cn/|https://siliconflow.cn/|g' network_health_monitor.sh

# 测试
./network_health_monitor.sh
```

### 方法3: 测试所有可能的地址

运行此脚本找出正确的地址：

```bash
#!/bin/bash
# 测试硅基流动所有可能的API地址

echo "测试硅基流动API地址..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━"

PROXY="http://127.0.0.1:7890"

urls=(
    "https://api.siliconflow.cn/"
    "https://api.siliconflow.cn/v1"
    "https://api.siliconflow.cn/v1/models"
    "https://api.siliconflow.cn/health"
    "https://siliconflow.cn/"
)

for url in "${urls[@]}"; do
    echo -n "测试: $url ... "
    if code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 --proxy "$PROXY" "$url" 2>/dev/null); then
        if [[ "$code" =~ ^[23] ]]; then
            echo "✅ $code (成功)"
        else
            echo "⚠️  $code"
        fi
    else
        echo "❌ 连接失败"
    fi
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

保存为 `test_siliconflow.sh` 并运行：

```bash
chmod +x test_siliconflow.sh
./test_siliconflow.sh
```

## 临时解决方案

如果暂时无法确定正确地址，可以临时从监控中移除硅基流动：

```bash
cd /home/gw/opt/clash-for-linux-install/vpn-tools
nano network_health_monitor.sh

# 找到并注释掉这一行（在前面加#）：
# "https://api.siliconflow.cn/|硅基流动"

# 或者替换为其他服务，例如：
"https://openrouter.ai/api/v1|OpenRouter"
```

## 验证修复

修复后，运行健康检查验证：

```bash
cd /home/gw/opt/clash-for-linux-install/vpn-tools
./network_health_monitor.sh

# 查看AI服务部分的输出
# 应该看到硅基流动变成绿色 ✅
```

## 关于硅基流动

硅基流动（SiliconFlow）是国内的AI推理服务提供商。根据您的使用情况：

1. **如果您有账号**：
   - 登录查看API文档获取正确端点
   - 某些端点可能需要API Key认证
   - 考虑使用需要认证的完整API测试

2. **如果只是测试连通性**：
   - 使用官网首页: `https://siliconflow.cn/`
   - 或使用健康检查端点（如有）

3. **如果API需要认证**：
   - 当前的简单HTTP GET可能无法通过
   - 考虑使用官网或健康检查端点

## 修改示例

### 示例1: 使用官网首页

```bash
cd /home/gw/opt/clash-for-linux-install/vpn-tools
nano network_health_monitor.sh

# 第107行修改为：
"https://siliconflow.cn/|硅基流动"
```

### 示例2: 使用V1端点

```bash
cd /home/gw/opt/clash-for-linux-install/vpn-tools
nano network_health_monitor.sh

# 第107行修改为：
"https://api.siliconflow.cn/v1/models|硅基流动"
```

### 示例3: 添加超时和重试

如果希望更宽松的测试条件，可以修改 `test_url` 函数：

```bash
nano network_health_monitor.sh

# 找到 test_url 函数（约第88行），修改超时参数：
# 将：--connect-timeout 5 --max-time 10
# 改为：--connect-timeout 10 --max-time 20
```

## 联系信息

如果以上方法都无法解决，建议：

1. 查看硅基流动官方文档
2. 检查是否需要API密钥
3. 咨询硅基流动客服获取正确的健康检查端点
4. 或考虑使用其他类似服务替代

## 其他AI服务备选

如果硅基流动暂时无法监控，可以考虑添加这些国内AI服务：

```bash
# 百度文心一言
"https://yiyan.baidu.com/|文心一言"

# 阿里通义千问
"https://tongyi.aliyun.com/|通义千问"

# 讯飞星火
"https://xinghuo.xfyun.cn/|讯飞星火"

# 智谱清言
"https://chatglm.cn/|智谱清言"

# Kimi
"https://kimi.moonshot.cn/|Kimi"
```

添加方法：

```bash
nano network_health_monitor.sh

# 在第107行附近，修改services数组为：
local services=(
    "https://chat.openai.com/|ChatGPT"
    "https://sg.uiuiapi.com/|UIUI-API"
    "https://siliconflow.cn/|硅基流动"
    "https://kimi.moonshot.cn/|Kimi"
)
```

---

**需要帮助？**

如果您知道硅基流动的正确API地址，请告诉我，我可以帮您快速修复！
