# VMUTEX

VMUTEX 是面向 Ubuntu ARM64 服务器的 Nginx Web 反向代理管理脚本。它可以管理 HTTPS 站点、Let's Encrypt 证书和 Cloudflare DNS，并通过 GitHub Release 安全更新自身。

> 首版仅在 Ubuntu ARM64 (`aarch64`) 上提供支持。脚本需要 root 权限。

## 安装

```bash
curl -fsSL https://github.com/EchoLunar/vmutex/releases/latest/download/install.sh | sudo bash
```

安装器要求系统中已有 `bash`、`curl`、`python3`、`nginx`、`certbot`、`sha256sum` 和 `install`。缺少依赖时会停止并列出缺少的命令，不会自动修改软件包。

首次运行：

```bash
sudo vmutex
```

首次进入面板时会要求设置主域名。Cloudflare Token、Zone ID、源站 IP 保存在 root 专用的 `/etc/vmutex/config`，不会写入仓库。

## 常用命令

```bash
sudo vmutex                 # 打开交互面板
sudo vmutex version         # 查看版本
sudo vmutex update          # 检查更新并确认
sudo vmutex update --yes    # 非交互确认更新
```

面板中的 `8. 检查并更新` 与 `vmutex update` 使用同一更新逻辑。更新只接受 `vX.Y.Z` Release，下载 `vmutex` 和 `vmutex.sha256`，通过 SHA-256、Bash 语法与版本一致性检查后才原子替换现有脚本。

配置、证书和 Nginx 站点不会在安装或更新时被删除。

## 回滚

更新和重复安装前的脚本保存在：

```text
/usr/local/lib/vmutex/backups/
```

选择需要恢复的文件后执行：

```bash
sudo install -o root -g root -m 0755 /usr/local/lib/vmutex/backups/<备份文件> /usr/local/bin/vmutex
sudo vmutex version
```

## 卸载

只删除程序并保留站点、证书和配置：

```bash
sudo rm /usr/local/bin/vmutex
```

确认不再需要备份和程序配置后，可另外删除 `/usr/local/lib/vmutex` 与 `/etc/vmutex`。VMUTEX 管理的 Nginx 文件和 Let's Encrypt 证书需按实际用途单独处理，避免中断现有服务。

## 发布

推送不可变语义版本标签，例如：

```bash
git tag v1.0.0
git push origin v1.0.0
```

Release 工作流会验证标签与脚本版本一致，执行测试，并发布 `vmutex`、`vmutex.sha256` 和 `install.sh`。更新器不会直接下载 `main` 分支内容。

## 开发检查

```bash
bash -n vmutex install.sh tests/test.sh
bash tests/test.sh
shellcheck vmutex install.sh tests/test.sh
```

## License

[MIT](LICENSE)
