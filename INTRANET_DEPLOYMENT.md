# 内网部署指南 (Intranet Deployment)

DeepWiki 支持完全内网部署：所有 AI 生成和向量嵌入都指向你们内部
OpenAI 兼容的 API 网关，无需任何外网访问。同时支持 SVN 仓库的输入与构建。

> 中文说明见本文档主体；English overview at the bottom.

---

## 1. 能力概览

- **内网 AI 接入**：通过 `OPENAI_BASE_URL` 指向内部网关，对话/Wiki 生成全部走内网。
- **内网 Embedding 接入**：默认复用 `OPENAI_BASE_URL`；也可用 `DEEPWIKI_EMBED_BASE_URL`
  单独指定嵌入端点，用 `DEEPWIKI_EMBED_MODEL` 指定内部嵌入模型名。
- **SVN 支持**：仓库类型新增 `svn`，后端用系统 `svn` 命令 checkout；
  前端平台选择新增 SVN，支持 `svn://`、`svn+ssh://` 及 http(s) 的 SVN 地址。
- **离线镜像传输**：在有网机器上构建镜像 → `docker save` 导出 tar →
  拷贝到内网机器 → `docker load` 导入 → 一键启动。

## 2. 镜像构建（有网机器上执行一次）

```bash
# 需要能访问外网（拉取 node/python 基础镜像并安装依赖）
./scripts/build-docker.sh          # Linux/macOS
scripts\build-docker.bat           # Windows

# 导出为 tar，用于拷入内网
./scripts/save-docker.sh           # 生成 deepwiki-open.tar
```

### 国内 / 企业内网镜像构建参数

在公司网络/国内环境下，`npmjs`、`pypi`、`deb.debian.org` 常被代理拦截。
Dockerfile 已内置可选的构建参数，按需传参即可（已在本环境验证通过）：

```bash
# 示例：npm 走 npmmirror、apt 走 LAN 镜像、走企业 HTTP 代理
NPM_REGISTRY=https://registry.npmmirror.com \
APT_MIRROR=http://10.153.3.130/debian \
APT_SECURITY_MIRROR=http://10.153.3.130/debian-security \
HTTP_PROXY=http://user:pass@proxy:8080 \
HTTPS_PROXY=http://user:pass@proxy:8080 \
./scripts/build-docker.sh
```

> 说明：代理对 npm/pypi 走 CONNECT 隧道时，默认 CA 即可验证，无需额外证书。
> 若你的内网 AI/嵌入网关使用企业私有 CA，运行时通过 docker-compose 挂载证书
> 并设置 `SSL_CERT_FILE` / `NODE_EXTRA_CA_CERTS`（见下方第 6 节）。

## 3. 内网导入与配置

```bash
# 在纯内网服务器上（无外网）
./scripts/load-docker.sh deepwiki-open.tar

# 生成并编辑环境配置
cp .env.example .env
# 编辑 .env，至少填写：
#   OPENAI_BASE_URL          -> 内部 AI 网关，如 http://192.168.1.10:8080/v1
#   OPENAI_API_KEY           -> 网关密钥
#   DEEPWIKI_DEFAULT_PROVIDER=openai
#   DEEPWIKI_DEFAULT_MODEL   -> 内部模型名，如 qwen2.5-32b-instruct
#   DEEPWIKI_EMBED_MODEL     -> 内部嵌入模型名，如 text-embedding-v3
```

### 关键环境变量

| 变量 | 说明 | 示例 |
|------|------|------|
| `OPENAI_BASE_URL` | 内部 OpenAI 兼容网关（生成 + 默认嵌入共用） | `http://192.168.1.10:8080/v1` |
| `OPENAI_API_KEY` | 网关密钥 | `sk-xxx` |
| `DEEPWIKI_DEFAULT_PROVIDER` | 默认生成提供商（内网通常 `openai`） | `openai` |
| `DEEPWIKI_DEFAULT_MODEL` | 默认生成模型名 | `qwen2.5-32b-instruct` |
| `DEEPWIKI_EMBED_BASE_URL` | （可选）独立嵌入端点 | `http://192.168.1.11:8081/v1` |
| `DEEPWIKI_EMBED_API_KEY` | （可选）独立嵌入密钥 | `sk-embed` |
| `DEEPWIKI_EMBED_MODEL` | 内部嵌入模型名 | `text-embedding-v3` |
| `SVN_USERNAME` / `SVN_PASSWORD` | （可选）私有 SVN 默认凭据 | `svnuser` / `svnpass` |
| `DEEPWIKI_AUTH_MODE` / `DEEPWIKI_AUTH_CODE` | （可选）生成鉴权 | `true` / `change-me` |

> 说明：生成（chat/wiki）通过 OpenAI SDK 读取 `OPENAI_BASE_URL`；
> 嵌入通过代码注入 `initialize_kwargs` 使用同一地址（或独立嵌入端点），
> 均无需修改任何 JSON 配置文件。

## 4. 启动

```bash
./scripts/deploy.sh               # Linux/macOS（自动检测 .env，缺则提示）
scripts\deploy.bat               # Windows

# 等价于：
docker compose up -d
```

启动后：
- Web UI：`http://<服务器IP>:3000/`
- API：`http://<服务器IP>:8001/`（可用 `/` 查看端点列表，`/health` 健康检查）
- 日志：`docker compose logs -f deepwiki`

数据目录 `~/.adalflow`（克隆的仓库、嵌入索引、Wiki 缓存）通过 volume 持久化，
容器重启不丢失。

### 4.1 内网 HTTPS 证书信任（可选）

若内部 AI/嵌入网关或 SVN 走 `https://` 且使用企业私有 CA，需让容器信任该 CA：

1. 把企业根证书放到 `certs/ca-certificates.crt`（`certs/` 已被 `.gitignore` 忽略，不会入库）。
2. 在 `docker-compose.yml` 中取消三行注释（`./certs:/certs:ro` 挂载 +
   `NODE_EXTRA_CA_CERTS` / `SSL_CERT_FILE` / `REQUESTS_CA_BUNDLE` 环境变量）。
3. 重新 `docker compose up -d`。

## 5. 使用 SVN / GitLab / 本地仓库

前端平台入口仅提供 **GitLab**、**SVN** 和 **本地路径** 三种（默认已移除 GitHub/Bitbucket）。
（后端仍兼容 github/bitbucket，粘贴此类 URL 亦可自动识别。）

### 5.1 SVN 仓库

1. 首页输入框填入 SVN 地址，例如：
   - `svn://192.168.1.20/svn/project/trunk`
   - `svn+ssh://user@192.168.1.20/repo`
   - `https://192.168.1.30/svn/project/trunk`（http(s) 方式的 SVN，请在弹窗中选择 **SVN** 平台）
2. 私有仓库：在配置弹窗中展开 “Add Access Tokens”，选择 **SVN** 平台，
   凭据支持两种写法：
   - `用户名:密码`（形如 `alice:secret`）
   - 仅填密码（配合环境变量 `SVN_USERNAME`，或地址里已含用户名）
3. 点击 Generate Wiki，其余流程与 Git 仓库一致。

> SVN 无浅克隆概念，默认为全量 checkout；大仓库首次生成会较慢。

## 6. 常见问题

- **生成报连接错误**：确认 `.env` 的 `OPENAI_BASE_URL` 可从服务器访问（curl 测试）。
- **嵌入维度不一致报错**：确认 `DEEPWIKI_EMBED_MODEL` 与网关实际模型一致，
  且各分块返回维度相同。
- **SVN 提示需要认证/卡住**：使用 `--non-interactive` 已禁用交互提示，
  请在 `token` 中提供 `username:password`，或设置 `SVN_USERNAME`/`SVN_PASSWORD`。
- **镜像里没有 svn 命令**：重新用最新代码构建镜像（Dockerfile 已安装 `subversion`）。

---

## English Overview

- Build once on an internet-connected machine: `./scripts/build-docker.sh`
- Export: `./scripts/save-docker.sh` → `deepwiki-open.tar`
- On the intranet host: `./scripts/load-docker.sh deepwiki-open.tar`
- Configure: `cp .env.example .env` (point `OPENAI_BASE_URL` at your internal
  OpenAI-compatible gateway, set `DEEPWIKI_DEFAULT_PROVIDER=openai`,
  `DEEPWIKI_DEFAULT_MODEL`, `DEEPWIKI_EMBED_MODEL`).
- Start: `./scripts/deploy.sh` (or `docker compose up -d`).
- SVN: paste an `svn://` / `svn+ssh://` URL; for http(s) SVN repos pick the
  **SVN** platform in the token dialog. Credentials may be `username:password`.
