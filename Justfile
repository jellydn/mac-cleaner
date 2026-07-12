# Run every prek hook across all files in the repo
default:
    @just --list

precommit:
    prek run --all-files

# Install prek Git shims so hooks fire on `git commit`
prek-install:
    prek install

# Build the ReleaseFast binary (-> zig-out/bin/mac-cleaner)
build:
    native build

# Run the headless UI + JSON parse + layout test suite
test:
    native test

# Build, run, and hot-reload on src/app.native changes
dev:
    native dev
