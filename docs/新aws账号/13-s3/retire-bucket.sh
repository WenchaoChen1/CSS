#!/usr/bin/env bash
# 退役一个 S3 桶（数据已迁走后清理）：先【逐对象比对】确认目标桶不缺东西，再清空并删除源桶。
# ⚠️ 不可逆。开了版本控制的桶必须连历史版本和删除标记一起清，否则删不掉。
#
# 用法: ./retire-bucket.sh <要退役的桶> <数据已迁到的桶> yes
#   例: ./retire-bucket.sh css-test-storage-582797602427 css-test-582797602427 yes
# 不加第三个参数 yes 时只做比对、不删任何东西。
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

SRC="${1:?用法: retire-bucket.sh <源桶> <目标桶> yes}"
DST="${2:?缺目标桶（数据迁到哪了）}"
CONFIRM="${3:-}"
REGION="us-east-1"
owned() { aws s3api list-buckets --query "Buckets[?Name=='$1'].Name" --output text | tr -d '\r' | grep -q .; }
owned "$SRC" || { echo "源桶 $SRC 不存在（可能已退役）"; exit 0; }
owned "$DST" || { echo "目标桶 $DST 不存在，拒绝执行"; exit 1; }

echo "=== 逐对象比对 $SRC -> $DST ==="
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
# 绝不能用 --query 'Contents[].[Key,Size]' --output text：Windows 版 aws.exe 用 GBK 写 stdout，
# 文件名里只要有一个非 GBK 字符（实测踩到 U+202F 窄空格）就中途崩溃并截断输出，
# 比对只覆盖前面一小部分对象却报"通过"——会误删数据的静默失败。
# 改用 ETag+Size（纯 ASCII 内容指纹，与文件名无关），python 分页读 JSON、按 bytes 解码。
dump() {  # $1=桶名 $2=输出文件；每行 "<ETag>	<Size>"
  # 关键：--query 里【不要 Key 字段】。实测同一个桶：
  #   Contents[].[Key,Size]  -> 只输出 27 行后崩（文件名含 U+202F，GBK 编码失败）
  #   Contents[].[ETag,Size] -> 完整 102 行（纯 ASCII，与文件名无关）
  aws --region "$REGION" s3api list-objects-v2 --bucket "$1"     --query 'Contents[].[ETag,Size]' --output text 2>/dev/null | tr -d '' | sort > "$2" || true
}
dump "$SRC" "$TMP/src.txt"
dump "$DST" "$TMP/dst.txt"
SN=$(grep -c . "$TMP/src.txt" || true); DN=$(grep -c . "$TMP/dst.txt" || true)
echo "  源桶 $SN 个对象 / 目标桶 $DN 个对象（按内容指纹 ETag+Size 比对，与文件名编码无关）"
[ "${SN:-0}" -gt 0 ] || { echo "  [FATAL] 源桶列举为 0，比对不可信，拒绝退役"; exit 1; }
MISSING=$(comm -23 "$TMP/src.txt" "$TMP/dst.txt" || true)
if [ -n "$MISSING" ]; then
  echo "  [FATAL] 以下内容指纹在目标桶缺失，拒绝退役（共 $(echo "$MISSING" | grep -c .) 条）："
  echo "$MISSING" | head -20
  echo "  先补同步: aws s3 sync s3://$SRC s3://$DST"
  exit 1
fi
echo "  [OK] 源桶全部 $SN 个对象的内容指纹在目标桶中均存在"

[ "$CONFIRM" = "yes" ] || { echo ""; echo "比对通过。加第三个参数 yes 才会真正清空并删除 $SRC"; exit 0; }

echo "=== 清空 $SRC（含历史版本与删除标记）==="
aws --region "$REGION" s3 rm "s3://$SRC" --recursive --only-show-errors || true
# 开了版本控制的桶：当前对象删掉后还剩 versions/删除标记，必须一并清
for _ in 1 2 3; do
  PAYLOAD=$( (python3 - "$SRC" "$REGION" 2>/dev/null || python - "$SRC" "$REGION") <<'PY'
import json, subprocess, sys
b, region = sys.argv[1], sys.argv[2]
r = subprocess.run(['aws','s3api','list-object-versions','--bucket',b,'--region',region,
                    '--max-items','800','--output','json'], capture_output=True, text=True)
try: d = json.loads(r.stdout or '{}')
except Exception: d = {}
objs = [{'Key':x['Key'],'VersionId':x['VersionId']}
        for x in (d.get('Versions') or []) + (d.get('DeleteMarkers') or [])]
print(json.dumps({'Objects': objs, 'Quiet': True}) if objs else '')
PY
)
  [ -z "$PAYLOAD" ] && break
  echo "$PAYLOAD" > "$TMP/del.json"
  if command -v cygpath >/dev/null 2>&1; then DF=$(cygpath -m "$TMP/del.json"); else DF="$TMP/del.json"; fi
  aws --region "$REGION" s3api delete-objects --bucket "$SRC" --delete "file://$DF" >/dev/null
  echo "  已清理一批历史版本"
done

aws --region "$REGION" s3api delete-bucket --bucket "$SRC"
echo "===== $SRC 已退役 ====="
echo "现存桶："
aws s3api list-buckets --query 'sort_by(Buckets,&Name)[].Name' --output text | tr '\t' '\n' | sed 's/^/  /'
