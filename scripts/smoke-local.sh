#!/usr/bin/env bash
# 로컬 스모크 테스트: 학생 2명으로 띄워서 인증(401/200), 학생 간 격리, 자원 제한을 확인한다.
# 저장소의 lab/secrets를 건드리지 않도록 임시 폴더에 복사해서 돌린다.
# 프록시가 TLS를 가로채는 환경에서 이미지를 빌드하려면 LAB_EXTRA_CA=<CA 파일>을 준다.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
base="http://127.0.0.1:8080"
pass=0
fail=0

compose() { docker compose -f "$work/lab/out/compose.yaml" "$@"; }

cleanup() {
  compose down -v --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

check() { # check "설명" 명령...
  local name="$1"; shift
  if "$@"; then echo "PASS  $name"; pass=$((pass + 1)); else echo "FAIL  $name"; fail=$((fail + 1)); fi
}

# 비밀번호가 프로세스 인자에 드러나지 않도록 curl 설정을 stdin으로 넘긴다.
status() { # status 사용자 비밀번호 경로 -> HTTP 상태 코드
  local user="$1" pw="$2" path="$3"
  if [ -z "$user" ]; then
    curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$base$path"
  else
    printf 'user = "%s:%s"\n' "$user" "$pw" | curl -s -o /dev/null -w '%{http_code}' --max-time 10 -K - "$base$path"
  fi
}

fails() { ! "$@"; }

expect_status() { [ "$(status "$2" "$3" "$4")" = "$1" ]; }

mkdir -p "$work/lab"
cp -r "$repo/lab/image" "$repo/lab/labctl" "$work/lab/"
python3 "$work/lab/labctl" init --students 2
python3 "$work/lab/labctl" render --mode local

pw1="$(awk -F, '$1=="s01"{print $2}' "$work/lab/secrets/students.csv")"
pw2="$(awk -F, '$1=="s02"{print $2}' "$work/lab/secrets/students.csv")"

echo "== 이미지 빌드, 기동"
build_args=()
if [ -n "${LAB_EXTRA_CA:-}" ]; then build_args=(--secret "id=extra_ca,src=$LAB_EXTRA_CA"); fi
docker build "${build_args[@]}" -t campus-lab/student:1 "$work/lab/image" >/dev/null
compose up -d

echo "== 프록시가 뜰 때까지 대기"
for _ in $(seq 1 60); do
  [ "$(status "" "" /s01/)" = "401" ] && break
  sleep 1
done

echo "== 완료 기준 3: 인증"
check "인증 없이 /s01/ -> 401" expect_status 401 "" "" /s01/
check "s01 비밀번호로 /s01/ -> 200" expect_status 200 s01 "$pw1" /s01/
check "s02 비밀번호로 /s01/ -> 401" expect_status 401 s01 "$pw2" /s01/
check "s02 계정+비밀번호로 /s01/ -> 401" expect_status 401 s02 "$pw2" /s01/
check "s02 비밀번호로 /s02/ -> 200" expect_status 200 s02 "$pw2" /s02/

echo "== 완료 기준 4: 학생 간 격리"
s02_ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' lab-s02)"
check "s01에서 이름(s02)으로 해석 불가" fails docker exec lab-s01 getent hosts s02
check "s01에서 s02 주소($s02_ip:7681)로 접속 불가" \
  fails docker exec lab-s01 curl -s --max-time 3 -o /dev/null "http://$s02_ip:7681/"
check "s01에서 s02 주소로 ping 불가" fails docker exec lab-s01 ping -c 1 -W 2 "$s02_ip"
check "(대조) s01에서 프록시 이름은 해석됨" docker exec lab-s01 getent hosts proxy

echo "== 완료 기준 5: 자원 제한"
limits() { docker inspect -f "$1" "$2"; }
for sid in s01 s02; do
  check "$sid 메모리 512MiB" [ "$(limits '{{.HostConfig.Memory}}' lab-$sid)" = 536870912 ]
  check "$sid 스왑 포함 512MiB" [ "$(limits '{{.HostConfig.MemorySwap}}' lab-$sid)" = 536870912 ]
  check "$sid CPU 0.5" [ "$(limits '{{.HostConfig.NanoCpus}}' lab-$sid)" = 500000000 ]
  check "$sid PID 256" [ "$(limits '{{.HostConfig.PidsLimit}}' lab-$sid)" = 256 ]
  check "$sid privileged 아님" [ "$(limits '{{.HostConfig.Privileged}}' lab-$sid)" = false ]
  check "$sid 호스트 포트 게시 없음" [ "$(limits '{{len .HostConfig.PortBindings}}' lab-$sid)" = 0 ]
done

echo "== reset"
docker exec lab-s01 touch /home/student/marker
python3 "$work/lab/labctl" reset s01 --yes >/dev/null
check "reset 후 s01 홈의 marker 사라짐" fails docker exec lab-s01 test -e /home/student/marker

echo
echo "통과 $pass, 실패 $fail"
[ "$fail" -eq 0 ]
