# 让本机浏览器/HTTP 客户端访问 AWS 入口时【绕过本地代理】，从而以直连出口 IP（在安全组白名单内）访问。
#
# 为什么需要（2026-08-05 记）：本机是双出口——
#   · SSH / psql 等原始 TCP：直连，出口固定 221.214.0.190（这个 IP 在各安全组白名单里）
#   · HTTP / HTTPS：走本地代理 127.0.0.1:7897，出口是代理服务器的 IP（实测 134.195.101.194，**会漂移**）
# 结果：test 的 kafka-ui 入口只放行 221.214.0.190/32 时，浏览器（走代理）访问会被安全组拦掉（实测 502），
# 而在代理排除列表里加上 AWS 域名后，浏览器改为直连 → 出口变成 221.x → 白名单命中 → 正常打开。
# 好处：不必把会漂移的代理出口写进 terraform 白名单（漂一次就要改代码 + apply）。
#
# 改的是【当前用户】的 WinINET 代理排除列表（ProxyOverride）——Chrome/Edge/IE 与多数用 WinINET 的程序都吃这个设置；
# Firefox 有自己的代理设置（about:config），不受影响，需另配。
# 同时同步 NO_PROXY 环境变量（curl / python / aws cli 等命令行程序看它）。
#
# 用法:
#   powershell -File 本机-AWS域名不走代理.ps1            # 查看当前状态（不改）
#   powershell -File 本机-AWS域名不走代理.ps1 -Apply     # 加入排除列表
#   powershell -File 本机-AWS域名不走代理.ps1 -Remove    # 撤销（恢复走代理）
# 生效：新开的浏览器标签/进程立即生效；已开的页面刷新一次。命令行需重开终端（读环境变量）。
param(
    [switch]$Apply,
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

# 要绕过代理的 AWS 主机模式（覆盖：各环境 ALB、开发入口 ALB、S3 直链、SSM/ECR 等 API 端点）
$patterns = @(
    '*.elb.amazonaws.com',       # 业务 ALB + 开发入口 ALB（kafka-ui 走这个）
    '*.chain-serve.com',         # <env>-demo 域名（CNAME 到 ALB）
    '*.s3.amazonaws.com',        # S3 直链（文件/发票/图片）
    's3.us-east-1.amazonaws.com',
    '*.us-east-1.amazonaws.com'  # 同区域 AWS API（ssm/ecr/rds 等）
)

$cur = (Get-ItemProperty -Path $key).ProxyOverride
if (-not $cur) { $cur = '' }
$list = @($cur -split ';' | Where-Object { $_ -ne '' })

function Show-State {
    $p = Get-ItemProperty -Path $key
    "ProxyEnable   = $($p.ProxyEnable)  (1=启用代理)"
    "ProxyServer   = $($p.ProxyServer)"
    "ProxyOverride = $($p.ProxyOverride)"
    "NO_PROXY(用户env) = $([Environment]::GetEnvironmentVariable('NO_PROXY','User'))"
    # 重新读注册表当前值，而不是脚本开头的快照——否则 -Apply 之后仍会误报"待加"
    $now = @()
    if ($p.ProxyOverride) { $now = @($p.ProxyOverride -split ';' | Where-Object { $_ -ne '' }) }
    $missing = $patterns | Where-Object { $now -notcontains $_ }
    if ($missing.Count -eq 0) { "[OK] 全部 AWS 模式已在排除列表中" }
    else { "[待加] 缺少: $($missing -join ', ')" }
}

if ($Remove) {
    $new = @($list | Where-Object { $patterns -notcontains $_ })
    Set-ItemProperty -Path $key -Name ProxyOverride -Value ($new -join ';')
    $np = [Environment]::GetEnvironmentVariable('NO_PROXY', 'User')
    if ($np) {
        $keep = @($np -split ',' | Where-Object { $_ -ne '' -and $patterns -notcontains $_ -and $_ -notlike '*amazonaws.com' -and $_ -notlike '*chain-serve.com' })
        [Environment]::SetEnvironmentVariable('NO_PROXY', ($keep -join ','), 'User')
    }
    "已撤销：AWS 域名恢复走代理"
    Show-State
    exit 0
}

if (-not $Apply) {
    "===== 当前状态（只读；加 -Apply 生效，-Remove 撤销）====="
    Show-State
    ""
    "说明：加入后浏览器访问 ALB / S3 / <env>-demo.chain-serve.com 将【直连】，"
    "      出口 IP = 221.214.0.190（安全组白名单内），test 的 kafka-ui :8085 即可正常打开。"
    exit 0
}

# ---- 应用 ----
$new = $list + ($patterns | Where-Object { $list -notcontains $_ })
Set-ItemProperty -Path $key -Name ProxyOverride -Value ($new -join ';')

# 命令行程序读 NO_PROXY（逗号分隔，且不吃通配前缀的 *，用 .domain 形式）
$noProxyAdds = @('.elb.amazonaws.com', '.chain-serve.com', '.amazonaws.com')
$np = [Environment]::GetEnvironmentVariable('NO_PROXY', 'User')
$npList = @()
if ($np) { $npList = @($np -split ',' | Where-Object { $_ -ne '' }) }
$npList += ($noProxyAdds | Where-Object { $npList -notcontains $_ })
[Environment]::SetEnvironmentVariable('NO_PROXY', ($npList -join ','), 'User')

"[OK] 已加入代理排除列表"
Show-State
""
"验证（新开一个终端，或在浏览器打开）："
"  curl -s https://checkip.amazonaws.com          # 走代理时=代理出口；本脚本不影响它（checkip 不在排除列表）"
"  浏览器打开 http://css-non-prod-entry-1482605872.us-east-1.elb.amazonaws.com:8085/   # 应出现 kafka-ui 登录页"
"⚠️ 已开着的浏览器标签要刷新；命令行程序需重开终端才读到新的 NO_PROXY。"
