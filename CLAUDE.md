# 練習ベース

練習メニューを1枚ずつカードとして貯め、「今日のトレーニング」（W-up / Tr.1 / Tr.2 / Game）に組み立てて印刷する、指導者向けのWebアプリ。最初の競技はサッカー。

- 設計図：https://claude.ai/code/artifact/6a8b5893-657c-4b05-8b27-5d4dadb679ec
- お手本：JFA ナショナルトレセンU-12「実技④ ゴールを奪う」
  https://www.jfa.jp/youth_development/national_tracen/pdf/ntc_u12_menu_04.pdf

## 構成

- `index.html` … 本体（HTML・CSS・JSすべて。ライブラリなし）
- `sw.js` … 電波のない場所でも開くための控え（ネット優先、だめな時だけキャッシュ）。https のときだけ登録される
- `manifest.webmanifest`、`icon-192.png`、`icon-512.png`、`apple-touch-icon.png`

サーバーなし。データは端末内の IndexedDB（DB名 `renshu-base`、ストア `cards` / `plans` / `meta`）。
図の画像は長辺1400pxのJPEGに縮めて、カードの `images` に data URL で持つ。

## データの形

- カード：`normCard()` が正。区分 `cats` は `wup|tr1|tr2|game`、出典 `src.type` は `own|jfa|web|book`
- 計画：`normPlan()` が正。`slots[].cardId` でカードを参照する（コピーは持たない）
- 読みこみ（設定 → 読みこむ）は `{cards, plans, themes}` でも、カードの配列だけでも受けつける。id がなければ新規発行

## 決めごと

- 資料の文章・図は丸写ししない。お手本6枚は要点を言いかえて入れてあり、図は入れていない。出典URLは必ず残す
- 資料を写したカードは `share:false`（自分用）のままにする。共有・販売版には `share:true` だけを載せる
- 体育プラン（生徒用の教材）とは別アプリ。コードは共有しない

## 公開

GitHub Pages：https://konkora780-ux.github.io/renshu-base/ （konkora780-ux/renshu-base の main に push すると反映）

## 動かし方

`D:\Claudプロジェクト\.claude\launch.json` の `renshu-base`（ポート8792）でプレビューできる。

## 段階

1. 済：カード登録、図鑑としぼり込み、今日のトレーニング、印刷（一覧版・詳細版）、JSONの書き出し・読みこみ、お手本カード
2. 未：アプリ内の作図ボード
3. 未：写真・PDFからのよみとり、ふりかえりの活用
4. 未：Supabaseでの共有、他競技、商用化の検討
