## 工具介绍

利用AI，实施人员只需提供一份需求文档，工具便会帮助把整套应用搭建好——表单、流程、动作流、页面一次性生成，无需手工逐项配置，提升实施效率。

## 获取工具

链接地址：[E10AI自动搭建工具使用指南（含最新版本安装包）](https://www.e-cology.com.cn/sp/doc/docDetail/1305327461416984615) 

入口：  
![](files/Pasted%20image%2020260906141425.png)

## 初次使用体验

使用上面链接中的文档里的 AI 智能搭建验证模板进行搭建，我使用的工具是 Qoder + deepseek-v4-flash-vision-exp 。  

AI 会根据你给出的需求文档，进行自动搭建，在搭建时耗时会比较久，大概半个小时，token 消耗也非常巨大，花费了我 `5千万 token`，成本是 3 块钱。

搭建效果还是可以的，表单和流程都按需求文档里搭建了， 不过中途出现了一次无法用技能（CLI）实现的一个小功能，后面在搭建自定义页面时就不能直接使用技能中的 CLI 搭建了，需要使用 AI 控制浏览器进行搭建，这个过程很慢，效果也不好。

**总结**  
- 耗时长 token 消耗量大
- 搭建效果可以

**后续优化**：
- 让 AI 学习，优化搭建耗时和费用

效果截图：

![](files/Pasted%20image%2020260906143853.png)

流程表单布局，估计是初始化做的

![](files/Pasted%20image%2020260906144107.png)

流程图：
![](files/Pasted%20image%2020260906144244.png)

前端效果：
![](files/Pasted%20image%2020260906144334.png)

动作流：
![](files/Pasted%20image%2020260906144418.png)

## 工具原理

### 一句话概括

它本质是一个**「薄指令层」的 AI 领域知识手册 + 操作决策树**，真正的"能搭建系统"能力由配套的 npm 包 **`e10-cli`** 提供。技能负责"**告诉 AI 该怎么做**"，CLI 负责"**真正去 E10 系统里做到**"。

核心文件：[主 SKILL.md](file:///Users/yaolilin/IdeaProjects/e10-secondev/.agents/skills/weaver-e10-builder/SKILL.md)

### 三层架构分工

| 层级 | 内容 | 作用 |
|------|------|------|
| **指令层** | SKILL.md、`_catalog.md`、`actionflows/SKILL.md` | 领域知识、决策树、工作流、平台能力边界 |
| **文档层** | `references/`（form/workflow/actionflows/coding…） | 各命令的详细参数说明、组件契约 |
| **执行层** | `e10-cli`（npm 包 `weaver-e10-builder`） | 真正调用 E10 后端 API 完成搭建 |

### 为什么能在 E10 系统搭建应用 —— 关键在 `e10-cli`

`e10-cli` 是泛微官方封装的命令行工具，它**直接映射到 E10/Ebuilder 平台的后端开放 REST API**。每一项"搭建"动作都对应平台真实的建模接口：

- 建应用 → `/app/info`（[app create](file:///Users/yaolilin/IdeaProjects/e10-secondev/.agents/skills/weaver-e10-builder/references/common/ref-cli-commands.md)）
- 建表单/字段 → `form create` / `form add-field`
- 配流程/节点/操作者 → `workflow create` / `workflow set-operator`
- 建菜单 → `menu add-table` / `menu add-start`（VIEWPORT/LAYOUT 类型）
- 生成动作流 → `actionflow generate`（语义 plan → 编译 → preflight → 保存并启用 → 正式回读）
- 配布局/权限/编号 → `form layout` / `form permission` / `form serial-mark`

**鉴权方式**使它能以"当前用户身份"操作平台：复用浏览器登录态（[guide-auth.md](file:///Users/yaolilin/IdeaProjects/e10-secondev/.agents/skills/weaver-e10-builder/references/auth/guide-auth.md)）

```bash
e10-cli auth set --eteamsid "<ETEAMSID>" --base-url "<平台地址>"
```

Cookie 里的 ETEAMSID 会自动解析出 `userId + tenantKey`，凭证用 AES-256-GCM 加密存于本机 OS keychain。所以 CLI 能"代替你登录"去调那些建模接口。

### AI 与 CLI 的分工

```
需求文档
   │
   ▼
AI 解析并发起确认 → 写 plan.md（按模板逐项列出资源）→ 用户确认
   │
   ▼
AI 按「决策树」命中并读取对应 references 文档 → 生成字段/条件/动作流 JSON
   │
   ▼
AI 调用 e10-cli 命令 → CLI 鉴权并调后端 API
   │
   ▼
CLI 保存后正式回读校验（readBackVerified）→ AI 打勾销号
```

**AI 负责**：理解模糊需求 → 翻译成精确的平台资源设计 → 按决策树查文档 → 写配置 JSON → 调用命令 → 校验结果。
**CLI 负责**：鉴权、API 调用、语义编译（如动作流 plan 编译）、数据回读与一致性校验。

### 为什么能**可靠**地搭建

1. **真实数据优先，不猜 ID**：先查询平台真实对象（`form-applications`、`workflow-nodes`、`component-describe`），拿不到就停止，绝不伪造。
2. **保存后回读校验**：每步生成后都要正式回读验证（如动作流的 `valid/saved/readBackVerified`），防止"写了但没生效"。
3. **能力边界诚实**：CLI/平台不支持的能力（如 [H5/移动端菜单](file:///Users/yaolilin/IdeaProjects/e10-secondev/.agents/skills/weaver-e10-builder/SKILL.md#L219-L228)）明确标注"不支持"，禁止 AI 编造操作步骤。

### 为什么它是"skill"而不是"程序"

因为它不自己执行任何逻辑，只是把**泛微 E10 的领域知识（决策树、组件契约、命令语法、平台规则）灌给 AI**，让 AI 能像懂 E10 的开发一样，把一句"帮我搭一个会议室预订"翻译成几十条准确的 `e10-cli` 命令，再由 CLI 真正落到平台上。这也是它文档版本与 CLI 版本强绑定的原因（[版本匹配](file:///Users/yaolilin/IdeaProjects/e10-secondev/.agents/skills/weaver-e10-builder/SKILL.md#L16-L40)）。

---

## 扩展技能

这是我为搭建工具创建的技能，对工具进行扩展和优化。
### 自动鉴权 : e10-cli-auth

使用自动搭建工具前需要执行 `e10-cli auth login` 命令进行鉴权，它会要求你先在浏览器登陆到E10 环境，拿到 `eteamsid` , 我的技能可以实现自动到已经登陆环境的浏览器上拿到 `eteamsid` ,不需要手动操作。  能让 AI 干的事就让 AI 干，对吧。  

**如何使用**：执行 `e10-cli auth login` 命令就会自动执行此技能

**技能文件**：
将该技能解压到当前项目目录中的 `.agents` 目录

![](files/e10-cli-auth.zip)

### 自动搭建工具优化: e10-builder-fast

功能：提升自动搭建工具 weaver-e10-builder 的速度

泛微 E10 Ebuilder 应用快速搭建经验汇总(踩坑与加速流程)。在使用 weaver-e10-builder / e10-cli 搭建应用、表单、流程、动作流、菜单、页面时加载，减少试错与反复。涵盖出口条件正确绑定、动作流生成、JSON 解析、CLI 不支持项、浏览器页面设计器正确姿势。  

**如何使用**：执行自动搭建工具就会自动执行此技能  

**技能文件**： 
将该技能解压到当前项目目录中的 `.agents` 目录  

![](files/e10-builder-fast.zip)