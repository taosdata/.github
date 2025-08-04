const { OPCUAClient, MessageSecurityMode, SecurityPolicy, AttributeIds, TimestampsToReturn } = require("node-opcua");

async function testClient() {
    const client = OPCUAClient.create({
        applicationName: "TestClient",
        connectionStrategy: {
            initialDelay: 1000,
            maxRetry: 1
        },
        securityMode: MessageSecurityMode.None,
        securityPolicy: SecurityPolicy.None,
        endpoint_must_exist: false
    });

    try {
        console.log("正在连接到 OPC UA 服务器...");
        
        // 尝试连接到本地服务器
        const endpointUrl = "opc.tcp://localhost:4840/UA/ConfigServer";
        await client.connect(endpointUrl);
        console.log("✅ 成功连接到服务器:", endpointUrl);

        // 创建会话
        const session = await client.createSession();
        console.log("✅ 会话创建成功");

        // 浏览根节点
        console.log("\n🔍 浏览服务器节点结构:");
        const browseResult = await session.browse("ns=0;i=84");
        console.log("根节点下的子节点:");
        browseResult.references?.forEach(ref => {
            console.log(`  - ${ref.browseName.toString()} (${ref.nodeId.toString()})`);
        });

        // 读取数据点
        console.log("\n📊 读取数据点:");
        const nodesToRead = [
            {
                nodeId: "ns=2;i=1001", // FastTemperature
                attributeId: AttributeIds.Value
            },
            {
                nodeId: "ns=2;i=1002", // SlowCounter
                attributeId: AttributeIds.Value
            }
        ];

        const dataValues = await session.read(nodesToRead);
        dataValues.forEach((dataValue, index) => {
            const nodeName = index === 0 ? "FastTemperature" : "SlowCounter";
            if (dataValue.statusCode.isGood()) {
                console.log(`  ✅ ${nodeName}: ${dataValue.value.value} (${dataValue.value.dataType})`);
            } else {
                console.log(`  ❌ ${nodeName}: 读取失败 - ${dataValue.statusCode.toString()}`);
            }
        });

        // 创建订阅来监控数据变化
        console.log("\n🔔 创建数据订阅 (监控5秒):");
        const subscription = await session.createSubscription2({
            requestedPublishingInterval: 1000,
            requestedLifetimeCount: 100,
            requestedMaxKeepAliveCount: 10,
            maxNotificationsPerPublish: 100,
            publishingEnabled: true,
            priority: 10
        });

        // 监控温度值
        const monitoredItem1 = await subscription.monitor({
            nodeId: "ns=2;i=1001",
            attributeId: AttributeIds.Value
        }, {
            samplingInterval: 500,
            discardOldest: true,
            queueSize: 10
        }, TimestampsToReturn.Both);

        // 监控计数器
        const monitoredItem2 = await subscription.monitor({
            nodeId: "ns=2;i=1002",
            attributeId: AttributeIds.Value
        }, {
            samplingInterval: 500,
            discardOldest: true,
            queueSize: 10
        }, TimestampsToReturn.Both);

        monitoredItem1.on("changed", (dataValue) => {
            console.log(`  🌡️  温度变化: ${dataValue.value.value.toFixed(2)}°C`);
        });

        monitoredItem2.on("changed", (dataValue) => {
            console.log(`  🔢 计数器变化: ${dataValue.value.value}`);
        });

        // 等待5秒观察数据变化
        await new Promise(resolve => setTimeout(resolve, 5000));

        // 清理资源
        await subscription.terminate();
        await session.close();
        console.log("\n✅ 测试完成，会话已关闭");

    } catch (error) {
        console.error("❌ 测试失败:", error.message);
    } finally {
        await client.disconnect();
        console.log("✅ 客户端已断开连接");
    }
}

// 运行测试
testClient().catch(console.error);
