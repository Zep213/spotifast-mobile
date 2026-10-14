#!/usr/bin/env bash
# Roda os mesmos gates de desktop (Linux) que o CI roda: fmt, check, clippy,
# test. O host pode não ter pkg-config/ALSA/cmake -- nesse caso o script usa
# Docker (imagem rust:1.98.0-bookworm) automaticamente.
# Uso: scripts/desktop-check.sh [--quick] [--host|--docker]
#   --quick   roda só fmt e check (gate rápido)
#   --host    força execução direto no host (falha se faltar pkg-config/alsa/cmake)
#   --docker  força execução em container Docker, mesmo se o host tiver os pacotes
# Sem flag de modo: roda os quatro gates (fmt, check, clippy, test).
# Saída: uma linha "GATE <nome>: PASS|FAIL" por gate, depois
# "DESKTOP_CHECK: PASS" ou "DESKTOP_CHECK: FAIL (<gates que falharam>)".
# Log completo (tee) em target/desktop-ci/desktop-check-<timestamp-UTC>.log.
# Código de saída: 1 se algum gate falhou, 0 se todos passaram.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

QUICK=0
MODE="auto"

for arg in "$@"; do
  case "$arg" in
    --quick) QUICK=1 ;;
    --host) MODE="host" ;;
    --docker) MODE="docker" ;;
    *)
      echo "Uso: scripts/desktop-check.sh [--quick] [--host|--docker]" >&2
      exit 2
      ;;
  esac
done

mkdir -p target/desktop-ci
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE="target/desktop-ci/desktop-check-${TIMESTAMP}.log"

# Tudo a partir daqui também vai para o log, via tee.
exec > >(tee -a "$LOG_FILE") 2>&1

echo "== Desktop check (desktop-check.sh) =="
echo "Repositório: $REPO_ROOT"
echo "Modo solicitado: $MODE | quick=$QUICK"
echo "Log: $LOG_FILE"
echo

# Modo auto: usa o host só se pkg-config encontrar alsa+libpulse e cmake existir.
if [ "$MODE" = "auto" ]; then
  if command -v pkg-config >/dev/null 2>&1 \
     && pkg-config --exists alsa libpulse 2>/dev/null \
     && command -v cmake >/dev/null 2>&1; then
    MODE="host"
  else
    MODE="docker"
  fi
  echo "Modo detectado automaticamente: $MODE"
  echo
fi

declare -a GATE_NAMES=()
declare -a GATE_RESULTS=()

record_gate() {
  local name="$1" status="$2"
  GATE_NAMES+=("$name")
  GATE_RESULTS+=("$status")
  echo "GATE ${name}: ${status}"
}

run_host() {
  export CARGO_TARGET_DIR="target/desktop-ci"
  export CARGO_BUILD_JOBS=4

  echo "--- fmt ---"
  if cargo fmt --all --check; then record_gate fmt PASS; else record_gate fmt FAIL; fi

  echo "--- check ---"
  if cargo check --locked; then record_gate check PASS; else record_gate check FAIL; fi

  if [ "$QUICK" -eq 1 ]; then
    return
  fi

  echo "--- clippy ---"
  if cargo clippy --locked --all-targets -- -D warnings; then record_gate clippy PASS; else record_gate clippy FAIL; fi

  echo "--- test ---"
  if cargo test --locked --all-targets; then record_gate test PASS; else record_gate test FAIL; fi
}

build_docker_image() {
  local tag="spotifast-desktop-ci:1.98.0"
  if docker image inspect "$tag" >/dev/null 2>&1; then
    echo "Imagem Docker $tag já existe, reaproveitando."
    return 0
  fi
  echo "Construindo imagem Docker $tag (primeira vez, pode demorar)..."
  docker build -t "$tag" - <<'DOCKERFILE'
FROM rust:1.98.0-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config libasound2-dev libpulse-dev libxkbcommon-dev \
    libwayland-dev libgl1-mesa-dev cmake libclang-dev clang dbus \
    && rm -rf /var/lib/apt/lists/*
RUN rustup toolchain install 1.98.0 --profile minimal -c rustfmt -c clippy \
    && chmod -R a+rwX /usr/local/rustup /usr/local/cargo
DOCKERFILE
}

run_docker() {
  if ! build_docker_image; then
    echo "ERRO: falha ao construir a imagem Docker spotifast-desktop-ci:1.98.0." >&2
    echo "Alternativa manual no host (requer senha de sudo):" >&2
    echo "  sudo apt-get update && sudo apt-get install -y pkg-config libasound2-dev libpulse-dev libxkbcommon-dev libwayland-dev libgl1-mesa-dev cmake libclang-dev clang dbus" >&2
    echo "AND-02 não pôde ser verificado nesta máquina (build da imagem Docker falhou)." >&2
    record_gate docker-image FAIL
    return
  fi

  local gates="fmt check"
  if [ "$QUICK" -ne 1 ]; then
    gates="fmt check clippy test"
  fi

  # Comandos executados dentro do container, um por linha, cada um prefixado
  # com GATE_START/GATE_END para que o host saiba o resultado de cada gate.
  local script='set -u
mkdir -p "$CARGO_TARGET_DIR"
RESULT=0
for gate in '"$gates"'; do
  case "$gate" in
    fmt) cmd="cargo fmt --all --check" ;;
    check) cmd="cargo check --locked" ;;
    clippy) cmd="cargo clippy --locked --all-targets -- -D warnings" ;;
    test) cmd="cargo test --locked --all-targets" ;;
  esac
  echo "--- $gate ---"
  if $cmd; then
    echo "GATE_RESULT $gate PASS"
  else
    echo "GATE_RESULT $gate FAIL"
    RESULT=1
  fi
done
exit $RESULT'

  local docker_out
  docker_out=$(mktemp)
  # --ulimit nofile: the test suite opens many sockets/temp files in
  # parallel (mpris/dbus private buses, image cache, async runtimes per
  # test). Docker's default (1024) is exhausted long before the suite
  # finishes and produces "Too many open files" failures that are an
  # artifact of this container, not of spotifast's code.
  docker run --rm --user "$(id -u):$(id -g)" \
    --ulimit nofile=65536:65536 \
    -e HOME=/tmp/home \
    -e CARGO_TARGET_DIR=/src/target/desktop-ci \
    -e CARGO_BUILD_JOBS=4 \
    -v "$REPO_ROOT":/src \
    -v "$HOME/.cargo/registry":/usr/local/cargo/registry \
    -v "$HOME/.cargo/git":/usr/local/cargo/git \
    -w /src \
    spotifast-desktop-ci:1.98.0 \
    bash -c "$script" | tee "$docker_out"

  for gate in $gates; do
    local line status
    line=$(grep "^GATE_RESULT ${gate} " "$docker_out" | tail -1)
    status=$(echo "$line" | awk '{print $3}')
    if [ "$status" = "PASS" ] || [ "$status" = "FAIL" ]; then
      record_gate "$gate" "$status"
    else
      record_gate "$gate" FAIL
    fi
  done
  rm -f "$docker_out"
}

if [ "$MODE" = "host" ]; then
  run_host
else
  run_docker
fi

echo
FAILED_GATES=()
for i in "${!GATE_NAMES[@]}"; do
  if [ "${GATE_RESULTS[$i]}" != "PASS" ]; then
    FAILED_GATES+=("${GATE_NAMES[$i]}")
  fi
done

if [ "${#FAILED_GATES[@]}" -eq 0 ] && [ "${#GATE_NAMES[@]}" -gt 0 ]; then
  echo "DESKTOP_CHECK: PASS"
  EXIT_CODE=0
else
  echo "DESKTOP_CHECK: FAIL (${FAILED_GATES[*]})"
  EXIT_CODE=1
fi

exit "$EXIT_CODE"
