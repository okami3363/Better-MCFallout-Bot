// 迴歸測試：伺服器送來的註冊表 key 沒有 `minecraft:` 命名空間時，
// core 仍要能登入並送出 connected 事件（否則 app 會顯示「無法連線到廢土伺服器」）。
//
// 執行：yarn test
const test = require("node:test");
const assert = require("node:assert");
const { spawn } = require("node:child_process");
const path = require("node:path");
const mc = require("minecraft-protocol");
const mcData = require("minecraft-data")("1.19.2");

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

  const server = mc.createServer({
    "online-mode": false,
    host: "127.0.0.1",
    port: 0,
    version: "1.19.2",
  });
  t.after(() => server.close());
  server.on("login", (client) => {
    client.write("login", { ...mcData.loginPacket, dimensionCodec });
    // mineflayer 收到第一個 update_health 才會發出 spawn
    client.write("update_health", { health: 20, food: 20, foodSaturation: 5 });
  });
  await new Promise((resolve) => server.once("listening", resolve));

  const config = {
    host: "127.0.0.1",
    port: server.socketServer.address().port,
    username: "test",
    token: "x",
    uuid: "00000000-0000-0000-0000-000000000000",
    auto_eat: false,
    auto_throw: false,
    warp_publicity: null,
    trade_publicity: null,
    allow_tpa: [],
    attack_interval_ticks: 12,
  };
  const core = spawn(process.execPath, [
    path.join(__dirname, "../dist/index.js"),
    JSON.stringify(config),
  ]);
  t.after(() => core.kill("SIGKILL"));

  let output = "";
  const connected = await new Promise((resolve) => {
    const onData = (chunk) => {
      output += chunk;
      if (output.includes('"event":"connected"')) resolve(true);
    };
    core.stdout.on("data", onData);
    core.stderr.on("data", onData);
    core.on("exit", () => resolve(false));
    setTimeout(() => resolve(false), 5000).unref();
  });

  assert.ok(connected, `core 沒有送出 connected 事件：\n${output}`);
});
