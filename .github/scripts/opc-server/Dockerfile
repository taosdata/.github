# 使用官方 Node.js 镜像作为基础镜像
FROM node:18-alpine

# 设置工作目录
WORKDIR /app

# 复制 package.json 和 package-lock.json
COPY package*.json ./

# 安装依赖
RUN npm ci --only=production

# 复制应用程序文件
COPY server.js ./
COPY server-config.json ./
COPY points-config.json ./
COPY test-client.js ./
COPY README.md ./

# 创建非 root 用户
RUN addgroup -g 1001 -S opcua && \
    adduser -S opcua -u 1001

# 更改工作目录权限
RUN chown -R opcua:opcua /app
USER opcua

# 暴露 OPC UA 服务器端口（默认 4840）
EXPOSE 4840

# 设置健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD node -e "const { OPCUAClient } = require('node-opcua'); const client = OPCUAClient.create({}); client.connect('opc.tcp://localhost:4840/UA/MyLittleServer').then(() => { client.disconnect(); process.exit(0); }).catch(() => process.exit(1));"

# 启动应用程序
CMD ["npm", "start"]
