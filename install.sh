#!/bin/sh
# Alpine / OpenRC · GOST port relay
set -eu
umask 077
VERSION=3.3.0
BIN=/usr/local/bin/gost-relay
CONF=/etc/gost-relay/config.yaml
INIT=/etc/init.d/gost-relay
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
running() { rc-service "$SERVICE" status >/dev/null 2>&1; }
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
[ -f /etc/alpine-release ] || fail '仅支持 Alpine Linux。'
[ -x /sbin/openrc-run ] || fail '需要完整的 OpenRC 系统。'
# Read answers from the terminal, keeping stdin available for `wget ... | sh`.
{ exec 3</dev/tty; } 2>/dev/null || fail '请在交互式 SSH 终端运行。'
TASK_TMP=$(mktemp -d)
PENDING=0
INSTALLED=0
WAS_RUNNING=0
cleanup() {
    RESULT=$?
    trap - EXIT INT TERM
    set +e
    if [ "$PENDING" = 1 ]; then
        rc-service "$SERVICE" stop >/dev/null 2>&1
        if [ "$INSTALLED" = 1 ]; then
            cp "$TASK_TMP/old-config" "$CONF"
            cp "$TASK_TMP/old-init" "$INIT"
            chmod 755 "$INIT"
            if [ "$WAS_RUNNING" = 1 ]; then
                if rc-service "$SERVICE" start > "$TASK_TMP/restore.log" 2>&1; then
                    say '已恢复原配置和服务。'
                else
                    say "原配置已恢复，服务启动失败；请查看 $LOG。"
                    tail -n 8 "$TASK_TMP/restore.log" >&2
                fi
            else
                say '已恢复原配置，服务保持停止。'
            fi
        else
            rc-update del "$SERVICE" default >/dev/null 2>&1
            rm -f "$BIN" "$CONF" "$INIT"
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
    if "$@" > "$TASK_TMP/action.log" 2>&1; then return 0; fi
    tail -n 8 "$TASK_TMP/action.log" >&2
    fail '操作未完成，原因见上方。'
}
if [ -e "$INIT" ] || [ -e "$BIN" ] || [ -e "$CONF" ]; then
    [ -x "$BIN" ] && [ -f "$CONF" ] && [ -f "$INIT" ] || fail '检测到不完整的旧安装，请检查 /etc/gost-relay 和服务文件。'
    grep -Fq 'command="/usr/local/bin/gost-relay"' "$INIT" || fail '发现其他服务文件，未修改。'
    INSTALLED=1
fi
printf '\n  %sGOST Relay%s  %sAlpine · v2%s\n' "$CYAN" "$RESET" "$DIM" "$RESET"
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
        2) show_rules; printf '\n'; [ ! -f "$LOG" ] || tail -n 6 "$LOG"; exit 0 ;;
        3) run rc-service "$SERVICE" restart; sleep 2; running || fail "服务启动失败，请查看 $LOG。"; say '服务已启动。'; exit 0 ;;
        4)
            ask '删除转发配置和服务？[y/N]：'
            case "$ANSWER" in y|Y) ;; *) exit 0 ;; esac
            if running; then run rc-service "$SERVICE" stop; fi
            run rc-update del "$SERVICE" default
            rm -f "$BIN" "$CONF" "$INIT"
            rmdir /etc/gost-relay 2>/dev/null || true
            say "已卸载，日志保留在 $LOG。"
            exit 0 ;;
        0|'') exit 0 ;;
        *) fail '没有这个选项。' ;;
    esac
else
    printf '  %s香港入口 → 商家入口 → 落地出口%s\n' "$DIM" "$RESET"
fi
printf '\n'
say '目标填商家的 A IP 和公网映射端口。'
ask '目标 IP / 域名：'
REMOTE=$ANSWER
case "$REMOTE" in ''|*[!a-zA-Z0-9.:_-]*|-*) fail '地址格式不正确，请勿填写协议或端口。' ;; esac
case "$REMOTE" in *:*) TARGET="[$REMOTE]" ;; *) TARGET=$REMOTE ;; esac
printf 'log:\n  level: warn\nservices:\n' > "$TASK_TMP/config.yaml"
: > "$TASK_TMP/ports"
USED=' '
i=1
while :; do
    read_port '香港本机端口：'; LOCAL=$ANSWER
    case "$USED" in *" $LOCAL "*) fail '两个本机端口不能重复。' ;; esac
    USED="$USED$LOCAL "
    read_port '目标映射端口：'; DEST=$ANSWER
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
    [ "$i" = 1 ] || break
    ask '再加一个端口？[y/N]：'
    case "$ANSWER" in y|Y) i=2; printf '\n' ;; *) break ;; esac
done
printf '\n'
say '正在准备…'
run apk add --no-cache ca-certificates curl tar iproute2
if [ "$INSTALLED" = 0 ]; then
    case "$(uname -m)" in
        x86_64) ARCH=amd64 ;;
        aarch64) ARCH=arm64 ;;
        armv7l) ARCH=armv7 ;;
        *) fail '支持的架构：x86_64、aarch64、armv7l。' ;;
    esac
    ASSET="gost_${VERSION}_linux_${ARCH}.tar.gz"
    BASE="https://github.com/go-gost/gost/releases/download/v${VERSION}"
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
fi
PENDING=1
if [ "$WAS_RUNNING" = 1 ]; then run rc-service "$SERVICE" stop; fi
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
run rc-service "$SERVICE" start
sleep 2
running || fail "服务未启动，请查看 $LOG。"
while read -r PROTO LOCAL; do
    case "$PROTO" in
        tcp) ss -H -ltn > "$TASK_TMP/listeners" ;;
        udp) ss -H -lun > "$TASK_TMP/listeners" ;;
    esac
    awk -v p="$LOCAL" '$4 ~ (":" p "$") {found=1} END {exit !found}' "$TASK_TMP/listeners" || fail "$PROTO/$LOCAL 监听失败，请查看 $LOG。"
done < "$TASK_TMP/ports"
run rc-update add "$SERVICE" default
PENDING=0
printf '\n  %s✓ 已启用%s  %s开机自启 · 异常重启%s\n\n' "$GREEN" "$RESET" "$DIM" "$RESET"
show_rules
printf '\n'
say '客户端连接香港入口，原节点认证和 SNI 保持原值。'
say '请放行对应端口；香港若有 NAT，客户端填公网映射端口。'
say '已验证本机监听，出口连通性请用客户端确认。'
printf '\n'
