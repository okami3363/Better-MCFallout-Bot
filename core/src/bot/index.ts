import { BotHelper } from "@/bot/bot_helper";
import { EventEmitter, Event } from "@/util/event_emitter";
import * as mineflayer from "mineflayer";
import * as autoeat from "mineflayer-auto-eat";
import * as readline from "readline";
import { ActionHandler } from "@/util/action_handler";
import { config } from "@/index";

export function createBot() {
  const bot = mineflayer.createBot({
    username: config.username,
    auth: async (client, options) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (options as any).haveCredentials = true;

      const session = {
        accessToken: config.token,
        selectedProfile: {
          name: config.username,
          id: config.uuid,
        },
      };

      client.session = session;
      client.username = session.selectedProfile.name;
      options.accessToken = session.accessToken;
      client.emit("session", session);

      options.connect?.(client);
    },
    version: "1.19.2",
    host: config.host,
    port: config.port,
    checkTimeoutInterval: 60 * 1000, // 60 seconds
  });

  // 廢土伺服器送來的註冊表 key 沒有命名空間（例如 `dimension_type`），
  // 但 mineflayer 只認 `minecraft:dimension_type`，登入時會直接當掉。
  // Minecraft 的識別碼省略命名空間時預設就是 `minecraft`，所以補上即可。
  // 用 prependListener 才能搶在 mineflayer 自己的 login 處理之前執行。
  bot._client.prependListener("login", (packet) => {
    const codec = packet.dimensionCodec?.value;
    if (!codec) return;

    for (const key of Object.keys(codec)) {
      if (key.includes(":")) continue;
      codec[`minecraft:${key}`] = codec[key];
      delete codec[key];
    }
  });

  bot.loadPlugin(autoeat.plugin);

  EventEmitter.info("Bot created");

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: false,
  });

  rl.on("line", function (line) {
    try {
      ActionHandler.handle(bot, line);
    } catch (error) {
      EventEmitter.error(`Error while handling action: ${error}`);
    }
  });

  listenBotEvent(bot);

  bot.once("end", (reason) => {
    EventEmitter.emit(Event.disconnected, { reason });
  });

  // Error handling
  bot.on("error", (err) => {
    EventEmitter.error(err.message);
  });
}

function listenBotEvent(bot: mineflayer.Bot) {
  bot.once("spawn", () => BotHelper.onSpawn(bot));

  bot.on("message", (jsonMsg) => {
    const message = jsonMsg.valueOf();

    const isTpa =
      message.startsWith("[系統] ") &&
      (message.includes("想要你傳送到 該玩家 的位置!") ||
        message.includes("想要傳送到 你 的位置"));

    if (isTpa) {
      const playerId = message.split("[系統] ")[1].split("想要")[0].trim();

      if (config.allow_tpa.includes(playerId)) {
        bot.chat("/tok");
      } else {
        bot.chat("/tno");
      }
    }

    EventEmitter.gameMessage(message.valueOf(), new Date().getTime());
  });

  // @ts-ignore
  bot.on("autoeat_error", (err) => {
    if (err) {
      EventEmitter.warning(`Auto eat failed: ${err}`);
    }
  });

  bot.on("health", () => {
    BotHelper.autoEatConfig(bot);
  });

  bot.on("kicked", (reason) => {
    EventEmitter.error(`The bot was kicked by server: ${reason}`);
  });
}
