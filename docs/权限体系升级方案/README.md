# Chain Serve 权限体系升级方案

> 一个用户、多个 Account、统一组织表，与「菜单 / 按钮 / 接口 / 数据」四级权限

| | |
|---|---|
| **范围** | CSS_backend（FastAPI）+ CSS_frontend（React 19） |
| **依据** | **test 分支**（= main + ops + support-demo）代码调研与逐条复核（初稿基于 main，2026-08-27 已按 origin/test 复核勘误） |
| **日期** | 2026-08-27 |
| **客户版页面** | https://claude.ai/code/artifact/3cfd78fe-3684-438e-83f6-822a581f801f |

> **分支基线说明**：test 分支包含 support-demo 老团队代码线的完整功能面（Quotations 全域、Manufacturers 区块、制造商分部层级、4 个新后端领域、22 个独有迁移），这些**尚不在 uat/prod 主线（main + ops）上**。本方案以 test 为准；涉及 test 独有功能面的权限设计，需在该功能面合入主线时同步落地。

**目录**

- [1. 需求与目标](#1-需求与目标)
- [2. 现状盘点](#2-现状盘点)
- [3. 目标权限模型](#3-目标权限模型)
- [4. 这样做的好处](#4-这样做的好处)
- [5. 菜单规划：新增、调整与下线](#5-菜单规划新增调整与下线)
- [6. 实施分期](#6-实施分期)
- [7. 表结构整合：多表归一](#7-表结构整合多表归一)
- [8. 需要修改的内容](#8-需要修改的内容)

---

## 1. 需求与目标

**典型场景：主管登录。** 张主管是**一个用户**（一次注册、一套登录凭证），名下有 4 个 account：A 公司总部（角色 Manager）、A 的子公司 A1（角色 CEO）、B 公司旗下两家餐厅（角色 Restaurant Manager）。登录后系统列出这 4 个 account；她选择「A 公司总部」进入，菜单、按钮、接口、数据都按 A 公司给 Manager 配置的权限呈现，且能看到 A1 子公司的数据；随时可切换到 B 公司餐厅的 account，界面与数据随之切换。

| 编号 | 需求 | 说明 |
|---|---|---|
| R1 | 一人多 account | 一个用户（user，登录身份）名下可有多个 account；**每个 account 精确绑定一个组织实体**（公司/子公司/餐厅/门店）和该处的一个角色，互不影响 |
| R2 | account 聚合与切换 | 登录后返回该用户的全部 account 清单；选择「当前 account」进入系统，可随时切换；记住上次选择、支持默认 account |
| R3 | 四级权限统一配置 | 页面菜单、按钮、接口、数据四个层面的权限都由后端配置并下发，前端不再硬编码 |
| R4 | 公司级权限自定义 | 沿用现有机制：同一角色在不同公司可配置不同权限（保留现有权限矩阵管理页并扩展） |
| R5 | 组织层级继承 | 父公司角色可按配置向下管辖子公司及其餐厅/门店；数据范围支持「本人/本实体/本公司/本公司含子公司」四档 |
| R6 | 权限管理界面 | 在现有「角色 × 权限 × 实体」矩阵页基础上，扩展菜单勾选、按钮勾选、数据范围下拉三个维度 |

---

## 2. 现状盘点

本方案不是推倒重来——现有代码已经具备一套「按公司自定义」的 RBAC 骨架，改造重点是**解除限制、归并冗余表结构、补齐消费链路**。

### 2.1 已有的能力 —— 既是复用基础，也是缺口所在

| 能力 | 现状与重大问题 |
|---|---|
| 组织树 | 公司支持父子层级（`parent_company_id` 自引用），公司下按类型挂餐厅 / 门店 / 制造分部三种业务实体；test 线已新增递归作用域查询（`get_descendant_company_ids` / `get_scoped_*`，main 上没有）。<br>**问题：公司关联太散**——公司和公司下的餐厅 / 门店 / 制造分部分成四个部分，权限、用户邀请等功能各做一套，改一处公司权限逻辑，四个部分都要跟着改。 |
| Account 的雏形 | 四张 member 表（公司/餐厅/门店/分部），每条记录 = 用户 × 一个实体 × 一个角色——正是「account」的形态；前端接口已叫 `/me/accounts`、状态叫 `activeAccount`。<br>**问题：**同构表拆四份，成员逻辑写四遍（team 门面、鉴权分支各四套）——**用户注册、用户权限的维护要做四次**，现有邀请码、邀请注册逻辑太散，同一个改动要维护多遍。 |
| 后端接口权限体系 | 一条完整的「角色 → 权限矩阵 → 接口鉴权」链路已经在跑：角色按「业务类型 × 公司层/实体层」二维划分；权限字典 = 增/查/改/删 × 12 个业务实体（test 线新增按业务类型收窄的实体白名单 `ALLOWED_API_ENTITIES_BY_BUSINESS_TYPE`，旧 `GET /entities` 已弃用）；权限按公司定制，存于 `company_role_permission` 四元组（公司 × 角色 × 权限 × 实体）并有管理界面（Settings → 权限矩阵页）；接口层由 `check_permissions` 依赖注入消费，已覆盖 200+ 处接口，CEO 直通、公司成员对下属门店有回退继承。<br>**问题：**① **只管后端 API，管不到前端页面菜单和按钮**——页面/按钮显隐由前端另一套硬编码体系决定（47 个角色 UUID、12 个角色缺权限条目、登录后界面近乎空白），管理员在矩阵页改权限，前端零消费、显隐完全无效；② 角色是全局种子数据，**公司不能新建、不能改名**；③ 鉴权四条实体分支重复维护，**租户取自 URL 参数而非登录态**、漏带参数或漏挂依赖的接口没有兜底，CEO 直通靠 `'CEO'` 字符串比较（test 线另有 CEO 写保护）——角色改名即静默失效。 |
| 切换身份的前端交互 | 侧边栏已有「切换账号」弹窗（母公司 ↔ 旗下门店/餐厅），切换实体即切换角色。<br>**问题：切换纯前端改内存、不经过后端**——很容易出现权限混乱，让不该在这个门店可见的菜单出现，不是最佳实践。 |

> ⚠️ **这些能力的另一面：数据太散，维护难度大。** 上面的机制虽然可以复用，但它们建立在**分散的表结构**之上：人员关系拆在 4 张同构的 member 表里，组织实体拆在公司 + 3 张同构的实体表里。每一项能力都因此要按实体类型写多份逻辑（鉴权四分支、作用域两套、/me 三路分流）——既是复用基础、也是关键缺口，这正是 [§7 表结构整合](#7-表结构整合多表归一) 要解决的问题。

### 2.2 其余关键缺口

| 缺口 | 说明与影响 |
|---|---|
| 菜单/按钮权限前端写死 | 前端 **26 个权限点**的布尔矩阵硬编码在 `constants/permissions.ts`；`roles.ts` 已有 **47 个角色 UUID 常量**，rules 只覆盖 35 个——**缺 12 个角色条目**（8 个 `MANUFACTURER_SUBDIVISION_*` + STORE_PARTNER + ADMIN + 2 个 vendor 公司角色）；后端下发的权限矩阵被合并进 AbacProvider 后**无任何组件消费**（`useMakeApiPermission` 在 test 全树 0 调用点，已重验）。<br>**影响：**管理界面改权限矩阵对前端显隐无效；缺条目的角色（如全部分部角色）登录后侧边栏近乎全空——可复现的功能性缺陷。 |
| 路由裸奔 | settings / orders / products / dashboard / subscribers / masterDatabase / catalog / chats 等路由无权限守卫；test 线**又新增 11 条零权限路由**（Quotations 7 条 + Manufacturers 4 条，代码注释自认 "No dedicated permission yet"）。<br>**影响：**菜单权限形同虚设，越权访问面在 test 上进一步扩大。 |
| 新功能面以「公司类型」代替权限 | test 线的 Quotations 侧边栏项对所有公司类型硬编码可见；Manufacturers 区块、Settings → Information 页签靠 `isVendor` / 公司类型判断显隐，不判角色。<br>**影响：**vendor 的任意角色（含司机、打包员）都能进入厂商条款、报价单等敏感页面。 |
| 数据权限无统一模型 | 数据隔离依赖每个接口在 URL 里带 `company_id / business_id` 再逐个校验成员关系；无「本人/本实体/本公司/含子公司」数据范围概念；鉴权中间件不递归父子公司（test 线的递归 CTE 只用于订单服务）。<br>**影响：**父公司主管看不到子公司数据；漏带参数或漏挂校验的接口没有兜底。 |
| 登录态不带业务上下文 | JWT 只含平台级角色（user/admin），无公司、无业务角色（test 上 `auth/tokens/services.py` 未改）。<br>**影响：**多 account 场景下「当前以哪个身份操作」无处表达。 |
| 隐式身份切换无治理 | test 线的 `useOpenQuotationDocument` 会为打开单据**自动 `changeActiveAccount`**——活动账号不再只由用户手动切换，而前端角色恰恰派生自 activeAccount。<br>**影响：**「打开一个链接就可能换角色」；account 切换设计必须把这条隐式路径纳入统一上下文机制。 |
| 无菜单资源表 | 数据库没有 menu / 资源表，页面与按钮不在权限模型管辖范围内。<br>**影响：**菜单、按钮两级权限无法配置化。 |

---

## 3. 目标权限模型

```
用户 User（一个人 · 一次注册 · 全局唯一登录身份，user 表）
  │
  │ 1 : N  一个用户名下多个 account
  ▼
Account（身份账户 · 新增 account 表，四张 member 表归一 · 权限判定的唯一锚点）
  │
  │ 每个 account 绑定「一个组织实体 + 一个角色」
  ▼
统一组织表 company（type 区分：公司 / 子公司 / 餐厅 / 门店 / 分部，parent_id 一棵树）
  ×
角色 role（按公司定制：company_role_permission / company_role_resource / data_scope）
  │
  │ 当前 account 的角色展开为四类权限
  ▼
┌──────────┬──────────┬──────────────────┬──────────────┐
│ 菜单权限  │ 按钮权限  │ 接口权限          │ 数据权限      │
│ resource │ resource │ 现有 permission × │ 新增          │
│ type=menu│ type=btn │ entity 机制       │ data_scope   │
└──────────┴──────────┴──────────────────┴──────────────┘
```

**核心原则：「当前 account」是所有权限判定的唯一锚点。** 用户登录后选定一个 account（登录态随即携带 account_id），后续菜单渲染、按钮显隐、接口校验、数据过滤全部基于该 account 所绑定的实体与角色展开；切换 account 即整体切换权限视图。**用户本身不直接持有任何业务权限——权限永远属于 account。**

### 四类权限分别如何落地

| 层级 | 控什么 | 怎么做 |
|---|---|---|
| 菜单权限 | 侧边栏菜单与页面路由的可见/可进入 | 新增资源表登记全部页面（编码+路径+树形结构），角色关联可见菜单；登录/切换 account 后调 `GET /me/permissions` 一次性下发菜单树，侧边栏按下发渲染，路由守卫按同一份数据拦截直敲 URL |
| 按钮权限 | 页面内操作按钮的显隐与可用 | 按钮作为资源表中 type=button 的叶子节点，编码如 `team:member:delete`；随菜单树一起下发权限码集合，前端 `usePermission('code')` 统一判定（替换硬编码布尔矩阵） |
| 接口权限 | 每个 API 是否允许当前 account 调用 | **沿用现有** `check_permissions('{动作}__{实体}')` 机制，两点增强：① 支持父公司递归管辖子公司（复用递归查询）；② 清点补挂未受保护接口，「无权限点 = 拒绝」成为默认 |
| 数据权限 | 同一列表接口不同人看到的数据行范围 | 「公司 × 角色」维度增加数据范围配置：**本人/本实体/本公司/本公司含子公司**四档；服务层按当前 account + 数据范围统一注入过滤条件（组织树展开复用 test 线已有的 `get_descendant_company_ids` 递归 CTE——目前它只被公司级订单服务使用，需推广为统一 scope 解析器并接入鉴权） |

---

## 4. 这样做的好处

1. **一人一号通行，贴合连锁与托管场景**——集团高管、区域主管、受托运营方不再需要多套登录凭证；一个用户名下的多个 account 覆盖多品牌、多公司、多门店，每个 account 的角色与权限独立设置又可集中管理。
2. **权限调整零发版**——菜单、按钮、接口、数据范围全部数据驱动，管理员界面勾选即时生效。
3. **前后端权限一致，堵住越权面**——菜单显隐与接口校验同源；「无权限点即拒绝」成为接口层默认；消除「侧边栏隐藏但 URL 直达」的现状。
4. **表结构归一，长期维护成本大降**——成员逻辑 4 套归 1、实体逻辑 3 套归 1，新组织形态加枚举即可；鉴权、作用域、审计都锚定单一 account_id。
5. **复用率高，改造风险可控**——约七成机制是收敛与复用而非新建；表整合采用保 id 迁移 + 兼容视图，业务数据零改写，现有单 account 用户行为不变，可分期灰度。
6. **组织层级真正生效**——父子公司与门店统一一棵树，总部主管天然管辖下级，为集团级报表与合并视图打底。
7. **审计与合规就绪**——权限判定收敛到统一入口，谁以哪个 account 做了什么、权限何时被谁修改，单点可记录、可追溯。

---

## 5. 菜单规划：新增、调整与下线

现有侧边栏菜单清单（按公司类型 + 硬编码权限点拼装）：Dashboard、Orders、Products、Chats、Clients、Vendors、Invoices、Team、Packing Slips、Quotations（vendor 含子菜单）、Catalog、Settings，制造商另有专用导航（Manufacturers / MFR Contact / Catalog），平台管理员走独立的 Admin 侧边栏（Subscribers、Master Database）。

### 5.1 新增菜单

| 菜单 | 归属 | 说明 | 可见范围 |
|---|---|---|---|
| **菜单管理** | 平台管理（Admin 区） | 维护 `resource` 树：菜单/按钮的编码、路径、图标、排序、启用停用；新页面上线登记于此即纳入权限管辖 | 平台管理员 |
| **角色管理** | 公司设置 | 公司自定义角色（现在角色是全局种子数据，只能选不能建改）：新建角色、复制模板角色、停用 | 公司管理员（CEO 等） |
| **权限配置** | 公司设置（现有权限矩阵页升级） | 在「角色 × 接口权限 × 实体」矩阵基础上扩展：菜单勾选、按钮勾选、数据范围下拉四个维度一页配齐 | 持权限管理权的角色 |
| **组织架构** | 公司设置 | 公司/子公司/门店/餐厅一棵树的可视化维护：建子公司、挂门店、调整层级；取代 Settings 里分散的 My Stores / 餐厅页签 | 公司管理员 |
| **成员与 Account 管理** | Team 升级 | 按 account 维度管理：给一个人分配/回收多个 account、跨实体授权、设默认 account、启停 | 持团队管理权限的角色 |
| **审计日志** | 公司设置 / Admin 区 | 权限变更记录（谁在何时改了哪个角色的什么权限）+ 现有 `user_action_log` 的界面呈现 | 公司管理员 / 平台管理员 |
| **Account 切换器** | 顶栏常驻组件（非侧边栏菜单） | 显示当前 account（公司/门店 + 角色），点击展开该用户全部 account 分组列表 | 所有多 account 用户 |

### 5.2 调整的菜单

| 菜单 | 调整内容 |
|---|---|
| **全部侧边栏菜单** | 渲染方式从「前端按公司类型 + 权限点硬编码拼装」改为**后端菜单树下发**；所有现有菜单项登记进 `resource` 表，成为可配置对象 |
| **Settings** | Permissions 页签升级为「权限配置」；My Stores / 餐厅相关页签并入「组织架构」；Billing、Notifications 等保留 |
| **Team** | 从单实体成员列表升级为「成员与 Account 管理」 |
| **Dashboard / 报表类** | 数据随当前 account + data_scope 呈现：父公司 account 可聚合查看子公司与下辖门店数据 |
| **Quotations 区块**（test 线） | 7 条路由目前**零权限点**、侧边栏对所有公司类型硬编码可见（代码注释自认 "No dedicated permission yet"）；登记进 resource 树并新设权限点（如 `READ_QUOTATIONS_PAGE` / `EDIT_QUOTATION` / `SEND_QUOTATION` / `SIGN_QUOTATION` / `EDIT_QUOTATION_NUMERATION`） |
| **Manufacturers 区块**（test 线） | MFR Contact / MFR Catalog 等 4 条路由可见性靠 `isVendor` 公司类型判断而非角色权限（vendor 的司机/打包员也能直达 URL）；同样登记进 resource 树并新设权限点（如 `READ_MANUFACTURERS_PAGE` / `EDIT_MFR_TERMS`） |
| **Admin 独立侧边栏** | Subscribers、Master Database 并入统一菜单机制，成为 resource 树中仅平台管理员可见的节点；双侧边栏体系收敛为一套（test 上 AdminSidebar 已重写为 Manufacturer/Vendor × E&S / F&B / Broadliner 两级筛选树，收敛时保留该信息架构） |
| **制造商专用导航** | 功能保留，但取消「制造商走另一套导航列表」的硬编码分流，统一由菜单树 + 权限控制可见性；test 线新增的 Settings → Information 页签（厂商主数据）目前仅按公司类型显隐、不判角色，需补权限点 |

### 5.3 下线 / 废弃

| 项目 | 说明 |
|---|---|
| 面向用户的功能菜单 | **无删除**——本次不砍任何业务功能 |
| 前端硬编码权限体系 | `constants/permissions.ts` 的 26 个权限点布尔矩阵、`constants/roles.ts` 的 47 个角色 UUID 常量、按公司类型拼菜单的 `Sidebar/utils.ts` 逻辑，随后端下发上线后废弃 |
| 移动端菜单特例 | Clients / Team 菜单项移动端写死可见的问题，随菜单树驱动一并消除 |
| 旧表 | 四张 member 表、三张实体表在兼容期结束后下线（见 [§7.3](#73-迁移策略与风险诚实项) 两步走） |

---

## 6. 实施分期

| 阶段 | 内容 | 交付 |
|---|---|---|
| **Phase 1：表结构整合 + 一人多 account** | 组织实体表归一（保 id 迁移 + 兼容视图）；account 表归一；account 选择与切换（含上下文签发）；接口鉴权四分支合一并全量清点补挂；父子公司递归管辖 | 主管一个用户多 account 登录、切换、按 account 鉴权 |
| **Phase 2：菜单/按钮配置化** | resource 表 + 角色资源关联 + 默认模板；`GET /me/permissions` 下发；前端菜单/按钮/路由守卫全面接入；**菜单管理、角色管理、权限配置**三个管理页上线 | 改权限不发版，界面与后端一致 |
| **Phase 3：数据权限** | 数据范围四档配置；统一 scope 解析与行级过滤；核心列表（订单/发票/团队/报表）接入；权限变更审计日志 | 同一页面按 account 呈现不同数据范围 |

**兼容性说明**：现有单公司用户不受影响——只有一个 account 的用户登录后自动进入该 account，行为与今天一致；表整合采用保 id + 兼容视图策略（见 [§7.3](#73-迁移策略与风险诚实项)），业务表外键值零改写，可灰度、可回退；所有迁移先在 test / uat 演练。

---

## 7. 表结构整合：多表归一

本方案包含两项结构性整合，它们是让 account 模型成立的地基。

### 7.1 整合一：四张成员表 → 一张 `account` 表

把 `company_member` / `restaurant_member` / `store_member` / `manufacturer_subdivision_member` 归并为一张 `account` 表：

```
account(id, user_id, entity_id → company.id, role_id, first_name, last_name,
        position, security_code, is_active, is_default, created_at, ...)
UNIQUE (user_id, entity_id)
```

**之前存在的问题：**

1. **同构四份，逻辑写四遍。** 四张表结构几乎相同（user_id + 实体 id + role_id + is_active），任何成员相关功能都要复制四份：team 领域（`team/services.py`）就是对四张表做的聚合门面，按 COMPANY / RESTAURANT / STORE 各写一遍归属校验；接口鉴权中间件（`middlewares/permissions/middlewares.py`）有 `check_company_member_permissions` / `check_restaurant_permissions` / `check_store_permissions` / `check_subdivision_permissions` 四条并行分支。
2. **「当前身份」无法用一个 id 表达。** JWT 里放不进权限锚点，只能靠 URL 用四种参数名传实体 id（`company_id` / `restaurant_id` / `vendor_id` / `subdivision_id`），其中 `vendor_id` 实际是 store_id——命名混乱已是四表并行的直接后果。
3. **查一个人的全部身份要 UNION 四张表。** `/me/accounts` 的聚合逻辑复杂，「一人一公司」的单值查询假设（`scalar_one_or_none`）正是从这里长出来的。
4. **档案重复四份。** first_name / last_name / security_code 在四张表里各存一份（仅 `position` 是 company_member 独有）——同一个人在不同实体下档案重复、改名要改多处，且四份之间没有一致性保障。
5. **审计指向不明。** `user_action_log.team_member_id` 无法表达指向四张表中的哪一张，审计追溯困难。

**这样做的好处：**

1. **account_id 成为权限、登录上下文、审计的统一锚点**——JWT / 请求头带一个 id 即可定位「谁、在哪个实体、什么角色」。
2. **鉴权四分支归一**：`check_permissions` 只需按 account 查一次，成员管理、邀请、启停用一套代码。
3. **新组织类型零建表**：未来加仓库、中央厨房等实体形态，不再需要新建第五张 member 表。
4. **约束与治理统一**：唯一约束、is_active、is_default、软删除在一处管理；档案不再重复四份。
5. **与前端概念直接对齐**：前端本就叫 `activeAccount` / `Change account`，后端补上同名实体后，两端说同一种语言。

### 7.2 整合二：餐厅 / 门店 / 分部表 → `company` 表（type 区分）

把 `restaurant` / `store` / `manufacturer_subdivision` 三张实体表并入 `company` 表，通过 `type` 字段区分类型，层级统一用 `parent_id`：

```
company(id, type ∈ {company, restaurant, store, subdivision, ...},
        parent_id → company.id, name, alternative_name, display_name,
        phone_number, email, address, opening_time, ..., 门店特有字段为可空列)
```

**之前存在的问题：**

1. **三张表字段高度对称**（name / alternative_name / display_name / opening_time / phone_number / email / address），仅门店多几个配送、打包开关——同一套字段维护三份，加一个公共字段要改三张表加三个迁移。
2. **两套层级机制并存。** 公司之间靠 `parent_company_id`，公司到门店靠 `company_id`——本质都是「上级组织」，却是两套外键、两套查询；数据作用域展开要分别写 `get_scoped_restaurant_ids` / `get_scoped_store_ids`（`companies/repositories.py:142-158`）。
3. **代码到处按类型三路分流。** `/me` 接口按 `company.type` match/case 三个分支取不同表（`main_app/me/services.py:70-77`）；`BusinessEntityType` 枚举（company/restaurant/store/manufacturer_subdivision）本身就证明系统一直把它们当同一抽象在用，只是表没跟上。
4. **订单等核心表无法直接表达租户。** `order` 没有 company_id，靠 `restaurant_id` + `store_id` 双外键，推导归属公司要二跳 JOIN。
5. **account 表无法建真外键。** 若实体表不归一，account 只能存 `entity_type + entity_id` 软引用，数据库层失去引用完整性保障。

**这样做的好处：**

1. **组织统一为一棵树**：`parent_id` + `type` 一套机制覆盖「集团 → 公司 → 子公司 → 门店/餐厅」，递归 CTE 一个查询算出任意节点的全部下辖范围——数据权限的 COMPANY_TREE 档位天然实现。
2. **account.entity_id 成为真外键**（指向统一 company 表），数据库层保证引用完整性。
3. **权限、数据范围、菜单配置的「实体维度」统一**，接口鉴权、scope 解析器不再按实体类型写分支。
4. **新组织形态加一个枚举值即可**（仓库、中央厨房、区域分公司……），无需建表、无需新增 member 表与鉴权分支。
5. **组织架构管理页与集团级报表**直接建立在一棵树上，聚合、下钻、权限继承同源。

### 7.3 迁移策略与风险（诚实项）

这两项整合是全方案中**最重的 schema 迁移**，必须正视代价：

- **引用面广**：`order` / `client` / `store_product` / `restaurant_license` / delivery 等大量表的外键指向 restaurant / store。
- **关键策略——保 id 迁移**：把 restaurant / store / subdivision 的原 UUID **原样搬入 company 表**（UUID 全局唯一，无冲突）。这样业务表里已存的外键**值不用改一行数据**，只需把外键约束的目标表改指向 company——迁移成本大幅下降。
- **字段差异处理**：门店特有的配送/打包开关等字段做成可空列（或扩展子表），type 不匹配时留空。
- **分两步走**：第一步建兼容视图（`restaurant` / `store` 视图映射到 company 表对应 type），存量代码零改动先跑通；第二步逐模块把 ORM 切到统一模型，最后删视图与旧表。
- **环境演练与迁移链分叉**：alembic 迁移先在 test / uat 全量演练并对比数据一致性后再上 prod。⚠️ 特别注意：test 分支为恢复单 head（`e8f2a4b6c1d3` 线）**删除了 main 独有的种子迁移 `b3d9f1a2c4e5`**（提交 b0ea653c），即 main→test 的迁移链不是纯追加——本方案的新迁移必须按分支线分别指定 down_revision（test 线接 `e8f2a4b6c1d3` 之后、主线接 `b3d9f1a2c4e5` 之后），跨线合并时会再次撞 head，需要提前规划 merge revision；同时确认被删的 liquor vendor company type 种子是否要在 test 线补回。

---

## 8. 需要修改的内容

### 8.1 数据库

| 改动 | 内容 |
|---|---|
| **新增** `account` 表 | 四张 member 表归一（见 §7.1），数据迁入后旧表下线；档案字段随迁 |
| **改造** `company` 表 | 吸收三张实体表（见 §7.2）：扩展 `type` 枚举、统一 `parent_id`、补可空特有字段；原实体 UUID 保 id 迁入 |
| **新增** `resource` 表 | 统一登记菜单与按钮（id、parent_id、code、type=menu\|button、path、icon、排序），一棵树管两级权限 |
| **新增** `company_role_resource` 表 | 公司 × 角色 × 资源，与现有 `company_role_permission` 同构；另备平台默认模板，公司未配置时回退 |
| **新增** 数据范围 | 公司角色配置上增加 `data_scope`（SELF / ENTITY / COMPANY / COMPANY_TREE） |

### 8.2 后端

| 改动 | 内容 | 位置 |
|---|---|---|
| account 领域落地 | 新建 account domain（service + repository），四张 member 表逻辑收敛于此；`/me/accounts` 返回该用户名下全部 account 清单（按公司分组，标明所绑实体与角色），解除「一人一公司」的单值查询假设 | `internal/core/` 新增，`main_app/me/services.py` |
| 组织模型归一 | restaurants / stores / manufacturer_subdivisions 三个 domain 与 team 门面向统一组织模型收敛（先兼容层、后替换） | `internal/core/companies` 等 |
| account 上下文 | 新增「选择 / 切换当前 account」接口，登录态携带 `account_id`（JWT 附加声明或请求头），取代从 URL 参数反推租户 | `auth/tokens/services.py`、新增 me/context |
| 权限下发接口 | **新增** `GET /me/permissions`：按当前 account 返回菜单树 + 按钮权限码 + 接口权限集 + 数据范围，一次请求供前端全量消费 | 新增 main_app/me 子模块 |
| 接口鉴权增强 | `check_permissions` 四分支合一（按 account_id）；支持父公司递归管辖（复用 test 线的递归 CTE，将其从「仅订单服务」推广为通用能力）；全量清点补挂漏保护的接口 | `middlewares/permissions/middlewares.py` |
| **test 线新功能面权限收口** | 为 Quotations（7 条路由 / 61 个 API 函数）、Manufacturers 区块及 4 个新领域（mafsi / manufacturer_profile / manufacturer_representation / manufacturer_terms，共 5 个新 router）补挂 `check_permissions` 并归类权限实体——这些端点未新增 api_entity 种子，需明确落到既有 12 实体（主要是 manufacturer / quotation / company） | test 线 `main_app/quotation`、`main_app/manufacturer/*`、`main_app/mafsi` |
| 实体白名单与角色保护兼容 | 权限配置界面按 `ALLOWED_API_ENTITIES_BY_BUSINESS_TYPE` 收窄可配实体（BUYER/VENDOR 9 个、MANUFACTURER 12 个），实体清单取自新端点 `/settings/companies/{id}/entities`（旧 `/entities` 已 deprecated）；「角色管理」须兼容两处硬编码：中间件按 `role.name == 'CEO'` 字符串直通、team 服务的 CEO 写保护 | `roles/domains.py:30-56`、`core/team/services.py` |
| 数据范围过滤 | 统一 scope 解析器（当前 account + data_scope → 可见组织节点 id 集合），核心列表服务接入 | orders / invoices / team / reports 等 service 层 |
| 管理接口扩展 | 权限矩阵读写接口增加菜单、按钮、数据范围三个维度 | `main_app/settings`、`internal/core/settings` |

### 8.3 前端

| 改动 | 内容 | 位置 |
|---|---|---|
| 权限数据源切换 | AccessControlProvider 从硬编码矩阵改为消费 `GET /me/permissions`（打通现在「已合并、无人用」的半成品链路）；硬编码 rules 仅保留为兜底并逐步删除 | `app/providers/AccessControlProvider.tsx`、`constants/permissions.ts` |
| 菜单后端驱动 | 侧边栏由下发菜单树渲染，删除按公司类型 + 权限点手拼菜单的逻辑；修复移动端两处菜单不受权限控制的问题 | `ui/widgets/Sidebar` |
| 路由守卫补齐 | 为 settings、orders、products、quotations 等裸奔路由统一加守卫，守卫依据与菜单同源 | `app/constants/routes.tsx`、`PrivateRoute` |
| 切换 account UI 升级 | 现有 `activeAccount` + 切换弹窗语义与本模型天然吻合；扩展为「多公司分组 + 旗下实体」两级选择，切换后调上下文接口、重拉权限、刷新菜单；**test 线的 `useOpenQuotationDocument` 隐式自动切换 activeAccount 必须并入统一上下文机制**（否则打开链接即换角色、且后端上下文不同步） | `features/SelectAccount`、`ChangeAccountForm`、`userStore`、`useOpenQuotationDocument` |
| 存量问题修复 | 权限点拼写错误（`CRATE_RESTAURANT` / `EDIT_RESTRAUNTS`）、**12 个角色缺 rules 条目**（8 个分部角色 + STORE_PARTNER + ADMIN + 2 个 vendor 公司角色）导致登录后界面近乎空白、以 vendor 权限点代替公司类型判断的反模式、`merge(后端矩阵, 本地rules)` 合并方向导致后端值被本地覆盖——随数据源切换一并消除 | `constants/permissions.ts`（26 权限点）、`roles.ts`（47 角色）等 10+ 处 |

---

## 附：调研代码索引

- 后端认证：`internal/main_app/auth/transport/handlers.py`（三段式注册/登录）、`internal/core/auth/tokens/services.py`（JWT 签发/刷新旋转/Redis 单会话）
- 成员与角色：`internal/core/companies/models.py`（company / company_member / company_role_permission）、`internal/core/roles/`（role / permission / api_entity）
- 接口鉴权：`internal/main_app/middlewares/permissions/middlewares.py`（check_permissions 四分支）
- 组织实体：`internal/core/restaurants|stores|manufacturer_subdivisions/models.py`
- 前端权限：`src/app/providers/AccessControlProvider.tsx`、`src/constants/permissions.ts|roles.ts`、`src/ui/widgets/Sidebar/`、`src/stores/userStore.ts`
