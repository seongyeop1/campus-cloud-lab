#!/usr/bin/env bash
# 전체 검사. 단계가 늘면 아래에 더한다. 폴더가 없는 검사는 건너뛴다.
# 도구는 먼저 `bash scripts/install-tools.sh`로 설치한다.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "$1 없음. 먼저 bash scripts/install-tools.sh" >&2; exit 1; }
}

step() { printf '\n== %s\n' "$*"; }

# --- 1단계: lab/ ---
if [ -d lab ]; then
  need shellcheck
  step "shellcheck"
  mapfile -t shell_files < <(find scripts lab -name '*.sh' -not -path '*/secrets/*' | sort)
  shellcheck "${shell_files[@]}"

  if [ -f lab/image/Dockerfile ]; then
    need hadolint
    step "hadolint"
    hadolint lab/image/Dockerfile
  fi

  if [ -f lab/labctl ]; then
    step "labctl 단위 테스트"
    (cd lab && python3 -m unittest)
  fi

  if [ -f lab/image/Dockerfile ]; then
    step "실습 이미지 빌드"
    need docker
    build_args=()
    # TLS를 가로채는 프록시 뒤에서만 쓴다: LAB_EXTRA_CA=<CA 파일>
    if [ -n "${LAB_EXTRA_CA:-}" ]; then build_args=(--secret "id=extra_ca,src=$LAB_EXTRA_CA"); fi
    docker build "${build_args[@]}" -t campus-lab/student:1 lab/image
  fi
fi

# --- 2단계: infra/terraform/ (추가 예정) ---

echo
echo "ci.sh: 모두 통과"
