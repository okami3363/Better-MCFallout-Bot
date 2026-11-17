# 用法：bash script/build_macos.sh [版本號]
# 有給版本號時，app 顯示的版本就是它；沒給則用 pubspec.yaml 裡的版本。
set -e

bash script/build_core_macos.sh

cd app
echo "[Info] Building the app"
flutter build macos --release ${1:+--build-name="$1"}

echo "[Info] Done"
