# GOST Relay

简洁的 Linux TCP / UDP 端口转发工具。自动识别系统，多条规则、多个目标，开机自启和异常重启。

## 支持范围

| 中转服务器系统 | 依赖安装 | 服务管理 |
| --- | --- | --- |
| Debian | apt-get | systemd |
| Ubuntu | apt-get | systemd |
| Alpine Linux | apk | OpenRC |

需要 root、交互式 SSH 终端，以及正常运行的服务管理器。支持 x86_64、aarch64、armv7l。普通 Docker 容器、未运行 systemd 的 Debian/Ubuntu、其他发行版不在当前支持范围内；脚本会在安装前退出并说明原因。

**目标机器不限地区、商家或操作系统**。只要中转服务器可以访问它的服务端口，就可以转发。目标服务可以是代理节点、Web 服务或其他 TCP/UDP 服务。本工具不会自动部署目标服务或额外加密流量。

仓库保留原来的 `alpine-gost-relay` 名称，让已分享的一键链接继续有效；脚本现已支持上述三种系统。

## 一键运行

在**中转服务器**的 root SSH 终端执行：

```sh
wget -qO- https://raw.githubusercontent.com/aoomee/alpine-gost-relay/main/install.sh | sh
```

已有 curl 也可以用：

```sh
curl -fsSL https://raw.githubusercontent.com/aoomee/alpine-gost-relay/main/install.sh | sh
```

不需要 Bash。输入从终端读取，支持管道运行；其余依赖自动安装。正常过程不刷屏，失败显示原因。

Alpine 通常自带 wget。精简 Debian/Ubuntu 如果 wget、curl 都没有，先安装：

```sh
apt-get update && apt-get install -y wget ca-certificates
```

首次直接配置，再次运行进入管理菜单：

```text
  GOST Relay  Debian · v3
  运行中

  1  修改转发
  2  查看状态
  3  启动 / 重启
  4  卸载
  0  退出
```

## 配置

```text
客户端 → 中转服务器:监听端口 → 目标地址:目标端口
```

| 提示 | 填写内容 |
| --- | --- |
| 目标 IP / 域名 | 中转机能访问的 IPv4、域名或 IPv6；IPv6 不加方括号 |
| 本机监听端口 | 中转服务器系统内可用的端口 |
| 目标端口 | 目标服务的可达端口；目标在 NAT 后面时填公网映射端口 |
| 协议 | 回车转发 TCP + UDP；填 t 只转 TCP；填 u 只转 UDP |
| 再加一条转发 | 填 y 继续添加，不限两条 |

每条规则可以指定不同目标。第二条起，目标地址直接回车会沿用上一条；本机端口不可重复。当前默认监听所有本机 IPv4 地址（`0.0.0.0`）；IPv6 目标访问要求中转机本身具有相应网络连通性。需要 IPv6 入站监听时可手动修改配置中的监听地址并重启。

如果中转机也有 NAT：**客户端填中转机公网映射端口，脚本填中转机内部监听端口**。不要占用 SSH 或其他已有服务端口。

转发已有代理节点时，客户端保留原节点协议、密码、公钥、Host、SNI 等参数；若 SNI 原来自动取自服务器地址，应显式填写原 TLS 域名。转发不改变目标服务的认证方式。

## 安装与修改

- 初次安装从 GOST 官方下载固定版本 3.3.0，使用官方 SHA-256 校验文件核验。需要能访问 GitHub 和系统软件源。
- 自动安装 ca-certificates、curl、tar、iproute2；不修改防火墙。相关主机、安全组和 NAT 映射需允许所选协议及端口。
- 修改配置会替换全部转发规则；复用已安装的 GOST，准备完成后才短暂停止旧服务。
- 应用失败时恢复旧配置、旧服务定义和原开机自启状态，并尝试恢复原运行状态。
- 兼容本仓库以前的 Alpine 安装；不用卸载重装，重新执行一键命令即可进入菜单。
- 卸载需输入 y 确认，保留系统依赖和历史日志。
- 安装结束只确认本机服务与监听状态；端到端连接需用客户端验证。

## 手动管理

Debian / Ubuntu：

```sh
systemctl status gost-relay
systemctl restart gost-relay
systemctl stop gost-relay
systemctl disable gost-relay       # 取消开机自启
journalctl -u gost-relay -n 50 --no-pager
```

Alpine：

```sh
rc-service gost-relay status
rc-service gost-relay restart
rc-service gost-relay stop
rc-update del gost-relay default   # 取消开机自启
tail -n 50 /var/log/gost-relay.log
```

统一配置路径：`/etc/gost-relay/config.yaml`。

## 验证范围

已完成 shell 语法检查，使用模拟环境覆盖 Alpine、Debian、Ubuntu 的依赖选择、服务管理、管道交互、多目标配置、失败回滚及卸载，并使用 GOST 3.3.0 验证真实的本地 TCP/UDP 往返。未在用户服务器或真实 systemd/OpenRC 环境中完整验证部署。

[GOST](https://github.com/go-gost/gost) · [转发文档](https://www.gost.run/en/getting-started/quick-start/) · [OpenRC](https://wiki.alpinelinux.org/wiki/OpenRC) · [Debian systemd](https://wiki.debian.org/systemd)
