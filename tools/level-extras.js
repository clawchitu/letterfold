// Add what export.js does not ship to levels.json: `optional` (「暗信」 side letters), the declared minimal solution
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
for (const lv of pack.levels) {
  const src = LEVELS.find((l) => l.id === lv.id);
  if (src.optional) lv.optional = true;
  const B = GEN.prep(src), g = GEN.explore(B), bp = GEN.bestPath(g);
  if (!bp) throw new Error(`${lv.id}: no solution`);
  lv.len = bp.par + bp.steps;
  if (src.len != null && src.len !== lv.len) throw new Error(`${lv.id}: declared len ${src.len}, measured ${lv.len}`);
  lv.solution = bp.path.map((k) => { const s = g.nodes.get(k); return [s.c, s.r, s.a, s.g > 0 ? 1 : 0, s.face]; });
}
fs.writeFileSync(file, JSON.stringify(pack, null, 2).replace(/\[\n\s+(-?\d+),\n\s+(-?\d+),\n\s+(-?\d+),\n\s+(-?\d+),\n\s+(-?\d+)\n\s+\]/g, '[$1, $2, $3, $4, $5]') + '\n');
console.log(`levels.json: optional / len / solution for ${pack.levels.length} levels`);
