# 更好的 Minecraft 廢土伺服器機器人

## 📚 介紹
這是個具有許多功能的廢土機器人，且完全**免費**與**開源**  
另一大特色就是具有容易操作的界面，而不是傳統的小黑窗，讓任何人都能夠輕鬆使用~

詳細功能請看 [這裡](#-功能)  
祝您使用愉快！  

> 這是 [SiongSng/Better-MCFallout-Bot](https://github.com/SiongSng/Better-MCFallout-Bot) 的修改版。原專案已封存，停在 1.0.6；與原版的差異請看 [這裡](#-與原版的差異)。

Discord 社群: https://discord.gg/WJSnhPzcgs  

## [立即下載](#-下載)   

![image](https://user-images.githubusercontent.com/48402225/182155275-dc162aae-85ca-44a4-80d6-cef10a9bb55b.png)

## 🎮 下載
目前只提供 macOS 版的安裝檔（macOS 12 以上，Intel 與 Apple Silicon 的 Mac 都能用）。Windows 與 Linux 需要自行從原始碼建置。

[前往下載頁面](https://github.com/okami3363/Better-MCFallout-Bot/releases/latest)

在下方的 `Assets` 欄位下載 `.dmg` 檔。

### 如何使用
1. 打開下載的 `.dmg`，把 `better_mcfallout_bot` 拖進「應用程式」
2. 第一次開啟時 macOS 會擋下來，屬於正常現象，因為沒使用 Apple 開發者帳號簽署 (Apple 開發者帳號蠻貴的)
3. 開啟「系統設定」，進入「隱私權與安全性」，往下捲到「安全性」，在 `better_mcfallout_bot` 的提示旁按「強制打開」

## 🎨 功能
### ***自動刷突襲塔***
自動攻擊突襲塔的怪物，獲得滿滿的綠寶石 💵💵💵 

### 自動掛機
對就是掛機，看似很一般的功能，但不用開啟麥塊本體就可以輕鬆掛物資。  
~~雖然我不是數學家，但這聽起來還不錯對吧~~
### 自動飲食
自動飲食，肉、蔬菜、湯都支援，可以防止餓死 (腐肉是黑名單)

### 自動丟棄物品
自動丟棄不重要的物品，保留重要物品，像是武器、不死圖騰、食物、裝備，在刷突襲塔的時候很有用

### 自動重新連線
自動重新連線伺服器，如果突然斷線或者廢土伺服器當機，會立刻重新連線；連不上（包含連上後隨即又斷線）就每 30 秒重試一次，連續失敗 10 次後改為每 15 分鐘重試一次，直到連上或您自己取消為止

### 多重開啟
同時啟動多個不同帳號的機器人，達成效益最大化！

## 🔧 與原版的差異
- 修正登入後連不上廢土伺服器的問題
- 連線失敗、被伺服器踢出時，會顯示真正的原因
- 斷線後會一直自動重連，直到連上或您自己取消；視窗被遮住或最小化時也一樣
- 不再回傳錯誤回報與使用統計
- 目前只提供 macOS 版的安裝檔

## 🪟 截圖
![image](https://user-images.githubusercontent.com/48402225/182106836-05185041-ecea-424f-833c-512fe81abd4a.png)
![image](https://user-images.githubusercontent.com/48402225/182161060-941173f2-8147-4a29-aee6-b85e9ad03dae.png)

## ⚙️ 開發
注意：這是給開發者看的，如果您是使用者請看 [這裡](#-下載)

首先請先安裝 [Flutter SDK](https://docs.flutter.dev/get-started/install) 與 [Node.js](https://nodejs.org/download) 還有 [Yarn](https://yarnpkg.com/getting-started/install).

### VSCode
另外請安裝 [Flutter 的擴充套件](https://marketplace.visualstudio.com/items?itemName=Dart-Code.flutter)  
接著切換到執行的分頁並點擊小綠旗稍等一下就可以囉~  

![image](https://user-images.githubusercontent.com/48402225/182102401-d76f2745-c81b-458c-99cb-4999c7c9ee9d.png)

### CLI
並執行以下指令，稍等幾分鐘應該就會跳出畫面

Windows
```shell
script/dev_windows.bat
```

Linux
```bash
bash script/dev_linux.sh
```

macOS
```shell
bash script/dev_macos.sh
```

### Technologies
[Flutter](https://flutter.dev)  
[Dart](https://dart.dev)  
[Typescript](https://www.typescriptlang.org)  
Javascript  
[Node.js](https://nodejs.org)  
[Mineflayer](https://github.com/PrismarineJS/mineflayer)

## 免責聲明
本程式不會回傳任何錯誤回報或使用統計。執行紀錄只會存在您自己的電腦上，從主畫面左上角的資料夾圖示可以打開存放位置  
若是擔心安全問題可以自行從程式原始碼編譯，如果還是不放心的話就不要用吧