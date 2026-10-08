# Alpine GOST Relay

在香港 Alpine 服务器上，将一到两个 TCP/UDP 端口转发至土耳其（或其他地区）已有的代理节点。基于 GOST 3.3.0，使用 OpenRC 管理服务。

## 一键安装

在**香港服务器**的 root 终端运行：

```sh
apk add --no-cache curl ca-certificates && sh -c "$(curl -fsSL https://raw.githubusercontent.com/aoomee/alpine-gost-relay/main/install.sh)"
```

脚本原生兼容 Alpine 的 `sh`，不需要安装 Bash。交互提示会询问目标地址、转发端口数量、本机监听端口、目标公网映射端口及 TCP/UDP 类型。

也可以先下载，再运行：

```sh
curl -fL https://raw.githubusercontent.com/aoomee/alpine-gost-relay/main/install.sh -o install-relay.sh && sh install-relay.sh
```

## 适用条件

- 香港服务器运行完整 Alpine/OpenRC 系统，具有 root 权限。
- 支持 x86_64、aarch64、armv7l。
- 土耳其端已有可用、带认证的代理节点，并有香港可以访问的公网映射端口。
- 两端的防火墙、安全组及服务商映射已允许相应 TCP/UDP 协议。脚本不修改这些规则。
- GitHub 和 GOST 官方 Releases 可以从香港服务器访问。

本脚本只部署端口中转，不会在土耳其自动安装代理节点，也不会额外加密已有流量。转发到土耳其的加密代理节点时，客户端继续使用该节点原有的认证和加密配置。

## NAT 端口怎么填

例如：

```text
香港公网:40001 → 香港本机:20001
土耳其公网:50001 → 土耳其本机代理:30001
```

脚本中填写：

- 香港本机监听端口：`20001`
- 土耳其公网映射端口：`50001`

客户端连接香港公网地址的 `40001` 端口。原节点协议、密码、SNI、Host、公钥等参数保持原值；若客户端原来自动从服务器地址推断 SNI，需要显式填写原来的 TLS 域名。

只需要一个入口时选择一条规则，另一个端口可保留给 SSH。不要把 SSH 端口当作转发端口。

## 安装行为

- 安装 `ca-certificates`、`curl`、`tar`、`iproute2`。
- 检查所选监听端口是否已被使用。
- 从 GOST 官方 Releases 下载固定版本，并使用官方 `checksums.txt` 核验 SHA-256。
- 创建独立的 `gost-relay` 服务，开机自启，异常退出后自动重启。
- 检查本机服务及端口监听状态。此检查不代表目标节点或端到端连接已成功。
- 遇到本脚本已有的程序、配置或服务文件时退出，避免覆盖现有安装。

## 管理

```sh
rc-service gost-relay status
rc-service gost-relay restart
rc-service gost-relay stop
tail -n 50 /var/log/gost-relay.log
```

配置文件：`/etc/gost-relay/config.yaml`。修改配置后重启服务生效。

若关闭开机自启：

```sh
rc-update del gost-relay default
```

卸载本脚本安装的服务与配置：

```sh
rc-service gost-relay stop
rc-update del gost-relay default
rm -f /etc/init.d/gost-relay /usr/local/bin/gost-relay
rm -f /etc/gost-relay/config.yaml
rmdir /etc/gost-relay
```

日志保留在 `/var/log/gost-relay.log`；安装依赖不会自动卸载。

## 验证范围

已完成 shell 语法检查，并使用 GOST 3.3.0 在本地验证生成的配置能进行 TCP 和 UDP 往返转发。尚未在实际 Alpine 服务器上验证安装与 OpenRC 生命周期。部署后请使用原代理客户端连接，检查目标网站是否可用及出口 IP 是否符合预期。

## 参考

- [GOST 官方项目](https://github.com/go-gost/gost)
- [GOST TCP/UDP 转发文档](https://www.gost.run/en/getting-started/quick-start/)
- [Alpine OpenRC 文档](https://wiki.alpinelinux.org/wiki/OpenRC)
