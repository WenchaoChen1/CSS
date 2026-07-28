# 06-ec2 —— 应用服务器 + 网络入口机 💰

两个脚本：`create-app-ec2.sh` 建各环境应用服务器（私有子网、无公网 IP、固定私网 IP、挂 `css-ec2-<env>` 实例角色，user-data 自动装 docker+compose）；`create-gateway.sh` 建网络入口机（非生产=三合一网关机，生产=堡垒机+托管 NAT 网关）。

## 怎么用

```bash
# 应用机（固定私网 IP：test 10.20.10.10 / uat 10.20.11.10 / prod 10.10.10.10）
./create-app-ec2.sh test              # t3.large（默认）
./create-app-ec2.sh uat               # t3.large（默认）
./create-app-ec2.sh prod c5.large     # 默认 c5.xlarge，第二参可覆盖

# 入口机
./create-gateway.sh nonprod [ssh-keypair名]   # css-nonprod-gw：t4g.nano+EIP 三合一
./create-gateway.sh prod    [ssh-keypair名]   # css-prod-bastion：t4g.nano+EIP 纯跳板 + NAT 网关
```

- 非生产网关机三合一：堡垒（22）/ NAT 出网（iptables）/ nginx 反代（80→test 10.20.10.10、8080→uat 10.20.11.10），并把私有路由表默认路由指向本机 ENI。
- 应用机 SSH 走跳板：`ssh -J ec2-user@<网关EIP> ec2-user@<私网IP>`；CI/CD 经 SSM 按标签 `CssEnv=css-<env>` 定位机器。
- 前置：对应组 VPC（01-vpc）与 IAM 实例角色（07-iam）已建好；脚本幂等，实例已存在即跳过。

## 可视化页面

1. **EC2 实例列表**（新账号 582797602427 / us-east-1）：
   - 直达：<https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#Instances:>
   - 按标签 `Group=css-non-prod` / `css-prod` 过滤；确认实例状态 Running、Name（`css-<env>-app` / `css-nonprod-gw` / `css-prod-bastion`）、私网 IP 与约定一致、无公网 IP（应用机）、Security 页签的安全组、IAM Role=`css-ec2-<env>`。
2. **Elastic IP 页**：
   - 直达：<https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#Addresses:>
   - 确认网关机/堡垒机各挂一个 EIP（这是外部访问与 SSH 跳板的唯一入口地址）。
3. VPC 控制台 → Route tables：确认 `*-private-rt` 默认路由已指向网关机 ENI（nonprod）或 NAT 网关（prod）。

## 状态/注意

- 💰 计费资源：约 $60-140/台/月，**等 Paid plan 后执行**；uat/prod 的 EC2 目前尚未创建。
- 应用机固定私网 IP 是网关 nginx 反代与 SSH 直达的依据，勿改。
- user-data 只在首次启动执行；建完约 1-2 分钟内 docker 才装好，别急着上机部署。
