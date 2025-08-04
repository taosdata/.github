const { OPCUAServer, Variant, DataType, StatusCodes, NodeId } = require("node-opcua");
const { IdentifierType } = require("node-opcua-types");
const fs = require("fs");
const path = require("path");

// 设置全局传输参数，避免 maxChunkCount 警告
const { setDebugFlag, messageHeaderToString } = require("node-opcua-debug");
const { MessageChunker } = require("node-opcua-chunkmanager");

// 尝试设置默认的传输参数
if (MessageChunker && MessageChunker.defaultMaxChunkCount !== undefined) {
  MessageChunker.defaultMaxChunkCount = 1000;
}

// 或者使用环境变量设置
process.env.OPCUA_MAX_CHUNK_COUNT = "1000";
process.env.OPCUA_MAX_MESSAGE_SIZE = "16777216"; // 16MB

// 加载配置文件
const pointsConfig = JSON.parse(fs.readFileSync(path.join(__dirname, "points-config.json"), "utf8"));
const serverConfig = JSON.parse(fs.readFileSync(path.join(__dirname, "server-config.json"), "utf8"));

// 存储动态变量的当前值
const dynamicValues = new Map();

// 初始化动态值存储
pointsConfig.forEach(point => {
  if (point.dynamic) {
    dynamicValues.set(point.name, point.initialValue);
  }
});

// 动态值生成器
const getDynamicValue = (point) => {
  switch (point.dynamicType) {
    case "random":
      const [min, max] = point.range;
      return min + Math.random() * (max - min);
    case "increment":
      const current = dynamicValues.get(point.name);
      const next = current + point.step;
      dynamicValues.set(point.name, next);
      return next;
    default:
      return point.initialValue;
  }
};

// 解析节点ID，替换命名空间索引为实际索引
const resolveNodeId = (nodeIdStr, actualNamespaceIndex) => {
  const match = nodeIdStr.match(/^ns=\d+;([a-z]+)=(\d+)$/);
  if (!match) {
    throw new Error(`无效的节点ID格式: ${nodeIdStr}`);
  }
  const [, identifierType, identifier] = match;

  // 直接映射为数值常量（替代枚举）
  const typeMap = {
    "i": 0,  // NUMERIC 对应 0
    "s": 1,  // STRING 对应 1
    "g": 2,  // GUID 对应 2
    "b": 3   // BYTESTRING 对应 3
  };
  const identifierTypeValue = typeMap[identifierType];
  if (identifierTypeValue === undefined) {
    throw new Error(`不支持的标识符类型: ${identifierType}`);
  }

  return {
    namespaceIndex: actualNamespaceIndex,
    identifierType: identifierTypeValue,  // 返回数值（如0）
    identifier: parseInt(identifier, 10)
  };
};

// 启动服务器
async function startServer() {
  const config = serverConfig.server;
  
  const server = new OPCUAServer({
    port: config.port,
    resourcePath: config.resourcePath,
    bindAddress: config.bindAddress,
    allowAnonymous: config.allowAnonymous,
    securityPolicies: config.securityPolicies,
    // 基本连接配置
    maxConnections: config.maxConnections,
    maxConnectionsPerEndpoint: config.maxConnectionsPerEndpoint,
    maxSessionsPerEndpoint: config.maxSessionsPerEndpoint,
    maxNodesPerRead: config.maxNodesPerRead,
    maxNodesPerHistoryReadData: config.maxNodesPerHistoryReadData || 100,
    maxNodesPerHistoryReadEvents: config.maxNodesPerHistoryReadEvents || 100,
    maxNodesPerWrite: config.maxNodesPerWrite || 1000,
    maxNodesPerHistoryUpdateData: config.maxNodesPerHistoryUpdateData || 100,
    maxNodesPerBrowse: config.maxNodesPerBrowse,
    maxBrowseContinuationPoints: config.maxBrowseContinuationPoints || 10,
    maxHistoryContinuationPoints: config.maxHistoryContinuationPoints || 10,
    // 传输层配置 - 彻底解决 maxChunkCount 警告
    transportSettings: config.transportSettings,
    // 服务器能力配置
    serverCapabilities: config.serverCapabilities,
    // 多端点配置
    alternateHostname: config.alternateHostname
  });

  await server.initialize();
  const addressSpace = server.engine.addressSpace;
  
  // 从配置文件注册自定义命名空间
  const namespaceConfig = serverConfig.namespace;
  const namespace = addressSpace.registerNamespace(namespaceConfig.uri);
  const actualNamespaceIndex = namespace.index;
  
  if (serverConfig.logging?.enableStartupInfo) {
    console.log(`自定义命名空间实际索引: ns=${actualNamespaceIndex} (${namespaceConfig.name})`);
  }

  // 获取默认根节点
  const rootNode = addressSpace.findNode("ns=0;i=84");
  if (serverConfig.logging?.enableStartupInfo) {
    console.log(`根节点 ID: ${rootNode.nodeId.toString()}`);
  }

  // 从配置文件创建节点结构
  const nodeStructure = serverConfig.nodeStructure;
  
  // 创建自定义根节点
  const customRootConfig = nodeStructure.customRoot;
  const customRoot = namespace.addObject({
    organizedBy: rootNode,
    browseName: customRootConfig.browseName,
    displayName: customRootConfig.displayName || customRootConfig.browseName,
    description: customRootConfig.description || "",
    nodeId: `ns=${actualNamespaceIndex};i=${customRootConfig.nodeId.split('=')[2]}`
  });

  // 创建设备节点
  const devices = {};
  nodeStructure.devices.forEach(deviceConfig => {
    const device = namespace.addObject({
      organizedBy: customRoot, // 假设所有设备都挂在 customRoot 下
      browseName: deviceConfig.browseName,
      displayName: deviceConfig.displayName || deviceConfig.browseName,
      description: deviceConfig.description || "",
      nodeId: `ns=${actualNamespaceIndex};i=${deviceConfig.nodeId.split('=')[2]}`
    });
    devices[deviceConfig.browseName] = device;
    
    if (serverConfig.logging?.enableNodeInfo) {
      console.log(`已创建设备节点: ${deviceConfig.browseName} (ns=${actualNamespaceIndex};i=${deviceConfig.nodeId.split('=')[2]})`);
    }
  });

  // 从配置文件创建点位
  pointsConfig.forEach(point => {
    const nodeId = `ns=${actualNamespaceIndex};i=${point.nodeId.split('=')[2]}`;
    
    // 确定点位应该挂载到哪个设备（默认挂载到第一个设备）
    const targetDevice = point.deviceName ? devices[point.deviceName] : Object.values(devices)[0];
    if (!targetDevice) {
      console.error(`找不到设备节点用于挂载点位: ${point.name}`);
      return;
    }

    try {
      const variableNode = namespace.addVariable({
        nodeId: nodeId,
        componentOf: targetDevice,
        browseName: point.name,
        displayName: point.displayName || point.name,
        description: point.description || "",
        dataType: point.type,
        accessLevel: point.dynamic ? "CurrentRead" : "CurrentRead | CurrentWrite",
        userAccessLevel: point.dynamic ? "CurrentRead" : "CurrentRead | CurrentWrite",
        minimumSamplingInterval: point.dynamic ? (point.interval || 1000) : 0,
        historizing: false,
        value: {
          get: () => {
            const value = point.dynamic ? getDynamicValue(point) : point.initialValue;
            return new Variant({
              dataType: DataType[point.type],
              value: value
            });
          },
          set: point.dynamic ? undefined : (variant) => {
            point.initialValue = variant.value;
            return StatusCodes.Good;
          }
        }
      });

      // 动态点位定时更新
      if (point.dynamic) {
        const interval = point.interval || 1000;
        setInterval(() => {
          try {
            const newValue = getDynamicValue(point);
            variableNode.setValueFromSource(
              new Variant({ dataType: DataType[point.type], value: newValue }),
              StatusCodes.Good
            );
          } catch (err) {
            console.error(`更新 ${point.name} 失败:`, err);
          }
        }, interval);
        
        if (serverConfig.logging?.enableTimerInfo) {
          console.log(`已启动 ${point.name} (${nodeId}) 的定时器，更新频率: ${interval}ms`);
        }
      }
    } catch (err) {
      console.error(`创建节点 ${point.name} (${nodeId}) 失败:`, err);
    }
  });

  await server.start();
  
  if (serverConfig.logging?.enableStartupInfo) {
    console.log("=== OPC UA 服务器启动成功 ===");
    console.log(`主端点: ${server.endpoints[0].endpointDescriptions()[0].endpointUrl}`);
  }
  
  // 打印所有可用的端点
  if (serverConfig.logging?.enableEndpointInfo) {
    console.log("\n可用端点列表:");
    server.endpoints.forEach((endpoint, index) => {
      const descriptions = endpoint.endpointDescriptions();
      descriptions.forEach((desc, descIndex) => {
        console.log(`  [${index}.${descIndex}] ${desc.endpointUrl} (安全策略: ${desc.securityPolicyUri.split('#').pop()})`);
      });
    });
    
    // 打印服务器信息
    console.log(`\n服务器配置信息:`);
    console.log(`  - 端口: ${config.port}`);
    console.log(`  - 资源路径: ${config.resourcePath}`);
    console.log(`  - 绑定地址: ${config.bindAddress} (监听所有网络接口)`);
    console.log(`  - 匿名访问: ${config.allowAnonymous ? '已启用' : '已禁用'}`);
    console.log(`  - 自定义命名空间: ns=${actualNamespaceIndex} (${namespaceConfig.name})`);
    
    // 打印推荐的客户端连接地址
    console.log(`\n推荐的客户端连接地址:`);
    config.alternateHostname.forEach(hostname => {
      console.log(`  - opc.tcp://${hostname}:${config.port}${config.resourcePath}`);
    });
    
    console.log(`\n数据点节点路径:`);
    console.log(`  ${nodeStructure.customRoot.browseName} > ${nodeStructure.devices.map(d => d.browseName).join(', ')} > [${pointsConfig.map(p => p.name).join(', ')}]`);
    console.log("================================");
  }
}

startServer().catch(console.error);
    