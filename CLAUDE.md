# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is Michael Koper's personal website built with Middleman (Ruby static site generator) and ESBuild for JavaScript bundling.

## Commands

### Development
```bash
# Start Middleman development server with live reload
bundle exec middleman server

# Start ESBuild in watch mode (runs automatically with Middleman)
npm start
```

### Build
```bash
# Build the static site
bundle exec middleman build

# Build JavaScript only
npm run build
```

### Dependencies
```bash
# Install Ruby dependencies
bundle install

# Install Node dependencies
npm install
```

## Architecture

### Tech Stack
- **Middleman 4.3**: Ruby-based static site generator handling HTML generation, asset management, and build process
- **ESBuild**: JavaScript bundler configured to watch and compile from `assets/javascript/main.js` to `tmp/dist/javascripts/`
- **Ruby 2.x**: Required for Middleman (check `.ruby-version`)
- **Node.js**: Required for ESBuild (check `.node-version`)

### Key Directories
- `source/`: Contains all source files for the static site (HTML templates, images, stylesheets)
- `assets/javascript/`: JavaScript source files (entry point: `main.js`)
- `tmp/dist/`: ESBuild output directory integrated with Middleman's external pipeline
- `build/`: Generated static site output (created after running `middleman build`)

### Build Pipeline
1. ESBuild compiles JavaScript from `assets/javascript/` to `tmp/dist/javascripts/`
2. Middleman's external pipeline (configured in `config.rb`) integrates ESBuild output
3. Middleman processes ERB templates, applies layouts, and generates final HTML
4. In production builds, Middleman applies asset hashing (except images) and gzip compression

### Key Configuration Files
- `config.rb`: Middleman configuration with external pipeline setup for ESBuild, helpers, and build settings
- `esbuild.config.js`: ESBuild configuration for JavaScript bundling
- `Gemfile`: Ruby dependencies
- `package.json`: Node dependencies and npm scripts