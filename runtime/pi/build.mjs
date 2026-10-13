import { build } from "esbuild";
import { mkdir, writeFile } from "node:fs/promises";
await mkdir("dist", { recursive: true });
const result = await build({
    entryPoints: ["worker.mjs"],
    bundle: true,
    platform: "node",
    target: "node22",
    format: "esm",
    outfile: "dist/worker.mjs",
    metafile: true,
    banner: {
        js: "import { createRequire as quillsideCreateRequire } from 'node:module'; const require = quillsideCreateRequire(import.meta.url);",
    },
});
await writeFile("dist/metafile.json", JSON.stringify(result.metafile, null, 2));
console.log("Bundled Pi worker.");
