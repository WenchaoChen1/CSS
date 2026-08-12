# 10-服务自愈与开机自启（原 10-自动重新部署）—— 已部署服务的自动恢复，不是发版工具

> ⏸ **以下暂不使用的只有 `setup-autodeploy.sh`**（2026-07-31 决策）——同目录的 `setup-cw-agent.sh`
> 与 `prune-docker-images.sh` 已在 test/uat 正常使用（2026-08-05）。
> 安装自愈功能前**必须先经负责人确认**，脚本已内置确认闸
> （需手动输入 `CONFIRM` 才会安装）。当前所有机器均未安装——机器重启/进程假死需人工用
> `09-远程执行与手动部署/deploy-env.sh <env>` 恢复（单个容器崩溃仍由 docker `restart:always` 自动拉起）。

给环境机器装上两层"自动恢复"：**systemd 单元**（机器重启后自动建网络、按序拉起三栈）+ **5 分钟自愈 cron**（后端冒烟失败自动 `deploy.sh up` 兜底）。经 SSM 远程安装，不用上机。

> 与 CI/CD 的边界：**发布新版本**永远走 GitHub Actions（构建→推 ECR→SSM 部署）；本文件夹只管"**已部署的服务**在重启/崩溃后自动回到运行状态"，不是新的发布入口。

## 脚本清单

### `setup-autodeploy.sh` — 经 SSM 给目标环境 EC2 装上"重启自动拉起三栈的 systemd 单元 + 每 5 分钟冒烟自愈 cron"

```bash
./setup-autodeploy.sh <test|uat|support-ref|support-demo|support-sync|prod>    # 唯一参数：环境名，只接受这几个值
./setup-autodeploy.sh test               # 给 test 环境机器配置开机自启 + 自愈（不上机，走 09 的 run.sh 下发）
```

前置：机器已是 SSM 部署目标（标签 `Environment=css-<env>`，见 09-远程执行与手动部署），且已被 CI 部署过至少一次（`/opt/css-cicd` 存在，脚本会远程校验）。
装完后重启实例验证：`systemctl status css-<env>` 应为 active(exited)，三栈自动在线。

装完得到：
- `css-<env>.service`（systemd，开机在 docker 之后跑 `deploy.sh <env> up`）；
- `/usr/local/bin/css-selfheal.sh` + `/etc/cron.d/css-selfheal`（每 5 分钟冒烟 `/api/docs`，失败自动 re-up，日志在 `/var/log/css-selfheal.log`）。

验证（可经 SSM 执行）：

```bash
bash docs/环境运维执行脚本/09-远程执行与手动部署/run.sh test 'systemctl is-enabled css-test && tail -5 /var/log/css-selfheal.log 2>/dev/null; echo ok'
```

### `setup-cw-agent.sh` — 装 CloudWatch Agent，让磁盘/内存进 CloudWatch（告警的前置条件）

```bash
./setup-cw-agent.sh <test|uat|support-ref|support-demo|support-sync|prod>      # 幂等：已装则只更新配置并重启，可反复执行
```

**为什么必须装**（2026-08-05 事故教训）：EC2 的原生 CloudWatch 指标由 hypervisor 采集——CPU、网络、
磁盘 IO 它看得见，但"客户机内部还剩多少磁盘/多少内存"看不见，那是操作系统内部的事。结果 test 机
50GB 根卷被 docker 镜像撑到 **98%**，CI 的 migrate 死在 `no space left on device`，而**当时一条告警都没有**。

上报两个指标（刻意不贪）：`disk_used_percent`（挂载点 `/`）与 `mem_used_percent`，间隔 60s，
成本约 $0.6/月/机。装完约 5 分钟指标出现在命名空间 `CWAgent`，然后 css-terraform 的
`<env>/monitoring` 传 `enable_agent_alarms = true` 才会生成 `css-<env>-ec2-disk-high`（>80%）与
`css-<env>-ec2-mem-high`（>85%）——**test/uat 已装已开（2026-08-05）**，prod 代码已开、建机后要跑本脚本。

⚠️ **换机/重建实例后必须重跑**，否则那两条告警停在 INSUFFICIENT_DATA（不误报，但等于没有防线）。
⚠️ 配置里的 `drop_device: true` 不是可选优化：默认 disk 指标带 4 个维度
`path`/`InstanceId`/`device`/`fstype`，而 CloudWatch 告警要求维度**完全匹配**，不 drop 告警永远无数据。

### `prune-docker-images.sh` — 清应用机上堆积的旧版本镜像（默认预演，`--yes` 才删）

```bash
./prune-docker-images.sh <test|uat|support-ref|support-demo|support-sync|prod> [保留版本数]         # 预演，默认保留最近 3 个版本
./prune-docker-images.sh <test|uat|support-ref|support-demo|support-sync|prod> [保留版本数] --yes    # 实际删除
```

**根因**（同一事故）：`deploy.sh` 收尾原本只跑 `docker image prune -f`，**那只删悬空镜像（`<none>` 无 tag 的）**，
而 CI 每次部署产生的是【带 tag】的版本镜像（`test-v25`、`v26`…），prune 完全不碰，于是无限堆积
（test 实测 81 个镜像 45.9GB，其中 41.28GB 是历史版本）。ECR 侧的 lifecycle 保 5 个管的是**仓库**，
跟机器上已拉下来的镜像是两件事，容易混。

策略：正在被容器使用的镜像绝不删；每个仓库按 tag 里的版本号倒序保留最近 N 个；同时清悬空镜像与构建缓存；
公共镜像（redis/kafka/rabbitmq 等，无 `<env>-vN` 形态 tag）只在悬空时清。
实测：test 释放 29GB（98% → 40%），uat 释放 20GB（79% → 40%，那次是预防性清理）。

> **常态化已落地**：`CSS_backend-main/deploy/bin/deploy.sh` 现在每次部署收尾自动跑同样的清理逻辑
> （`prune_old_images`，`KEEP_IMAGES` 默认 3）。本脚本用于**应急**（盘已经满了、CI 跑不动时先救急）
> 或想一次性用不同保留数清理时。

## 可视化页面

| 看什么 | 在哪 |
|--------|------|
| 安装/自愈的执行记录 | Systems Manager → Run Command → Command history：`https://us-east-1.console.aws.amazon.com/systems-manager/run-command/complete-commands?region=us-east-1` |
| 机器重启（触发自启验证） | EC2 实例页 → Instance state → Reboot：`https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#Instances:` |
| 服务是否真的回来了 | test/uat 页面（经非生产网关机 `http://<网关EIP>/`、`:8080`）；或 `run.sh <env> 'docker ps'` 看容器状态 |
| systemd/自愈日志 | Session Manager 上机：`systemctl status css-<env>`、`cat /var/log/css-selfheal.log` |

## 状态 / 注意

- 未安装（等 CI 首次部署跑通后对 test 执行，uat/prod 机器建好、首次部署后各跑一次）；
- 容器级 `restart: always` 已覆盖"进程挂了拉起"；本方案补的是**网络创建顺序、一次性 ocr-migrator 依赖、docker 起但栈没起**这几个缝隙；
- 自愈只做 `up`（不 pull 新镜像），所以永远不会"自动升级版本"——版本变更只可能来自 CI；
- kafka 不落盘：机器重启会丢未消费的 2FA 验证码消息（既有设计，与本方案无关）。
