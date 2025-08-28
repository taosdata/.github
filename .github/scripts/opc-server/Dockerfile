# 使用官方 Node.js 镜像作为基础镜像
FROM node:18-alpine

# 设置工作目录
WORKDIR /app

# 安装必要的系统依赖
RUN apk add --no-cache dumb-init

# 复制 package.json 和 package-lock.json
COPY package*.json ./

# 安装依赖
RUN npm ci --only=production && npm cache clean --force

# 复制应用程序文件
COPY server.js ./
COPY test-client.js ./
COPY README.md ./

# 复制默认配置文件（可被挂载覆盖）
COPY config.json ./config.json.default

# 创建配置文件目录和数据目录
RUN mkdir -p /app/config /app/data /app/logs

# 创建非 root 用户
RUN addgroup -g 1001 -S opcua && \
    adduser -S opcua -u 1001 -G opcua

# 更改工作目录权限
RUN chown -R opcua:opcua /app
USER opcua

# 创建启动脚本，支持配置文件挂载
RUN echo '#!/bin/sh' > /app/entrypoint.sh && \
    echo 'if [ ! -f /app/config/config.json ]; then' >> /app/entrypoint.sh && \
    echo '  echo "使用默认配置文件..."' >> /app/entrypoint.sh && \
    echo '  cp /app/config.json.default /app/config.json' >> /app/entrypoint.sh && \
    echo 'else' >> /app/entrypoint.sh && \
    echo '  echo "使用挂载的配置文件..."' >> /app/entrypoint.sh && \
    echo '  cp /app/config/config.json /app/config.json' >> /app/entrypoint.sh && \
    echo 'fi' >> /app/entrypoint.sh && \
    echo 'exec dumb-init node server.js' >> /app/entrypoint.sh && \
    chmod +x /app/entrypoint.sh

# 暴露 OPC UA 服务器端口（默认 4840）
EXPOSE 4840

# 定义挂载卷
VOLUME ["/app/config", "/app/data", "/app/logs"]

# 设置环境变量
ENV NODE_ENV=production
ENV OPCUA_MAX_CHUNK_COUNT=1000
ENV OPCUA_MAX_MESSAGE_SIZE=16777216

# 设置健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
  CMD node -e "const { OPCUAClient } = require('node-opcua'); const client = OPCUAClient.create({}); client.connect('opc.tcp://localhost:4840/UA/ConfigServer').then(() => { console.log('Health check passed'); client.disconnect(); process.exit(0); }).catch((err) => { console.log('Health check failed:', err.message); process.exit(1); });"

# 使用启动脚本
ENTRYPOINT ["/app/entrypoint.sh"]