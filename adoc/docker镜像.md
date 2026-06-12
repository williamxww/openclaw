# 基于当前工程构建 Docker 镜像并手动部署到 Linux 服务器

本文档说明如何用当前仓库源码构建 OpenClaw 的 Docker 镜像，把镜像打包成离线文件，再手动上传到 Linux 服务器加载运行。

> 适用场景：本地（Windows / PowerShell）构建 → `docker save` 导出 tar → `scp` 上传 → 服务器 `docker load` 运行。无需镜像仓库（registry）。

---

## 一、工程关键事实（构建依据）

| 项 | 值 | 来源 |
| --- | --- | --- |
| Node 版本 | `>=22.19.0`，推荐 24 | `package.json` `engines`、`openclaw.mjs` |
| 包管理器 | `pnpm@11.2.2`（corepack 激活） | `package.json` `packageManager` |
| 构建命令 | `pnpm build:docker` | `package.json` `scripts` |
| 运行入口 | `node openclaw.mjs` → 加载 `dist/entry.js` | `openclaw.mjs` |
| 启动 gateway | `openclaw gateway run` | `docs/concepts/mantis.md` |
| 状态/配置目录 | `~/.openclaw`，可用 `OPENCLAW_STATE_DIR` 覆盖 | `openclaw.mjs` |
| 对外绑定 | 默认绑 loopback；绑非 loopback 必须带鉴权 token/password | `src/gateway/server-runtime-config.ts:140` |

仓库根已附带两份配套文件：

- `Dockerfile` — 多阶段构建（builder 装依赖 + `pnpm build:docker`，runtime 以非 root 用户跑 gateway）。
- `.dockerignore` — 裁剪构建上下文，排除宿主 `node_modules`/`dist`/`.git`/本地状态等。

---

## 二、前置条件

- 本地装好 Docker Desktop（含 buildx），且 Docker 正在运行。
- 目标 Linux 服务器已安装 Docker，当前用户可执行 `docker`（在 `docker` 组或用 `sudo`）。
- 确认目标服务器 CPU 架构：绝大多数云主机为 `amd64`（x86_64）。如服务器是 ARM（如部分鲲鹏 / Graviton），把下文 `linux/amd64` 改成 `linux/arm64`。

---

## 三、构建镜像（本地 / PowerShell）

在仓库根目录 `d:\repository\github\openclaw` 执行。

```powershell
# 指定目标平台构建（跨平台到 Linux 服务器关键，避免在 Windows/ARM 上构出错误架构）
docker buildx build `
  --platform linux/amd64 `
  -t openclaw:local `
  --load `
  .
```

说明：

- `--platform linux/amd64`：保证产物可在 amd64 Linux 服务器运行（本地无论什么架构都按此目标构建）。
- `--load`：把构建结果加载进本地 Docker，便于随后 `docker save`。
- 首次构建会下载基础镜像、`pnpm install`、`pnpm build:docker`，耗时较长（数分钟级）；后续命中缓存会快很多。

构建完成后确认：

```powershell
docker images openclaw:local
```

### （可选）本地冒烟验证

仅验证 CLI 能起来（不连任何渠道）：

```powershell
docker run --rm openclaw:local --version
docker run --rm openclaw:local gateway --help
```

如需本地试跑 gateway，挂一个本地目录做状态卷：

```powershell
docker run --rm -it `
  -v ${PWD}\.docker-data:/data `
  openclaw:local gateway run
```

> 默认 gateway 绑 loopback，仅在容器内可达；要从宿主/网络访问见第六节的对外暴露说明。

---

## 四、把镜像打包成离线文件

将镜像导出为 tar，并压缩以缩小传输体积。

```powershell
# 导出为 tar
docker save -o openclaw-local.tar openclaw:local

# 压缩（PowerShell 自带，跨平台可解）
Compress-Archive -Path openclaw-local.tar -DestinationPath openclaw-local.zip
```

若本地装有 gzip（如 Git Bash），用 `.tar.gz` 更通用、Linux 端解压更顺手：

```bash
docker save openclaw:local | gzip > openclaw-local.tar.gz
```

---

## 五、上传到 Linux 服务器

任选其一。

```powershell
# scp（OpenSSH，Windows 10+ 自带）
scp openclaw-local.tar.gz user@your-server:/home/user/

# 或 rsync（断点续传更稳，需服务器支持）
# rsync -avP openclaw-local.tar.gz user@your-server:/home/user/
```

把 `user@your-server` 换成实际账号与地址，目标路径按需调整。

---

## 六、在服务器上加载并运行（Linux / bash）

SSH 登录服务器后执行。

### 1. 加载镜像

```bash
# 如果上传的是 .tar.gz
gunzip -c openclaw-local.tar.gz | docker load

# 如果上传的是未压缩 tar
# docker load -i openclaw-local.tar
```

确认镜像已就绪：

```bash
docker images openclaw:local
```

### 2. 准备状态目录与配置

```bash
mkdir -p /opt/openclaw/data
# 放入 openclaw.json（模型 / 渠道 / 路由等全局配置）
# 容器内 OPENCLAW_STATE_DIR=/data，所以配置文件路径是 /opt/openclaw/data/openclaw.json
vi /opt/openclaw/data/openclaw.json
```

`openclaw.json` 的具体写法见仓库 `adoc/Agent装配方案.md` 与 `adoc/claw定制.md`。

### 3. 运行容器

```bash
docker run -d \
  --name openclaw \
  --restart unless-stopped \
  -v /opt/openclaw/data:/data \
  openclaw:local
```

容器默认执行 `openclaw gateway run`，连接 `openclaw.json` 里配置的渠道（Telegram / Discord / WhatsApp 等为出站连接，通常无需开放入站端口）。

查看日志确认启动：

```bash
docker logs -f openclaw
```

### 4. （仅当需要 Control UI / HTTP 入站时）对外暴露端口

OpenClaw 默认把 gateway 绑在 loopback。要让宿主或外部访问，必须同时：① 把绑定改成非 loopback；② 配置鉴权 token，否则会拒绝启动
（见 `src/gateway/server-runtime-config.ts:140`）。

在 `openclaw.json` 中设置 gateway 绑定与端口（示例，端口以你的配置为准），并通过环境变量注入 token：

```bash
docker run -d \
  --name openclaw \
  --restart unless-stopped \
  -v /opt/openclaw/data:/data \
  -e OPENCLAW_GATEWAY_TOKEN='请填一个强随机串' \
  -p 0.0.0.0:<宿主端口>:<gateway端口> \
  openclaw:local
```

> token 也可写进 `openclaw.json` 的 `gateway.auth.token`；非 loopback 的 Control UI 还需配置 `gateway.controlUi.allowedOrigins`。具体键名用 `docker run --rm openclaw:local config schema` 对照。

---

## 七、升级（重新部署新版本）

```powershell
# 本地重建并重新打包
docker buildx build --platform linux/amd64 -t openclaw:local --load .
docker save openclaw:local | gzip > openclaw-local.tar.gz   # Git Bash；或用 Compress-Archive
scp openclaw-local.tar.gz user@your-server:/home/user/
```

```bash
# 服务器加载新镜像并重建容器（状态卷 /opt/openclaw/data 保留）
gunzip -c openclaw-local.tar.gz | docker load
docker rm -f openclaw
docker run -d --name openclaw --restart unless-stopped \
  -v /opt/openclaw/data:/data \
  openclaw:local
```

> 建议给镜像打带版本的 tag（如 `openclaw:2026.5.25`）便于回滚，而不是只用 `:local`。

---

## 八、常见问题

- **架构不匹配**：服务器报 `exec format error` → 构建时的 `--platform` 与服务器架构不一致，按第二节调整后重建。
- **构建慢/卡在 install**：首次需联网下载依赖与基础镜像；CI 环境无外网时需预置镜像源。
- **`sharp` 相关报错**：镜像已设 `SHARP_IGNORE_GLOBAL_LIBVIPS=1` 使用预编译二进制；若仍失败，确认目标平台与 `--platform` 一致。
- **gateway 拒绝启动并提示 auth**：你把绑定改成了非 loopback 却没给 token/password，按第六节第 4 步注入 `OPENCLAW_GATEWAY_TOKEN`。
- **配置不生效**：确认配置文件落在卷内的 `/data/openclaw.json`（容器里 `OPENCLAW_STATE_DIR=/data`）。
