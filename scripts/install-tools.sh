#!/usr/bin/env bash
# 검사 도구를 고정 버전으로 설치한다 (체크섬 확인). 1단계에서는 hadolint, shellcheck만.
# 3단계에서 tflint, terraform, trivy를 여기에 더한다.
set -euo pipefail

HADOLINT_VERSION=2.12.0
SHELLCHECK_VERSION=0.10.0
BIN_DIR="${BIN_DIR:-/usr/local/bin}"

case "$(uname -m)" in
  x86_64)
    HADOLINT_ASSET=hadolint-Linux-x86_64
    HADOLINT_SHA256=56de6d5e5ec427e17b74fa48d51271c7fc0d61244bf5c90e828aab8362d55010
    SHELLCHECK_ARCH=x86_64
    SHELLCHECK_SHA256=6c881ab0698e4e6ea235245f22832860544f17ba386442fe7e9d629f8cbedf87
    ;;
  aarch64)
    HADOLINT_ASSET=hadolint-Linux-arm64
    HADOLINT_SHA256=5798551bf19f33951881f15eb238f90aef023f11e7ec7e9f4c37961cb87c5df6
    SHELLCHECK_ARCH=aarch64
    SHELLCHECK_SHA256=324a7e89de8fa2aed0d0c28f3dab59cf84c6d74264022c00c22af665ed1a09bb
    ;;
  *) echo "지원하지 않는 CPU: $(uname -m)" >&2; exit 1 ;;
esac

SUDO=""
if [ ! -w "$BIN_DIR" ]; then SUDO="sudo"; fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

have_version() { command -v "$1" >/dev/null 2>&1 && "$1" --version 2>&1 | grep -q "$2"; }

if have_version hadolint "$HADOLINT_VERSION"; then
  echo "hadolint $HADOLINT_VERSION 이미 설치됨"
else
  curl -fsSL -o "$work/hadolint" \
    "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/${HADOLINT_ASSET}"
  echo "${HADOLINT_SHA256}  $work/hadolint" | sha256sum -c -
  $SUDO install -m 0755 "$work/hadolint" "$BIN_DIR/hadolint"
fi

if have_version shellcheck "$SHELLCHECK_VERSION"; then
  echo "shellcheck $SHELLCHECK_VERSION 이미 설치됨"
else
  archive="shellcheck-v${SHELLCHECK_VERSION}.linux.${SHELLCHECK_ARCH}.tar.xz"
  curl -fsSL -o "$work/$archive" \
    "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/${archive}"
  echo "${SHELLCHECK_SHA256}  $work/$archive" | sha256sum -c -
  tar -xJf "$work/$archive" -C "$work"
  $SUDO install -m 0755 "$work/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" "$BIN_DIR/shellcheck"
fi

hadolint --version
shellcheck --version | sed -n '2p'
