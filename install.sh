#!/bin/sh
# GOST port relay · Alpine/OpenRC and Debian/Ubuntu/systemd
set -eu
umask 077
GOST_VERSION=3.3.0
BIN=/usr/local/bin/gost-relay
CONF=/etc/gost-relay/config.yaml
SERVICE=gost-relay
LOG=/var/log/gost-relay.log
CYAN='' GREEN='' DIM='' RESET=''
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    CYAN=$(printf '\033[36m'); GREEN=$(printf '\033[32m')
    DIM=$(printf '\033[2m'); RESET=$(printf '\033[0m')
fi
say() { printf '  %s\n' "$*"; }
fail() { printf '\n  错误 · %s\n\n' "$*" >&2; exit 1; }
ask() { printf '  %s ' "$1"; IFS= read -r ANSWER <&3 || fail '输入已结束。'; }
port() {
    case "$1" in ''|*[!0-9]*|0*) return 1 ;; esac
    [ "${#1}" -le 5 ] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}
read_port() {
    while :; do
        ask "$1"; port "$ANSWER" && return 0
        say '请输入 1–65535 之间的端口，不带前导零。'
    done
}
service_action() {
    if [ "$MANAGER" = systemd ]; then
        systemctl "$1" "$SERVICE.service"
    else
        rc-service "$SERVICE" "$1"
    fi
}
running() {
    if [ "$MANAGER" = systemd ]; then
        systemctl is-active --quiet "$SERVICE.service"
    else
        rc-service "$SERVICE" status >/dev/null 2>&1
    fi
}
enabled() {
    if [ "$MANAGER" = systemd ]; then
        systemctl is-enabled --quiet "$SERVICE.service"
    else
        rc-update show default | awk -v s="$SERVICE" '$1 == s {found=1} END {exit !found}'
    fi
}
autostart() {
    if [ "$MANAGER" = systemd ]; then
        systemctl "$1" "$SERVICE.service"
    elif [ "$1" = enable ]; then
        rc-update add "$SERVICE" default
    elif enabled; then
        rc-update del "$SERVICE" default
    fi
}
reload_manager() {
    if [ "$MANAGER" = systemd ]; then systemctl daemon-reload; fi
}
show_logs() {
    if [ "$MANAGER" = systemd ]; then
        journalctl -u "$SERVICE.service" -n 6 --no-pager
    elif [ -f "$LOG" ]; then
        tail -n 6 "$LOG"
    fi
}
show_rules() {
    [ -f "$CONF" ] || return 0
    awk '
        /name: relay-/ {local=""; proto=""}
        /type:/ {proto=$2}
        /addr:/ {
            a=$2; gsub(/"/, "", a)
            if (local == "") {local=a; sub(/^0.0.0.0:/, "", local)}
            else printf "  %-5s  :%-5s → %s\n", toupper(proto), local, a
        }
    ' "$CONF"
}

[ "$(id -u)" = 0 ] || fail '请使用 root 运行。'
[ -r /etc/os-release ] || fail '无法识别系统，需要 Alpine、Debian 或 Ubuntu。'
. /etc/os-release
case "${ID:-}" in
    alpine)
        MANAGER=openrc; DISTRO=Alpine; INIT=/etc/init.d/gost-relay
        [ -x /sbin/openrc-run ] && command -v rc-service >/dev/null 2>&1 || fail '需要完整的 OpenRC 系统。'
        LOG_HINT=$LOG ;;
    debian|ubuntu)
        MANAGER=systemd; INIT=/etc/systemd/system/gost-relay.service
        case "$ID" in debian) DISTRO=Debian ;; ubuntu) DISTRO=Ubuntu ;; esac
        [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1 || fail '需要运行中的 systemd；普通容器不适用。'
        LOG_HINT='journalctl -u gost-relay --no-pager' ;;
    *) fail "暂不支持 ${ID:-未知系统}，当前支持 Alpine、Debian、Ubuntu。" ;;
esac
# Read answers from the terminal, keeping stdin available for `wget ... | sh`.
{ exec 3</dev/tty; } 2>/dev/null || fail '请在交互式 SSH 终端运行。'
TASK_TMP=$(mktemp -d)
PENDING=0
INSTALLED=0
WAS_RUNNING=0
WAS_ENABLED=0
cleanup() {
    RESULT=$?
    trap - EXIT INT TERM
    set +e
    if [ "$PENDING" = 1 ]; then
        service_action stop >/dev/null 2>&1
        if [ "$INSTALLED" = 1 ]; then
            cp "$TASK_TMP/old-config" "$CONF"
            cp "$TASK_TMP/old-init" "$INIT"
            if [ "$MANAGER" = openrc ]; then chmod 755 "$INIT"; else chmod 644 "$INIT"; fi
            reload_manager
            if [ "$WAS_ENABLED" = 1 ]; then autostart enable; else autostart disable; fi
            if [ "$WAS_RUNNING" = 1 ]; then
                if service_action start > "$TASK_TMP/restore.log" 2>&1; then
                    say '已恢复原配置和服务。'
                else
                    say "原配置已恢复，服务启动失败；请查看 $LOG_HINT。"
                    tail -n 8 "$TASK_TMP/restore.log" >&2
                fi
            else
                say '已恢复原配置，服务保持停止。'
            fi
        else
            autostart disable >/dev/null 2>&1
            rm -f "$BIN" "$CONF" "$INIT"
            reload_manager
            rmdir /etc/gost-relay 2>/dev/null
            say '安装未完成，已撤回服务文件。'
        fi
    fi
    rm -rf "$TASK_TMP"
    exit "$RESULT"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
run() {
    if "$@" < /dev/null > "$TASK_TMP/action.log" 2>&1; then return 0; fi
    tail -n 8 "$TASK_TMP/action.log" >&2
    fail '操作未完成，原因见上方。'
}
if [ -e "$INIT" ] || [ -e "$BIN" ] || [ -e "$CONF" ]; then
    [ -x "$BIN" ] && [ -f "$CONF" ] && [ -f "$INIT" ] || fail '检测到不完整的旧安装，请检查 /etc/gost-relay 和服务文件。'
    if [ "$MANAGER" = systemd ]; then
        grep -Fqx 'ExecStart=/usr/local/bin/gost-relay -C /etc/gost-relay/config.yaml' "$INIT" || fail '发现其他服务文件，未修改。'
    else
        grep -Fqx 'command="/usr/local/bin/gost-relay"' "$INIT" || fail '发现其他服务文件，未修改。'
    fi
    INSTALLED=1
fi
printf '\n  %sGOST Relay%s  %s%s · v3%s\n' "$CYAN" "$RESET" "$DIM" "$DISTRO" "$RESET"
if [ "$INSTALLED" = 1 ]; then
    if running; then STATE=运行中; else STATE=已停止; fi
    printf '  %s%s%s\n\n' "$DIM" "$STATE" "$RESET"
    say '1  修改转发'
    say '2  查看状态'
    say '3  启动 / 重启'
    say '4  卸载'
    say '0  退出'
    printf '\n'
    ask '选择 [0]：'
    case "${ANSWER:-0}" in
        1) ;;
        2) show_rules; printf '\n'; show_logs; exit 0 ;;
        3) run service_action restart; sleep 2; running || fail "服务启动失败，请查看 $LOG_HINT。"; say '服务已启动。'; exit 0 ;;
        4)
            ask '删除转发配置和服务？[y/N]：'
            case "$ANSWER" in y|Y) ;; *) exit 0 ;; esac
            if running; then run service_action stop; fi
            run autostart disable
            rm -f "$BIN" "$CONF" "$INIT"
            reload_manager
            rmdir /etc/gost-relay 2>/dev/null || true
            say '已卸载，系统依赖和历史日志保留。'
            exit 0 ;;
        0|'') exit 0 ;;
        *) fail '没有这个选项。' ;;
    esac
else
    printf '  %s本机端口 → 目标地址:端口%s\n' "$DIM" "$RESET"
fi
printf '\n'
say '在中转服务器运行，目标填本机能够访问的服务地址。'
REMOTE=''
printf 'log:\n  level: warn\nservices:\n' > "$TASK_TMP/config.yaml"
: > "$TASK_TMP/ports"
USED=' '
i=1
while :; do
    printf '\n'
    if [ -n "$REMOTE" ]; then ask "目标 IP / 域名 [$REMOTE]："; else ask '目标 IP / 域名：'; fi
    REMOTE=${ANSWER:-$REMOTE}
    case "$REMOTE" in ''|*[!a-zA-Z0-9.:_-]*|-*) fail '地址格式不正确，请勿填写协议或端口；IPv6 不加方括号。' ;; esac
    case "$REMOTE" in *:*) TARGET="[$REMOTE]" ;; *) TARGET=$REMOTE ;; esac
    read_port '本机监听端口：'; LOCAL=$ANSWER
    case "$USED" in *" $LOCAL "*) fail '本机端口不能重复。' ;; esac
    USED="$USED$LOCAL "
    read_port '目标端口：'; DEST=$ANSWER
    ask '协议 [回车=双协议 / t=TCP / u=UDP]：'
    case "$ANSWER" in
        ''|b|B) PROTOS='tcp udp' ;;
        t|T|tcp|TCP) PROTOS=tcp ;;
        u|U|udp|UDP) PROTOS=udp ;;
        *) fail '协议请输入 t、u，或直接回车。' ;;
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
        - name: target-$i
          addr: "$TARGET:$DEST"
EOF
        printf '%s %s\n' "$PROTO" "$LOCAL" >> "$TASK_TMP/ports"
    done
    ask '再加一条转发？[y/N]：'
    case "$ANSWER" in y|Y) i=$((i + 1)) ;; *) break ;; esac
done
printf '\n'
say '正在准备…'
if [ "$MANAGER" = openrc ]; then
    run apk add --no-cache ca-certificates curl tar iproute2
else
    run env DEBIAN_FRONTEND=noninteractive apt-get update
    run env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl tar iproute2
fi
if [ "$INSTALLED" = 0 ]; then
    case "$(uname -m)" in
        x86_64) ARCH=amd64 ;;
        aarch64) ARCH=arm64 ;;
        armv7l) ARCH=armv7 ;;
        *) fail '支持的架构：x86_64、aarch64、armv7l。' ;;
    esac
    ASSET="gost_${GOST_VERSION}_linux_${ARCH}.tar.gz"
    BASE="https://github.com/go-gost/gost/releases/download/v${GOST_VERSION}"
    run curl -fsSL --retry 3 --connect-timeout 15 --max-time 300 "$BASE/$ASSET" -o "$TASK_TMP/$ASSET"
    run curl -fsSL --retry 3 --connect-timeout 15 --max-time 60 "$BASE/checksums.txt" -o "$TASK_TMP/checksums.txt"
    HASH=$(awk -v f="$ASSET" '$2 == f || $2 == "*" f {print $1}' "$TASK_TMP/checksums.txt")
    [ "${#HASH}" = 64 ] || fail '未找到有效的官方校验值。'
    case "$HASH" in *[!a-fA-F0-9]*) fail '校验值格式不正确。' ;; esac
    printf '%s  %s\n' "$HASH" "$TASK_TMP/$ASSET" > "$TASK_TMP/verify.txt"
    run sha256sum -c "$TASK_TMP/verify.txt"
    run tar -xzf "$TASK_TMP/$ASSET" -C "$TASK_TMP" gost
    chmod 755 "$TASK_TMP/gost"
    run "$TASK_TMP/gost" -V
fi
# Stop the previous service only after all input and downloads are ready.
if [ "$INSTALLED" = 1 ]; then
    cp "$CONF" "$TASK_TMP/old-config"
    cp "$INIT" "$TASK_TMP/old-init"
    if running; then WAS_RUNNING=1; fi
    if enabled; then WAS_ENABLED=1; fi
fi
PENDING=1
if [ "$WAS_RUNNING" = 1 ]; then run service_action stop; fi
while read -r PROTO LOCAL; do
    case "$PROTO" in
        tcp) ss -H -ltn > "$TASK_TMP/listeners" ;;
        udp) ss -H -lun > "$TASK_TMP/listeners" ;;
    esac
    if awk -v p="$LOCAL" '$4 ~ (":" p "$") {found=1} END {exit !found}' "$TASK_TMP/listeners"; then
        fail "$PROTO/$LOCAL 已占用，请换一个本机端口。"
    fi
done < "$TASK_TMP/ports"
mkdir -p /usr/local/bin /etc/gost-relay
if [ "$INSTALLED" = 0 ]; then cp "$TASK_TMP/gost" "$BIN"; chmod 755 "$BIN"; fi
cp "$TASK_TMP/config.yaml" "$CONF"
chmod 600 "$CONF"
if [ "$MANAGER" = systemd ]; then
    mkdir -p /etc/systemd/system
    cat > "$INIT" <<'SYSTEMD'
[Unit]
Description=GOST TCP/UDP relay
Wants=network-online.target
After=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=/usr/local/bin/gost-relay -C /etc/gost-relay/config.yaml
Restart=on-failure
RestartSec=5
TimeoutStopSec=20
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SYSTEMD
    chmod 644 "$INIT"
else
cat > "$INIT" <<'OPENRC'
#!/sbin/openrc-run
description="GOST TCP/UDP relay"
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
fi
run reload_manager
run service_action start
sleep 2
running || fail "服务未启动，请查看 $LOG_HINT。"
while read -r PROTO LOCAL; do
    case "$PROTO" in
        tcp) ss -H -ltn > "$TASK_TMP/listeners" ;;
        udp) ss -H -lun > "$TASK_TMP/listeners" ;;
    esac
    awk -v p="$LOCAL" '$4 ~ (":" p "$") {found=1} END {exit !found}' "$TASK_TMP/listeners" || fail "$PROTO/$LOCAL 监听失败，请查看 $LOG_HINT。"
done < "$TASK_TMP/ports"
run autostart enable
PENDING=0
printf '\n  %s✓ 已启用%s  %s开机自启 · 异常重启%s\n\n' "$GREEN" "$RESET" "$DIM" "$RESET"
show_rules
printf '\n'
say '请放行所选协议和端口；本机若有 NAT，使用其公网映射端口连接。'
say '转发已有代理节点时，客户端保留原认证和 TLS/SNI 配置。'
say '已验证本机监听，目标服务连通性请用客户端确认。'
printf '\n'
