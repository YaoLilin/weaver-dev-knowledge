---
name: browser-use
description: 使用 browser-use 库进行浏览器自动化和网页数据抓取。当用户需要访问网页、提取网页内容、自动化浏览器操作或进行网页测试时使用此技能。
---

# Browser-use 自动化技能

## 前置条件

使用 browser-use 前确保：
1. 虚拟环境已创建并激活
2. 已安装 browser-use 和 langchain-openai
3. 已设置 API Key（OpenAI 或 Anthropic）

## 快速开始

### 1. 检查/创建虚拟环境

```bash
# 检查是否已有虚拟环境
if [ ! -d ".venv" ] && [ ! -d "venv" ]; then
    # 创建新的虚拟环境
    python3.12 -m venv .venv
fi

# 激活虚拟环境
source .venv/bin/activate  # macOS/Linux
# 或
.venv\Scripts\activate  # Windows
```

### 2. 安装依赖

```bash
pip install browser-use langchain-openai
```

### 3. 设置 API Key

```bash
export OPENAI_API_KEY="your-api-key"
# 或
export ANTHROPIC_API_KEY="your-api-key"
```

## 基本使用模式

### 模式一：简单网页访问

```python
import asyncio
from browser_use import Agent
from langchain_openai import ChatOpenAI

async def browse_webpage(url: str, task: str):
    agent = Agent(
        task=f"访问 {url} 并{task}",
        llm=ChatOpenAI(model="gpt-4o-mini"),
    )
    return await agent.run()

# 使用
result = asyncio.run(browse_webpage(
    "https://example.com",
    "提取页面标题和主要内容"
))
```

### 模式二：多步骤任务

```python
async def complex_task():
    agent = Agent(
        task="""
        1. 访问 https://www.weaver.com.cn
        2. 找到产品中心页面
        3. 提取所有产品名称和简介
        4. 整理成表格格式
        """,
        llm=ChatOpenAI(model="gpt-4o"),
    )
    return await agent.run()
```

### 模式三：表单填写

```python
async def fill_form():
    agent = Agent(
        task="""
        访问指定表单页面，填写以下信息：
        - 姓名：张三
        - 邮箱：zhangsan@example.com
        - 提交表单
        """,
        llm=ChatOpenAI(model="gpt-4o"),
    )
    return await agent.run()
```

## 常用场景

### 场景 1：网页内容提取

```python
async def extract_content(url: str):
    agent = Agent(
        task=f"访问 {url}，提取文章的标题、作者、发布时间和正文内容",
        llm=ChatOpenAI(model="gpt-4o-mini"),
    )
    return await agent.run()
```

### 场景 2：数据抓取

```python
async def scrape_data(url: str):
    agent = Agent(
        task=f"""
        访问 {url}，抓取以下数据：
        - 所有商品名称
        - 价格
        - 评分
        并以 JSON 格式返回
        """,
        llm=ChatOpenAI(model="gpt-4o"),
    )
    return await agent.run()
```

### 场景 3：网页测试

```python
async def test_webpage(url: str):
    agent = Agent(
        task=f"""
        测试 {url} 页面：
        1. 检查页面是否正常加载
        2. 测试主要功能按钮是否可用
        3. 检查是否有错误信息
        4. 生成测试报告
        """,
        llm=ChatOpenAI(model="gpt-4o"),
    )
    return await agent.run()
```

## 最佳实践

### 1. 任务描述要清晰

- **好**："访问页面，点击'登录'按钮，输入用户名和密码，点击提交"
- **差**："帮我登录网站"

### 2. 选择合适的模型

- **简单任务**：gpt-4o-mini（更快更便宜）
- **复杂任务**：gpt-4o（更准确）

### 3. 处理长任务

对于复杂任务，可以分步骤执行：

```python
# 步骤 1：导航到目标页面
result1 = await agent.run("访问网站并找到产品列表页面")

# 步骤 2：提取数据
result2 = await agent.run("从产品列表中提取所有产品信息")

# 步骤 3：处理数据
result3 = await agent.run("将提取的数据整理成表格格式")
```

### 4. 错误处理

```python
import asyncio
from browser_use import Agent
from langchain_openai import ChatOpenAI

async def safe_browse(task: str):
    try:
        agent = Agent(
            task=task,
            llm=ChatOpenAI(model="gpt-4o-mini"),
        )
        result = await agent.run()
        return {"success": True, "result": result}
    except Exception as e:
        return {"success": False, "error": str(e)}
```

## 故障排除

### 问题 1：浏览器无法启动

**解决**：安装 Playwright 浏览器
```bash
playwright install chromium
```

### 问题 2：API Key 错误

**检查**：
```bash
echo $OPENAI_API_KEY
echo $ANTHROPIC_API_KEY
```

### 问题 3：依赖冲突

**解决**：重新创建虚拟环境
```bash
rm -rf .venv
python3.12 -m venv .venv
source .venv/bin/activate
pip install browser-use langchain-openai
```

## 参考资源

- browser-use 文档：https://github.com/browser-use/browser-use
- 支持的模型：OpenAI GPT-4/GPT-3.5、Anthropic Claude、Google Gemini 等
