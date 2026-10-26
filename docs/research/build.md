# 建置環境

本次實測：Apple Silicon arm64、macOS 27.0.1（26A434）、Xcode 27.1（27A9275）、Swift 6.4、Apple Git 2.54.0。Xcode 工程最低執行系統為 macOS 13，C++20。上游 AGENTS.md 的舊版環境說明不是當前工程設定。

執行 `scripts/build.sh Debug`。首度建置由 Xcode 解析 SwiftyOpenCC、SQLite.swift，Data target 產生詞庫。建置不執行安裝器；僅以 ad-hoc 簽章，不使用個人憑證。

C++：`cmake -DENABLE_TEST=ON -S Source -B build/engine`、`cmake --build build/engine -j 4`、`ctest --test-dir build/engine --output-on-failure`。正確入口是 Source/CMakeLists.txt，不是單獨 Engine。

Swift：`xcodebuild -project McBopomofo.xcodeproj -scheme McBopomofo -configuration Debug -derivedDataPath build/DerivedData CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test`。

更新時間：2026-10-26T16:13:42+08:00
