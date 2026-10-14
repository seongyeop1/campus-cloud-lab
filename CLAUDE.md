# Campus Cloud Lab — 작업 안내 (Claude Code용)

브라우저로 쓰는 리눅스 실습실 프로토타입. 학생마다 격리된 우분투 컨테이너(웹 터미널)를 EC2 한 대에 띄우고, Caddy가 HTTPS와 학생별 인증을 맡는다. 인프라는 Terraform으로 만든다. 전체 그림은 README.md, 설계 이유는 docs/decisions.md.

작업은 단계별로 한다. 한 세션에서 한 단계만 하고, 단계마다 PR 하나로 올린다. 시작하기 전에 README의 진행 단계를 보고 어디까지 됐는지 확인한다.

## 꼭 지킬 것

- **AWS 자격 증명을 요구하거나 저장하지 않는다.** `terraform plan/apply`, `aws` CLI 같은 실제 계정 호출은 하지 않는다. 검증은 `fmt`, `validate`, 정적 분석까지만.
- **평문 비밀번호, 개인 키, `*.tfstate`, `*.tfvars`는 커밋하지 않는다.** 테스트용 비밀번호도 실행할 때 만든다. 커밋 전에 `git status`로 확인한다.
- **`.github/workflows/`는 고치지 않는다.** 클라우드 세션에서는 워크플로 파일 push가 거절된다. 워크플로는 `scripts/install-tools.sh`와 `scripts/ci.sh`를 부르기만 하니, CI 내용은 이 두 스크립트에서 바꾼다.
- 베이스 이미지, 도구, 받는 바이너리는 버전을 고정하고, 바이너리는 체크섬을 확인한다.
- 학생 컨테이너에 privileged, 호스트 네트워크, docker.sock 마운트를 쓰지 않는다.
- 완료 기준은 직접 실행해서 확인하고, 명령과 결과 요약을 PR 설명에 남긴다. 확인하지 못한 항목은 못 했다고 적는다.
- 문서는 한국어로 짧고 구체적으로 쓴다. 명령은 복사해서 바로 돌아가게 쓴다.
- 결정이 바뀌거나 새로 생기면 docs/decisions.md에 덧붙인다.

## 1단계: 실습 컨테이너와 로컬 실행 (`lab/`)

만들 것

- `lab/image/Dockerfile`: `ubuntu:24.04` 기반. 리눅스 실습 도구(bash-completion, vim, nano, less, gcc, make, python3, git, curl, iproute2, iputils-ping, tree, htop, sudo 등), ttyd(GitHub 릴리스 고정 버전, 체크섬 확인), sudo를 쓸 수 있는 `student` 사용자.
- `lab/labctl`: 파이썬 표준 라이브러리만 쓰는 관리 도구.
  - `init --students N`: 학생별 무작위 비밀번호 생성. 평문 명단은 `lab/secrets/`(gitignore)에만 둔다.
  - `render --mode local|deploy [--domain ...]`: `compose.yaml`과 `Caddyfile` 생성. 로컬 모드는 `http://localhost:8080`, 배포 모드는 자동 HTTPS(실패 대비 `tls internal` 옵션).
  - `reset sNN`: 해당 학생 홈 초기화.
- 생성되는 compose 구성: Caddy 프록시 + 학생 컨테이너 `s01`..`sNN`. 학생마다 별도 네트워크(프록시만 전부에 연결), 메모리 512MB · CPU 0.5 · PID 256 제한, 홈 디렉터리 볼륨, 학생 컨테이너는 포트를 바깥에 열지 않음.
- 비밀번호 해시는 Caddy가 받아들이는 형식(bcrypt)으로 만든다. 방법은 자유(예: `caddy hash-password`를 컨테이너로 실행).
- `scripts/ci.sh`: 1단계 검사(hadolint, shellcheck, labctl 단위 테스트, 이미지 빌드). 단계가 늘면 여기에 더한다. 폴더가 없는 검사는 건너뛰게 한다.
- `scripts/smoke-local.sh`: 아래 완료 기준 3~5를 자동으로 확인.
- `docs/local.md`: 로컬에서 띄우고 접속하고 끄는 방법.

완료 기준 (전부 실제로 실행)

1. hadolint, shellcheck 경고 없음.
2. `python3 -m unittest`로 labctl 테스트 통과.
3. 학생 2명으로 `docker compose up` 후 프록시를 거쳐 s01에 접속: 인증 없으면 401, 맞는 비밀번호면 200, 다른 학생 비밀번호로는 실패.
4. s01 컨테이너에서 s02로 접근 불가(이름·주소 모두).
5. `docker inspect`로 메모리·CPU·PID 제한 확인.
6. `git status`에 비밀번호나 키 파일이 보이지 않음.

## 2단계: AWS 배포 코드 (`infra/terraform/`)

만들 것

- 서울 리전(`ap-northeast-2`). 변수: `student_count`, `allowed_cidrs`(기본값 없음, 필수), `instance_type`(기본 `t3.small`), `lab_repo_url`, `lab_repo_ref`(고정 커밋이나 태그).
- 네트워크: 퍼블릭 서브넷 하나짜리 작은 VPC 또는 기본 VPC. 고른 이유를 decisions.md에.
- 보안 그룹: 80/443만 `allowed_cidrs`에서. 22번은 열지 않는다.
- EC2: Ubuntu 24.04 AMI(data source, Canonical 소유자 ID), IMDSv2 필수, gp3 루트 볼륨 암호화, AmazonSSMManagedInstanceCore만 붙인 인스턴스 프로파일.
- user_data(cloud-init): Docker 설치, userns-remap 설정, 저장소를 고정 ref로 받아 `labctl init/render` 후 `docker compose up -d`.
- 출력: 접속 주소, 인스턴스 ID, 학생 명단을 SSM으로 확인하는 명령.
- `docs/deploy.md`: 관리자 PC에서 할 일 순서. AWS Budgets 알림 → `terraform apply` → 접속 확인 → 명단 배포 → `terraform destroy` → 지워졌는지 확인.
- `scripts/ci.sh`에 Terraform 검사 추가.

완료 기준

1. `terraform fmt -check`, `terraform init -backend=false`, `terraform validate` 통과.
2. tflint 경고 없음.
3. checkov 또는 `trivy config`에서 HIGH 이상 0건. 남기는 경고는 이유를 `docs/security.md`에.
4. plan/apply는 하지 않는다.

## 3단계: CI와 보안 스캔

만들 것

- `scripts/install-tools.sh`: hadolint, shellcheck, tflint, terraform, trivy를 고정 버전으로 설치(체크섬 확인). GitHub Actions의 ubuntu-24.04 러너와 클라우드 세션 둘 다에서 돌아야 한다.
- `scripts/ci.sh`: 1·2단계 검사 + 실습 이미지 `trivy image`(CRITICAL 0건) + `trivy config` + SBOM 파일 생성.
- `docs/architecture.md`: 구성도와 요청 흐름(mermaid).
- `docs/security.md`: 위협 모델. 학생 간 접근, 컨테이너 탈출, 자격 증명 노출, 자원 남용(채굴 등)과 각각의 대응.
- `docs/report-notes.md`: 보고서에 쓸 실측 수치. 이미지 크기, 컨테이너 시작 시간, 학생 한 명당 메모리, 30명 기준 월 비용 계산식(시간당 가격은 변수로 두고 출처 표시).

완료 기준

1. 클라우드 세션에서 `bash scripts/install-tools.sh && bash scripts/ci.sh`가 처음부터 끝까지 통과.
2. trivy CRITICAL 0건. HIGH가 남으면 목록과 이유를 security.md에.

## 4단계 (선택)

- 수업 시간 밖에는 EC2 자동 중지·시작(EventBridge Scheduler).
- k3s 버전: 학생별 네임스페이스, NetworkPolicy, ResourceQuota.
