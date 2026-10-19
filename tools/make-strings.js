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
  'cover.begin': ['开始', 'Begin', 'はじめる', '시작'],
  'cover.beginLabel': ['开始：轻点或往下拉纸签', 'Begin: tap the tag or pull it down', 'はじめる：札をタップするか下に引く', '시작: 꼬리표를 누르거나 아래로 당기세요'],
  'cover.settings': ['设置', 'Settings', '設定', '설정'],
  'nav.book': ['书', 'Book', '本', '책'],
  'nav.bookLabel': ['回到章节', 'Back to the chapters', '章の一覧へ', '장 목록으로'],
  'map.title': ['两岸', 'Both Banks', '両岸', '양안'],
  'map.progress': ['已送达 {n} / {total}', '{n} of {total} delivered', '{n} / {total} 通 届いた', '{total}통 중 {n}통 도착'],
  'map.continue': ['继续 {n}', 'Continue {n}', 'つづき {n}', '이어서 {n}'],
  'ch.1': ['对页', 'Facing Page', '見開き', '맞은편'],
  'ch.2': ['立', 'Stand', '立つ', '일어서다'],
  'ch.3': ['影', 'Shade', '影', '그림자'],
  'ch.4': ['岸', 'Shore', '岸', '강가'],
  'ch.5': ['翻页', 'Turn the Page', 'ページをめくる', '책장 넘기기'],
  'ch.label': ['第{n}章，{name}', 'Chapter {n}, {name}', '第{n}章、{name}', '{n}장, {name}'],
  'ch.delivered': ['已送达', 'Delivered', '届いた', '도착함'],
  'ch.inProgress': ['进行中', 'In progress', '進行中', '진행 중'],
  'ch.sealed': ['未启封', 'Sealed', '未開封', '미개봉'],
  'ch.soon': ['即将推出', 'Coming soon', '近日公開', '곧 공개'],
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
  // 0.1 (3): one language at a time, the end of the preview, phone-portrait hints, the paper switch
  'preview.end': ['第一章完。下一封信，还在路上。', 'End of chapter one. The next letter is still on its way.', '第一章、おわり。次の手紙は、まだ旅の途中。', '1장 끝. 다음 편지는 아직 오는 중이에요.'],
  'letter.1.body': ['河很宽，纸很薄。\n我把想说的话折了四次，\n等你合上它的那天。', 'The river is wide; the paper, thin.\nI folded what I meant to say\nfour times,\nfor the day you close it.', '川は広く、紙は薄い。\n言いたいことを四度折って、\nきみが閉じる日を待つ。', '강은 넓고 종이는 얇다.\n하고 싶은 말을 네 번 접어,\n네가 덮는 날을 기다린다.'],
  'letter.1.sign': ['——左岸', '— the Left Bank', '——左岸より', '— 왼쪽 강가에서'],
  'walk.close': ['收起', 'Close', '閉じる', '닫기'],
  'hint.portrait.bridge': ['把上页合下来：上页的纸板会正好盖住缺口。', 'Close the book: the card on the top page lands exactly over the gap.', '本を閉じると、上のページの厚紙がすき間にぴたりと重なる。', '책을 덮으면 위 페이지의 종이판이 틈을 꼭 덮어요.'],
  'hint.portrait.facing': ['合上，走到上页的路上；石头挡住了，就展开继续走。', 'Close, and step onto the top page’s path; when a stone blocks you, open and walk on.', '閉じて上のページの道へ。石にふさがれたら、開いて先へ。', '닫고 위 페이지의 길로 건너가요. 돌이 막으면 펼쳐서 계속 걸어요.'],
  'hint.portrait.back': ['合上过去，展开走一段，再合上回到下页。', 'Close to cross, open to walk a while, then close again to come back to the bottom page.', '閉じて渡り、開いて少し歩き、また閉じて下のページへ戻る。', '닫아서 건너고, 펼쳐서 조금 걷고, 다시 닫아 아래 페이지로 돌아와요.'],
  'hint.portrait.key': ['钥匙和门隔着折痕上下对称。合上，它们就碰到了。', 'Key and door mirror each other across the fold. Close, and they meet.', '鍵と扉は折り目をはさんで向かい合う。閉じれば、ふれあう。', '열쇠와 문은 접는 선을 사이에 두고 마주 보고 있어요. 닫으면 서로 닿아요.'],
  'hint.portrait.ink': ['合上一次，墨会印到上页的缺口上；展开后它还在。', 'Close once: the ink prints onto the gap on the top page, and stays when you open.', '一度閉じると、墨が上のページのすき間に写る。開いても残る。', '한 번 닫으면 먹이 위 페이지 틈에 찍혀요. 펼쳐도 남아 있어요.'],
  // 0.1 (4): chapter 2 「立」, the hinge setting (design-review-2, plan.md §12)
  'paper.ch2': ['米纸，纸片会站起来。', 'Rice paper; the tabs can stand.', '米色の紙。紙片は立ち上がる。', '쌀종이, 종이 조각이 일어설 수 있어요.'],
  'ch.2.line': ['纸也会站起来。', 'Paper can stand up too.', '紙だって、立ち上がる。', '종이도 일어설 수 있다.'],
  'teach.half': ['书可以只打开一半', 'The book can open just halfway', '本は半分だけ開くこともできる', '책은 반만 펼칠 수도 있어요'],
  'set.hinge': ['铰链折页', 'Fold with the hinge', 'ヒンジで折る', '힌지로 접기'],
  'set.hinge.d': ['合上手机时，书也跟着合上', 'Closing the phone folds the book too', 'スマホを閉じると本も折れる', '휴대폰을 접으면 책도 접혀요'],
  'letter.2.title': ['右岸来信', 'A Letter from the Right Bank', '右岸からの手紙', '오른쪽 강가에서 온 편지'],
  'letter.2.body': ['河没有变窄，\n纸却先站了起来，\n替我走到岸边。', 'The river is no narrower,\nbut the paper stood up first\nand walked to the bank for me.', '川は狭くならない。\nけれど紙が先に立ちあがり、\nわたしの代わりに岸まで歩いた。', '강은 좁아지지 않았다.\n그런데 종이가 먼저 일어서서\n나 대신 강가까지 걸어갔다.'],
  'letter.2.sign': ['——右岸', '— the Right Bank', '——右岸より', '— 오른쪽 강가에서'],
  'hint.portrait.shadow': ['把书慢慢合到一半多一点，上页石头的影子会落在缺口上。影子能走。', 'Close the book slowly, a little past halfway: the shadow of the top page\'s stone falls on the gap. Shadows can be walked on.', '本をゆっくり半分より少し多く閉じると、上のページの石の影がすき間に落ちる。影は歩ける。', '책을 반보다 조금 더 천천히 닫으면 위 페이지 돌의 그림자가 틈에 떨어져요. 그림자 위는 걸을 수 있어요.'],
  'preview.end3': ['第三章完。下一封信，还在路上。', 'End of chapter three. The next letter is still on its way.', '第三章、おわり。次の手紙は、まだ旅の途中。', '3장 끝. 다음 편지는 아직 오는 중이에요.'],
  'preview.end2': ['第二章完。下一封信，还在路上。', 'End of chapter two. The next letter is still on its way.', '第二章、おわり。次の手紙は、まだ旅の途中。', '2장 끝. 다음 편지는 아직 오는 중이에요.'],
  'hint.portrait.stand': ['把上页立起到一半：折痕上的两片纸片会连成一座桥。', 'Stand the top page halfway: the two tabs on the crease join into a bridge.', '上のページを半分だけ立てると、折り目の紙片がつながって橋になる。', '위 페이지를 반쯤 세우면 접는 선의 종이 조각이 이어져 다리가 돼요.'],
  'hint.portrait.twoBridges': ['立起到一半，两座桥都在：走过一座，沿着立起的上页走，再从另一座回来。', 'Stand the page halfway: both bridges are up. Cross one, walk along the standing page, come back over the other.', '半分立てると橋が二つ。一つを渡り、立ったページを歩いて、もう一つで戻る。', '반쯤 세우면 다리가 둘이에요. 하나를 건너 선 페이지를 걷고, 다른 다리로 돌아와요.'],
  'hint.portrait.standClose': ['先立起来过桥，在上页走到头，再合上：终点就在脚下。', 'Stand the page and cross, walk to the end of the top page, then close: the goal is right under you.', '立てて橋を渡り、上のページを端まで歩いてから閉じる。ゴールは足もと。', '세워서 다리를 건너 위 페이지 끝까지 걷고 닫아요. 도착점이 발밑이에요.'],
  'hint.portrait.doorBridge': ['先合上，让钥匙开门；再立起到一半，从纸片桥上走过去。', 'Close so the key opens the door; then stand the page halfway and cross on the tabs.', '閉じて鍵で扉を開け、半分立てて紙片の橋を渡る。', '닫아서 열쇠로 문을 열고, 반쯤 세워 종이 다리를 건너요.'],
  'hint.portrait.inkBridge': ['只合上一次，让墨印到上页；再立起到一半过桥。', 'Close only once so the ink prints onto the top page; then stand it halfway and cross.', '一度だけ閉じて墨を上のページに写し、半分立てて渡る。', '한 번만 닫아 먹을 위 페이지에 찍고, 반쯤 세워 건너요.'],
  'hint.portrait.crease': ['先合上一次，钥匙和墨都印过去；再立起过桥、走到门边，最后合上。', 'Close once so the key and the ink carry across; stand the page, cross, walk to the door, then close.', 'まず一度閉じて鍵と墨を写す。立てて橋を渡り、扉まで歩いて、最後に閉じる。', '먼저 한 번 닫아 열쇠와 먹을 찍어요. 세워서 다리를 건너 문까지 걷고, 마지막에 닫아요.'],
  // 0.1 (9): chapter 4 「岸」, the end of book one (design-review-ch4)
  'map.nextPage': ['下一页', 'Next page', '次の頁', '다음 페이지'],
  'map.book2': ['卷二', 'Book Two', '第二巻', '제2권'],
  'closed.arrived': ['信，到了。', 'The letter is here.', '手紙が、届いた。', '편지가 닿았다.'],
  'letter.2.end': ['第二章完。\n下一封信，还在路上。', 'End of Chapter Two.\nThe next letter is still on its way.', '第二章 了。\n次の手紙は、まだ途中。', '제2장 끝.\n다음 편지는 아직 오는 길.'],
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
