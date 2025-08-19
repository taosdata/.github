# OPC UA 服务器配置说明

这是一个用于测试的简易OPC UA Server 程序，可以通过配置文件完成基本的OPC UA Server配置和运行，并支持各种数据类型的测点和测试数据生成。

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

这个文件定义了所有的 OPC UA 变量节点（数据点）。支持两种配置方式：**批量生成**和**单个配置**。

#### 批量生成点位配置
```json
{
  "namePrefix": "Temperature",           // 点位名称前缀
  "displayNamePrefix": "温度传感器",      // 显示名称前缀
  "description": "模拟的温度传感器",      // 点位描述
  "nodeIdPrefix": "ns=1;i=1000",        // 节点ID前缀（基础ID）
  "type": "Double",                     // 数据类型
  "dynamic": true,                      // 是否为动态点位
  "dynamicType": "random",              // 动态类型（random/increment）
  "range": [20, 30],                    // 随机值范围（仅用于 random 类型）
  "interval": 1000,                     // 更新间隔（毫秒）
  "deviceName": "DynamicDevice",        // 挂载的设备名称
  "count": 5                            // 生成点位数量
}
```

#### 单个点位配置
```json
{
  "name": "StaticValue",                // 点位名称
  "displayName": "静态值",              // 显示名称
  "description": "静态数值，可读写",     // 点位描述
  "nodeId": "ns=1;i=4001",             // 节点ID
  "type": "Double",                     // 数据类型
  "dynamic": false,                     // 静态点位
  "initialValue": 100.0,                // 初始值
  "deviceName": "DynamicDevice"         // 挂载的设备名称
}
```

#### 支持的数据类型
- `Double`: 双精度浮点数
- `Int32`: 32位整数
- `String`: 字符串
- `Boolean`: 布尔值

#### 动态类型说明
- `random`: 在指定范围内生成随机值
- `increment`: 按指定步长递增

#### 批量生成规则
1. 点位名称：`{namePrefix}{序号}`，例如：`Temperature1`、`Temperature2`...
2. 显示名称：`{displayNamePrefix}{序号}`，例如：`温度传感器1`、`温度传感器2`...
3. 节点ID：基于 `nodeIdPrefix` 的数字部分递增，例如：`ns=1;i=1001`、`ns=1;i=1002`...

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

#### 批量添加多个相似数据点
在 `points-config.json` 中添加：
```json
{
  "namePrefix": "Pressure",
  "displayNamePrefix": "压力传感器",
  "description": "压力值（0-10 bar）",
  "nodeIdPrefix": "ns=1;i=2000",
  "type": "Double",
  "dynamic": true,
  "dynamicType": "random",
  "range": [0, 10],
  "interval": 2000,
  "deviceName": "SensorDevice",
  "count": 3                             // 生成 3 个压力传感器
}
```
这将自动生成：`Pressure1`、`Pressure2`、`Pressure3` 三个点位。

#### 添加单个数据点
在 `points-config.json` 中添加：
```json
{
  "name": "ManualPressure",
  "displayName": "手动压力传感器",
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
2. **批量点位生成**: 支持通过配置文件批量生成大量相似点位，只需指定前缀和数量
3. **灵活的节点结构**: 可以通过配置文件定义复杂的节点层次结构
4. **易于扩展**: 添加新设备和数据点只需修改 JSON 文件
5. **多语言支持**: 支持中文显示名称和描述
6. **日志控制**: 可以通过配置控制日志输出级别
7. **环境适配**: 可以为不同环境配置不同的端点地址
8. **混合配置**: 支持批量生成和单个配置混合使用

## 📝 注意事项

1. 节点 ID 中的 `ns=1` 会自动替换为实际的命名空间索引
2. 数据点的 `deviceName` 必须与设备节点的 `browseName` 匹配
3. 修改配置文件后需要重启服务器才能生效
4. 确保节点 ID 在同一命名空间内唯一
5. **批量配置注意事项**：
   - 确保 `nodeIdPrefix` 的基础数字不重复
   - `count` 字段大于1时才会批量生成，否则按单个点位处理
   - 批量生成的节点ID会自动递增，避免冲突
   - 动态点位会自动启动定时器进行数值更新

## 📊 当前配置示例

当前配置文件生成的点位：
- **温度传感器** (5个): Temperature1-5，随机值范围 20-30，更新间隔 1秒
- **压力传感器** (3个): Pressure1-3，随机值范围 0-100，更新间隔 2秒
- **计数器** (2个): Counter1-2，每秒递增1
- **静态值** (1个): StaticValue，可读写的静态值

总计：**11个数据点**（10个动态 + 1个静态）
