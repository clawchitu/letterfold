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
  'pre.leanLabel': ['斜起到 45°', 'Lean the page to 45°', '45°まで傾ける', '45°로 기울이기'],
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
  'ch.5': ['胶', 'Glue', '糊', '풀'],
  // 0.1 (13): vol. 2 《翻页》 (design-review-v2c1 §3 地图)
  'vol.2': ['翻页', 'Turn the Page', 'ページをめくる', '책장 넘기기'],
  'map.vol1Back': ['卷一《两岸》', 'Book One: Both Banks', '第一巻『両岸』', '제1권 《양안》'],
  'map.vol1BackLabel': ['回到卷一《两岸》，已送达 {n} / {total}', 'Back to Book One, Both Banks: {n} of {total} delivered', '第一巻『両岸』へ戻る、{n} / {total} 通 届いた', '제1권 《양안》으로, {total}통 중 {n}통 도착'],
  'map.toBook2': ['下一页：卷二《翻页》', 'Next page: Book Two, Turn the Page', '次の頁：第二巻『ページをめくる』', '다음 페이지: 제2권 《책장 넘기기》'],
  'ch.unwritten': ['尚未写', 'Not yet written', 'まだ書かれていない', '아직 쓰이지 않음'],
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
  // 0.1 (14): the 暗信 side letters, the shut book's VoiceOver and the two rules the 10/20 playtest found nowhere on screen
  'dark.title': ['暗信', 'Hidden letters', '隠された手紙', '숨은 편지'],
  'dark.note': ['三封，可不读', 'three, optional', '三通、読まなくてもいい', '세 통, 안 읽어도 돼요'],
  'dark.label': ['暗信，三封可以不读的难信', 'Hidden letters: three hard letters you may leave unread', '隠された手紙、読まなくてもいい難しい三通', '숨은 편지, 안 읽어도 되는 어려운 편지 세 통'],
  'dark.lockedToast': ['暗信要等「胶」的信送到，才拆得开。', 'The hidden letters open once the Glue letter is delivered.', '隠された手紙は「糊」の手紙が届いてから開く。', '숨은 편지는 「풀」의 편지가 도착한 뒤에 열려요.'],
  'intro.dark': ['{name}。{line}你在{you}，终点在{goal}。书是打开的。', '{name}. {line} You are at {you}; the goal is at {goal}. The book is open.', '{name}。{line}あなたは{you}、ゴールは{goal}。本は開いています。', '{name}. {line} 지금 {you}에 있고, 도착점은 {goal}에 있어요. 책은 펼쳐져 있어요.'],
  'dark.back': ['回到章节', 'Back to the chapters', '章の一覧へ', '장 목록으로'],
  'hereOnPage': ['你在这里，{page}', 'you are here, on the {page}', 'あなたはここ、{page}', '여기 있어요, {page}'],
  'stack.blocked': ['这一叠里有石头，走不过去', 'a stone in this stack: no way through', 'この重なりに石、通れない', '이 겹에 돌이 있어 지나갈 수 없어요'],
  'stack.under': ['上页是空处，站上去在下页', 'a hole in the top page: you would stand on the bottom page', '上の頁は穴、立てば下の頁', '위 페이지는 빈 곳, 서면 아래 페이지'],
  'rule.blocked': ['一叠里只要有石头，纸也托不住你。', 'A stack with a stone in it won’t hold you, paper or not.', '重なりに石があれば、紙でも通れない。', '겹 안에 돌이 있으면 종이라도 지나갈 수 없어요.'],
  'rule.under': ['合着时，上页的空处底下，是下页的纸。', 'Shut, through a hole in the top page you stand on the page below.', '閉じているとき、上の頁の穴の下は下の頁の紙。', '닫혀 있을 때, 위 페이지의 빈 곳 아래는 아래 페이지의 종이예요.'],
  'reach.more': ['多了几格能走，信还走不到', 'more squares are within reach; the letter is not yet', '歩ける枡が増えた。手紙にはまだ届かない', '걸을 수 있는 칸이 늘었어요. 편지에는 아직 못 가요'],
  'level.code': ['{ch}-{n}', '{ch}-{n}', '{ch}-{n}', '{ch}-{n}'],
  'level.title': ['{code} · {name}', '{code} · {name}', '{code} · {name}', '{code} · {name}'],
  'undoGesture': ['两指左滑撤销', 'Swipe left with two fingers to undo', '2本指で左にスワイプして取り消し', '두 손가락으로 왼쪽으로 쓸어 실행 취소'],
  // 0.1 (3): one language at a time, the end of the preview, phone-portrait hints, the paper switch
  'preview.end': ['第一章完。下一封信，还在路上。', 'End of chapter one. The next letter is still on its way.', '第一章、おわり。次の手紙は、まだ旅の途中。', '1장 끝. 다음 편지는 아직 오는 중이에요.'],
  'letter.1.body': ['河很宽，纸很薄。\n我把想说的话折了四次，\n等你合上它的那天。', 'The river is wide; the paper, thin.\nI folded what I meant to say\nfour times,\nfor the day you close it.', '川は広く、紙は薄い。\n言いたいことを四度折って、\nきみが閉じる日を待つ。', '강은 넓고 종이는 얇다.\n하고 싶은 말을 네 번 접어,\n네가 덮는 날을 기다린다.'],
  'letter.1.sign': ['——左岸', '— the Left Bank', '——左岸より', '— 왼쪽 강가에서'],
  'walk.close': ['收起', 'Close', '閉じる', '닫기'],
  'hint.portrait.bridge': ['把上页合下来：上页的纸板会正好盖住缺口。', 'Close the book: the card on the top page lands exactly over the gap.', '本を閉じると、上のページの厚紙がすき間にぴたりと重なる。', '책을 덮으면 위 페이지의 종이판이 틈을 꼭 덮어요.'],
  'hint.portrait.facing': ['直着往下的那一叠被石头堵住了。在上页走到靠折痕那一行的第 2 列，在那里合上：这一叠下面是石头，你站在它背上。合着往右一格，纸把你换到下页；再往下、往右，换回上页。打开，信就在旁边。', 'The straight stack is walled by a stone. On the top page, walk to the row by the crease, second column, and close there: there is a stone under this stack; you stand on its back. Closed, one step right — the paper hands you to the bottom page; down and right again, and you are back on the top page. Open: the letter is beside you.', 'まっすぐ下る重なりは石でふさがれている。上の頁を折り目沿いの行の2列目まで歩いて閉じる。この重なりの下は石、きみはその背に立つ。閉じたまま右へ一枡で下の頁へ、さらに下・右で上の頁に戻る。開けば手紙はとなり。', '곧장 내려가는 겹은 돌에 막혀 있어요. 위 페이지에서 접는 선 옆 줄의 두 번째 칸까지 가서 닫아요. 이 겹 아래는 돌, 당신은 그 등 위에 서 있어요. 닫은 채 오른쪽으로 한 칸 가면 아래 페이지로, 다시 아래·오른쪽으로 가면 위 페이지로 돌아와요. 펼치면 편지가 옆에.'],
  'hint.portrait.back': ['先往上一格，往右两格，回到折痕边，再沿折痕往右走到最右一格，合上。合着往下走到底，再往左一格，打开：你在上页最上面一行。再往左一格，合上——这一叠一直通到左下角的信。', 'One step up, two right, back down to the crease, then along it right to the last square, and close. Closed, walk down to the end, one step left, and open: you are on the top row of the top page. One more step left, close again — this stack runs all the way to the letter in the bottom-left corner.', '上へ一枡、右へ二枡、折り目へ戻り、折り目沿いに右端まで歩いて閉じる。閉じたまま下の端まで、左へ一枡、開く。きみは上の頁のいちばん上の行にいる。もう一枡左へ、また閉じる。この重なりは左下の手紙まで通じている。', '위로 한 칸, 오른쪽으로 두 칸, 다시 접는 선으로 내려와 선을 따라 오른쪽 끝까지 가서 닫아요. 닫은 채 아래 끝까지, 왼쪽으로 한 칸 가서 펼쳐요. 위 페이지 맨 윗줄이에요. 왼쪽으로 한 칸 더 가서 다시 닫아요. 이 겹은 왼쪽 아래의 편지까지 이어져요.'],
  'hint.portrait.key': ['只有下页那扇门有钥匙。先在上页往右走到底、再往上，到最上面一行的第 4 列，合上：门开了，这一叠下面是石头。合着往左两格，往上一格进到开着的门里，打开，再往上一格，合上：往左一格、再往上一格就是信。上页那扇门没有钥匙，它只是墙。', 'Only the door on the bottom page has a key. On the top page walk right to the end, then up, to column 4 of the top row, and close: the door opens, and this stack sits on a stone. Closed, two steps left and one up into the open door; open, one more step up, and close again: one step left and one up is the letter. The door on the top page has no key; it is only a wall.', '鍵があるのは下の頁の扉だけ。上の頁を右端まで、それから上へ、いちばん上の行の4列目で閉じる。扉が開き、この重なりの下は石。閉じたまま左へ二枡、上へ一枡で開いた扉の中へ。開いて、さらに上へ一枡、また閉じる。左へ一枡、上へ一枡で手紙。上の頁の扉に鍵はない、ただの壁。', '열쇠가 있는 문은 아래 페이지의 문뿐이에요. 위 페이지에서 오른쪽 끝까지, 그다음 위로 가서 맨 윗줄 4열에서 닫아요. 문이 열리고, 이 겹 아래는 돌이에요. 닫은 채 왼쪽으로 두 칸, 위로 한 칸 가서 열린 문 안으로. 펼치고 위로 한 칸 더, 다시 닫아요. 왼쪽으로 한 칸, 위로 한 칸이면 편지예요. 위 페이지의 문에는 열쇠가 없어요. 그냥 벽이에요.'],
  'hint.portrait.ink': ['一开始就合上：墨印到了上页。合着往左走到底，再往上走到折痕边，往右一格，打开；再往右一格（第 3 列），合上：这一叠经过印过去的墨往右，通到最右一列。往下一格，打开，往上一格就是信。', 'Close at once: the ink prints onto the top page. Closed, walk left to the end, then up to the crease, one step right, and open; one more step right (column 3), and close again: this stack runs right through the printed ink to the last column. One step down, open, and one step up is the letter.', 'すぐに閉じる。墨が上の頁に写る。閉じたまま左端まで、上へ折り目まで、右へ一枡、開く。もう一枡右（3列目）で、また閉じる。この重なりは写った墨を通って右端の列へ。下へ一枡、開けば、上へ一枡で手紙。', '바로 닫아요. 먹이 위 페이지에 찍혀요. 닫은 채 왼쪽 끝까지, 위로 접는 선까지, 오른쪽으로 한 칸 가서 펼쳐요. 오른쪽으로 한 칸 더(3열) 가서 다시 닫아요. 이 겹은 찍힌 먹을 지나 맨 오른쪽 열까지 이어져요. 아래로 한 칸, 펼치면 위로 한 칸이 편지예요.'],
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
  'hint.portrait.standClose': ['往左再往上走到桥头，立起来过桥，沿立起的上页往上走到顶，再往右两格，合上。合着往上一格、往右一格、再往上一格，打开：你在上页，信就在左边一格。', 'Go left and up to the bridge, stand the page and cross, walk the standing top page up to its top, then two steps right, and close. Closed: one step up, one right, one up again, then open: you are on the top page with the letter one square to the left.', '左へ、上へ歩いて橋のたもとへ。頁を立てて渡り、立った上の頁をいちばん上まで、右へ二枡、閉じる。閉じたまま上へ一枡、右へ一枡、また上へ一枡、開く。きみは上の頁、手紙は左へ一枡。', '왼쪽으로, 위로 걸어 다리 앞까지. 페이지를 세워 건너고, 선 위 페이지를 맨 위까지, 오른쪽으로 두 칸 가서 닫아요. 닫은 채 위로 한 칸, 오른쪽으로 한 칸, 다시 위로 한 칸 가서 펼쳐요. 위 페이지이고, 편지는 왼쪽으로 한 칸이에요.'],
  'hint.portrait.doorBridge': ['往左再往上，走到纸片那格，合上：门开了。立起来过桥、穿门，沿上页往上走到顶，再往右走到底，合上——这一叠下面是石头，你站在它背上。合着往上一格，纸把你换到下页，再往上一格就是信。', 'Go left and up to the tab and close: the door opens. Stand the page, cross, go through the door and up the top page to its top, then right to the end, and close again — this stack sits on a stone; you stand on its back. Closed, one step up hands you to the bottom page; one more step up is the letter.', '左へ、上へ、紙片の枡まで歩いて閉じる。扉が開く。頁を立てて橋を渡り、扉を抜け、上の頁をいちばん上まで、右端まで歩いて、また閉じる。この重なりの下は石、きみはその背に。閉じたまま上へ一枡で下の頁へ、もう一枡上で手紙。', '왼쪽으로, 위로 종이 조각 칸까지 가서 닫아요. 문이 열려요. 페이지를 세워 다리를 건너고 문을 지나 위 페이지 맨 위까지, 오른쪽 끝까지 가서 다시 닫아요. 이 겹 아래는 돌, 당신은 그 등 위에. 닫은 채 위로 한 칸 가면 아래 페이지로, 한 칸 더 위가 편지예요.'],
  'hint.portrait.inkBridge': ['踩过墨往下、再往左绕到桥头，合上：墨印到了上页。立起来过桥，沿上页往上走两格，往右走过印过去的墨，往下一格、往右一格，再合上——这一叠下面是石头。合着往上一格就是信。', 'Step over the ink, down and left round to the bridge, and close: the ink prints onto the top page. Stand the page, cross, two steps up the top page, then right over the printed ink, one down, one right, and close again — this stack sits on a stone. Closed, one step up is the letter.', '墨を踏んで下へ、左へ回って橋のたもとへ、閉じる。墨が上の頁に写る。頁を立てて渡り、上の頁を上へ二枡、写った墨を通って右へ、下へ一枡、右へ一枡、また閉じる。この重なりの下は石。閉じたまま上へ一枡で手紙。', '먹을 밟고 아래로, 왼쪽으로 돌아 다리 앞까지 가서 닫아요. 먹이 위 페이지에 찍혀요. 페이지를 세워 건너고, 위 페이지를 위로 두 칸, 찍힌 먹을 지나 오른쪽으로, 아래로 한 칸, 오른쪽으로 한 칸 가서 다시 닫아요. 이 겹 아래는 돌이에요. 닫은 채 위로 한 칸이 편지예요.'],
  'hint.portrait.rightBank': ['在最右一列的桥上立起来，过到上页，往左走到另一座桥（最左一列），回到下页，往下走到左下角，合上。合着往右一格，你在上页。立起来，再往右一格，合上——这一叠下面是石头，你站在它背上。合着往右一格就是信。', 'Stand the page at the bridge in the right-most column and cross to the top page; walk left to the other bridge (left-most column), back onto the bottom page, and down to its bottom-left corner; close. Closed, one step right: you are on the top page. Stand the page, one more step right, and close — this stack sits on a stone; you stand on its back. Closed, one step right is the letter.', '一番右の列の橋で頁を立てて上の頁へ。左へ、もう一つの橋（一番左の列）まで歩いて下の頁に戻り、左下の角まで下りて閉じる。閉じたまま右へ一枡、きみは上の頁。立てて、さらに右へ一枡、閉じる。この重なりの下は石、きみはその背に。閉じたまま右へ一枡で手紙。', '맨 오른쪽 열의 다리에서 페이지를 세워 위 페이지로 건너요. 왼쪽으로 다른 다리(맨 왼쪽 열)까지 가서 아래 페이지로 돌아와 왼쪽 아래 모서리까지 내려가 닫아요. 닫은 채 오른쪽으로 한 칸, 위 페이지예요. 세우고 오른쪽으로 한 칸 더 가서 닫아요. 이 겹 아래는 돌, 당신은 그 등 위에. 닫은 채 오른쪽으로 한 칸이 편지예요.'],
  'hint.portrait.crease': ['走到折痕边，沿折痕往右走到桥头，立起来过桥，往上一格，合上：钥匙开门、墨印过去，这一叠下面是石头。合着往下、往左、再往下，然后往上一格、往左两格，到门那一格，打开，往上一格到上页顶上，再合上——这一叠下面又是一块石头，往左一步就是信。', 'Walk to the crease and along it right to the bridge; stand and cross, one step up, and close: the key opens the door, the ink prints across, and this stack sits on a stone. Closed: down, left, down again, then one up and two left to the door square; open, one step up to the top of the top page, and close again — this stack sits on another stone, and one step left is the letter.', '折り目まで歩き、折り目沿いに右へ橋のたもとまで。立てて渡り、上へ一枡、閉じる。鍵が扉を開け、墨が写り、この重なりの下は石。閉じたまま下・左・また下、それから上へ一枡、左へ二枡で扉の枡。開いて、上へ一枡で上の頁のいちばん上、また閉じる。この重なりの下もまた石、左へ一歩で手紙。', '접는 선까지 가서 선을 따라 오른쪽으로 다리 앞까지. 세워서 건너고 위로 한 칸 가서 닫아요. 열쇠가 문을 열고 먹이 찍히고, 이 겹 아래는 돌이에요. 닫은 채 아래, 왼쪽, 다시 아래, 그다음 위로 한 칸, 왼쪽으로 두 칸 가면 문 칸. 펼치고 위로 한 칸 가서 위 페이지 맨 위에서 다시 닫아요. 이 겹 아래도 돌, 왼쪽으로 한 걸음이 편지예요.'],
  // 0.1 (9): chapter 4 「岸」, the end of book one (design-review-ch4)
  'map.nextPage': ['下一页', 'Next page', '次の頁', '다음 페이지'],
  'map.book2': ['卷二', 'Book Two', '第二巻', '제2권'],
  'closed.arrived': ['信，到了。', 'The letter is here.', '手紙が、届いた。', '편지가 닿았다.'],
  'letter.2.end': ['第二章完。\n下一封信，还在路上。', 'End of Chapter Two.\nThe next letter is still on its way.', '第二章 了。\n次の手紙は、まだ途中。', '제2장 끝.\n다음 편지는 아직 오는 길.'],
  'closeAllLabel': ['合上书', 'Close the book', '本を閉じる', '책 덮기'],
  'openAllLabel': ['打开书', 'Open the book', '本を開く', '책 펴기'],
  // 0.1 (15): chapter skins (design-skins §4, design-review-skins §3.3): 「皮名（规则名）」, the rule's name in brackets; a
  // chapter without a key reads the plain kind.* (ch. 1 throughout, ch. 3's stone). noun.* (the rule sentences) unchanged.
  // ja / ko: TODO native review (as ch. 2).
  'kind.D.ch2': ['篱门（锁着的门）', 'bamboo gate (locked door)', '竹垣の門（鍵のかかった扉）', '대나무 문(잠긴 문)'],
  'kind.o.ch2': ['篱门（开着的门）', 'bamboo gate (open door)', '竹垣の門（開いた扉）', '대나무 문(열린 문)'],
  'kind.k.ch2': ['竹钥（钥匙）', 'bamboo key (key)', '竹の鍵（鍵）', '대나무 열쇠(열쇠)'],
  'kind.G.ch3': ['灯笼（终点）', 'lantern (goal)', '提灯（ゴール）', '등롱(도착점)'],
  'kind.x.ch4': ['缆桩（石头）', 'bollard (stone)', '係船柱（石）', '계선주(돌)'],
  'kind.D.ch4': ['月洞门（锁着的门）', 'moon gate (locked door)', '月洞門（鍵のかかった扉）', '월동문(잠긴 문)'],
  'kind.o.ch4': ['月洞门（开着的门）', 'moon gate (open door)', '月洞門（開いた扉）', '월동문(열린 문)'],
  'kind.k.ch4': ['铁钥（钥匙）', 'iron key (key)', '鉄の鍵（鍵）', '쇠 열쇠(열쇠)'],
  'kind.p.ch4': ['渡板（纸片）', 'plank (tab)', '渡し板（紙片）', '건널판(종이 조각)'],
  'kind.x.ch5': ['镇石（石头）', 'paperweight (stone)', '文鎮石（石）', '문진돌(돌)'],
  'kind.D.ch5': ['闸（锁着的门）', 'sluice (locked door)', '水門（鍵のかかった扉）', '수문(잠긴 문)'],
  'kind.o.ch5': ['闸（开着的门）', 'sluice (open door)', '水門（開いた扉）', '수문(열린 문)'],
  'kind.k.ch5': ['符（钥匙）', 'token (key)', '割符（鍵）', '부절(열쇠)'],
  'kind.i.ch5': ['墨池（湿墨）', 'ink pool (wet ink)', '墨池（濡れた墨）', '먹물 웅덩이(젖은 먹)'],
  'kind.p.ch5': ['笺条（纸片）', 'ruled slip (tab)', '便箋の切れ端（紙片）', '편지지 조각(종이 조각)'],
  'kind.G.ch5': ['信封（终点）', 'envelope (goal)', '封筒（ゴール）', '봉투(도착점)'],
  // 0.1 (16): chapter 6 「翻」 (fold-proto design-ch6.md): the turn's VoiceOver action / hint, the carry message at the
  // final position (playtest-ch6 §2 #6), skinned kinds (ch. 6 reuses ch. 5's 信笺 objects). ja / ko: TODO-native-check.
  'ch.6': ['翻', 'Turn', 'めくる', '넘김'],
  carried: ['影子把你从第{from}列带到第{to}列（你现在在这里）', 'The shadow carried you from column {from} to column {to} (you are there now)', '影がきみを{from}列目から{to}列目へ運んだ（いまはそこにいる）', '그림자가 당신을 {from}열에서 {to}열로 옮겼어요(지금 거기 있어요)'],
  // the next chapter, not yet written (map card)
  'ch.7': ['墨晕', 'Bleed', '滲み', '번짐'],
  'ch.8': ['待续', 'To Be Continued', 'つづく', '다음 이야기'],
  // 0.1 (19) ch. 7 「墨晕」: fold-proto names only `i` (「湿墨」); the native board also reads `I` aloud, so the two inks
  // need different names when they share a page (7-3). Not in fold-proto yet (reported upstream). ja/ko: TODO-native-check.
  'kind.I': ['未干的墨，每合一次洇一圈', 'undried ink, bleeds a ring each close', '乾いていない墨、閉じるたびにひとまわり滲む', '마르지 않은 먹, 닫을 때마다 한 겹 번짐'],
  'noun.I': ['未干的墨', 'undried ink', '乾いていない墨', '마르지 않은 먹'],
  'kind.i.ch7': ['墨，已干，只印不洇', 'ink, dry: it prints but never bleeds', '墨、乾いている：写るが滲まない', '먹, 말라 있음: 찍히지만 번지지 않음'],
  'flip.action': ['翻过来', 'Turn over', '裏返す', '뒤집기'],
  'flip.hint': ['合上时把书翻个面', 'Turns the closed book over', '閉じた本を裏返す', '닫힌 책을 뒤집어요'],
  'kind.x.ch6': ['镇石（石头）', 'paperweight (stone)', '文鎮石（石）', '문진돌(돌)'],
  'kind.D.ch6': ['闸（锁着的门）', 'sluice (locked door)', '水門（鍵のかかった扉）', '수문(잠긴 문)'],
  'kind.o.ch6': ['闸（开着的门）', 'sluice (open door)', '水門（開いた扉）', '수문(열린 문)'],
  'kind.k.ch6': ['符（钥匙）', 'token (key)', '割符（鍵）', '부절(열쇠)'],
  'kind.i.ch6': ['墨池（湿墨）', 'ink pool (wet ink)', '墨池（濡れた墨）', '먹물 웅덩이(젖은 먹)'],
  'kind.p.ch6': ['笺条（纸片）', 'ruled slip (tab)', '便箋の切れ端（紙片）', '편지지 조각(종이 조각)'],
  'kind.G.ch6': ['信封（终点）', 'envelope (goal)', '封筒（ゴール）', '봉투(도착점)'],
  // 0.1 (17): 「重新开始」 in the level (Haoqiang 10/25): footer / top-bar button, its VoiceOver label, the announcement.
  // Undoable, so no confirmation. ja / ko: TODO-native-check.
  restart: ['重新开始', 'Restart', 'やり直す', '다시 시작'],
  restartLabel: ['重新开始本关', 'Restart the level', 'この関を最初からやり直す', '이 단계를 처음부터 다시 시작'],
  restartHint: ['回到这一关的开头，撤销可以回来', 'Back to how the level began; undo brings you back', '関の最初に戻る。戻すで元に戻せる', '단계 처음으로 돌아가요. 되돌리기로 돌아올 수 있어요'],
  restarted: ['已重新开始。你在{pos}，撤销可以回到刚才', 'Restarted. You are at {pos}; undo to go back', 'やり直しました。あなたは{pos}。戻すでさっきに戻れます', '다시 시작했어요. 지금 {pos}, 되돌리기로 방금 전으로 돌아갈 수 있어요'],
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

// 0.1 (16): ch. 6 strings fold-proto has only in zh / en (or in an older form) for ja / ko. Marked TODO-native-check in
// the catalog comments until a native speaker has read them.
const CH6_NATIVE = ['ch.6', 'ch.7', 'ch.8', 'kind.I', 'noun.I', 'kind.i.ch7', 'carried', 'flip.action', 'flip.hint', 'restart', 'restartLabel', 'restartHint', 'restarted'];
const STRING_FIX = {
  ja: {
    'chHead.6': '六 · めくる',
    'no.flip.leaf': 'めくる頁の上に立っている——閉じたまま左頁へ歩いてから、めくる',
    layerRule: '閉じたまま歩くとき：両方の頁が紙のところでは、いまの頁にとどまる。片方だけが紙のところで、その頁へ移る',
    shadowOnPaper: '紙の上の影は、ただの紙。きみを運べるのは、すき間の上の影だけ',
    'why.stoneTop': '上の頁の石がこの重なりをふさいでいる',
    'why.stoneUnder': 'この重なりの下に左頁の石がある',
  },
  ko: {
    'no.flip.leaf': '넘길 페이지 위에 서 있어요. 닫은 채 왼쪽 페이지로 걸어간 뒤 넘기세요',
    layerRule: '닫은 채 걸을 때: 두 페이지가 모두 종이인 곳에서는 지금 페이지에 머물러요. 한쪽만 종이인 곳에서만 그 페이지로 옮겨 가요',
    shadowOnPaper: '종이 위 그림자는 그냥 종이예요. 당신을 실어 나르는 건 틈 위의 그림자뿐이에요',
    'why.stoneTop': '위 페이지의 돌이 이 겹을 막고 있어요',
    'why.stoneUnder': '이 겹 아래에 왼쪽 페이지의 돌이 있어요',
  },
};
const HELP_ADD = {
  ja: ['O：開く。', 'O：開く。T：めくる（閉じているとき）。閉じたまま歩くとき、両方の頁が紙なら同じ頁にとどまり、片方だけが紙なら頁を移る。紙の上の影は、ただの紙。'],
  ko: ['O: 열기.', 'O: 열기. T: 넘기기(닫혀 있을 때). 닫은 채 걸을 때 두 페이지가 모두 종이면 그 페이지에 머물고, 한쪽만 종이일 때만 페이지를 옮겨요. 종이 위 그림자는 그냥 종이예요.'],
};
// 0.1 (19): ch. 7 「墨晕」 strings — fold-proto has zh / en final and ja / ko drafts (design-ch7.md §5–6, TODO review there).
const CH7_DRAFTS = ['ch.7.line', 'chHead.7', 'paper.ch7', 'inkBled', 'letter.7.title', 'letter.7.body', 'letter.7.sign', 'letter.7.end',
  'slip.wet.title', 'slip.wet.body', 'slip.wet.pic'];
const CHECKED = new Set(['help', ...Object.keys(STRING_FIX.ja), ...Object.keys(STRING_FIX.ko), ...CH7_DRAFTS]);
for (const [l, table] of Object.entries(STRING_FIX)) Object.assign(src.strings[l], table);
for (const [l, [from, to]] of Object.entries(HELP_ADD)) {
  if (!src.strings[l].help.includes(to)) src.strings[l].help = src.strings[l].help.replace(from, to);
}

const ui = {};
for (const key of Object.keys(src.strings.en)) {
  const values = {};
  for (const l of Object.keys(LANG)) values[l] = src.strings[l][key] ?? src.strings.en[key];
  const params = [...new Set((values.en.match(/\{\w+/g) || []).map((p) => p.slice(1)))];
  const where = A11Y.test(key) ? 'VoiceOver / announcement' : 'UI';
  ui[key] = { comment: `${where}. From fold-proto i18n.js.` + (params.length ? ` Placeholders: ${params.map((p) => '{' + p + '}').join(' ')}` : '') + (CHECKED.has(key) ? ' ja/ko: TODO-native-check.' : ''), values };
}
for (const [key, [zh, en, ja, ko]] of Object.entries(NATIVE)) {
  ui[key] = { comment: (A11Y.test(key) || /^restart(Label|Hint|ed)$/.test(key) ? 'VoiceOver' : 'UI') + '. Native app only.' + (CH6_NATIVE.includes(key) || key.endsWith('.ch6') ? ' ja/ko: TODO-native-check.' : ''), values: { zh, en, ja, ko } };
}
// 0.1 (18): the nine 物件笺 (fold-proto design-onboarding §2.4–2.5; zh / en final there, ja / ko drafts). `.body` is the
// portrait copy (top / bottom page), `.body.h` the vertical crease's where they differ. ja/ko: TODO-native-check.
const SLIPS = {
  'slip.stone.title': ["石头", "Stone", "石", "돌"],
  'slip.stone.body': ["石头挡路，开着合着都绕不过它。合上书，从别的一叠走。", "A stone blocks the road, open or closed. Close the book and take another stack round it.", "石は道をふさぐ。開いていても閉じていても越えられない。本を閉じて、別の重なりから回り込む。", "돌은 길을 막아요. 펼쳐도 닫아도 넘을 수 없어요. 책을 닫고 다른 겹으로 돌아가세요."],
  'slip.door.title': ["门与钥匙", "Door and Key", "扉と鍵", "문과 열쇠"],
  'slip.door.body': ["门锁着，钥匙在对面那页。合上书，钥匙对上门，门就开了。", "The door is locked; the key is on the facing page. Close the book: the key meets the door, and it opens.", "扉は鍵がかかっていて、鍵は向かいのページにある。本を閉じると鍵が扉に重なり、扉が開く。", "문은 잠겨 있고, 열쇠는 맞은편 페이지에 있어요. 책을 닫으면 열쇠가 문에 닿아 문이 열려요."],
  'slip.ink.title': ["墨", "Ink", "墨", "먹"],
  'slip.ink.body': ["墨。合上书，它印到对面那一格——那里就多出一格纸。", "Ink. Close the book and it prints onto the facing square — one more square of paper there.", "墨。本を閉じると向かいの枡に写り、そこが一枡ぶんの紙になる。", "먹이에요. 책을 닫으면 맞은편 칸에 찍혀서, 그곳이 종이 한 칸이 돼요."],
  'slip.tab.title': ["纸片", "Tab", "紙片", "종이 조각"],
  'slip.tab.body': ["纸片在中缝两边成对。把书立到一半，它们站起来，搭成桥。", "Tabs sit in pairs across the crease. Stand the book half open and they rise into a bridge.", "紙片は折り目の両側に対になっている。本を半分立てると起き上がり、橋になる。", "종이 조각은 접는 선 양쪽에 짝으로 있어요. 책을 반쯤 세우면 일어나 다리가 돼요."],
  'slip.shadow.title': ["影子", "Shadow", "影", "그림자"],
  'slip.shadow.body': ["把上页斜起，灯在它背后：上页的石头把影子投到下页。影子，也是路。", "Lean the top page towards the lamp: its stone throws a shadow onto the page below. A shadow is a road too.", "上のページを傾けると、灯が後ろにある。上のページの石が下のページに影を落とす。影も、道。", "위 페이지를 기울이면 등불이 그 뒤에 있어요. 위 페이지의 돌이 아래 페이지에 그림자를 드리워요. 그림자도 길이에요."],
  'slip.shadow.body.h': ["把右页斜起，灯在它背后：右页的石头把影子投到左页。影子，也是路。", "Lean the right page towards the lamp: its stone throws a shadow onto the left page. A shadow is a road too.", "右のページを傾けると、灯が後ろにある。右のページの石が左のページに影を落とす。影も、道。", "오른쪽 페이지를 기울이면 등불이 그 뒤에 있어요. 오른쪽 페이지의 돌이 왼쪽 페이지에 그림자를 드리워요. 그림자도 길이에요."],
  'slip.press.title': ["压", "Press", "押す", "누름"],
  'slip.press.body': ["合上时，上页的石头会落下来。别站在它正对面的那一格。", "When the book closes, a stone on the top page comes down. Don't stand on the square facing it.", "閉じるとき、上のページの石が落ちてくる。その真向かいの枡に立たないこと。", "책을 닫으면 위 페이지의 돌이 떨어져요. 그 바로 맞은편 칸에는 서지 마세요."],
  'slip.press.body.h': ["合上时，右页的石头会落下来。别站在它正对面的那一格。", "When the book closes, a stone on the right page comes down. Don't stand on the square facing it.", "閉じるとき、右のページの石が落ちてくる。その真向かいの枡に立たないこと。", "책을 닫으면 오른쪽 페이지의 돌이 떨어져요. 그 바로 맞은편 칸에는 서지 마세요."],
  'slip.ride.title': ["乘影", "Ride the Shadow", "影に乗る", "그림자 타기"],
  'slip.ride.body': ["站在影子上，慢慢改变页角：影子会带着你走。", "Stand on a shadow and change the angle slowly: the shadow carries you with it.", "影の上に立ってページの角度をゆっくり変えると、影があなたを運ぶ。", "그림자 위에 서서 페이지 각도를 천천히 바꾸면, 그림자가 당신을 데려가요."],
  'slip.glue.title': ["胶", "Glue", "糊", "풀"],
  'slip.glue.body': ["胶。合上书，它把对面那格的石头粘过来——石头换了页，路也换了。", "Glue. Close the book and it pulls the stone facing it across — the stone changes page, and so does the road.", "糊。本を閉じると、向かいの枡の石をこちらに貼りつける。石がページを変え、道も変わる。", "풀이에요. 책을 닫으면 맞은편 칸의 돌을 이쪽으로 붙여 와요. 돌이 페이지를 옮기면 길도 바뀌어요."],
  'slip.turn.title': ["第三页", "The Third Page", "三枚目の頁", "세 번째 페이지"],
  'slip.turn.body': ["这封信有第三页。合上书，翻个面再打开：下页没变，对面换成了第三页。", "This letter has a third page. Close the book, turn it over and open it: the bottom page is the same, but it now faces the third page.", "この手紙には三枚目の頁がある。本を閉じ、裏返して開くと、下の頁はそのまま、向かいが三枚目の頁になる。", "이 편지에는 세 번째 페이지가 있어요. 책을 닫고 뒤집어 펼치면, 아래 페이지는 그대로이고 맞은편이 세 번째 페이지로 바뀌어요."],
  'slip.turn.body.h': ["这封信有第三页。合上书，翻个面再打开：左页没变，对面换成了第三页。", "This letter has a third page. Close the book, turn it over and open it: the left page is the same, but it now faces the third page.", "この手紙には三枚目の頁がある。本を閉じ、裏返して開くと、左頁はそのまま、向かいが三枚目の頁になる。", "이 편지에는 세 번째 페이지가 있어요. 책을 닫고 뒤집어 펼치면, 왼쪽 페이지는 그대로이고 맞은편이 세 번째 페이지로 바뀌어요."],
  'slip.pic.stone': ["图：纸人绕开石头那一叠，合着走到终点。", "Picture: closed, she walks round the stone's stack to the letter.", "図：閉じたまま、石の重なりを避けて終点まで歩く。", "그림: 닫은 채, 돌이 있는 겹을 피해 도착점까지 걸어가요."],
  'slip.pic.door': ["图：书合上，钥匙碰到门，门开了；纸人穿过门口走到终点。", "Picture: the book closes, the key meets the door and it opens; she walks through to the letter.", "図：本を閉じると鍵が扉に重なって開き、扉を抜けて終点へ。", "그림: 책을 닫으면 열쇠가 문에 닿아 열리고, 문을 지나 도착점으로 가요."],
  'slip.pic.ink': ["图：书合上，墨印到对面的缺口上；打开后纸人踩着印出来的墨走到终点。", "Picture: the book closes and the ink prints onto the gap facing it; opened, she walks over the printed ink to the letter.", "図：本を閉じると墨が向かいのすき間に写り、開いてからその墨を踏んで終点へ。", "그림: 책을 닫으면 먹이 맞은편 틈에 찍히고, 펼친 뒤 찍힌 먹을 밟고 도착점으로 가요."],
  'slip.pic.tab': ["图：书立到一半，两片纸片搭成桥，纸人从桥上走过中缝。", "Picture: the book stands half open, the two tabs make a bridge, and she walks across the crease.", "図：本を半分立てると二枚の紙片が橋になり、折り目を渡る。", "그림: 책을 반쯤 세우면 두 종이 조각이 다리가 되어, 접는 선을 건너가요."],
  'slip.pic.shadow': ["图：上页斜起，石头的影子填住下页的缺口，纸人踩着影子走到终点。", "Picture: the top page leans, the stone's shadow fills the gap on the page below, and she walks over it to the letter.", "図：上のページを傾けると石の影が下のページのすき間を埋め、影を踏んで終点へ。", "그림: 위 페이지를 기울이면 돌의 그림자가 아래 페이지의 틈을 메우고, 그림자를 밟고 도착점으로 가요."],
  'slip.pic.press': ["图：纸人站在石头正对面，合上时被压回起点；站开一格再合上，就没事。", "Picture: standing facing the stone, she is pressed back to the start when the book closes; one square aside, she is safe.", "図：石の真向かいに立っていると、閉じたとき押されて出発点に戻る。一枡ずれて閉じれば無事。", "그림: 돌 바로 맞은편에 서 있으면 책을 닫을 때 눌려 출발점으로 돌아가요. 한 칸 비켜서 닫으면 괜찮아요."],
  'slip.pic.ride': ["图：纸人站在影子上，页角慢慢变，影子带着她滑到另一格。", "Picture: she stands on a shadow; as the angle slowly changes, the shadow carries her to another square.", "図：影の上に立ち、角度がゆっくり変わると、影が別の枡まで運ぶ。", "그림: 그림자 위에 서서 각도가 천천히 바뀌면, 그림자가 다른 칸으로 데려가요."],
  'slip.pic.glue': ["图：书合上，胶把对面的石头粘过来；石头换了页，纸人从空出来的路走到终点。", "Picture: the book closes and the glue pulls the stone across; the stone has changed page, and she walks the freed road to the letter.", "図：本を閉じると糊が向かいの石を貼りつけ、石がページを移り、空いた道を通って終点へ。", "그림: 책을 닫으면 풀이 맞은편 돌을 붙여 오고, 돌이 페이지를 옮겨 비워진 길로 도착점에 가요."],
  'slip.pic.turn': ["图：书合上，翻个面再打开，对面换成了第三页，终点就在那里。", "Picture: closed, the book turns over and opens on the third page, where the letter is.", "図：閉じて裏返して開くと、向かいが三枚目の頁になり、終点はそこにある。", "그림: 닫고 뒤집어 펼치면 맞은편이 세 번째 페이지가 되고, 도착점은 거기 있어요."],
  'slip.tuck': ["收起", "Tuck in", "しまう", "넣기"],
  'slip.next': ["下一张", "Next", "次へ", "다음"],
  'slip.aria': ["物件笺", "object slip", "物の栞", "물건 쪽지"],
  'slip.label': ["物件笺，{name}", "Object slip: {name}", "物の栞、{name}", "물건 쪽지, {name}"],
  'slip.bookmark': ["{name}，物件笺", "{name}, object slip", "{name}、物の栞", "{name}, 물건 쪽지"],
  'slip.hint': ["双击收起", "Double-tap to tuck it in", "ダブルタップでしまう", "두 번 탭하면 넣어요"],
  'slip.hintNext': ["双击看下一张", "Double-tap for the next slip", "ダブルタップで次へ", "두 번 탭하면 다음 쪽지"],
  'slip.bookmarkHint': ["双击再读一遍", "Double-tap to read it again", "ダブルタップでもう一度読む", "두 번 탭하면 다시 읽어요"],
  'slip.pageOf': ["第 {n} 张，共 {total} 张", "Slip {n} of {total}", "{total} 枚中 {n} 枚目", "{total}장 중 {n}번째"],
};
for (const [key, [zh, en, ja, ko]] of Object.entries(SLIPS)) {
  ui[key] = { comment: (/^slip\.(pic|label|bookmark|hint|pageOf|aria)/.test(key) ? 'VoiceOver' : 'UI') + '. Native app only. 物件笺 (fold-proto design-onboarding §2.4–2.5). ja/ko: TODO-native-check.', values: { zh, en, ja, ko } };
}
// 0.1 (18): the contents page and the 「物件」 page (fold-proto design-onboarding §2.6, §3.5; review F7–F9).
// zh / en from the spec; ja / ko drafts: TODO-native-check.
const CONTENTS = {
  'map.vol2Back': ["卷二《翻页》", "Book Two: Turning the Page", "第二巻『ページをめくる』", "제2권 《책장 넘기기》"],
  'lv.done': ["已送达", "Delivered", "届いた", "도착"],
  'lv.next': ["下一封", "Next letter", "次の手紙", "다음 편지"],
  'lv.locked': ["未到", "Not yet", "まだ", "아직"],
  'lv.lockedValue': ["未到，先送出上一封", "Not yet: deliver the letter before it first", "まだ。先に前の手紙を届けて", "아직, 먼저 앞 편지를 전하세요"],
  'lv.lockedToast': ["先送出上一封。", "Deliver the letter before it first.", "先に前の手紙を届けて。", "먼저 앞 편지를 전하세요."],
  'lv.why': ["为什么锁着", "Why it is tied shut", "なぜ閉じているか", "왜 묶여 있나요"],
  'lv.par': ["折 {n} · 标准 {par}", "{n} folds · par {par}", "折り {n} · 標準 {par}", "접기 {n} · 기준 {par}"],
  'lv.parSpoken': ["折 {n}，标准 {par}", "{n} folds, par {par}", "折り {n}、標準 {par}", "접기 {n}, 기준 {par}"],
  'dark.code': ["暗{n}", "Hidden {n}", "隠{n}", "숨은 {n}"],
  'dark.afterChapter': ["章送完后开", "Opens once the chapter is delivered", "章を届けたら開く", "장을 다 전하면 열려요"],
  'contents.objects': ["物件笺 · 已集 {n} / {total}", "Object slips · {n} / {total} collected", "物の栞 · {n} / {total} 集めた", "물건 쪽지 · {n} / {total} 모음"],
  'objects.title': ["物件", "Objects", "物", "물건"],
  'objects.count': ["已集 {n} / {total}", "{n} / {total} collected", "{n} / {total} 集めた", "{n} / {total} 모음"],
  'objects.unseen': ["还没遇到", "Not met yet", "まだ出会っていない", "아직 못 만났어요"],
  'objects.unseenLabel': ["物件笺，还没遇到", "Object slip, not met yet", "物の栞、まだ出会っていない", "물건 쪽지, 아직 못 만났어요"],
  'slips.introLine': ["书里夹了几张物件笺", "A few object slips are tucked in the book", "本に物の栞が何枚か挟まっている", "책에 물건 쪽지가 몇 장 끼워져 있어요"],
  'settings.bookGroup': ["书", "Book", "本", "책"],
  'settings.objects': ["物件笺", "Object slips", "物の栞", "물건 쪽지"],
};
for (const [key, [zh, en, ja, ko]] of Object.entries(CONTENTS)) {
  ui[key] = { comment: (/^(lv\.(lockedValue|why|parSpoken)|objects\.unseenLabel)$/.test(key) ? 'VoiceOver' : 'UI') + '. Native app only. 章页 / 物件 (fold-proto design-onboarding §2.6, §3.5). ja/ko: TODO-native-check.', values: { zh, en, ja, ko } };
}
fs.writeFileSync(path.join(outDir, 'Localizable.xcstrings'), catalog(ui));

const lv = {};
// Level copy the prototype has not caught up with yet (reported upstream; drop an entry once fold-proto's i18n.js has it).
// 2-8 rightBank was redrawn in the 卷一 retune (a4f7938) but kept the old board's line and hint (ink, key, one close).
const LEVEL_FIX = {
  rightBank: {
    zh: ['右岸', '两座桥，一扇没有钥匙的门。', '在下面那座桥立起来，过到右页，沿右页往上，再从上面那座桥回到左页，走到左上角，合上。合着往下一格，你在右页。立起来，再往下一格，合上——这一叠下面是石头，你站在它背上。合着往下一格就是信。', '两次合，两次换页。'],
    en: ['The Right Bank', 'Two bridges, and a door with no key.', 'Stand the page at the lower bridge and cross to the right page, walk up it and back over the upper bridge to the left page’s top-left corner, and close. Closed, one step down: you are on the right page. Stand the page, one more step down, and close — this stack sits on a stone; you stand on its back. Closed, one step down is the letter.', 'Two closes, two page changes.'],
    ja: ['右岸', '橋が二つ、鍵のない扉が一つ。', '（TODO ja）下の橋で頁を立てて右頁へ渡り、右頁を上へ、上の橋から左頁へ戻って左上の角まで歩き、閉じる。閉じたまま下へ一枡、きみは右頁。立てて、さらに下へ一枡、閉じる。この重なりの下は石、きみはその背に。閉じたまま下へ一枡で手紙。', '二度閉じ、二度頁をまたぐ。'],
    ko: ['오른쪽 강가', '다리 둘, 열쇠 없는 문 하나.', '(TODO ko) 아래 다리에서 페이지를 세워 오른쪽 페이지로 건너고, 위로 올라가 위 다리로 왼쪽 페이지에 돌아와 왼쪽 위 모서리까지 가서 닫아요. 닫은 채 아래로 한 칸, 오른쪽 페이지예요. 세우고 아래로 한 칸 더 가서 닫아요. 이 겹 아래는 돌, 당신은 그 등 위에. 닫은 채 아래로 한 칸이 편지예요.', '두 번 닫고, 두 번 페이지를 바꿔요.'],
  },
};
for (const [id, langs] of Object.entries(LEVEL_FIX)) for (const [l, v] of Object.entries(langs)) src.levelTexts[l][id] = v;

// 0.1 (16): ch. 6 「翻」 level copy for ja / ko (fold-proto falls back to en). TODO-native-check.
const LEVEL_CH6 = {
  ja: {
    turn: ['めくる', 'この頁に手紙はない。', '閉じて、裏返して、閉じたまま下へ歩く。5行目は左頁がすき間で三枚目の頁が紙——その重なりへ歩けば三枚目の頁に移る。手紙はそこに。', '閉じた本は、裏返すこともできる。'],
    overleaf: ['裏面', '立っている頁は、めくれない。', '閉じる。閉じたまま歩くとき、両方の頁が紙ならいまの頁にとどまり、片方だけが紙の重なりでだけ頁を移る。右頁がすき間の重なりへ歩けば左頁に移る——そこでめくる。それから閉じたまま下まで歩く。彼女は三枚目の頁の角にいる。', 'めくる前に、左頁へ。'],
    twoFaces: ['両面', '灯りが照らすのは、この面。', '左頁を左下の角まで歩き、60°まで傾ける。石の影が4列目につながる。影をたどって3行目へ、閉じて裏返し、閉じたまま上まで歩く——手紙は三枚目の頁のいちばん上の行。', 'まずこの面の影を使ってから、めくる。'],
    inlay: ['間紙', '石が二つ、角度は一つ。', '左頁3行目の左端まで歩き、40°まで傾ける。二つの石の影が一緒にいちばん上の行を敷く。右上の紙まで歩いて、閉じて裏返し、閉じたまま下へ二枡。', 'いちばん上の行は、閉じてではなく歩いて行く。'],
    bleed: ['裏写り', '裏の字が透けて見える。', '先に閉じないこと：角の糊が左上の石を引き取り、影も消える。左頁をいちばん上の行の2列目（糊の上）まで歩き、55°まで傾ける。影が3列目2行目に落ちる。踏んで、本を70°まで開く。影がきみを4列目へ運ぶ。下へ一枡、3行目で閉じて裏返し、閉じたまま3番目の重なりのいちばん上へ。', 'まだ閉じないで。'],
    pressedFlower: ['押し花', '頁の角に糊。急がないで。', '先に閉じると糊が石を引き寄せ、道が切れる。はじめの位置から左下の角へ歩き、40°まで傾けて影に乗り、60°まで開く。影がきみを2列目へ運ぶ。4列目2行目まで歩いて、閉じて裏返し、閉じたまま下まで。', '閉じる前に、影を歩ききる。'],
  },
  ko: {
    turn: ['넘김', '이 페이지에는 편지가 없다.', '닫고, 뒤집고, 닫은 채 아래로 걸어요. 5행은 왼쪽 페이지가 틈이고 세 번째 페이지가 종이예요. 그 겹으로 가면 세 번째 페이지로 옮겨 가요. 편지는 거기 있어요.', '닫힌 책은 뒤집을 수도 있다.'],
    overleaf: ['뒷면', '서 있는 페이지는 넘어가지 않는다.', '닫아요. 닫은 채 걸을 때 두 페이지가 모두 종이면 지금 페이지에 머물고, 한쪽만 종이인 겹에서만 페이지를 옮겨요. 오른쪽 페이지가 틈인 겹으로 가면 왼쪽 페이지에 닿아요. 거기서 넘겨요. 그다음 닫은 채 맨 아래까지 걸어요. 그녀는 세 번째 페이지 모서리에 있어요.', '넘기기 전에 먼저 왼쪽 페이지로.'],
    twoFaces: ['양면', '등불이 비추는 건 이 면이다.', '왼쪽 페이지를 따라 왼쪽 아래 모서리까지 가서 60°로 기울여요. 돌의 그림자가 4열에 이어져요. 그림자를 따라 3행까지 가서 닫고 뒤집은 뒤, 닫은 채 맨 위까지 걸어요. 편지는 세 번째 페이지 맨 윗줄에 있어요.', '먼저 이 면의 그림자를 쓰고, 그다음 넘겨요.'],
    inlay: ['속지', '돌 둘, 각도 하나.', '왼쪽 페이지 3행 왼쪽 끝까지 가서 40°로 기울여요. 두 돌의 그림자가 함께 맨 윗줄을 깔아요. 오른쪽 위 종이까지 걸어가 닫고 뒤집은 뒤, 닫은 채 아래로 두 칸.', '맨 윗줄은 닫아서가 아니라 걸어서 간다.'],
    bleed: ['배어 나온 글', '뒷면의 글이 비쳐 보인다.', '먼저 닫지 마세요. 모서리의 풀이 왼쪽 위 돌을 붙여 가면 그림자도 사라져요. 왼쪽 페이지를 따라 맨 윗줄 2열(풀 위)까지 가서 55°로 기울여요. 그림자가 3열 2행에 떨어져요. 밟고 올라선 뒤 책을 70°까지 펼쳐요. 그림자가 당신을 4열로 옮겨요. 아래로 한 칸, 3행에서 닫고 뒤집은 뒤, 닫은 채 세 번째 겹 맨 위까지.', '아직 닫지 마세요.'],
    pressedFlower: ['압화', '페이지 모서리에 풀. 서두르지 마.', '먼저 닫으면 풀이 돌을 끌어와 길이 끊겨요. 출발점에서 왼쪽 아래 모서리까지 가서 40°로 기울여 그림자에 올라선 뒤 60°까지 펼쳐요. 그림자가 당신을 2열로 옮겨요. 4열 2행까지 걸어가 닫고 뒤집은 뒤, 닫은 채 맨 아래까지.', '닫기 전에 그림자를 끝까지 걸어요.'],
  },
};
for (const [l, table] of Object.entries(LEVEL_CH6)) for (const [id, v] of Object.entries(table)) if (!src.levelTexts[l][id]) src.levelTexts[l][id] = v;
// 0.1 (17): 4-6 twoFigures and 6-7 lastPage were reworked in fold-proto (difficulty-v3.md §6, 82e0990 / 37b91e4). fold-proto
// has ja / ko only as a 「（TODO ja）」 draft for 4-6 and none for 6-7; these replace both. TODO-native-check.
const LEVEL_V17 = {
  ja: {
    twoFigures: ['二人', '両岸がふれる。手紙は、届いた。', '右へ一枡。いま立っているのは左頁の石の真上——ここで閉じる。この重なりには入れないが、出ることはできる。閉じたまま左へ歩いて左頁へ。80°まで開いて4列目をいちばん下まで。55°まで閉じると、いちばん下の行の影が左下の角へ運んでくれる。扉は最初に閉じたときに開いている。扉の中で閉じて、一つ上の重なりへ——その人がいる。', '石の背の上でも、閉じられる。'],
    lastPage: ['最後の頁', '最後の頁まで、めくる。', '右上の角の紙——左頁の石とちょうど向かい合うマス——まで歩いて、そこで閉じる。閉じたままその重なりを出て、左頁へ。本を裏返す：左頁の糊が三枚目の頁の石を引き寄せる。もう一度裏返して戻す：こんどは右頁の糊がそれを受け取る。石はいま右頁にある。55°まで傾けると、その影が手紙の横のすき間にちょうど落ちる。', '石の背も、紙のうち。'],
  },
  ko: {
    twoFigures: ['두 사람', '두 강가가 맞닿는다. 편지는, 도착했다.', '오른쪽으로 한 칸. 지금 왼쪽 페이지 돌의 바로 위에 서 있어요. 여기서 닫아요. 이 겹에는 들어올 수 없지만 나갈 수는 있어요. 닫은 채 왼쪽으로 걸어 왼쪽 페이지로. 80°까지 펼치고 4열을 맨 아래까지 내려가요. 55°까지 닫으면 맨 아랫줄의 그림자가 왼쪽 아래 모서리로 데려가요. 문은 처음 닫을 때 이미 열렸어요. 문 안에 서서 닫고 한 겹 위로 가면, 그 사람이 있어요.', '돌의 등 위에서도 닫을 수 있다.'],
    lastPage: ['마지막 페이지', '마지막 페이지까지 넘겨라.', '오른쪽 위 모서리의 종이, 왼쪽 페이지의 돌과 마주 보는 칸까지 걸어가 거기서 닫아요. 닫은 채 그 겹을 나와 왼쪽 페이지로. 책을 뒤집어요. 왼쪽 페이지의 풀이 세 번째 페이지의 돌을 끌어와요. 다시 뒤집어 되돌리면, 이번엔 오른쪽 페이지의 풀이 그 돌을 받아 가요. 이제 돌은 오른쪽 페이지에 있어요. 55°로 기울이면 그 그림자가 편지 옆 틈에 딱 떨어져요.', '돌의 등도 종이다.'],
  },
};
for (const [l, table] of Object.entries(LEVEL_V17)) Object.assign(src.levelTexts[l], table);
// 0.1 (19): ch. 7 「墨晕」 ja / ko are fold-proto's drafts (TODO review there). 7-6 turned was cut (design-ch7.md §3): no
// level, no strings.
const LEVEL_CH7 = ['wet', 'print', 'ring', 'spoiled', 'pocket', 'through'];
const LEVEL_CUT = new Set(['turned']);
const LEVEL_CHECKED = new Set([...Object.keys(LEVEL_CH6.ja), ...Object.keys(LEVEL_V17.ja), ...LEVEL_CH7]);

for (const id of Object.keys(src.levelTexts.en).filter((x) => !LEVEL_CUT.has(x))) {
  // an optional 4th entry: the first rung of the 「?」 ladder (design-review-v2c1 §2), shown before the hint
  ['name', 'line', 'hint', 'hint1'].forEach((part, i) => {
    if (i === 3 && !(src.levelTexts.en[id] || [])[3]) return;
    const values = {};
    for (const l of Object.keys(LANG)) values[l] = (src.levelTexts[l][id] || src.levelTexts.en[id])[i] ?? src.levelTexts.en[id][i];
    const what = { name: 'title', line: 'one-line teaser', hint: 'hint', hint1: 'first hint (the 「?」 ladder, before the hint)' }[part];
    lv[`${id}.${part}`] = { comment: `Level "${id}": ${what}. From fold-proto i18n.js.` + (LEVEL_CHECKED.has(id) ? ' ja/ko: TODO-native-check.' : ''), values };
  });
}
fs.writeFileSync(path.join(outDir, 'Levels.xcstrings'), catalog(lv));

const brand = { zh: '折信', en: 'Letterfold', ja: '折り文', ko: '접은 편지' };
fs.writeFileSync(path.join(outDir, 'InfoPlist.xcstrings'), catalog({
  CFBundleDisplayName: { comment: 'App name on the Home Screen', values: brand },
  CFBundleName: { comment: 'App name', values: brand },
}));
console.log(`Localizable: ${Object.keys(ui).length} keys, Levels: ${Object.keys(lv).length} keys`);
