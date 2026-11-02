# AI注音 GitHub 命令列操作指南

整理時間：2026-11-03T01:34:06+08:00

儲存庫：https://github.com/edwardhome/AI-Bopomofo

主線固定使用小寫 `main`。你明天可以自行建立 0.6.11 Release；本次整理不會替你發布或安裝輸入法。

## 1. 先看懂四個東西

| 名稱 | 用途 | 本專案範例 |
| --- | --- | --- |
| Commit（提交） | 一次已保存的程式變動，有唯一編號 | `git log` 中的編號 |
| Branch（分支） | 開發路線，可以繼續往前更新 | `main`、`fix/example` |
| Tag（標籤） | 固定指向某個版本的提交 | `v0.6.10`、之後的 `v0.6.11` |
| Release（發布頁） | 掛在標籤上的說明及下載附件 | pkg、app ZIP、校驗檔 |

分支包含相同歷史很正常，不表示 GitHub 存了好幾份重複程式。舊的兩個 PR 都是向 `release/0.6.7` 提議整合，內容已在最新歷史中。本次主線整理會關閉這些重複提案；關閉 PR 和合併 PR 的狀態不同，但程式仍保留在主線。

以後不需要每個版本都換預設分支。持續更新 `main`，版本用標籤保存。歷史標籤與已發布附件不要隨意覆寫。未整合的 `research/apple-fm` 研究另外保留。

## 2. 進入專案與登入

Mac mini 的專案位置：

```bash
cd /Volumes/DATA/DATA/AI_Bopomofo
git status
git remote -v
gh auth status
```

`origin` 是你的 `edwardhome/AI-Bopomofo`；`upstream` 是小麥注音上游。平常只推送 `origin`。

Git 的 SSH 登入與 `gh` 的 GitHub API 登入是兩件事。能 `git push` 不代表能 `gh release create`。如果 `gh` 顯示尚未登入，執行：

```bash
gh auth login --hostname github.com --git-protocol ssh --web --skip-ssh-key
```

依畫面指示用瀏覽器完成登入，不需要把密碼或權杖貼進聊天或專案。`--skip-ssh-key` 表示不重複上傳 SSH 公鑰；新電腦仍須有可用的 Git SSH 認證，或自行選用 HTTPS。

MacBook Air 若還沒有專案，可在想放專案的目錄執行：

```bash
git clone git@github.com:edwardhome/AI-Bopomofo.git
cd AI-Bopomofo
```

若只要使用輸入法，直接安裝交付資料夾裡的 pkg 即可，不必 clone 或編譯。

## 3. 查看目前有哪些版本

```bash
git fetch origin --prune --tags
git status
git branch -vv
git branch -a
git log --oneline --graph --decorate -20
git tag --list 'v0.6.*' --sort=-version:refname
gh release list --repo edwardhome/AI-Bopomofo
```

- `git branch -vv`：本機分支及追蹤對象；星號代表目前所在分支。
- `git branch -a`：包含遠端分支。`origin/main` 是上次同步所得的遠端主線位置。
- `ahead 2`：本機比追蹤分支多兩個提交，尚未推送；不是多兩個檔案。
- `behind 2`：追蹤分支有兩個你尚未取得到目前分支的提交。
- `--prune`：清除已不存在的遠端分支之本機追蹤紀錄，不刪你的未提交檔案。
- Draft 只有有權限的人看得到；Pre-release 是開發測試發布。
- `v0.6.*` 篩選本專案目前的版本；不加篩選會同時看到保留的小麥注音上游標籤，那些不是重複資料。

## 4. 開始改一個功能

先確認 `git status` 沒有未保存的修改，再更新主線：

```bash
git switch main
git pull --ff-only origin main
git switch -c fix/my-input-change
```

`fix/my-input-change` 是範例名稱，請換成這次工作名稱。新功能可用 `feature/...`。如果 `pull --ff-only` 失敗，表示兩邊歷史分岔，先看 `git log --graph --oneline --all`，不要直接強制覆蓋。

修改完成後先看差異，再明確選擇檔案提交：

```bash
git diff
git status --short
git add Source/QuickSymbolLayer.swift
git diff --cached
git commit -m "fix(input): describe the actual change"
git push -u origin fix/my-input-change
```

上面的檔名與說明都要換成實際修改內容。不要把私人詞庫、密碼、編譯產物或整個資料夾不加檢查地提交。本機設定可能要求明確指定推送目的地，所以教學中的 `git push` 都寫出遠端與分支。

## 5. 檢查、編譯與打包

```bash
mkdir -p artifacts
scripts/test-headless.sh > artifacts/headless.log 2>&1
scripts/build.sh Release > artifacts/release.log 2>&1
```

上一個指令成功後才繼續。檢查結束後可用 `echo $?` 看退出碼，0 是成功；失敗時讀對應 log。這個測試流程執行無介面測試，整合測試只編譯，不啟動輸入法或模擬打字。

要打 0.6.11 的新本機包，先確定版本與原始碼：

```bash
git status --short
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Source/McBopomofo-Info.plist
scripts/package.sh 0.6.11-local.1 Release
scripts/verify-package.sh dist/0.6.11-local.1
```

`package.sh` 不改版本、不重新編譯、不安裝。要先完成上面的 Release 編譯，而且 app 版本必須是 0.6.11。輸出資料夾若已存在，改用 `0.6.11-local.2`，保留舊包供回退。

輸入法是否真的好打仍需實鍵驗收。你已回報：等待時間 100 毫秒時，「去、七、其」可重疊輸入；還可以測「其實我是要告訴你怎麼去這裡」，以及先長按 F 再按 U／M 的 8／2。

## 6. 把功能合併到 main

推薦用命令列建立 PR，GitHub 會顯示差異及檢查結果：

```bash
gh pr create --repo edwardhome/AI-Bopomofo \
  --base main --head fix/my-input-change \
  --title "fix(input): describe the actual change" \
  --body "說明問題、修改後行為，以及已完成的測試。"
gh pr list --repo edwardhome/AI-Bopomofo
```

記下新 PR 編號。以下 `123` 只是範例，換成你的編號：

```bash
gh pr diff 123 --repo edwardhome/AI-Bopomofo
gh pr checks 123 --repo edwardhome/AI-Bopomofo --watch
gh pr merge 123 --repo edwardhome/AI-Bopomofo --merge --delete-branch \
  --subject "fix(input): merge the reviewed input change"
git switch main
git pull --ff-only origin main
git fetch origin --prune
```

檢查通過、確認差異後才執行 merge。`--merge` 保留功能分支的提交歷史。刪除的是完成工作的分支名稱，不會刪掉已合併程式；不要刪未合併研究分支。

## 7. 明天自行發布 0.6.11

這一節的指令會真的建立標籤及 Release，請在你準備發布時才執行。本次整理不替你執行。先同步 `main` 並檢查 GitHub CI：

```bash
git switch main
git pull --ff-only origin main
git status --short
gh run list --repo edwardhome/AI-Bopomofo --branch main --limit 10
```

如果檢查失敗，用畫面上的數字 ID 取代下面的 `RUN_ID`：

```bash
gh run view RUN_ID --repo edwardhome/AI-Bopomofo --log-failed
```

準備使用本次的 `0.6.11-dev.3` 包時，先在專案根目錄核對：

```bash
cat dist/0.6.11-dev.3/SOURCE-COMMIT.txt
git diff --exit-code "$(cat dist/0.6.11-dev.3/SOURCE-COMMIT.txt)" HEAD \
  -- Source Packages McBopomofo.xcodeproj scripts LICENSE.txt ACKNOWLEDGEMENTS.md licenses
scripts/verify-package.sh dist/0.6.11-dev.3
```

`git diff` 沒有輸出且退出碼為 0，代表這些程式與建置路徑沒有變動。若你又修改程式，應重新編譯並用新的包名打包，不能拿舊安裝檔配新程式標籤。MacBook Air 的 Git clone 不包含 dist；本機開發包在指定的「AI Bopomofo/0.6.11」同步資料夾，若要完整重新驗證來源，可在 Air 自行建置並打包。

確定內容後，查詢標籤是否存在：

```bash
git fetch origin --tags
git tag --list v0.6.11
```

沒有輸出才建立新標籤：

```bash
git tag -a v0.6.11 -m "AI-Bopomofo 0.6.11"
git push origin v0.6.11
```

若已存在，先用 `git show --no-patch v0.6.11` 核對，不要刪掉重做或強制推送。標籤正確但 Release 還沒建立時，可直接繼續下面步驟。

從 Mac mini 的已驗證打包目錄建立草稿；如果使用自行重建的包，替換資料夾及附件名稱：

```bash
cd /Volumes/DATA/DATA/AI_Bopomofo/dist/0.6.11-dev.3
shasum -a 256 -c checksums.txt
gh release create v0.6.11 \
  AI-Bopomofo-0.6.11-dev.3.pkg \
  AI-Bopomofo-0.6.11-dev.3.zip \
  checksums.txt SOURCE-COMMIT.txt \
  --repo edwardhome/AI-Bopomofo \
  --verify-tag --draft --prerelease \
  --title "AI注音輸入法 0.6.11 開發測試版" \
  --generate-notes
gh release view v0.6.11 --repo edwardhome/AI-Bopomofo --web
```

`--verify-tag` 要求標籤已存在；`--draft` 先存草稿；`--prerelease` 標示開發測試版。自動產生的說明可能不完整，請在頁面補上「快速 ㄑㄧ／ㄑㄩ 保護、100 毫秒實測、其他 F 組合鍵維持立即啟動」，確認附件正確。

確認後，你可以按網頁的發布按鈕，或用命令列正式公開草稿：

```bash
gh release edit v0.6.11 --repo edwardhome/AI-Bopomofo --draft=false
gh release view v0.6.11 --repo edwardhome/AI-Bopomofo
```

公開後仍保留 Pre-release 身分。日後要改成穩定發布，應在完成相容性驗收後另外決定，不必現在改。

## 8. 常見疑問

**為什麼 README 變新，下載包還是舊版？**

推送 `main` 只更新程式碼與文件，沒有自動建立 Release，也沒有自動換附件。

**為什麼出現兩個 Source code 下載？**

GitHub 自動提供標籤的 ZIP 與 tar.gz 原始碼，它們不是輸入法安裝包。朋友應下載你附上的 pkg。

**要看舊版程式，又不想弄亂工作目錄？**

```bash
git show v0.6.10:README.md
git diff v0.6.10..main --stat
```

只讀取，不切換或修改檔案。想實際編譯舊版時，可另建 worktree，再依該版文件建置。

**預設主線怎麼確認？**

```bash
gh repo view edwardhome/AI-Bopomofo --json defaultBranchRef --jq .defaultBranchRef.name
```

應顯示 `main`。不必在每次發布時更改它。舊版本有標籤、Release 與 Git 歷史可以追溯。

**哪些動作先不要用？**

不熟悉時不要用 `git push --force`、`git reset --hard`、刪除歷史標籤或推送 `upstream`。若工作目錄有未提交修改，先保存與檢查，不要把錯誤訊息當作必須清空資料的理由。
