# 로컬에서 실행하기

Docker(Compose v2)와 Python 3만 있으면 된다. 아래는 모두 저장소 루트에서 실행한다.

## 1. 띄우기

```bash
python3 lab/labctl init --students 3        # 학생 3명 비밀번호 생성 (lab/secrets/, 커밋 금지)
python3 lab/labctl render --mode local      # lab/out/compose.yaml, Caddyfile 생성
docker compose -f lab/out/compose.yaml up -d --build
```

처음에는 이미지를 빌드해서 1~2분 걸린다.
HTTPS를 가로채는 프록시 뒤에서 빌드가 인증서 오류로 실패하면, 프록시 CA 파일을 넘겨서 직접 빌드한 뒤 `up`을 한다.

```bash
docker build --secret id=extra_ca,src=<CA 파일 경로> -t campus-lab/student:1 lab/image
docker compose -f lab/out/compose.yaml up -d
```

## 2. 접속하기

- 주소: `http://localhost:8080/s01/` (학생 번호에 맞춰 `/s02/`, ...)
- 사용자 이름은 `s01`, 비밀번호는 `lab/secrets/students.csv`에서 찾는다.

```bash
grep '^s01,' lab/secrets/students.csv
```

학생은 자기 주소에서 자기 비밀번호로만 들어갈 수 있다. 다른 학생의 비밀번호로는 401이 나온다.

## 3. 관리

```bash
docker compose -f lab/out/compose.yaml ps            # 상태
python3 lab/labctl reset s01                         # s01 홈 초기화 (확인 질문 있음, --yes로 생략)
```

## 4. 끄기

```bash
docker compose -f lab/out/compose.yaml down          # 컨테이너만 내림, 학생 홈은 남음
docker compose -f lab/out/compose.yaml down -v       # 학생 홈 볼륨까지 삭제
```

비밀번호를 새로 만들려면 `python3 lab/labctl init --students N --force` 후 `render`를 다시 하고 `up -d`.
기존 비밀번호는 무효가 된다.

## 자동 확인

```bash
bash scripts/smoke-local.sh   # 임시 폴더에서 2명을 띄워 인증·격리·자원 제한을 확인하고 정리한다
```
