#!/usr/bin/env bats
# scripts/check-reuse.sh profile --detect — a proposed reuse profile, and no
# file written.
#
# tools: one version probe per toolchain whose manifest exists AND whose binary
# is on PATH:
#   package.json → node --version, plus the packageManager tool's --version
#   go.mod → go version · Cargo.toml → rustc --version
#   pyproject.toml / requirements*.txt → python3 --version
#   composer.json → php --version · build.gradle* / pom.xml → java -version
#   Gemfile → ruby --version · deno.json* → deno --version
# inputs: gitignored files named .env, .env.*, .dev.vars or
#   *.local.{json,yaml,yml,toml,php}, outside node_modules/ and vendor/.
# never: [] — which commands need credentials is a judgement, not a detection.
# A package.json that is not valid JSON loses only its packageManager probe
# (node stays), and a directory outside git proposes no inputs — each with a
# warning on stderr and exit 0.
#
# PATH is built for each case from a copy of the machine's PATH with every
# toolchain binary removed, plus fake binaries the case puts there itself, so
# "on PATH" and "absent" mean the same thing on every machine.

bats_require_minimum_version 1.5.0

TOOLCHAIN="node npm npx pnpm yarn bun corepack go gofmt rustc cargo python python3 php java ruby gem deno"

setup_file() {
  SYSBIN="$BATS_FILE_TMPDIR/sysbin"
  mkdir -p "$SYSBIN"
  local d f name
  IFS=: read -r -a dirs <<< "$PATH"
  for d in "${dirs[@]}"; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      name=${f##*/}
      [ -x "$f" ] && [ ! -d "$f" ] || continue
      case " $TOOLCHAIN " in *" $name "*) continue ;; esac
      [ -e "$SYSBIN/$name" ] || ln -s "$f" "$SYSBIN/$name"
    done
  done
  export SYSBIN
}

setup() {
  # shellcheck source=tests/lib/reuse-fixture.sh
  source "$BATS_TEST_DIRNAME/lib/reuse-fixture.sh"
  reuse_setup
  FAKEBIN="$WORK/fakebin"
  mkdir -p "$FAKEBIN"
  printf '.env\n.env.*\n!.env.example\n.envrc\n.dev.vars\n*.local.*\nnode_modules/\nvendor/\nbuild/\n' > .gitignore
  git add -A && commit_all "ignore the local files"
}

teardown() { reuse_teardown; }

on_path() {  # <name...> — a fake binary for each, on this case's PATH
  local n
  for n in "$@"; do
    printf '#!/bin/sh\necho "%s 1.0"\n' "$n" > "$FAKEBIN/$n"
    chmod +x "$FAKEBIN/$n"
  done
}

detect() { run --separate-stderr env PATH="$FAKEBIN:$SYSBIN" bash "$CR" profile --detect; }

tools() { jq -c '.tools | sort' <<< "$output"; }

# --- Hostile halves: a probe needs BOTH the manifest and the binary ---

@test "a manifest whose binary is absent yields no probe" {
  printf 'module example.invalid/app\n' > go.mod
  printf '[package]\nname = "app"\n' > Cargo.toml
  on_path ruby
  detect
  [ "$status" -eq 0 ]
  jq -e '.version == 1' <<< "$output"
  [ "$(tools)" = '[]' ]
}

@test "a binary on PATH with no manifest yields no probe" {
  on_path go rustc python3 node php java ruby deno
  printf 'Gemfile\n' > README.txt
  detect
  [ "$status" -eq 0 ]
  jq -e '.version == 1 and .mode == "shadow"' <<< "$output"
  [ "$(tools)" = '[]' ]
}

@test "two manifests of one toolchain yield one probe, not two" {
  on_path python3 java
  printf '[project]\nname = "app"\n' > pyproject.toml
  printf 'requests\n' > requirements.txt
  printf 'pytest\n' > requirements-dev.txt
  printf '<project/>\n' > pom.xml
  printf 'plugins {}\n' > build.gradle.kts
  detect
  [ "$(tools)" = '["java -version","python3 --version"]' ]
}

@test "a packageManager tool that is not on PATH is not probed; node still is" {
  on_path node
  printf '{"name": "app", "packageManager": "yarn@4.1.0"}\n' > package.json
  detect
  [ "$(tools)" = '["node --version"]' ]
}

# --- Each toolchain ---

@test "every manifest with its binary on PATH yields its probe" {
  on_path node pnpm go rustc python3 php java ruby deno
  printf '{"name": "app", "packageManager": "pnpm@9.1.0"}\n' > package.json
  printf 'module example.invalid/app\n' > go.mod
  printf '[package]\nname = "app"\n' > Cargo.toml
  printf 'requests\n' > requirements.txt
  printf '{}\n' > composer.json
  printf 'plugins {}\n' > build.gradle
  printf "source 'https://rubygems.org'\n" > Gemfile
  printf '{}\n' > deno.jsonc
  detect
  [ "$status" -eq 0 ]
  [ "$(tools)" = '["deno --version","go version","java -version","node --version","php --version","pnpm --version","python3 --version","ruby --version","rustc --version"]' ]
}

# --- Inputs ---

@test "inputs: gitignored env and local-config files, never a tracked one, a lookalike or a dependency's" {
  mkdir -p apps/api config node_modules/pkg vendor/lib
  printf 'A=1\n' > .env
  printf 'A=1\n' > apps/api/.env.test
  printf 'A=1\n' > .dev.vars
  printf '{}\n' > config/app.local.json
  printf 'a: 1\n' > config/app.local.yaml
  printf 'a: 1\n' > config/app.local.yml
  printf 'a = 1\n' > config/app.local.toml
  printf '<?php\n' > config/app.local.php
  # Not inputs: a tracked example, names outside the four patterns, and the
  # same names inside dependency directories.
  printf 'A=\n' > .env.example
  git add .env.example && commit_all "an env example"
  printf 'x\n' > .envrc
  printf 'x\n' > config/notes.local.md
  printf 'A=1\n' > node_modules/pkg/.env
  printf '{}\n' > vendor/lib/app.local.json
  detect
  [ "$status" -eq 0 ]
  [ "$(jq -c '.inputs | sort' <<< "$output")" = '[".dev.vars",".env","apps/api/.env.test","config/app.local.json","config/app.local.php","config/app.local.toml","config/app.local.yaml","config/app.local.yml"]' ]
}

@test "never is proposed empty, whatever the project holds" {
  on_path node
  printf '{"name": "app"}\n' > package.json
  printf 'A=1\n' > .env
  detect
  jq -e '.never == [] and .mode == "shadow" and .version == 1' <<< "$output"
  [ "$(tools)" = '["node --version"]' ]
}

# --- What detection cannot read ---

@test "a malformed package.json: the packageManager probe is skipped, node kept, exit 0 and a warning" {
  on_path node pnpm
  printf '{"name": "app", "packageManager": "pnpm@9.1.0",\n' > package.json
  detect
  [ "$status" -eq 0 ]
  [ "$(tools)" = '["node --version"]' ]
  [ -n "$stderr" ]
}

@test "outside a git work tree: tools still detected, inputs [], exit 0 and a warning" {
  mkdir -p "$WORK/plain"
  cd "$WORK/plain"
  on_path go
  printf 'module example.invalid/app\n' > go.mod
  printf 'A=1\n' > .env
  printf '{}\n' > app.local.json
  detect
  [ "$status" -eq 0 ]
  [ "$(tools)" = '["go version"]' ]
  jq -e '.inputs == []' <<< "$output"
  [ -n "$stderr" ]
  [ ! -e "$WORK/plain/.git" ]
}

# --- Writes nothing ---

@test "--detect writes no file: no profile appears, an existing one is untouched, git status unchanged" {
  on_path node
  printf '{"name": "app"}\n' > package.json
  status_before=$(git status --porcelain --ignored)
  detect
  [ "$status" -eq 0 ]
  [ "$(tools)" = '["node --version"]' ]
  [ ! -e .epico/reuse-profile.json ]
  [ "$(git status --porcelain --ignored)" = "$status_before" ]
  write_profile '{"version": 1, "mode": "on", "tools": [], "inputs": [], "never": ["kept"]}'
  cp .epico/reuse-profile.json "$WORK/profile.before"
  detect
  cmp -s "$WORK/profile.before" .epico/reuse-profile.json
}
