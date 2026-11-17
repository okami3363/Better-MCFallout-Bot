set -e

cd core
echo "[Info] Install dependencies"
# --ignore-engines：有相依套件宣告只支援到 Node 18，但打包時用的是 pkg 內建的 Node 18
yarn install --frozen-lockfile --ignore-engines
echo "[Info] Building core to executable"
yarn pkg:macos

echo "[Info] Copying the core to the app"
cd ..
# Intel 與 Apple Silicon 各一份，app 會依 CPU 選用
cp core/out/better-mcfallout-bot-core-x64 core/out/better-mcfallout-bot-core-arm64 app/assets/
