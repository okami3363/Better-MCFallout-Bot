// 測試共用：本機的 1.19.2 假伺服器，以及啟動 core 連上它。
const { spawn } = require("node:child_process");
const path = require("node:path");
const mc = require("minecraft-protocol");
const mcData = require("minecraft-data")("1.19.2");

/** 啟動本機的 1.19.2 假伺服器，用戶端登入後呼叫 onLogin。回傳埠號。 */
async function startServer(t, onLogin) {
  const server = mc.createServer({
    "online-mode": false,
    host: "127.0.0.1",
    port: 0,
    version: "1.19.2",
  });
  // 收尾時直接切斷還連著的用戶端，不用 server.close()：它會對每個還在的用戶端
  // 再呼叫一次 client.end()。測試自己結束過的用戶端（例如把它踢掉）如果連線還
  // 沒真的結束，minecraft-protocol 會留下前一次 end() 設的 30 秒計時器，測試
  // 行程要等它跑完才會結束。
  t.after(() => {
    for (const client of Object.values(server.clients)) client.socket.destroy();
    server.socketServer.close();
  });
  server.on("login", onLogin);
  await emitted(server, "listening");
  return server.socketServer.address().port;
}

/**
 * 讓登入的用戶端進入遊戲：core 會因此回報 connected，之後照常運作。
 * loginPacket 預設是原版 1.19.2 的登入封包。
 */
function joinGame(client, loginPacket = mcData.loginPacket) {
  client.write("login", loginPacket);
  // core 每秒回報狀態時要用到世界時間，沒收過的話會當掉
  client.write("update_time", { age: [0, 0], time: [0, 0] });
  // mineflayer 收到第一個 update_health 才會發出 spawn
  client.write("update_health", { health: 20, food: 20, foodSaturation: 5 });
}

// 設了 CORE_BIN 就改測打包好的執行檔，否則測 dist 裡編譯好的程式
const packagedCore = process.env.CORE_BIN;

// 等 core 做出反應的上限。打包好的 Intel 版在 Apple Silicon 上第一次執行時，
// 要先經過 Rosetta 轉譯，會比平常慢很多。
const TIMEOUT_MS = packagedCore ? 60000 : 5000;

/** 啟動 core 連到本機假伺服器。和 app 一樣用管線啟動，stdin 會一直開著。 */
function startCore(t, port) {
  const config = {
    host: "127.0.0.1",
    port,
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
  const [command, ...args] = packagedCore
    ? [packagedCore]
    : [process.execPath, path.join(__dirname, "../dist/index.js")];
  const core = spawn(command, [...args, JSON.stringify(config)]);
  t.after(() => core.kill("SIGKILL"));
  return core;
}

/**
 * 啟動 core 連到本機假伺服器，等它送出第一個指定名稱的事件。
 * 回傳 { event, output, core }；core 結束或逾時沒等到時 event 為 undefined。
 */
function firstEvent(t, port, name) {
  const core = startCore(t, port);

  let stdout = "";
  let output = "";
  const found = new Promise((resolve) => {
    core.stdout.on("data", (chunk) => {
      stdout += chunk;
      output += chunk;
      for (const line of stdout.split("\n")) {
        try {
          const event = JSON.parse(line);
          if (event.event === name) return resolve(event);
        } catch {
          // 不是事件，或這一行還沒收完
        }
      }
    });
    core.stderr.on("data", (chunk) => (output += chunk));
    core.on("close", () => resolve());
  });
  return inTime(found).then((event) => ({ event, output, core }));
}

/** emitter 發出 name 事件時完成，結果是 true。 */
function emitted(emitter, name) {
  return new Promise((resolve) => emitter.once(name, () => resolve(true)));
}

/** 等 promise 完成並回傳它的結果；等超過上限還沒完成就回傳 undefined。 */
function inTime(promise) {
  return Promise.race([
    promise,
    new Promise((resolve) => setTimeout(resolve, TIMEOUT_MS).unref()),
  ]);
}

module.exports = {
  startServer,
  joinGame,
  startCore,
  firstEvent,
  emitted,
  inTime,
};
