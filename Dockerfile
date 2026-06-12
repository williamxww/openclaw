# syntax=docker/dockerfile:1.7
#
# OpenClaw 生产镜像。
# 多阶段构建：builder 用 pnpm 装依赖并执行 `pnpm build:docker` 产出 dist/；
# runtime 仅保留运行所需文件，以非 root 用户启动 gateway。

# ---------- builder ----------
FROM node:24-bookworm-slim AS builder

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
# 避免从源码编译 libvips，使用 sharp 自带预编译二进制。
ENV SHARP_IGNORE_GLOBAL_LIBVIPS=1

# git/python3 覆盖部分依赖与插件安装脚本所需的执行路径。
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates git python3 \
 && rm -rf /var/lib/apt/lists/*

# packageManager 字段固定 pnpm 版本，corepack 据此激活。
RUN corepack enable

WORKDIR /app

COPY . .

RUN pnpm install --frozen-lockfile
RUN pnpm build:docker

# ---------- runtime ----------
FROM node:24-bookworm-slim AS runtime

# 运行期：插件安装/媒体处理等路径需要 git 与 python3。
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates git python3 \
 && rm -rf /var/lib/apt/lists/* \
 && corepack enable

ENV NODE_ENV=production
ENV NODE_OPTIONS="--disable-warning=ExperimentalWarning"
# 配置与状态（openclaw.json、credentials、sessions 等）统一落到挂载卷 /data。
ENV OPENCLAW_STATE_DIR=/data
ENV HOME=/data

RUN useradd --create-home --home-dir /home/appuser --shell /bin/bash appuser \
 && mkdir -p /data \
 && chown -R appuser:appuser /data

WORKDIR /app

# 整目录复制：pnpm 的 node_modules 软链是相对路径，落到同一 /app 路径后仍有效。
COPY --from=builder --chown=appuser:appuser /app /app

RUN ln -sf /app/openclaw.mjs /usr/local/bin/openclaw

USER appuser

VOLUME ["/data"]

ENTRYPOINT ["node", "/app/openclaw.mjs"]
CMD ["gateway", "run"]
