// Usage: node scripts/generate-backpack-filter-reference.cjs <Snap.Metadata/Genshin/CHS>
const { readFileSync, writeFileSync } = require('node:fs');
const { join, resolve } = require('node:path');

const root = process.argv[2];
if (!root) throw new Error('Pass the Snap.Metadata Genshin/CHS directory');
const read = (name) => JSON.parse(readFileSync(join(root, `${name}.json`), 'utf8').replace(/^\uFEFF/, ''));

const setNames = new Map(read('ReliquarySet').map((set) => [set.SetId, set.Name]));
const reliquaries = {};
for (const item of read('Reliquary')) {
  const previous = reliquaries[item.Icon];
  if (previous && (previous.equipType !== item.EquipType || previous.setId !== item.SetId)) {
    throw new Error(`Conflicting relic metadata: ${item.Icon}`);
  }
  reliquaries[item.Icon] = { equipType: item.EquipType, setId: item.SetId, setName: setNames.get(item.SetId) ?? '' };
}

const food = {};
for (const recipe of read('CookRecipe')) {
  for (const [quality, item] of recipe.QualityOutput.entries()) {
    // BackpackViewModel.cs uses the first recipe output for each material ID.
    food[item.Id] ??= { type: recipe.FoodType, quality };
  }
}

const output = resolve(__dirname, '../entry/src/main/resources/rawfile/backpack/filters.json');
writeFileSync(output, `${JSON.stringify({ reliquaries, food })}\n`);
