#!/bin/sh
# Alpine/OpenRC: forward one or two local ports to an existing remote proxy.
# Run on the Hong Kong server as root: sh alpine-gost-relay.sh
set -eu
umask 077

VERSION=3.3.0
SERVICE=gost-relay
BIN=/usr/local/bin/gost-relay
CONF=/etc/gost-relay/config.yaml
INIT=/etc/init.d/gost-relay
fail() { printf '\n错误：%s\n' "$*" >&2; exit 1; }
ask() { printf '%s' "$1" >&2; IFS= read -r ANSWER || fail '输入已结束。'; }
port() {
    case "$1" in ''|*[!0-9]*|0*) return 1 ;; esac
    [ "${#1}" -le 5 ] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

[ "$(id -u)" = 0 ] || fail '请以 root 运行。'
[ -f /etc/alpine-release ] || fail '本脚本仅适用于 Alpine Linux。'
[ -x /sbin/openrc-run ] || fail '需要完整的 OpenRC 系统，不能在普通 Docker 容器内使用。'
for path in "$BIN" "$CONF" "$INIT"; do
    [ ! -e "$path" ] || fail "已存在 $path；为保留现有配置，本次退出。修改配置后可执行 rc-service gost-relay restart。"
done
case "$(uname -m)" in
    x86_64) ARCH=amd64 ;;
    aarch64) ARCH=arm64 ;;
    armv7l) ARCH=armv7 ;;
    *) fail '目前支持 x86_64、aarch64 和 armv7l。' ;;
esac

printf '\n香港 → 土耳其端口中转（GOST %s）\n' "$VERSION"
printf '请在香港服务器运行。土耳其端需要已经有可用且带认证的代理节点。\n'
printf '土耳其填写公网映射端口；香港填写本机监听端口，不能占用 SSH 端口。\n\n'
ask '土耳其公网 IPv4 / 域名 / IPv6（不带协议、不带端口、IPv6不加方括号）：'
REMOTE=$ANSWER
case "$REMOTE" in ''|*[!a-zA-Z0-9.:_-]*|-*) fail '地址格式不正确。' ;; esac
case "$REMOTE" in *:*) TARGET="[$REMOTE]" ;; *) TARGET=$REMOTE ;; esac
ask '转发几个端口？1 或 2 [默认 1]：'
COUNT=${ANSWER:-1}
case "$COUNT" in 1|2) ;; *) fail '只能填 1 或 2。' ;; esac

TASK_TMP=$(mktemp -d)
trap 'rm -rf "$TASK_TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf 'log:\n  level: warn\nservices:\n' > "$TASK_TMP/config.yaml"
: > "$TASK_TMP/ports"
: > "$TASK_TMP/summary"
USED=' '
i=1
while [ "$i" -le "$COUNT" ]; do
    printf '\n第 %s 条规则\n' "$i"
    ask '香港本机监听端口：'
    LOCAL=$ANSWER
    port "$LOCAL" || fail '端口必须为 1–65535，不能带前导零。'
    case "$USED" in *" $LOCAL "*) fail '两条规则不能使用同一个香港监听端口。' ;; esac
    USED="$USED$LOCAL "
    ask '土耳其公网映射端口：'
    DEST=$ANSWER
    port "$DEST" || fail '端口必须为 1–65535，不能带前导零。'
    ask '转发类型：1=TCP，2=UDP，3=TCP+UDP [默认 3]：'
    case "${ANSWER:-3}" in
        1) PROTOS=tcp ;;
        2) PROTOS=udp ;;
        3) PROTOS='tcp udp' ;;
        *) fail '只能填 1、2 或 3。' ;;
    esac
    for PROTO in $PROTOS; do
        cat >> "$TASK_TMP/config.yaml" <<EOF
  - name: relay-$i-$PROTO
    addr: "0.0.0.0:$LOCAL"
    handler:
      type: $PROTO
    listener:
      type: $PROTO
    forwarder:
      nodes:
        - name: turkey-$i
          addr: "$TARGET:$DEST"
EOF
        printf '%s %s\n' "$PROTO" "$LOCAL" >> "$TASK_TMP/ports"
        printf '%s：香港本机 %s → %s:%s\n' "$PROTO" "$LOCAL" "$TARGET" "$DEST" >> "$TASK_TMP/summary"
    done
    i=$((i + 1))
done

printf '\n正在安装依赖并检查端口……\n'
apk add --no-cache ca-certificates curl tar iproute2
while read -r PROTO LOCAL; do
    case "$PROTO" in
        tcp) ss -H -ltn > "$TASK_TMP/listeners" ;;
        udp) ss -H -lun > "$TASK_TMP/listeners" ;;
    esac
    if awk -v p="$LOCAL" '$4 ~ (":" p "$") {found=1} END {exit !found}' "$TASK_TMP/listeners"; then
        fail "$PROTO/$LOCAL 已被占用，请换端口后重新运行。"
    fi
done < "$TASK_TMP/ports"

ASSET="gost_${VERSION}_linux_${ARCH}.tar.gz"
BASE="https://github.com/go-gost/gost/releases/download/v${VERSION}"
printf '\n正在从 GOST 官方下载，并核验 SHA-256……\n'
curl -fL --retry 3 --connect-timeout 15 --max-time 300 "$BASE/$ASSET" -o "$TASK_TMP/$ASSET"
curl -fL --retry 3 --connect-timeout 15 --max-time 60 "$BASE/checksums.txt" -o "$TASK_TMP/checksums.txt"
HASH=$(awk -v f="$ASSET" '$2 == f || $2 == "*" f {print $1}' "$TASK_TMP/checksums.txt")
[ "${#HASH}" = 64 ] || fail '官方校验文件中未找到对应文件。'
case "$HASH" in *[!a-fA-F0-9]*) fail '校验值格式不正确。' ;; esac
(cd "$TASK_TMP" && printf '%s  %s\n' "$HASH" "$ASSET" | sha256sum -c -)
tar -xzf "$TASK_TMP/$ASSET" -C "$TASK_TMP" gost
chmod 755 "$TASK_TMP/gost"
"$TASK_TMP/gost" -V

mkdir -p /usr/local/bin /etc/gost-relay
cp "$TASK_TMP/gost" "$BIN"
chmod 755 "$BIN"
cp "$TASK_TMP/config.yaml" "$CONF"
chmod 600 "$CONF"
cat > "$INIT" <<'OPENRC'
#!/sbin/openrc-run
description="GOST TCP/UDP relay to Turkey"
command="/usr/local/bin/gost-relay"
command_args="-C /etc/gost-relay/config.yaml"
supervisor="supervise-daemon"
respawn_delay=5
respawn_max=0
output_log="/var/log/gost-relay.log"
error_log="/var/log/gost-relay.log"
depend() {
    need net
    after firewall
}
OPENRC
chmod 755 "$INIT"
rc-update add "$SERVICE" default
rc-service "$SERVICE" start
sleep 2
rc-service "$SERVICE" status || fail '服务未正常运行，请查看 /var/log/gost-relay.log。'
while read -r PROTO LOCAL; do
    case "$PROTO" in
        tcp) ss -H -ltn > "$TASK_TMP/listeners" ;;
        udp) ss -H -lun > "$TASK_TMP/listeners" ;;
    esac
    awk -v p="$LOCAL" '$4 ~ (":" p "$") {found=1} END {exit !found}' "$TASK_TMP/listeners" ||
        fail "$PROTO/$LOCAL 没有成功监听，请查看 /var/log/gost-relay.log。"
done < "$TASK_TMP/ports"

printf '\n服务已启动并设为开机自启：\n'
cat "$TASK_TMP/summary"
printf '\n请确保香港入站和土耳其映射端口已放行对应的 TCP/UDP 协议。\n'
printf '如果香港也有 NAT 映射：客户端填写香港公网映射端口，而不是上面的本机监听端口。\n'
printf '客户端改为香港公网地址和入口端口；原节点的协议、密码、SNI、Host、公钥等保持原值。\n'
printf '此处只确认本机服务和监听状态；完整连通性请用原客户端连接并查看出口 IP。\n'
printf '\n状态：rc-service gost-relay status\n重启：rc-service gost-relay restart\n停止：rc-service gost-relay stop\n日志：tail -n 50 /var/log/gost-relay.log\n配置：/etc/gost-relay/config.yaml\n'
