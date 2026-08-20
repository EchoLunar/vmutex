#!/usr/bin/env bash

set -o pipefail

readonly VMUTEX_REPOSITORY_DEFAULT="EchoLunar/vmutex"

INSTALL_PATH="${VMUTEX_INSTALL_PATH:-/usr/local/bin/vmutex}"
CONFIG_DIR="${VMUTEX_CONFIG_DIR:-/etc/vmutex}"
REPOSITORY_FILE="${VMUTEX_REPOSITORY_FILE:-${CONFIG_DIR}/repository}"
BACKUP_DIR="${VMUTEX_BACKUP_DIR:-/usr/local/lib/vmutex/backups}"

fail() {
    echo "❌ $*" >&2
    exit 1
}

require_supported_host() {
    local missing=() command_name

    if [ "${VMUTEX_TEST_MODE:-0}" != "1" ]; then
        [ "$EUID" -eq 0 ] || fail "请使用 root 运行安装器，例如 curl ... | sudo bash"
        # shellcheck disable=SC1091
        source /etc/os-release
        [ "${ID:-}" = "ubuntu" ] || fail "v1.0.0 仅支持 Ubuntu"
        [ "$(uname -m)" = "aarch64" ] || fail "v1.0.0 仅支持 ARM64 (aarch64)"
    fi

    for command_name in bash curl python3 nginx certbot sha256sum install; do
        command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        fail "缺少依赖：${missing[*]}。请先安装后重试。"
    fi
}

repository_name() {
    local repository="${VMUTEX_REPOSITORY:-$VMUTEX_REPOSITORY_DEFAULT}"

    if [ "$repository" = "__VMUTEX_REPOSITORY__" ] || ! [[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
        fail "安装器尚未绑定 GitHub 仓库；请从正式 GitHub Release 下载 install.sh"
    fi
    printf '%s\n' "$repository"
}

valid_release_tag() {
    [[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

script_version() {
    sed -n 's/^readonly VMUTEX_VERSION="\([0-9][0-9.]*\)"$/\1/p' "$1" | head -1
}

main() {
    local repository api_url download_root temp_dir metadata tag version candidate checksum
    local install_temp backup stamp

    require_supported_host
    repository=$(repository_name)
    api_url="${VMUTEX_RELEASE_API_URL:-https://api.github.com/repos/${repository}/releases/latest}"
    download_root="${VMUTEX_RELEASE_DOWNLOAD_BASE:-https://github.com/${repository}/releases/download}"
    temp_dir=$(mktemp -d) || fail "无法创建临时目录"
    trap 'rm -rf "$temp_dir"' EXIT
    metadata="$temp_dir/release.json"

    echo "正在读取 VMUTEX 最新版本..."
    curl -fsSL --connect-timeout 10 --max-time 30 "$api_url" -o "$metadata" || fail "无法读取 GitHub Release 信息"
    tag=$(python3 - "$metadata" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        print(json.load(handle).get("tag_name", ""))
except (OSError, ValueError, TypeError):
    pass
PY
)
    valid_release_tag "$tag" || fail "Release 版本标签无效：${tag:-空}"
    version="${tag#v}"

    candidate="$temp_dir/vmutex"
    checksum="$temp_dir/vmutex.sha256"
    curl -fsSL --connect-timeout 10 --max-time 60 "$download_root/$tag/vmutex" -o "$candidate" || fail "主脚本下载失败"
    curl -fsSL --connect-timeout 10 --max-time 30 "$download_root/$tag/vmutex.sha256" -o "$checksum" || fail "校验文件下载失败"
    (cd "$temp_dir" && sha256sum -c vmutex.sha256 >/dev/null) || fail "SHA-256 校验失败"
    bash -n "$candidate" || fail "下载脚本语法检查失败"
    [ "$(script_version "$candidate")" = "$version" ] || fail "脚本版本与 Release 标签不一致"

    mkdir -p "$(dirname "$INSTALL_PATH")" "$CONFIG_DIR" "$BACKUP_DIR"
    chmod 700 "$CONFIG_DIR" "$BACKUP_DIR"
    if [ -e "$INSTALL_PATH" ]; then
        stamp=$(date -u +%Y%m%dT%H%M%SZ)
        backup="$BACKUP_DIR/vmutex-preinstall-${stamp}"
        cp -p "$INSTALL_PATH" "$backup" || fail "无法备份现有脚本"
        echo "已备份现有脚本：$backup"
    fi

    install_temp="${INSTALL_PATH}.new.$$"
    if ! install -o root -g root -m 0755 "$candidate" "$install_temp" 2>/dev/null; then
        if [ "${VMUTEX_TEST_MODE:-0}" = "1" ]; then
            install -m 0755 "$candidate" "$install_temp" || fail "无法准备新脚本"
        else
            fail "无法准备新脚本"
        fi
    fi
    mv -f "$install_temp" "$INSTALL_PATH" || fail "无法安装脚本"

    umask 077
    printf '%s\n' "$repository" > "$REPOSITORY_FILE"
    chmod 600 "$REPOSITORY_FILE"

    echo "✅ VMUTEX $tag 安装完成"
    echo "运行：sudo vmutex"
}

main "$@"
