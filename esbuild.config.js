const path = require('path')

require("esbuild").build({
  entryPoints: ["main.js"],
  bundle: true,
  outdir: path.join(process.cwd(), "tmp/dist/javascripts"),
  absWorkingDir: path.join(process.cwd(), "assets/javascript"),
  watch: process.argv.includes("--watch"),
  plugins: [],
}).catch(() => process.exit(1))