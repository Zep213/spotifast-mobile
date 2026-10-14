#!/usr/bin/env bash
# Verifica se a máquina está pronta para compilar o spotifast para Android.
# Uso: scripts/check-android-env.sh [pasta-do-repo]   (padrão: pasta atual)
# Saída: PASS / WARN / FAIL por item. Código de saída 1 se houver algum FAIL.

REPO_DIR="${1:-.}"
FAILS=0
WARNS=0

pass() { printf '  [PASS] %s\n' "$1"; }
warn() { printf '  [WARN] %s\n         -> %s\n' "$1" "$2"; WARNS=$((WARNS + 1)); }
fail() { printf '  [FAIL] %s\n         -> %s\n' "$1" "$2"; FAILS=$((FAILS + 1)); }
have() { command -v "$1" >/dev/null 2>&1; }

echo "== Ambiente para spotifast no Android =="
echo "Repositório: $(cd "$REPO_DIR" 2>/dev/null && pwd || echo "$REPO_DIR")"
echo

echo "[1] Ferramentas básicas"
if have git; then pass "git: $(git --version)"; else fail "git não encontrado" "instale o git"; fi
if have rustup; then pass "rustup encontrado"; else fail "rustup não encontrado" "instale em https://rustup.rs"; fi
if have cargo; then pass "cargo encontrado"; else fail "cargo não encontrado" "instale o Rust via rustup"; fi

echo
echo "[2] Toolchain Rust"
PINNED=""
if [ -f "$REPO_DIR/rust-toolchain.toml" ]; then
  PINNED=$(grep -E '^[[:space:]]*channel[[:space:]]*=' "$REPO_DIR/rust-toolchain.toml" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
fi
if [ -z "$PINNED" ]; then
  warn "rust-toolchain.toml não encontrado ou sem 'channel'" "rode o script dentro do repositório ou passe o caminho dele"
  PINNED="1.98.0"
fi
echo "  versão exigida pelo projeto: $PINNED"
TC=""
if have rustup; then
  TC=$(rustup toolchain list 2>/dev/null | awk '{print $1}' | grep -E "^${PINNED}(-|$)" | head -1)
fi
if [ -n "$TC" ]; then
  pass "toolchain instalada: $TC ($(rustc +"$PINNED" --version 2>/dev/null))"
  INSTALLED_TARGETS=$(rustup target list --installed --toolchain "$TC" 2>/dev/null)
  for T in aarch64-linux-android x86_64-linux-android; do
    if printf '%s\n' "$INSTALLED_TARGETS" | grep -qx "$T"; then
      pass "alvo $T instalado"
    else
      fail "alvo $T ausente" "rustup target add $T --toolchain $PINNED"
    fi
  done
else
  fail "toolchain $PINNED não instalada" "rustup toolchain install $PINNED --profile minimal -c rustfmt -c clippy"
fi

echo
echo "[3] Android SDK e NDK"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -n "$SDK" ] && [ -d "$SDK" ]; then
  pass "Android SDK: $SDK"
  if ls "$SDK"/platforms/android-* >/dev/null 2>&1; then
    pass "plataformas instaladas: $(ls "$SDK"/platforms | tr '\n' ' ')"
  else
    fail "nenhuma plataforma Android em $SDK/platforms" "sdkmanager \"platforms;android-34\""
  fi
else
  fail "ANDROID_HOME/ANDROID_SDK_ROOT não definido ou pasta inexistente" "instale o Android SDK (Android Studio ou command-line tools) e exporte ANDROID_HOME"
fi
NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
if [ -z "$NDK" ] && [ -n "$SDK" ] && ls -d "$SDK"/ndk/* >/dev/null 2>&1; then
  NDK=$(ls -d "$SDK"/ndk/* | sort -V | tail -1)
fi
if [ -n "$NDK" ] && [ -d "$NDK" ]; then
  pass "NDK: $NDK"
  [ -n "${ANDROID_NDK_HOME:-}" ] || warn "ANDROID_NDK_HOME não está definido" "export ANDROID_NDK_HOME=\"$NDK\""
else
  fail "NDK não encontrado" "sdkmanager \"ndk;27.0.12077973\" (ou outra versão estável) e exporte ANDROID_NDK_HOME"
fi

echo
echo "[4] Java e empacotamento"
if have java; then pass "java: $(java -version 2>&1 | grep -m1 -E 'version' | sed -E 's/^.*(version "[^"]+").*$/\1/')"; else fail "java não encontrado" "instale um JDK 17 ou superior"; fi
PKG_FOUND=0
for P in "cargo-apk:cargo apk" "xbuild:x" "cargo-ndk:cargo ndk"; do
  BIN="${P%%:*}"
  if have "$BIN"; then pass "empacotador disponível: $BIN"; PKG_FOUND=1; fi
done
if [ "$PKG_FOUND" -eq 0 ]; then
  warn "nenhum empacotador (cargo-apk, xbuild ou cargo-ndk) instalado" "a Fase 1 decide qual usar; por exemplo: cargo install cargo-apk"
fi

echo
echo "[5] Dispositivo para teste"
if have adb; then
  DEVS=$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device"{print $1}')
  if [ -n "$DEVS" ]; then pass "dispositivo/emulador conectado: $(echo "$DEVS" | tr '\n' ' ')"
  else warn "adb encontrado, mas nenhum dispositivo conectado" "ligue a depuração USB ou inicie um emulador (AVD x86_64)"; fi
else
  warn "adb não encontrado" "adicione \$ANDROID_HOME/platform-tools ao PATH"
fi

echo
echo "[6] Recursos e conectividade"
FREE_KB=$(df -Pk "$REPO_DIR" 2>/dev/null | awk 'NR==2{print $4}')
if [ -n "$FREE_KB" ] && [ "$FREE_KB" -lt 10485760 ]; then
  warn "menos de 10 GB livres no disco" "builds Android com LTO ocupam vários GB"
elif [ -n "$FREE_KB" ]; then
  pass "espaço livre suficiente"
fi
if have curl; then
  CODE=$(curl -s -o /dev/null -m 15 -w '%{http_code}' https://index.crates.io/config.json 2>/dev/null)
  case "$CODE" in 2*|3*) pass "acesso ao índice do crates.io ($CODE)";; *) fail "sem acesso ao crates.io" "verifique rede e proxy";; esac
else
  warn "curl não encontrado" "não foi possível testar o acesso ao crates.io"
fi
# O cargo baixa as dependências por git (fastframe, forks do egui/winit/librespot).
if have git; then
  if timeout 30 git ls-remote https://github.com/crmne/fastframe HEAD >/dev/null 2>&1; then
    pass "acesso ao GitHub para dependências git"
  else
    fail "sem acesso ao GitHub (git ls-remote falhou)" "o projeto depende de forks em github.com/crmne; verifique rede, proxy e credenciais"
  fi
fi
have cmake && pass "cmake presente (só necessário para MilkDrop, que fica desligado no Android)" \
  || echo "  [INFO] cmake ausente: não é necessário no Android (MilkDrop desligado)"

echo
if [ "$FAILS" -gt 0 ]; then
  echo "RESULTADO: $FAILS falha(s), $WARNS aviso(s). Corrija as falhas antes de seguir para a Fase 1."
  exit 1
fi
echo "RESULTADO: ambiente OK ($WARNS aviso(s))."
exit 0
