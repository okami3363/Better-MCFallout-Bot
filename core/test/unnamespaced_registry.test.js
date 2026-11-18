// 迴歸測試：伺服器送來的註冊表 key 沒有 `minecraft:` 命名空間時，
// core 仍要能登入並送出 connected 事件（否則 app 會顯示「無法連線到廢土伺服器」）。
//
// 執行：yarn test
const test = require("node:test");
const assert = require("node:assert");
const mcData = require("minecraft-data")("1.19.2");
const { startServer, joinGame, firstEvent } = require("./support");

// 廢土伺服器（BungeeCord 26.x）對 1.19.2 用戶端送的是 `dimension_type`，
// 而不是原版的 `minecraft:dimension_type`。
function withoutNamespace(codec) {
  const value = {};
  for (const [key, registry] of Object.entries(codec.value)) {
    value[key.replace(/^minecraft:/, "")] = registry;
  }
  return { ...codec, value };
}

test("註冊表 key 沒有 minecraft: 命名空間時仍能連線", async (t) => {
  const dimensionCodec = withoutNamespace(mcData.loginPacket.dimensionCodec);
  assert.deepStrictEqual(Object.keys(dimensionCodec.value).sort(), [
    "chat_type",
    "dimension_type",
    "worldgen/biome",
  ]);

  const port = await startServer(t, (client) =>
    joinGame(client, { ...mcData.loginPacket, dimensionCodec })
  );

  const { event, output } = await firstEvent(t, port, "connected");

  assert.ok(event, `core 沒有送出 connected 事件：\n${output}`);
});
