const path = require('path');
const postcss = require('postcss');
const slugify = require('slugify');

const tokensDir = path.join(__dirname, '..', 'design-tokens');
const clampGenerator = require(path.join(__dirname, '..', 'css-utils', 'clamp-generator.js'));

function slugName(text) {
  return slugify(text, { lower: true });
}

function toMap(items) {
  const map = {};
  items.forEach(({ name, value }) => {
    map[slugName(name)] = Array.isArray(value) ? value.join(', ') : value;
  });
  return map;
}

function loadTokens() {
  const colorTokens = require(path.join(tokensDir, 'colors.json'));
  const fontTokens = require(path.join(tokensDir, 'fonts.json'));
  const spacingTokens = require(path.join(tokensDir, 'spacing.json'));
  const textSizeTokens = require(path.join(tokensDir, 'text-sizes.json'));
  const textLeadingTokens = require(path.join(tokensDir, 'text-leading.json'));
  const textWeightTokens = require(path.join(tokensDir, 'text-weights.json'));

  return {
    colors: toMap(colorTokens.items),
    spacing: toMap(clampGenerator(spacingTokens.items)),
    fontSize: toMap(clampGenerator(textSizeTokens.items)),
    fontLeading: toMap(textLeadingTokens.items),
    fontFamily: toMap(fontTokens.items),
    fontWeight: toMap(textWeightTokens.items),
  };
}

const propertyGroups = [
  { key: 'colors', prefix: 'color' },
  { key: 'spacing', prefix: 'space' },
  { key: 'fontSize', prefix: 'size' },
  { key: 'fontLeading', prefix: 'leading' },
  { key: 'fontFamily', prefix: 'font' },
  { key: 'fontWeight', prefix: 'font' },
];

const utilityGroups = [
  { key: 'spacing', prefix: 'flow-space', property: '--flow-space' },
  { key: 'spacing', prefix: 'region-space', property: '--region-space' },
  { key: 'spacing', prefix: 'gutter', property: '--gutter' },
  { key: 'colors', prefix: 'indent-color', property: '--indent-color' },
  { key: 'fontSize', prefix: 'text', property: 'font-size' },
];

module.exports = (opts = {}) => {
  return {
    postcssPlugin: 'design-tokens',
    Once(root) {
      const tokens = loadTokens();

      // Prepend :root block with all custom properties
      const rootRule = postcss.rule({ selector: ':root' });

      propertyGroups.forEach(({ key, prefix }) => {
        const map = tokens[key];
        Object.entries(map).forEach(([name, value]) => {
          rootRule.append(postcss.decl({ prop: `--${prefix}-${name}`, value: String(value) }));
        });
      });

      root.prepend(rootRule);

      // Append utility classes at the end
      utilityGroups.forEach(({ key, prefix, property }) => {
        const map = tokens[key];
        Object.entries(map).forEach(([name, value]) => {
          const rule = postcss.rule({ selector: `.${prefix}-${name}` });
          rule.append(postcss.decl({ prop: property, value: String(value) }));
          root.append(rule);
        });
      });
    },
  };
};

module.exports.postcss = true;
