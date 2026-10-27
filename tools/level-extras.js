// Add what export.js does not ship to levels.json: `optional`, `lamp` (ch. 8), (「暗信」 side letters), the declared minimal solution
// length `len` (posture changes + steps, docs/difficulty-postmortem.md §6), and the proto solver's shortest solution
// (tools/gen.js bestPath: fewest postures, then fewest steps) as [c, r, foldAngle, stamped, face] states (face: vol. 2 ch. 6, which page faces the left page; a state that only changes it is a turn), which the
// FoldCore tests replay and turn into the XCUITest playthrough plan.
// node tools/level-extras.js <fold-proto> <levels.json>
const fs = require('fs');
const path = require('path');
const [proto, file] = process.argv.slice(2);
const LEVELS = require(path.join(proto, 'levels.js'));
const GEN = require(path.join(proto, 'tools', 'gen.js'));
const pack = JSON.parse(fs.readFileSync(file, 'utf8'));
// fold-proto 0053ff1 reuses the id 'lamp' for 8-1 (3-6 is 'lamp' too). Save slots and strings are keyed by id, so the
// native app ships the later one under its own id. export.js keeps levels.js order, so levels pair up by index.
const NATIVE_IDS = { 'lamp@8': 'leftLamp' };
pack.levels.forEach((lv, i) => {
  const src = LEVELS[i];
  if (src.id !== lv.id) throw new Error(`levels.json #${i} is ${lv.id}, levels.js has ${src.id}`);
  const nid = NATIVE_IDS[`${src.id}@${src.chapter}`];
  if (nid) lv.id = nid;
  if (src.optional) lv.optional = true;
  if (src.lamp && src.lamp !== 'R') lv.lamp = src.lamp;   // vol. 2 ch. 8 「灯位」: export.js does not ship it
  const B = GEN.prep(src), g = GEN.explore(B), bp = GEN.bestPath(g);
  if (!bp) throw new Error(`${lv.id}: no solution`);
  lv.len = bp.par + bp.steps;
  if (src.len != null && src.len !== lv.len) throw new Error(`${lv.id}: declared len ${src.len}, measured ${lv.len}`);
  lv.solution = bp.path.map((k) => { const s = g.nodes.get(k); return [s.c, s.r, s.a, s.g > 0 ? 1 : 0, s.face]; });
});
const ids = pack.levels.map((l) => l.id);
if (new Set(ids).size !== ids.length) throw new Error('duplicate level ids: ' + ids.filter((x, i) => ids.indexOf(x) !== i));
fs.writeFileSync(file, JSON.stringify(pack, null, 2).replace(/\[\n\s+(-?\d+),\n\s+(-?\d+),\n\s+(-?\d+),\n\s+(-?\d+),\n\s+(-?\d+)\n\s+\]/g, '[$1, $2, $3, $4, $5]') + '\n');
console.log(`levels.json: optional / len / solution for ${pack.levels.length} levels`);
