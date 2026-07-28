# 10-自动重新部署 —— docker 服务自愈与开机自启

给环境机器装上两层"自动恢复"：**systemd 单元**（机器重启后自动建网络、按序拉起三栈）+ **5 分钟自愈 cron**（后端冒烟失败自动 `deploy.sh up` 兜底）。经 SSM 远程安装，不用上机。

> 与 CI/CD 的边界：**发布新版本**永远走 GitHub Actions（构建→推 ECR→SSM 部署）；本文件夹只管"**已部署的服务**在重启/崩溃后自动回到运行状态"，不是新的发布入口。

## 怎么用

```bash
# 前置：该环境机器已被 CI 部署过至少一次（/opt/css-cicd 存在），且是 SSM 目标（09 文件夹）
bash docs/新aws账号/10-自动重新部署/setup-autodeploy.sh test
```

装完得到：
- `css-<env>.service`（systemd，开机在 docker 之后跑 `deploy.sh <env> up`）；
- `/usr/local/bin/css-selfheal.sh` + `/etc/cron.d/css-selfheal`（每 5 分钟冒烟 `/api/docs`，失败自动 re-up，日志在 `/var/log/css-selfheal.log`）。

验证（可经 SSM 执行）：

```bash
bash docs/新aws账号/09-ssm-run-command/run.sh test 'systemctl is-enabled css-test && tail -5 /var/log/css-selfheal.log 2>/dev/null; echo ok'
```

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
