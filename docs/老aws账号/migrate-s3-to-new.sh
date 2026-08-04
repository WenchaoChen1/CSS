#!/usr/bin/env bash
# 老账号 S3 桶 → 新账号环境桶【跨账号流式增量同步】（2026-08-04 新增）
#
# 与同目录 拉取S3.ps1 的区别：那个是"全量下载到本地 备份/s3/ 再可选回推"（需 7.5GB 磁盘、非增量）；
# 本脚本是【流式直传不落盘 + 增量 + 幂等】，专为"临时迁移 → 20 天后彻底迁移再跑一次"设计：
#   · 增量：逐对象比对 key+size，只传目标桶缺失或大小不同的；老环境这期间新增的文件下次自动补上
#   · 幂等：重复跑无副作用（已同步的跳过）；中断可直接重跑续传
#   · 不删除：目标桶多出来的对象（=新环境自己产生的文件）绝不动，只做"补齐"
#
# ⚠️ key 结构刻意【原样保留】不重映射（2026-08-04 读码确认）：
#   代码 key = {S3_LOCATION}/{uuid}_{文件名}，URL = {S3_ENDPOINT_URL}/{S3_STORAGE_BUCKET_NAME}/{key}。
#   老配置把桶名/区域填反了（BUCKET_NAME=eu-central-1、真桶名在 endpoint 里），boto 把"桶名"降级成
#   key 首段 → 老对象 key = `eu-central-1/files/xxx`；新环境 key = `us-east-1/xxx`。前缀不同、
#   同桶共存不冲突，所以历史文件保持老 key 搬过来即可，库里的 URL 只需换域名前缀
#   （见 05-数据库运维/rewrite-file-urls.sh）。若重映射 key 反而会让两个脚本都变复杂且不可逆。
#
# 用法:
#   ./migrate-s3-to-new.sh <test|uat|prod> [--dry-run] [--jobs N] [--src-bucket 桶名] [--prefix 前缀]
#     --dry-run     只统计差异（传多少个/多大），不传输
#     --jobs N      并发数，默认 8
#     --src-bucket  源桶，默认 chain-serve-test（老 dev/stage/preprod 三环境共用这一个桶）
#     --prefix      只同步指定 key 前缀（分批用）
# 前置:
#   · 老账号只读 profile（源环境.env 的 SRC_AWS_PROFILE，实际是 css-client）已 aws configure
#   · 新账号凭证 = 默认 profile；python3 + boto3
set -euo pipefail
cd "$(dirname "$0")"

ENV_NAME="${1:-}"; shift || true
case "$ENV_NAME" in test|uat|prod) ;; *) echo "用法: $0 <test|uat|prod> [--dry-run] [--jobs N] [--src-bucket 桶] [--prefix 前缀]"; exit 1 ;; esac

DRY=0; JOBS=8; SRC_BUCKET="chain-serve-test"; PREFIX=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --jobs) JOBS="$2"; shift ;;
    --src-bucket) SRC_BUCKET="$2"; shift ;;
    --prefix) PREFIX="$2"; shift ;;
    *) echo "[FAIL] 未知参数: $1"; exit 1 ;;
  esac
  shift
done

# python 命令名：Windows git-bash 常只有 python，Linux 常只有 python3
PY="$(command -v python3 || command -v python || true)"
[ -n "$PY" ] || { echo "[FAIL] 找不到 python/python3"; exit 1; }
"$PY" -c 'import boto3' 2>/dev/null || { echo "[FAIL] python 缺 boto3：pip install boto3"; exit 1; }

SRC_PROFILE="$(grep -E '^SRC_AWS_PROFILE=' 源环境.env 2>/dev/null | cut -d= -f2 | tr -d '\r' || true)"
SRC_PROFILE="${SRC_PROFILE:-css-client}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
DST_BUCKET="css-${ENV_NAME}-${ACCOUNT_ID}"

echo "===== S3 跨账号增量同步 ====="
echo "源: s3://$SRC_BUCKET${PREFIX:+/$PREFIX}  (profile $SRC_PROFILE, eu-central-1)"
echo "目标: s3://$DST_BUCKET  (当前账号 $ACCOUNT_ID, us-east-1)"
echo "并发 $JOBS｜$([ $DRY = 1 ] && echo '【DRY-RUN 只统计】' || echo '实际传输')"

# 身份校验：源必须是老账号，目标必须不是老账号
SRC_ACCT="$(aws --profile "$SRC_PROFILE" sts get-caller-identity --query Account --output text 2>/dev/null || echo FAIL)"
[ "$SRC_ACCT" = "021213872872" ] || { echo "[FAIL] profile $SRC_PROFILE 指向账号 $SRC_ACCT，期望老账号 021213872872"; exit 1; }
[ "$ACCOUNT_ID" != "021213872872" ] || { echo "[FAIL] 默认凭证也是老账号，目标账号配置有误"; exit 1; }

DRY="$DRY" JOBS="$JOBS" SRC_PROFILE="$SRC_PROFILE" SRC_BUCKET="$SRC_BUCKET" \
DST_BUCKET="$DST_BUCKET" PREFIX="$PREFIX" "$PY" - <<'PYEOF'
import os, sys, boto3, threading, queue
from botocore.config import Config

DRY = os.environ['DRY'] == '1'
JOBS = int(os.environ['JOBS'])
SRC_BUCKET, DST_BUCKET, PREFIX = os.environ['SRC_BUCKET'], os.environ['DST_BUCKET'], os.environ['PREFIX']
cfg = Config(retries={'max_attempts': 5, 'mode': 'standard'}, max_pool_connections=JOBS + 4)
src = boto3.Session(profile_name=os.environ['SRC_PROFILE']).client('s3', region_name='eu-central-1', config=cfg)
dst = boto3.Session().client('s3', region_name='us-east-1', config=cfg)

def index(client, bucket, prefix):
    """列全桶 → {key: size}；桶不存在/为空返回 {}"""
    out = {}
    try:
        for page in client.get_paginator('list_objects_v2').paginate(Bucket=bucket, Prefix=prefix):
            for o in page.get('Contents', []):
                out[o['Key']] = o['Size']
    except client.exceptions.NoSuchBucket:
        print('[FAIL] 桶不存在: %s' % bucket); sys.exit(1)
    return out

print('扫描源桶…', flush=True)
s_idx = index(src, SRC_BUCKET, PREFIX)
print('扫描目标桶…', flush=True)
d_idx = index(dst, DST_BUCKET, PREFIX)
print('源 %d 对象 / 目标 %d 对象（同前缀）' % (len(s_idx), len(d_idx)))

todo = [(k, v) for k, v in s_idx.items() if d_idx.get(k) != v]
skip = len(s_idx) - len(todo)
bytes_todo = sum(v for _, v in todo)
print('需传输 %d 个（%.2f GB）｜已一致跳过 %d 个' % (len(todo), bytes_todo / 1024**3, skip))
# 目标桶独有对象=新环境自己产生的文件，只报数不动它
extra = len(set(d_idx) - set(s_idx))
if extra:
    print('目标桶另有 %d 个源桶没有的对象（新环境自产文件），本脚本不会删除/覆盖它们' % extra)

if DRY or not todo:
    print('===== %s =====' % ('DRY-RUN 结束（未传输）' if DRY else '已全部一致，无需传输'))
    sys.exit(0)

q = queue.Queue()
for item in todo:
    q.put(item)
done = {'n': 0, 'bytes': 0, 'err': 0}
lock = threading.Lock()

def worker():
    while True:
        try:
            key, size = q.get_nowait()
        except queue.Empty:
            return
        try:
            obj = src.get_object(Bucket=SRC_BUCKET, Key=key)
            extra_args = {}
            if obj.get('ContentType'):
                extra_args['ContentType'] = obj['ContentType']
            # 不设 ACL：新桶 block_public_acls=true，公有读由桶策略统一提供（临时债，见 css-terraform §15-B.4）
            dst.upload_fileobj(obj['Body'], DST_BUCKET, key, ExtraArgs=extra_args or None)
            with lock:
                done['n'] += 1; done['bytes'] += size
                if done['n'] % 200 == 0 or done['n'] == len(todo):
                    print('  进度 %d/%d（%.2f GB）' % (done['n'], len(todo), done['bytes'] / 1024**3), flush=True)
        except Exception as e:
            with lock:
                done['err'] += 1
                if done['err'] <= 10:
                    print('[WARN] 失败 %s: %s' % (key[:80], str(e)[:120]), flush=True)
        finally:
            q.task_done()

ts = [threading.Thread(target=worker, daemon=True) for _ in range(JOBS)]
[t.start() for t in ts]
[t.join() for t in ts]
print('===== 完成：成功 %d 个（%.2f GB），失败 %d 个 =====' % (done['n'], done['bytes'] / 1024**3, done['err']))
if done['err']:
    print('[WARN] 有失败项——直接重跑本脚本即可续传（幂等）')
    sys.exit(1)
PYEOF

echo
echo "下一步：库里的 file_url 仍指向老桶域名，需改写 →"
echo "  bash ../环境运维执行脚本/05-数据库运维/rewrite-file-urls.sh $ENV_NAME --dry-run"
