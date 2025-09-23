const path = require('path')
const { spawn } = require('child_process')

const isWatch = process.argv.includes("--watch")

// Run esbuild
require("esbuild").build({
  entryPoints: ["main.js"],
  bundle: true,
  outdir: path.join(process.cwd(), "tmp/dist/javascripts"),
  absWorkingDir: path.join(process.cwd(), "assets/javascript"),
  watch: isWatch,
  plugins: [],
}).catch(() => process.exit(1))

// Run Tailwind CLI
const tailwindArgs = [
  '-i', './assets/stylesheets/tailwind-input.css',
  '-o', './tmp/dist/stylesheets/tailwind.css'
]

if (isWatch) {
  tailwindArgs.push('--watch')
}

const tailwind = spawn('npx', ['@tailwindcss/cli', ...tailwindArgs], {
  stdio: 'inherit',
  shell: true
})

tailwind.on('error', (err) => {
  console.error('Failed to start Tailwind CSS:', err)
  process.exit(1)
})

tailwind.on('exit', (code) => {
  if (code !== 0 && !isWatch) {
    process.exit(code)
  }
})