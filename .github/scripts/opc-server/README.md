# OPC UA 服务器配置说明

这是一个用于测试的简易OPC UA Server 程序，可以通过配置文件完成基本的OPC UA Server配置和运行，并支持各种数据类型的测点和测试数据生成。

## 启动opc-server

```bash
npm install
npm server.js
```
## 配置文件结构

### 统一配置文件 `config.json`

所有配置都统一在 `config.json` 文件中，包括服务器配置、命名空间、节点结构、数据点和日志配置：

#### 服务器基础配置 (`server` 节)
```json
{
  "server": {
    "port": 4840,                    // 服务器端口
    "resourcePath": "/UA/ConfigServer", // 资源路径
    "bindAddress": "0.0.0.0",        // 绑定地址（0.0.0.0 监听所有接口）
    "allowAnonymous": true,          // 是否允许匿名访问
    "securityPolicies": ["None", "Basic128Rsa15", "Basic256Sha256"], // 安全策略
    "alternateHostname": ["localhost", "127.0.0.1"] // 备用主机名
  }
}
```

#### 命名空间配置 (`namespace` 节)
```json
{
  "namespace": {
    "uri": "http://example.com/dynamic-config", // 命名空间 URI
    "name": "CustomNamespace"                   // 命名空间显示名称
  }
}
```

#### 节点结构配置 (`nodeStructure` 节)
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

#### 日志配置 (`logging` 节)
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

#### 数据点配置 (`dataPoints` 节)

定义所有的 OPC UA 变量节点（数据点）。

#### 批量生成点位配置
```json
{
  "dataPoints": [
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
  ]
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

## 节点定义说明

### CustomRoot 节点 (`ns=2;i=9000`)

- **定义位置**: `config.json` → `nodeStructure.customRoot`
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

- **定义位置**: `config.json` → `nodeStructure.devices[]`
- **作用**: 作为数据点的容器
- **配置方式**: 可以定义多个设备节点

### 数据点节点

- **定义位置**: `config.json` → `dataPoints[]`
- **挂载方式**: 通过 `deviceName` 字段指定挂载到哪个设备

## 注意事项

1. 节点 ID 中的 `ns=1` 会自动替换为实际的命名空间索引
2. 数据点的 `deviceName` 必须与设备节点的 `browseName` 匹配
3. 修改配置文件后需要重启服务器才能生效
4. 确保节点 ID 在同一命名空间内唯一
5. **批量配置注意事项**：
   - 确保 `nodeIdPrefix` 的基础数字不重复
   - `count` 字段大于1时才会批量生成，否则按单个点位处理
   - 批量生成的节点ID会自动递增，避免冲突
   - 动态点位会自动启动定时器进行数值更新

## 当前配置示例

当前配置文件生成的点位：
- **温度传感器** (5个): Temperature1-5，随机值范围 20-30，更新间隔 1秒
- **压力传感器** (3个): Pressure1-3，随机值范围 0-100，更新间隔 2秒
- **计数器** (2个): Counter1-2，每秒递增1
- **静态值** (1个): StaticValue，可读写的静态值

总计：**11个数据点**（10个动态 + 1个静态）
