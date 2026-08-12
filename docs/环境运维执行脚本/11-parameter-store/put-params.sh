#!/usr/bin/env bash
# 把环境配置灌入 SSM Parameter Store（唯一事实源）：
#   /css/<env>/backend.env  ← 工作区 deploy-env/<env>/backend.env  （SecureString, Advanced 层）
#   /css/<env>/frontend.env ← 工作区 deploy-env/<env>/frontend.env （SecureString, Standard 层）
# （deploy-env/ 2026-07-28 由 CSS_backend-main/deploy/env 迁出，与两个代码仓库同级）
#
# 防误覆盖（2026-07-31 新增）：推送前先取远程当前值对比本地——
#   一致   → 跳过（不产生新的参数版本）；
#   有差异 → ① 把远程值备份到 deploy-env/<env>/<名>.env.remote-bak（单槽位，每次发现差异都覆盖上一次备份）
#            ② 打印【键级】差异（只列变了哪些 KEY，不回显值）③ 要求输入 yes 确认后才覆盖。
#   这样在控制台页面手动改过参数后，跑本脚本不会不知不觉把页面改动冲掉。
#
# 用法: ./put-params.sh <test|uat|support-ref|support-demo|support-sync|prod> [-y]     # -y = 跳过确认（备份与差异提示照常）
# 注意: Windows git-bash 下 aws.exe 读中文路径/编码会炸——本脚本先拷到 ASCII 临时路径并设 UTF-8。
set -euo pipefail

ENV_NAME="${1:?用法: put-params.sh <test|uat|support-ref|support-demo|support-sync|prod> [-y]}"
case "$ENV_NAME" in test|uat|support-ref|support-demo|support-sync|prod) ;; *) echo "环境必须是 test|uat|support-ref|support-demo|support-sync|prod"; exit 1 ;; esac
YES="${2:-}"
REGION="us-east-1"
export AWS_CLI_FILE_ENCODING=UTF-8
# 参数值含 ⚠ 等非 GBK 字符时，aws.exe 在中文 Windows 上输出会因 gbk 编码崩溃（曾把"读取失败"误判成
# "参数不存在"）——强制 Python UTF-8 模式根治（Linux 上无影响）
export PYTHONUTF8=1
# git-bash(MSYS) 会把 /css/... 开头的参数误转成 Windows 路径,禁用该转换(Linux 上无影响)
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../../../deploy-env/$ENV_NAME"
[ -f "$SRC_DIR/backend.env" ]  || { echo "缺 $SRC_DIR/backend.env（以同目录 example 为底稿填值）"; exit 1; }
[ -f "$SRC_DIR/frontend.env" ] || { echo "缺 $SRC_DIR/frontend.env"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
if command -v cygpath >/dev/null 2>&1; then TMPF="$(cygpath -m "$TMP")"; else TMPF="$TMP"; fi

keys_of() { grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$1" 2>/dev/null | cut -d= -f1 | sort -u; }
val_of()  { grep -E "^$2=" "$1" | tail -1; }

# key_diff <文件A> <文件B> <标题>：打印 A→B 的键级差异（只列 KEY 不回显值），无差异不打印
key_diff() {
  local A="$1" B="$2" TITLE="$3" ONLY_A ONLY_B CHANGED="" k
  keys_of "$A" > "$TMP/ka"; keys_of "$B" > "$TMP/kb"
  ONLY_A=$(comm -23 "$TMP/ka" "$TMP/kb" | tr '\n' ' ')
  ONLY_B=$(comm -13 "$TMP/ka" "$TMP/kb" | tr '\n' ' ')
  while read -r k; do
    [ "$(val_of "$A" "$k")" = "$(val_of "$B" "$k")" ] || CHANGED="$CHANGED$k "
  done < <(comm -12 "$TMP/ka" "$TMP/kb")
  [ -z "$ONLY_A$ONLY_B$CHANGED" ] && return 0
  echo "  $TITLE"
  [ -n "$ONLY_B" ]  && echo "    · 新增: $ONLY_B"
  [ -n "$ONLY_A" ]  && echo "    · 删除: $ONLY_A"
  [ -n "$CHANGED" ] && echo "    · 改值: $CHANGED"
  return 0
}

# put_one <本地文件> <参数名后缀> <tier>
put_one() {
  local SRC="$SRC_DIR/$1" NAME="/css/$ENV_NAME/$1" TIER="$2"
  local LOCAL="$TMP/local-$1" REMOTE="$TMP/remote-$1"
  # 归一化：去 \r + 去尾部空行（--output text 取回的值会带一个附加换行，不归一会误报差异）
  printf '%s' "$(tr -d '\r' < "$SRC")" > "$LOCAL"

  # 取远程当前值。只有明确的 ParameterNotFound 才算"首次灌入"；其他任何读取失败一律中止，
  # 绝不盲推（否则可能在没看到远程内容的情况下把它覆盖掉）。
  local GET_OK=1
  aws ssm get-parameter --region "$REGION" --name "$NAME" --with-decryption \
    --query 'Parameter.Value' --output text > "$REMOTE.raw" 2> "$TMP/err-$1" || GET_OK=0
  if [ "$GET_OK" = 0 ] && ! grep -q "ParameterNotFound" "$TMP/err-$1"; then
    echo "[$1] ❌ 读取远程失败（非'参数不存在'），为防误覆盖已中止本参数："
    sed 's/^/      /' "$TMP/err-$1"
    return 1
  fi
  local BAK="$SRC_DIR/$1.remote-bak"
  if [ "$GET_OK" = 1 ]; then
    printf '%s' "$(tr -d '\r' < "$REMOTE.raw")" > "$REMOTE"
    # 基准 = 上次运行时备份的远程值（.remote-bak）。三方对比：基准 / 远程当前 / 本地底稿
    local BASE="$TMP/base-$1" HAS_BASE=0
    if [ -f "$BAK" ]; then HAS_BASE=1; printf '%s' "$(tr -d '\r' < "$BAK")" > "$BASE"; fi

    if cmp -s "$LOCAL" "$REMOTE"; then
      cp "$REMOTE.raw" "$BAK"   # 刷新基准（单槽位）
      echo "[$1] 远程与本地一致，跳过（不产生新版本；基准备份已刷新）"; return 0
    fi

    # —— 有差异：三方键级对比 + 备份远程（单槽位）+ 确认 ——
    echo "[$1] ⚠️ 远程与本地存在差异（键级对比，只列 KEY 不回显值）："
    if [ "$HAS_BASE" = 1 ]; then
      local D1 D2
      if cmp -s "$BASE" "$REMOTE"; then
        echo "  ① 远程 自上次备份以来【无变化】（差异全部来自你本地的修改）"
      else
        D1=$(key_diff "$BASE" "$REMOTE" "① 远程 自上次备份以来的变化（页面/他人改的，覆盖后将丢失）：")
        echo "${D1:-  ① 远程 自上次备份以来有变化，但仅注释/空行/顺序（无键级变化）}"
      fi
      if cmp -s "$BASE" "$LOCAL"; then
        echo "  ② 本地底稿 相对上次备份【无修改】（差异全部来自远程侧）"
      else
        D2=$(key_diff "$BASE" "$LOCAL" "② 本地底稿 相对上次备份的修改（你改的，将推到远程）：")
        echo "${D2:-  ② 本地底稿 相对上次备份有改动，但仅注释/空行/顺序（无键级变化）}"
      fi
    else
      echo "  （无上次备份，首次对比没有基准，只能给出两边净差异）"
    fi
    local NET
    NET=$(key_diff "$REMOTE" "$LOCAL" "③ 覆盖后的净变化（远程 → 本地）：")
    if [ -n "$NET" ]; then echo "$NET"; else echo "  ③ 覆盖后的净变化：无键级变化（仅注释/空行/顺序差异）"; fi
    cp "$REMOTE.raw" "$BAK"
    echo "  远程当前值已备份到 $BAK（单槽位，已覆盖旧备份）"
    if [ "$YES" != "-y" ]; then
      local ANS=""
      read -rp "  确认用【本地】覆盖【远程】？(yes/其他=跳过) " ANS || true
      [ "$ANS" = "yes" ] || { echo "[$1] 已跳过，远程未动（想采纳远程改动：对照 $BAK 更新本地底稿后重跑）"; return 0; }
    fi
  else
    echo "[$1] 远程参数不存在，首次灌入"
  fi

  cp "$SRC" "$TMP/push-$1"
  aws ssm put-parameter --region "$REGION" --name "$NAME" \
    --type SecureString --tier "$TIER" --overwrite --value "file://$TMPF/push-$1" >/dev/null
  local LEN
  LEN=$(aws ssm get-parameter --region "$REGION" --name "$NAME" --with-decryption \
    --query 'length(Parameter.Value)' --output text | tr -d '\r')
  echo "[$1] ✅ 已灌入 $NAME（长度 $LEN 字符）"
}

put_one backend.env  Advanced
put_one frontend.env Standard

echo "生效: 后端变量重跑 deploy job / deploy-env.sh <env> core 即可；前端 VITE_* 需重新构建镜像"
