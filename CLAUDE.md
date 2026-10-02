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
カードの `images` は `{src, board}` の配列。写真は長辺1400pxのJPEG（data URL）で `board` は null。
作図ボードで描いた図は `board`（`{field, items}`、座標は1000×700）が正で、`src` は `svgURL(board)` で毎回作りなおすSVG。

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
2. 済：アプリ内の作図ボード（コート5種、選手・用具、パス／人の動き／ドリブルの線、わく、文字）。お手本6枚にも図を追加
3. 済：写真・PDFからのよみとり（Gemini。キーは localStorage `renshu-base.gemini`、モデル既定 `gemini-2.5-flash`）、実施の記録（`plan.done`・`slot.rating`・`slot.result` → `cardStats()`）、おまかせの改良（`pickScore()`）、時間のふり分け。**よみとりは実際のAPIでは未検証**（fetchを差しかえた模擬でのみ確認）
4. 未：Supabaseでの共有、他競技、商用化の検討

## 2026-10-02 の追加

- **選手の向き**：選手（`t:'p'`）に `rot`（0=上、90=右、180=下、270=左）を追加。両手を体の前に描き、手のある側が前。置くときに指をずらすか、「えらぶ」で青い丸を動かして向きを変える
- **練習集**：`packData()` に22枚（JFA 2016 実技①②③、JFA 2020 トレセンU-12とGK、ジュニアサッカー大学のロンド2本）と、ひな型3件。id は `pk-…`。文章は言いかえ、図は描きおこし、出典URLつき
- 既存の端末には meta の `pack2` フラグで1回だけ入る。お手本の図の向きは `seedfig2` で、元のままの図だけ入れかえる
- 人数は資料から読みとれるものだけ入れた。所要時間は資料にないので空欄（ロンド2本だけ記事の値）
