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
