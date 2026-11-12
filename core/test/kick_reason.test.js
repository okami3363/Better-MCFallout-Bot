// 迴歸測試：被伺服器踢出時，core 回報的是看得懂的原因，而不是聊天元件的
// 原始 JSON（app 會把這段文字直接顯示在錯誤對話框）。
//
// 執行：yarn test
const test = require("node:test");
const assert = require("node:assert");
const { startServer, firstEvent } = require("./support");

test("被伺服器踢出時回報純文字的原因", async (t) => {
  const reason = {
    text: "",
    extra: [{ text: "您已被伺服器封鎖：" }, { text: "測試原因", color: "red" }],
  };
  const port = await startServer(t, (client) =>
    client.end("kicked", JSON.stringify(reason))
  );

  const { event } = await firstEvent(t, port, "error");

  assert.strictEqual(
    event?.data.message,
    "被伺服器踢出：您已被伺服器封鎖：測試原因"
  );
});
