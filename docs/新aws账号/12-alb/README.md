# 12-alb —— 系统入口 ALB（Web 只经 ALB+域名访问）

**访问规范（2026-07-28 用户拍板）**：
1. 所有 EC2 的 **SSH/IP 直连一律只经堡垒机**（nonprod=css-nonprod-gw、prod=css-prod-bastion，仅放行管理 IP 221.214.0.190/32）；
2. **系统（Web）只能通过 ALB 配的域名访问**，应用机全部在私有子网、无公网 IP；
3. **RDS 只能内网访问**（`--no-publicly-accessible`，安全组仅放行 app/堡垒 SG 的 5432）。

本目录创建第 2 条的 ALB：`css-nonprod-alb`（默认→test 机 10.20.10.10，给 uat 域名时按 Host 头分流 10.20.11.10）
和 `css-prod-alb`（→prod 机 10.10.10.10）。安全组 `css-<组>-alb-sg` 已由 01-vpc 创建（80/443 对公网）。

## 怎么用

```bash
cd docs/新aws账号/12-alb
./create-alb.sh nonprod                       # 只有 test：80 默认转发 test 机
./create-alb.sh nonprod uat.你的域名.com       # test 默认 + uat 按 Host 分流
CERT_ARN=arn:aws:acm:us-east-1:...:certificate/xxx ./create-alb.sh prod   # 带 HTTPS
```

- 💰 计费：每个 ALB ~$16/月 + LCU 流量费；**等应用机（06-ec2）创建后再执行**（目标组按固定私网 IP 注册，机器不存在时健康检查全红）。
- HTTPS：先在 ACM 控制台申请证书（DNS 验证），拿到 ARN 后用 `CERT_ARN` 环境变量重跑即可补 443 监听器。
- **ALB 就绪后必须收掉过渡通道**：网关机 nginx 反代（06-ec2 user-data 里的 80/8080）与 01-vpc 中
  gw-sg 的 80/8080 管理 IP 放行、app-sg"来自 gw 的 80"规则——脚本尾部有提示清单。

## 可视化页面

**EC2 控制台 → Load Balancers**（us-east-1）：
- 直达：<https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#LoadBalancers:>
- 看什么：① ALB 状态 Active；② **Listeners and rules** 页签核对 80/443 转发与 Host 分流规则；
  ③ Target groups → css-test-tg/css-uat-tg/css-prod-tg 的 **Targets** 页签健康状态 healthy（应用机起来后）。

## 状态/注意

- ⏳ 未执行：等 Paid plan + 06-ec2 应用机 + 域名定妥后创建。
- 实例大小可以后期修改：停机 → Actions → Instance settings → Change instance type → 开机（几分钟停机窗口；
  私网 IP 与 EIP 不变，ALB 目标组按 IP 注册也不受影响）。
