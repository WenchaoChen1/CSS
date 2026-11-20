# sprint6 数据核实查询（2026-11-20）

用户要求在 test / uat / prod 上只读核实审查报告里需要数据验证的问题。查询由 Workflow 按迁移代码编写、逐条挑错，三库只读执行，结论写进 `../../审查报告.md`「〇-E」和 `findings.json` 各条的「第 9 版数据核实」。

| 文件 | 内容 |
|---|---|
| `升级前预测_uat_prod.sql` | 80 条，按旧结构（`731ddff784cc`）预测 sprint6 的 92 个迁移会动到哪些数据、会不会因现有数据失败 |
| `升级后结果_test.sql` | 44 条，在已跑完迁移的 test 上看实际结果 |
| `查询说明.json` | 每条查询的对应问题、依据的迁移行号、结果怎么读 |
| `run_ro.sh` | 只读执行：本机取 RDS 地址和 master secret ARN，经堡垒机现取密码（不落盘、不出 AWS），会话 `default_transaction_read_only=on`、语句超时 120 秒 |

用法：`./run_ro.sh <test|uat|prod> <sql 文件>`。只输出计数和 id，不输出邮箱、手机号、姓名、地址。

**uat/prod 升级前要紧挨着再跑一次 `升级前预测_uat_prod.sql`**：main 还在持续写数据（尤其 N97 的邀请占位公司、F15/F32 的计数），这次的结果只代表 2026-11-20 的时点。
