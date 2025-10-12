#!/usr/bin/env bash
# load_env.sh
# 统一的环境变量加载函数
# 用法: source "$(dirname "$0")/load_env.sh"

# 查找 .env 文件（向上递归查找）
find_env_file() {
    local dir="$1"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/.env" ]]; then
            echo "$dir/.env"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# 加载 .env 配置
load_env_config() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local parent_dir="$(dirname "$script_dir")"
    local env_file=""
    
    # 优先级: 1. 当前目录 2. 父目录 3. 递归查找
    if [[ -f "$script_dir/.env" ]]; then
        env_file="$script_dir/.env"
    elif [[ -f "$parent_dir/.env" ]]; then
        env_file="$parent_dir/.env"
    else
        env_file=$(find_env_file "$script_dir" 2>/dev/null || echo "")
    fi
    
    if [[ -n "$env_file" && -f "$env_file" ]]; then
        # 使用 set -a 自动导出所有变量
        set -a
        # shellcheck disable=SC1090
        source "$env_file"
        set +a
        
        # 记录加载成功（仅在详细模式下）
        [[ "${VERBOSE:-0}" == "1" ]] && echo "[INFO] 已加载配置: $env_file" >&2
        return 0
    else
        # 没有找到 .env 文件，使用默认配置
        [[ "${VERBOSE:-0}" == "1" ]] && echo "[WARN] 未找到 .env 配置文件，使用默认配置" >&2
        return 1
    fi
}

# 验证必需的环境变量
require_env_var() {
    local var_name="$1"
    local var_value="${!var_name:-}"
    
    if [[ -z "$var_value" ]]; then
        echo "错误: 未设置环境变量 $var_name" >&2
        echo "请在 .env 文件中配置，或通过环境变量设置" >&2
        return 1
    fi
    return 0
}

# 自动加载（当被 source 时）
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    load_env_config
fi
