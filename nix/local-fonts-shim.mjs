// Rewrites `next/font/google` usage to `next/font/local` during the Nix build.
//
// Why this exists: `next/font/google` downloads font binaries from fonts.googleapis.com
// at build time. The Nix sandbox has no network, so every Google font import is a build
// failure. Upstream ships these fonts as Google imports (see app/layout.tsx), so the Nix
// packaging substitutes vendored copies of the same faces.
//
// The alternative — a `patches` entry holding a unified diff against app/layout.tsx —
// has to restate that file's import block and every font call verbatim, so it breaks the
// moment upstream edits layout.tsx for any unrelated reason. Rewriting in a script keeps
// working across reordering, added imports, and added/removed call sites.
//
// Usage: node local-fonts-shim.mjs <layout.tsx> <fonts-dir>

import { readFileSync, writeFileSync } from "node:fs";

const [layoutPath, fontsDir] = process.argv.slice(2);
if (!layoutPath || !fontsDir) {
  console.error("usage: node local-fonts-shim.mjs <layout.tsx> <fonts-dir>");
  process.exit(1);
}

// Vendored faces, keyed by the export name `next/font/google` would have provided.
// `weight` is the variable-font axis range. Google fonts declare discrete weights that
// `next/font/local` cannot satisfy against a variable font, so the call site keeps its
// own `variable`/`display` options but always requests the full weight range.
const FONT_MAP = {
  Geist: { file: "Geist.ttf", weight: "100 900" },
  JetBrains_Mono: { file: "JetBrainsMono.ttf", weight: "100 800" },
  Noto_Sans_Mono: { file: "NotoSansMono.ttf", weight: "100 900" },
  Source_Serif_4: { file: "SourceSerif4Variable-Roman.otf", weight: "200 900" },
  Noto_Serif_SC: { file: "NotoSerifSC-VF.otf", weight: "200 900" },
};

// Used for any font upstream adds that has no vendored counterpart. Rendering in a
// fallback face beats failing the whole build over a missing typeface.
const FALLBACK = FONT_MAP.Geist;

const layout = readFileSync(layoutPath, "utf8");
const importMatch = /import\s*\{([^}]*)\}\s*from\s*["']next\/font\/google["']/.exec(layout);

if (!importMatch) {
  // Upstream moved off next/font/google, or vendors the fonts itself already.
  console.log("[local-fonts-shim] no next/font/google import found; nothing to rewrite");
  process.exit(0);
}

const requested = importMatch[1]
  .split(",")
  .map((name) => name.trim())
  .filter(Boolean);

if (requested.length === 0) {
  console.error("[local-fonts-shim] matched an empty next/font/google import");
  process.exit(1);
}

const unmapped = requested.filter((name) => !(name in FONT_MAP));
if (unmapped.length > 0) {
  console.warn(
    `[local-fonts-shim] WARNING: no vendored font for ${unmapped.join(", ")}; ` +
      `falling back to ${FALLBACK.file}. Add the face to nix/package.nix and to ` +
      `FONT_MAP in nix/local-fonts-shim.mjs to render it correctly.`,
  );
}

// Pull a string option out of a font call's option object, e.g. `variable: "--font-geist"`.
const optionValue = (options, key) => {
  const match = new RegExp(`\\b${key}\\s*:\\s*"([^"]+)"`).exec(options);
  return match ? match[1] : undefined;
};

// `importMatch[0]` spans the statement's trailing semicolon, so the replacement omits it.
let rewritten = layout.replace(importMatch[0], 'import localFont from "next/font/local"');

for (const name of requested) {
  const { file, weight } = FONT_MAP[name] ?? FALLBACK;
  // `next/font/local` must be called directly in module scope and assigned to a const,
  // so the call site itself becomes the localFont call. Options are non-nested, so
  // matching up to the first `})` is sufficient.
  const callSite = new RegExp(`\\b${name}\\(\\{([\\s\\S]*?)\\}\\)`);
  if (!callSite.test(rewritten)) {
    console.warn(
      `[local-fonts-shim] WARNING: imported ${name} but found no ${name}({ ... }) call site; ` +
        `leaving it on next/font/google, which will fail to fetch in the sandbox.`,
    );
    continue;
  }
  rewritten = rewritten.replace(callSite, (_match, options) => {
    const variable = optionValue(options, "variable");
    const display = optionValue(options, "display") ?? "swap";
    return [
      `localFont({`,
      `  src: "./fonts/${file}",`,
      `  weight: "${weight}",`,
      ...(variable ? [`  variable: "${variable}",`] : []),
      `  display: "${display}",`,
      `})`,
    ].join("\n");
  });
}

writeFileSync(layoutPath, rewritten);

const stillGoogle = /next\/font\/google/.test(rewritten);
if (stillGoogle) {
  console.error("[local-fonts-shim] next/font/google references remain after rewrite");
  process.exit(1);
}

console.log(`[local-fonts-shim] rewrote ${requested.length} font call site(s) in ${layoutPath}`);