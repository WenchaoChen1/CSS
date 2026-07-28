# 01-vpc —— 网络骨架（VPC / 子网 / IGW / 路由 / S3 端点 / 安全组）

一条命令建出一组环境的全套零成本网络：VPC + 2 公有 2 私有子网（跨 1a/1b 两 AZ）+ IGW + 公私路由表 + S3 Gateway 端点 + 安全组，全部打 `Group` 标签，幂等可重复执行。

## 怎么用

```bash
cd docs/新aws账号/01-vpc
./create-vpc.sh nonprod   # css-non-prod：10.20.0.0/16（test+uat 共用）
./create-vpc.sh prod      # css-prod：   10.10.0.0/16
```

- 幂等：按 Name 标签查找已有资源，存在即复用，重复跑安全。
- 网段约定：公有 `x.x.0/1.0/24`，私有 `x.x.10/11.0/24`；管理白名单 IP 写死在脚本 `ADMIN_CIDR`。
- 拓扑设计见 `docs/环境/aws-css-non-prod.md` 与 `aws-css-prod.md`。

## 可视化页面

**VPC 控制台**（新账号 582797602427 / us-east-1）：

- 直达：<https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#vpcs:>
- 入口路径：控制台 → VPC → Your VPCs

在页面上看什么：

1. VPC 列表按标签 `Group=css-non-prod` / `Group=css-prod` 过滤，确认两个 VPC 及其 CIDR（10.20.0.0/16 / 10.10.0.0/16）。
2. 左侧切到 **Subnets**：每组应有 4 个子网（`*-public-1a/1b`、`*-private-1a/1b`），AZ 与 CIDR 对得上。
3. **Route tables**：公有路由表默认路由指向 IGW；私有路由表暂无出网路由（等 06-ec2 网关建好后补）。
4. **Endpoints**：每个 VPC 有一个 S3 Gateway 端点；**Security groups** 里能看到各组的 app/rds/gw 安全组。

## 状态/注意

- ✅ 2026-07-28 两组均已执行：`css-non-prod=vpc-014be109b904d6a07`、`css-prod=vpc-0ecf70f71565ddcc8`。
- 全部资源零成本，可随时重跑核对。
- 后续脚本（04-rds / 06-ec2）都按 Name 标签查这里建的子网/安全组，删改标签会导致它们找不到资源。
