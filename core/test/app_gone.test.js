// 迴歸測試：app 沒有先叫 core 斷線就消失時（當掉、被強制結束，或沒經過關閉
// 確認就結束），core 要跟著結束。否則它會留在背景，帳號繼續留在伺服器上。
//
// core 的 stdin 是 app 開的管線，app 的行程一結束它就會關閉，這裡用關閉 stdin
// 來模擬 app 消失。
//
// 執行：yarn test
const test = require("node:test");
const assert = require("node:assert");
const net = require("node:net");
const {
  startServer,
  joinGame,
  startCore,
  firstEvent,
  emitted,
  inTime,
} = require("./support");

test("app 消失時，已經登入的 core 會結束，伺服器上的連線也跟著斷開", async (t) => {
  let disconnected;
  const port = await startServer(t, (client) => {
    disconnected = emitted(client, "end");
    // 要進到遊戲裡才算數：這時 core 有定時工作在跑，只斷線的話行程會留著
    joinGame(client);
  });
  const { event, output, core } = await firstEvent(t, port, "connected");
  assert.ok(event, `core 沒有連上：\n${output}`);
  const exited = emitted(core, "exit");

  core.stdin.end();

  assert.ok(await inTime(exited), "app 消失後 core 沒有結束");
  assert.ok(await inTime(disconnected), "伺服器上的連線沒有斷開");
});

test("core 還沒登入時 app 就消失，core 一樣會結束", async (t) => {
  // 只接受連線、不回應登入的伺服器：core 會一直停在登入之前
  const server = net
    .createServer((socket) => t.after(() => socket.destroy()))
    .listen(0, "127.0.0.1");
  t.after(() => server.close());
  await emitted(server, "listening");
  const connected = emitted(server, "connection");
  const core = startCore(t, server.address().port);

  assert.ok(await inTime(connected), "core 沒有連到伺服器");
  const exited = emitted(core, "exit");

  core.stdin.end();

  assert.ok(await inTime(exited), "app 消失後 core 沒有結束");
});
