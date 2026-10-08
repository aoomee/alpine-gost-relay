# GOST Relay

简洁的 Alpine 端口中转工具。TCP / UDP，最多两条规则，OpenRC 开机自启。

## 一键运行

在香港服务器的 root SSH 终端执行：

```sh
wget -qO- https://raw.githubusercontent.com/aoomee/alpine-gost-relay/main/install.sh | sh
```

使用 Alpine 自带的 `wget` 和 `sh`。输入从终端读取，支持管道运行，无需预装 Bash 或 curl。依赖自动安装，正常过程不刷屏，失败时显示原因。

首次直接配置；再次运行进入管理菜单：

```text
  GOST Relay  Alpine · v2
  运行中

  1  修改转发
  2  查看状态
  3  启动 / 重启
  4  卸载
  0  退出
```

## 怎么填

```text
你 → 香港 → 商家入口 A → 土耳其出口 B → 目标网站
```

| 提示 | 填写内容 |
| --- | --- |
| 目标 IP / 域名 | 商家提供的 A IP，即使它属于罗马尼亚 |
| 香港本机端口 | 香港系统里可用的监听端口 |
| 目标映射端口 | 商家 A IP 上通往原代理节点的公网映射端口 |
| 协议 | 回车转发 TCP + UDP；也可填 t 或 u |
| 再加一个端口 | 默认不加，填 y 配置第二条规则 |

客户端改用香港公网入口，保留原节点协议、密码、公钥、Host、SNI 等参数。如果 SNI 原来自动取自服务器地址，应显式填入原 TLS 域名。

香港如果也有 NAT，**客户端填香港公网映射端口，脚本填香港本机监听端口**。不要占用 SSH 端口。

## 要求与行为

- 完整 Alpine / OpenRC 系统、root 权限、交互式终端。支持 x86_64 / aarch64 / armv7l。
- 目标端已有可用且带认证的代理节点；这是端口中转工具，不会创建土耳其代理节点。
- 香港和商家映射都需放行相应 TCP/UDP 协议；脚本不改防火墙，不改变原节点加密方式。
- 初次安装从 GOST 官方下载固定版本 3.3.0，核验官方 SHA-256。需要能访问 GitHub 和 Alpine 软件源。
- 修改配置复用已安装的 GOST，准备完成才短暂停止旧服务；应用失败会恢复原配置，并尝试恢复原运行状态。
- 兼容本仓库第一版安装。卸载需输入 y 确认，保留日志和系统依赖。
- 只验证本机服务和监听端口，实际连接与出口 IP 需使用客户端确认。

## 手动管理

```sh
rc-service gost-relay status
rc-service gost-relay restart
rc-service gost-relay stop
rc-update del gost-relay default  # 取消开机自启
```

配置：`/etc/gost-relay/config.yaml`

日志：`/var/log/gost-relay.log`

## 验证

已检查 shell 语法、通过模拟环境验证管道交互和服务管理流程，并使用 GOST 3.3.0 完成真实的本地 TCP/UDP 往返测试。没有在用户的 Alpine 服务器上实测安装或 OpenRC 生命周期。

[GOST](https://github.com/go-gost/gost) · [转发文档](https://www.gost.run/en/getting-started/quick-start/) · [OpenRC](https://wiki.alpinelinux.org/wiki/OpenRC)
