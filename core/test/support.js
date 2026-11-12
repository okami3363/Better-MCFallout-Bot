// 測試共用：本機的 1.19.2 假伺服器，以及啟動 core 連上它。
const { spawn } = require("node:child_process");
const path = require("node:path");
const mc = require("minecraft-protocol");

/** 啟動本機的 1.19.2 假伺服器，用戶端登入後呼叫 onLogin。回傳埠號。 */
async function startServer(t, onLogin) {
  const server = mc.createServer({
    "online-mode": false,
    host: "127.0.0.1",
    port: 0,
    version: "1.19.2",
  });
  t.after(() => server.close());
  server.on("login", onLogin);
  await new Promise((resolve) => server.once("listening", resolve));
  return server.socketServer.address().port;
}

/**
 * 啟動 core 連到本機假伺服器，等它送出第一個指定名稱的事件。
 * 回傳 { event, output }；core 結束或 5 秒內沒等到時 event 為 undefined。
 */
function firstEvent(t, port, name) {
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
  const core = spawn(process.execPath, [
    path.join(__dirname, "../dist/index.js"),
    JSON.stringify(config),
  ]);
  t.after(() => core.kill("SIGKILL"));

  let stdout = "";
  let output = "";
  return new Promise((resolve) => {
    const done = (event) => resolve({ event, output });

    core.stdout.on("data", (chunk) => {
      stdout += chunk;
      output += chunk;
      for (const line of stdout.split("\n")) {
        try {
          const event = JSON.parse(line);
          if (event.event === name) return done(event);
        } catch {
          // 不是事件，或這一行還沒收完
        }
      }
    });
    core.stderr.on("data", (chunk) => (output += chunk));
    core.on("close", () => done());
    setTimeout(done, 5000).unref();
  });
}

module.exports = { startServer, firstEvent };
