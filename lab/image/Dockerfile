FROM ubuntu:24.04

ARG TTYD_VERSION=1.7.7
ARG TTYD_SHA256_X86_64=8a217c968aba172e0dbf3f34447218dc015bc4d5e59bf51db2f2cd12b7be4f55
ARG TTYD_SHA256_AARCH64=b38acadd89d1d396a0f5649aa52c539edbad07f4bc7348b27b4f4b7219dd4165

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# apt 패키지 버전은 고정하지 않는다: 우분투 저장소는 옛 버전을 지워서 고정하면 빌드가 깨진다.
# 대신 베이스 이미지 태그를 고정하고, 재현성은 이미지 스캔(3단계)으로 확인한다.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash-completion ca-certificates curl file gcc git htop iproute2 iputils-ping \
        less make nano procps python3 sudo tree vim \
    && rm -rf /var/lib/apt/lists/*

# ttyd: GitHub 릴리스 바이너리를 받아 체크섬을 확인한다.
# TLS를 가로채는 프록시 뒤에서 빌드할 때만 추가 CA 파일을 시크릿(extra_ca)으로 넘긴다. 없으면 시스템 CA만 쓴다.
RUN --mount=type=secret,id=extra_ca,required=false \
    arch="$(uname -m)" \
    && case "$arch" in \
         x86_64) sha="$TTYD_SHA256_X86_64" ;; \
         aarch64) sha="$TTYD_SHA256_AARCH64" ;; \
         *) echo "지원하지 않는 CPU: $arch" >&2; exit 1 ;; \
       esac \
    && ca=() \
    && if [ -s /run/secrets/extra_ca ]; then ca=(--cacert /run/secrets/extra_ca); fi \
    && curl -fsSL "${ca[@]}" -o /usr/local/bin/ttyd \
         "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${arch}" \
    && echo "${sha}  /usr/local/bin/ttyd" | sha256sum -c - \
    && chmod 0755 /usr/local/bin/ttyd

# 베이스 이미지의 기본 사용자(ubuntu, uid 1000)를 지우고 student가 그 자리를 쓴다.
RUN userdel -r ubuntu \
    && useradd -m -u 1000 -s /bin/bash student \
    && echo 'student ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/student \
    && chmod 0440 /etc/sudoers.d/student

COPY entrypoint.sh /usr/local/bin/lab-entrypoint
RUN chmod 0755 /usr/local/bin/lab-entrypoint

USER student
WORKDIR /home/student
EXPOSE 7681
ENTRYPOINT ["/usr/local/bin/lab-entrypoint"]
