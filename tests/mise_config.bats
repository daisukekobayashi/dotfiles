#!/usr/bin/env bats

load 'helpers/test_helper.bash'

@test "baseline mise config excludes optional language runtimes" {
  run grep -E '^(clojure|kotlin)[[:space:]]*=' "$(repo_root)/mise/config.toml"
  [ "$status" -ne 0 ]

  run grep -F '"asdf:mise-plugins/mise-r"' "$(repo_root)/mise/config.toml"
  [ "$status" -ne 0 ]
}

@test "R mise config is opt-in and builds a shared library with cairo" {
  local config="$(repo_root)/mise/config.r.toml"

  [ -f "${config}" ]
  grep -F '"asdf:mise-plugins/mise-r"' "${config}"
  grep -F 'version = "4.6.1"' "${config}"
  grep -F 'R_EXTRA_CONFIGURE_OPTIONS = "--enable-R-shlib --with-cairo"' "${config}"
}

@test "JVM extra mise config contains optional Kotlin and Clojure runtimes" {
  local config="$(repo_root)/mise/config.jvm-extra.toml"

  [ -f "${config}" ]
  grep -F 'clojure = "1.12.4"' "${config}"
  grep -F 'kotlin = "2.3.10"' "${config}"
}

@test "mise README documents optional env configs instead of expanding the root README" {
  local mise_readme="$(repo_root)/mise/README.md"

  [ -f "${mise_readme}" ]
  grep -F 'config.r.toml' "${mise_readme}"
  grep -F 'config.jvm-extra.toml' "${mise_readme}"
  grep -F 'mise install -E r' "${mise_readme}"
  grep -F 'mise exec -E r -- R --version' "${mise_readme}"
  grep -F 'mise install -E jvm-extra' "${mise_readme}"
  grep -F 'mise install -E linux,r' "${mise_readme}"

  grep -F 'mise/README.md' "$(repo_root)/README.md"
  grep -F 'mise/README.md' "$(repo_root)/README.ja.md"
  run grep -F 'mise exec -E r -- R' "$(repo_root)/README.md" "$(repo_root)/README.ja.md"
  [ "$status" -ne 0 ]
}
