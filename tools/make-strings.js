// Build the String Catalogs from fold-proto's i18n.js tables (exported by fold-proto/tools/export.js).
// node tools/make-strings.js <strings.json>
// Writes App/Resources/{Localizable,Levels,InfoPlist}.xcstrings. Templates keep the web's {name} placeholders
// (and Korean {word:이} particles); App/Sources/L10n.swift fills them in, so every language keeps its own word order.
const fs = require('fs');
const path = require('path');
const src = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const LANG = { zh: 'zh-Hans', en: 'en', ja: 'ja', ko: 'ko' };
const outDir = path.join(__dirname, '..', 'App', 'Resources');

// strings the native app needs that the web prototype does not have
const NATIVE = {
  walkHere: ['走到这里', 'Walk here', 'ここへ歩く', '여기로 걷기'],
  hingeSource: ['折叠输入', 'Fold input', '折りの入力', '접기 입력'],
  'hinge.simulated': ['滑块与拖动', 'Slider and drag', 'スライダーとドラッグ', '슬라이더와 드래그'],
  'hinge.device': ['设备铰链', 'Device hinge', '本体のヒンジ', '기기 힌지'],
  'hinge.tilt': ['体感（未完成）', 'Tilt (coming soon)', '傾き（準備中）', '기울기(준비 중)'],
  'hinge.unavailable': ['这台设备没有铰链，继续用滑块', 'No hinge on this device; using the slider', 'この端末にはヒンジがありません。スライダーを使います', '이 기기에는 힌지가 없어요. 슬라이더를 사용해요'],
  'hinge.tiltSoon': ['体感还没做好，继续用滑块', 'Tilt is not ready yet; using the slider', '傾きはまだ準備中です。スライダーを使います', '기울기는 아직 준비 중이에요. 슬라이더를 사용해요'],
  'pre.stand': ['立起', 'Stand', '立てる', '세우기'],
  levelDoneMark: ['已完成', 'Solved', 'クリア', '완료'],
  // M1 (design-spec v1): cover, chapter map, letter, settings, button control, VoiceOver, sound mode
  'cover.tagline': ['一本合上才能读懂的书', 'A puzzle book you solve by closing it', '閉じてはじめて読める本', '덮어야 읽히는 책'],
  'cover.taglineEn': ['A puzzle book you solve by closing it', '', 'A puzzle book you solve by closing it', 'A puzzle book you solve by closing it'],
  'cover.begin': ['开始', 'Begin', 'はじめる', '시작'],
  'cover.beginLabel': ['开始：点这个线结', 'Begin: tap the knot', 'はじめる：結び目をタップ', '시작: 매듭을 누르세요'],
  'cover.settings': ['设置', 'Settings', '設定', '설정'],
  'nav.book': ['书', 'Book', '本', '책'],
  'nav.bookLabel': ['回到章节', 'Back to the chapters', '章の一覧へ', '장 목록으로'],
  'map.title': ['两岸', 'Both Banks', '両岸', '양안'],
  'map.progress': ['已送达 {n} / {total}', '{n} of {total} delivered', '{n} / {total} 通 届いた', '{total}통 중 {n}통 도착'],
  'map.continue': ['继续 {n}', 'Continue {n}', 'つづき {n}', '이어서 {n}'],
  'ch.1': ['对页', 'Facing Page', '見開き', '맞은편'],
  'ch.2': ['立', 'Stand', '立つ', '일어서다'],
  'ch.3': ['影', 'Shade', '影', '그림자'],
  'ch.4': ['倾', 'Tilt', '傾き', '기울기'],
  'ch.5': ['翻页', 'Turn the Page', 'ページをめくる', '책장 넘기기'],
  'ch.label': ['第{n}章，{name}', 'Chapter {n}, {name}', '第{n}章、{name}', '{n}장, {name}'],
  'ch.delivered': ['已送达', 'Delivered', '届いた', '도착함'],
  'ch.inProgress': ['进行中', 'In progress', '進行中', '진행 중'],
  'ch.sealed': ['未启封', 'Sealed', '未開封', '미개봉'],
  'ch.soon': ['即将推出 · Soon', 'Coming soon', '近日公開', '곧 공개'],
  'ch.count': ['{n}/{total}', '{n}/{total}', '{n}/{total}', '{n}/{total}'],
  'ch.lockedToast': ['这一章还没启封：先把第一章的信送到。', 'This chapter is still sealed: deliver the first letter first.', 'この章はまだ開封されていません。まず第1章の手紙を届けて。', '이 장은 아직 봉인되어 있어요. 먼저 1장의 편지를 전하세요.'],
  'letter.title': ['左岸来信', 'A Letter from the Left Bank', '左岸からの手紙', '왼쪽 강가에서 온 편지'],
  'letter.next': ['下一封信 →', 'Next letter →', '次の手紙 →', '다음 편지 →'],
  'letter.nextLabel': ['下一封信', 'Next letter', '次の手紙', '다음 편지'],
  'letter.onTheWay': ['下一封信还在路上。', 'The next letter is still on its way.', '次の手紙はまだ届いていません。', '다음 편지는 아직 오는 중이에요.'],
  'letter.read': ['读信', 'Read the letter', '手紙を読む', '편지 읽기'],
  'closed.caption': ['信，送到了。', 'The letter has arrived.', '手紙が届いた。', '편지가 도착했다.'],
  'seal.tong': ['路通了', 'The way is open', '道が通った', '길이 열렸다'],
  'win.continue': ['继续', 'Continue', 'つづける', '계속'],
  'settings.title': ['设置', 'Settings', '設定', '설정'],
  'set.buttons': ['按钮控制', 'Button control', 'ボタン操作', '버튼 조작'],
  'set.buttons.d': ['用按钮代替拖页与点格', 'Buttons instead of dragging the page and tapping squares', 'ページのドラッグとマスのタップの代わりにボタンで', '페이지 끌기와 칸 누르기 대신 버튼으로'],
  'set.speak.d': ['朗读格子、纸人与页的角度', 'Read squares, the figure and the page angle aloud', 'マス・人形・ページの角度を読み上げる', '칸, 인형, 페이지 각도를 읽어 줘요'],
  'set.sound.d': ['音高 = 行，音色 = 页', 'Pitch = row, timbre = page', '音の高さ＝行、音色＝ページ', '음높이 = 행, 음색 = 페이지'],
  'set.haptics': ['触觉强度', 'Haptics', '触覚の強さ', '햅틱 세기'],
  'set.haptics.d': ['合书、落印与路接通时的震动', 'When the book closes, a seal drops or a path connects', '閉じる・押印・道がつながる時の振動', '책을 덮을 때, 도장을 찍을 때, 길이 이어질 때'],
  'haptic.0': ['关', 'Off', 'オフ', '끔'],
  'haptic.1': ['弱', 'Light', '弱', '약'],
  'haptic.2': ['强', 'Strong', '強', '강'],
  'set.hc': ['高对比度', 'High contrast', '高コントラスト', '고대비'],
  'set.hc.d': ['用花纹区分格子，而非颜色', 'Patterns, not colour, tell the squares apart', '色ではなく模様でマスを区別', '색 대신 무늬로 칸을 구분'],
  'set.big': ['超大格子（≥64pt）', 'Extra-large squares (≥64pt)', '特大マス（64pt以上）', '아주 큰 칸 (64pt 이상)'],
  'set.big.d': ['任何关卡的格子都不小于 64pt', 'No square smaller than 64pt on any level', 'どのステージでもマスは64pt以上', '어떤 레벨에서도 칸이 64pt 이상'],
  'set.rm': ['减少动态效果', 'Reduce motion', '視差効果を減らす', '동작 줄이기'],
  'set.rm.d': ['折页以淡入代替翻转', 'Pages fade instead of turning', 'ページは回転せずフェードで切り替え', '페이지가 넘어가는 대신 서서히 바뀌어요'],
  'lang.system': ['跟随系统', 'System', 'システム', '시스템'],
  'switch.on': ['开', 'On', 'オン', '켬'],
  'switch.off': ['关', 'Off', 'オフ', '끔'],
  'fold.page': ['折页', 'Fold the page', 'ページを折る', '페이지 접기'],
  'fold.pageHint': ['上下轻扫每次 15°', 'Swipe up or down to move 15° at a time', '上下にスワイプで15°ずつ', '위아래로 쓸어 15°씩'],
  'fold.value': ['{mode} {a}°', '{mode}, {a}°', '{mode} {a}°', '{mode} {a}°'],
  'rotor.path': ['路', 'Paths', '道', '길'],
  'rotor.gap': ['缺口', 'Gaps', 'すき間', '틈'],
  'rotor.object': ['物件', 'Objects', 'もの', '물건'],
  'rotor.shadow': ['影子', 'Shadows', '影', '그림자'],
  'prog.step': ['第 {n} 步', 'step {n}', '{n}歩目', '{n}번째 걸음'],
  'prog.dist': ['离终点 {d} 格', '{d} squares from the goal', 'ゴールまで{d}マス', '도착점까지 {d}칸'],
  'prog.far': ['终点还走不到', 'the goal is out of reach for now', 'ゴールにはまだ届かない', '아직 도착점에 갈 수 없어요'],
  'page.fixed': ['下页（左岸）', 'bottom page (left bank)', '下のページ（左岸）', '아래 페이지(왼쪽 강가)'],
  'page.folding': ['上页（右岸）', 'top page (right bank)', '上のページ（右岸）', '위 페이지(오른쪽 강가)'],
  'paper.ch1': ['新纸，墨还湿着。', 'New paper; the ink is still wet.', '新しい紙、墨はまだ乾いていない。', '새 종이, 먹이 아직 마르지 않았어요.'],
  'walk.tab': ['走', 'Walk', '歩く', '걷기'],
  'walk.title': ['走 · 一步', 'Walk · one step', '歩く・1歩', '걷기 · 한 걸음'],
  'walk.one': ['一格', 'one square', '1マス', '한 칸'],
  'caption.label': ['播报', 'Announcement', '読み上げ', '안내'],
  'grid.more': ['下页还有 {n} 行 · 两指滑动', '{n} more rows below · scroll with two fingers', '下にあと{n}行・2本指でスクロール', '아래에 {n}줄 더 · 두 손가락으로 스크롤'],
  'level.code': ['{ch}-{n}', '{ch}-{n}', '{ch}-{n}', '{ch}-{n}'],
  'level.title': ['{code} · {name}', '{code} · {name}', '{code} · {name}', '{code} · {name}'],
  'undoGesture': ['两指左滑撤销', 'Swipe left with two fingers to undo', '2本指で左にスワイプして取り消し', '두 손가락으로 왼쪽으로 쓸어 실행 취소'],
  'closeAllLabel': ['合上书', 'Close the book', '本を閉じる', '책 덮기'],
  'openAllLabel': ['打开书', 'Open the book', '本を開く', '책 펴기'],
};
const A11Y = /^(kind|noun|pos|col|here|fallsHere|doorKey|crushedHere|inkPrints|tabBridge|stoneShadow|keyOpens|inkTo|covers|book\.|connected|lost|doorOpened|inkPrinted|shadow|intro|elsewhere|stack|already|arrived|cantReach|no\.|slid|undone|win$|dir\.|goal|where|leftPage|rightPage|nowhere|nothingToUndo|lv|walkHere|sep|list|semi|angle$|step|foldLessLabel|foldMoreLabel)/;

function catalog(entries) {
  const strings = {};
  for (const [key, { comment, values }] of Object.entries(entries).sort(([a], [b]) => (a < b ? -1 : 1))) {
    const localizations = {};
    for (const [lang, value] of Object.entries(values)) {
      if (value != null) localizations[LANG[lang]] = { stringUnit: { state: 'translated', value } };
    }
    strings[key] = { comment, extractionState: 'manual', localizations };
  }
  return JSON.stringify({ sourceLanguage: 'en', strings, version: '1.0' }, null, 2) + '\n';
}

const ui = {};
for (const key of Object.keys(src.strings.en)) {
  const values = {};
  for (const l of Object.keys(LANG)) values[l] = src.strings[l][key] ?? src.strings.en[key];
  const params = [...new Set((values.en.match(/\{\w+/g) || []).map((p) => p.slice(1)))];
  const where = A11Y.test(key) ? 'VoiceOver / announcement' : 'UI';
  ui[key] = { comment: `${where}. From fold-proto i18n.js.` + (params.length ? ` Placeholders: ${params.map((p) => '{' + p + '}').join(' ')}` : ''), values };
}
for (const [key, [zh, en, ja, ko]] of Object.entries(NATIVE)) {
  ui[key] = { comment: (A11Y.test(key) ? 'VoiceOver' : 'UI') + '. Native app only.', values: { zh, en, ja, ko } };
}
fs.writeFileSync(path.join(outDir, 'Localizable.xcstrings'), catalog(ui));

const lv = {};
for (const id of Object.keys(src.levelTexts.en)) {
  ['name', 'line', 'hint'].forEach((part, i) => {
    const values = {};
    for (const l of Object.keys(LANG)) values[l] = (src.levelTexts[l][id] || src.levelTexts.en[id])[i];
    lv[`${id}.${part}`] = { comment: `Level "${id}": ${part === 'name' ? 'title' : part === 'line' ? 'one-line teaser' : 'hint'}. From fold-proto i18n.js.`, values };
  });
}
fs.writeFileSync(path.join(outDir, 'Levels.xcstrings'), catalog(lv));

const brand = { zh: '折信', en: 'Letterfold', ja: '折り文', ko: '접은 편지' };
fs.writeFileSync(path.join(outDir, 'InfoPlist.xcstrings'), catalog({
  CFBundleDisplayName: { comment: 'App name on the Home Screen', values: brand },
  CFBundleName: { comment: 'App name', values: brand },
}));
console.log(`Localizable: ${Object.keys(ui).length} keys, Levels: ${Object.keys(lv).length} keys`);
