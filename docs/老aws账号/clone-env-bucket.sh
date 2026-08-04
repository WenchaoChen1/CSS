#!/usr/bin/env bash
# 把【新账号】一个环境桶的对象克隆到另一个环境桶（2026-08-04 新增，S3 迁移流程第 2 步）
#
# 为什么需要：老账号那个桶是老 dev/stage/preprod【三环境共用】的，历史文件混在一起、按环境拆不开
#   （2026-08-04 用户拍板：暂不区分，四个新桶都放同一份历史全量，只有【新产生】的文件才各归各桶）。
#   四个桶各自从老账号下载一遍 = 28 GB 走本机带宽；而同账号同区域的桶间复制是 **S3 服务端操作**
#   （copy_object，不经本机、不计流量费、大文件也秒级）→ 所以：老账号只拉一次到 test，其余三桶从 test 克隆。
#
# 与 migrate-s3-to-new.sh 的分工：
#   migrate-s3-to-new.sh  老账号 → test 桶（跨账号，走本机流式）
#   clone-env-bucket.sh   test 桶 → uat/prod/dev 桶（同账号，服务端复制）    ← 本脚本
#
# 增量 + 幂等（与 migrate 脚本同口径）：比对 key+size，只复制目标缺失/不同的；不删除目标独有对象
# （那些是该环境自己产生的文件）。20 天后彻底迁移时按同样两步重跑即可。
#
# 用法:
#   ./clone-env-bucket.sh <源env> <目标env...> [--dry-run] [--jobs N]
#   ./clone-env-bucket.sh test uat prod dev            # test 的内容克隆到其余三桶
#   ./clone-env-bucket.sh test uat --dry-run           # 预演
set -euo pipefail
cd "$(dirname "$0")"

SRC_ENV="${1:-}"; shift || true
case "$SRC_ENV" in test|uat|prod|dev) ;; *) echo "用法: $0 <源env> <目标env...> [--dry-run] [--jobs N]"; exit 1 ;; esac

DRY=0; JOBS=16; TARGETS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --jobs) JOBS="$2"; shift ;;
    test|uat|prod|dev) TARGETS+=("$1") ;;
    *) echo "[FAIL] 未知参数: $1"; exit 1 ;;
  esac
  shift
done
[ ${#TARGETS[@]} -gt 0 ] || { echo "[FAIL] 至少给一个目标环境"; exit 1; }

PY="$(command -v python3 || command -v python || true)"
[ -n "$PY" ] || { echo "[FAIL] 找不到 python/python3"; exit 1; }

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
[ "$ACCOUNT_ID" != "021213872872" ] || { echo "[FAIL] 当前凭证是老账号，本脚本只在新账号内复制"; exit 1; }

echo "===== 桶间克隆（服务端复制，不走本机带宽）====="
echo "源: css-${SRC_ENV}-${ACCOUNT_ID}｜目标: ${TARGETS[*]}｜并发 $JOBS｜$([ $DRY = 1 ] && echo 'DRY-RUN' || echo '实际复制')"

for T in "${TARGETS[@]}"; do
  [ "$T" != "$SRC_ENV" ] || { echo "跳过 $T（与源相同）"; continue; }
  echo
  echo "---- $SRC_ENV → $T ----"
  SRC_BUCKET="css-${SRC_ENV}-${ACCOUNT_ID}" DST_BUCKET="css-${T}-${ACCOUNT_ID}" \
  DRY="$DRY" JOBS="$JOBS" "$PY" - <<'PYEOF'
import os, sys, boto3, threading, queue
from botocore.config import Config

DRY = os.environ['DRY'] == '1'
JOBS = int(os.environ['JOBS'])
SRC, DST = os.environ['SRC_BUCKET'], os.environ['DST_BUCKET']
cfg = Config(retries={'max_attempts': 5, 'mode': 'standard'}, max_pool_connections=JOBS + 4)
s3 = boto3.Session().client('s3', region_name='us-east-1', config=cfg)

def index(bucket):
    out = {}
    for page in s3.get_paginator('list_objects_v2').paginate(Bucket=bucket):
        for o in page.get('Contents', []):
            out[o['Key']] = o['Size']
    return out

s_idx, d_idx = index(SRC), index(DST)
todo = [(k, v) for k, v in s_idx.items() if d_idx.get(k) != v]
extra = len(set(d_idx) - set(s_idx))
print('源 %d 个 / 目标 %d 个 → 需复制 %d 个（%.2f GB）；目标独有 %d 个（该环境自产，不动）'
      % (len(s_idx), len(d_idx), len(todo), sum(v for _, v in todo) / 1024**3, extra))
if DRY or not todo:
    print('  %s' % ('DRY-RUN 未复制' if DRY else '已一致，无需复制'))
    sys.exit(0)

q = queue.Queue()
for it in todo:
    q.put(it)
st = {'n': 0, 'err': 0}
lock = threading.Lock()

def worker():
    while True:
        try:
            key, size = q.get_nowait()
        except queue.Empty:
            return
        try:
            # 服务端复制：数据不经过本机；MetadataDirective 默认 COPY，保留 ContentType 等
            s3.copy({'Bucket': SRC, 'Key': key}, DST, key)
            with lock:
                st['n'] += 1
                if st['n'] % 500 == 0 or st['n'] == len(todo):
                    print('  进度 %d/%d' % (st['n'], len(todo)), flush=True)
        except Exception as e:
            with lock:
                st['err'] += 1
                if st['err'] <= 5:
                    print('  [WARN] %s: %s' % (key[:70], str(e)[:100]), flush=True)
        finally:
            q.task_done()

ts = [threading.Thread(target=worker, daemon=True) for _ in range(JOBS)]
[t.start() for t in ts]
[t.join() for t in ts]
print('  完成：成功 %d，失败 %d%s' % (st['n'], st['err'], '（重跑本脚本可续）' if st['err'] else ''))
sys.exit(1 if st['err'] else 0)
PYEOF
done

echo
echo "===== 全部完成 ====="
echo "别忘了各环境的库内 URL 改写（指向各自的桶）："
for T in "${TARGETS[@]}"; do
  case "$T" in test|uat|prod) echo "  bash ../环境运维执行脚本/05-数据库运维/rewrite-file-urls.sh $T --dry-run" ;; esac
done
