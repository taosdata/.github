# OPC UA 服务器配置说明

这是一个用于测试的简易OPC UA服务器程序，可以通过配置文件完成基本的OPC UA Server配置和运行，并支持各种数据类型的测点。

## 启动opc-server

```bash
npm install
npm server.js
```
## 📁 配置文件结构

### 1. `server-config.json` - 服务器主配置文件

这个文件定义了 OPC UA 服务器的所有核心配置，包括：

#### 🔧 服务器基础配置 (`server` 节)
```json
{
  "server": {
    "port": 4840,                    // 服务器端口
    "resourcePath": "/UA/ConfigServer", // 资源路径
    "bindAddress": "0.0.0.0",        // 绑定地址（0.0.0.0 监听所有接口）
    "allowAnonymous": true,          // 是否允许匿名访问
    "securityPolicies": ["None", "Basic128Rsa15", "Basic256Sha256"], // 安全策略
    "alternateHostname": ["localhost", "127.0.0.1", "192.168.100.45"] // 备用主机名
  }
}
```

#### 🏗️ 命名空间配置 (`namespace` 节)
```json
{
  "namespace": {
    "uri": "http://example.com/dynamic-config", // 命名空间 URI
    "name": "CustomNamespace"                   // 命名空间显示名称
  }
}
```

#### 🌳 节点结构配置 (`nodeStructure` 节)
```json
{
  "nodeStructure": {
    "customRoot": {
      "browseName": "CustomRoot",     // 浏览名称
      "nodeId": "ns=1;i=9000",       // 节点ID（ns=1会被自动替换为实际命名空间索引）
      "description": "自定义根节点",   // 描述
      "displayName": "CustomRoot"     // 显示名称
    },
    "devices": [                      // 设备节点数组
      {
        "browseName": "DynamicDevice",
        "nodeId": "ns=1;i=1000",
        "description": "动态设备节点",
        "displayName": "DynamicDevice",
        "parentNode": "customRoot"    // 父节点引用
      }
    ]
  }
}
```

#### 📊 日志配置 (`logging` 节)
```json
{
  "logging": {
    "enableStartupInfo": true,       // 启用启动信息日志
    "enableEndpointInfo": true,      // 启用端点信息日志
    "enableNodeInfo": true,          // 启用节点创建信息日志
    "enableTimerInfo": true          // 启用定时器信息日志
  }
}
```

### 2. `points-config.json` - 数据点配置文件

这个文件定义了所有的 OPC UA 变量节点（数据点）：

```json
[
  {
    "name": "FastTemperature",              // 节点名称
    "displayName": "快速温度传感器",         // 显示名称
    "description": "模拟的快速更新温度传感器", // 描述
    "nodeId": "ns=1;i=1001",               // 节点ID
    "type": "Double",                      // 数据类型
    "dynamic": true,                       // 是否为动态值
    "dynamicType": "random",               // 动态类型（random/increment）
    "range": [20, 30],                     // 随机值范围
    "interval": 1000,                      // 更新间隔（毫秒）
    "deviceName": "DynamicDevice"          // 挂载到的设备名称
  }
]
```

## 🎯 节点定义说明

### CustomRoot 节点 (`ns=2;i=9000`)

- **定义位置**: `server-config.json` → `nodeStructure.customRoot`
- **作用**: 作为所有自定义节点的根容器
- **配置方式**: 
  ```json
  "customRoot": {
    "browseName": "CustomRoot",      // 可自定义浏览名称
    "nodeId": "ns=1;i=9000",        // 可自定义节点ID
    "description": "自定义根节点",   // 可自定义描述
    "displayName": "CustomRoot"      // 可自定义显示名称
  }
  ```

### 设备节点 (`ns=2;i=1000`)

- **定义位置**: `server-config.json` → `nodeStructure.devices[]`
- **作用**: 作为数据点的容器
- **配置方式**: 可以定义多个设备节点

### 数据点节点

- **定义位置**: `points-config.json`
- **挂载方式**: 通过 `deviceName` 字段指定挂载到哪个设备

## 🔄 配置修改示例

### 1. 修改服务器端口
在 `server-config.json` 中修改：
```json
{
  "server": {
    "port": 4841  // 改为其他端口
  }
}
```

### 2. 添加新的设备节点
在 `server-config.json` 的 `nodeStructure.devices` 中添加：
```json
{
  "browseName": "SensorDevice",
  "nodeId": "ns=1;i=2000",
  "description": "传感器设备",
  "displayName": "传感器设备",
  "parentNode": "customRoot"
}
```

### 3. 添加新的数据点
在 `points-config.json` 中添加：
```json
{
  "name": "Pressure",
  "displayName": "压力传感器",
  "description": "压力值（0-10 bar）",
  "nodeId": "ns=1;i=2001",
  "type": "Double",
  "dynamic": true,
  "dynamicType": "random",
  "range": [0, 10],
  "interval": 2000,
  "deviceName": "SensorDevice"
}
```

### 4. 修改根节点名称
在 `server-config.json` 中修改：
```json
{
  "nodeStructure": {
    "customRoot": {
      "browseName": "MyPlantRoot",
      "displayName": "我的工厂根节点",
      "description": "工厂自动化系统根节点"
    }
  }
}
```

## 🚀 优势

1. **配置与代码分离**: 无需修改代码即可调整服务器配置
2. **灵活的节点结构**: 可以通过配置文件定义复杂的节点层次结构
3. **易于扩展**: 添加新设备和数据点只需修改 JSON 文件
4. **多语言支持**: 支持中文显示名称和描述
5. **日志控制**: 可以通过配置控制日志输出级别
6. **环境适配**: 可以为不同环境配置不同的端点地址

## 📝 注意事项

1. 节点 ID 中的 `ns=1` 会自动替换为实际的命名空间索引
2. 数据点的 `deviceName` 必须与设备节点的 `browseName` 匹配
3. 修改配置文件后需要重启服务器才能生效
4. 确保节点 ID 在同一命名空间内唯一
