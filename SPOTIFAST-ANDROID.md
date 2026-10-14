# Spotifast Android — documento de ideia/PRD para o GSD

> **Como usar (Claude Code):**
> 1. Clone o fork do projeto e entre na pasta: `git clone https://github.com/crmne/spotifast.git spotifast-android && cd spotifast-android`
> 2. Coloque este arquivo na raiz do repositório e o script `check-android-env.sh` em `scripts/`.
> 3. **Antes de qualquer coisa**, rode `scripts/check-android-env.sh` e corrija todas as linhas `[FAIL]` (Fase 0, abaixo).
> 4. Rode `/gsd-new-project --auto @SPOTIFAST-ANDROID.md` (ou `/gsd-ingest-docs` se preferir tratar este arquivo como PRD).
> 5. Depois: `/gsd-plan-phase 0`, `/gsd-execute-phase 0`, `/gsd-verify-work` e repita por fase.
>
> O GSD está instalado com `npx @opengsd/gsd-core@latest --claude --global`. Reinicie o Claude Code depois de instalar.

---

## 1. Objetivo

Levar o **spotifast** (cliente Spotify nativo em Rust + egui, MIT) para **Android**, mantendo Rust e egui. É um projeto de **estudo pessoal**: um fork rodando no meu próprio celular ou emulador, com a minha conta Spotify Premium.

Resultado esperado: um APK de debug que abre, faz login, navega pela biblioteca, busca, toca música e continua tocando com a tela apagada.

**Fora do escopo:** iOS, publicação em loja, distribuição para terceiros, reescrever a interface em Kotlin e **qualquer download ou cache offline de músicas do Spotify** (ver seção 2).

## 2. Limites inegociáveis

- **Licença:** manter o `LICENSE` MIT e a atribuição ao autor original (crmne). O fork não é afiliado ao Spotify.
- **Conta:** playback exige Spotify Premium. Contas gratuitas só navegam e buscam.
- **Sem burlar proteção:** não implementar Lossless, não contornar DRM, não adicionar fontes alternativas de áudio do Spotify. A capacidade de playback vem do librespot e nada além dela.
- **Sem baixar músicas.** O spotifast toca por **streaming**, com a conta Premium; não existe um recurso de download e o app não deve ganhar um. Salvar o áudio do Spotify em arquivo seria contornar a proteção do serviço, e o `AGENTS.md` do projeto proíbe fontes alternativas de áudio. Por isso **não é preciso baixar nenhuma música** para desenvolver, e o celular precisa de internet para tocar. Para testar sem conta e sem rede de áudio, usar o modo `--demo`. Se um dia quiser tocar arquivos de áudio seus (MP3/FLAC próprios), isso seria um recurso separado e novo, fora deste documento.
- **Sem engenharia reversa do Spotify.** O REA **não** é usado neste projeto: o código-fonte está completo e aberto, e a skill do REA manda pular casos assim. Só poderia ser usado depois, no APK que nós mesmos gerarmos, para estudar a ferramenta.
- **Do `AGENTS.md` do projeto, que continua valendo no fork:** sem engine de navegador, sem telemetria, sem backend hospedado; credenciais nunca no log nem em JSON comum; nenhuma nova dependência sem comentário no `Cargo.toml` explicando o motivo.
- **Não quebrar o desktop:** toda mudança para Android fica atrás de `cfg(target_os = "android")` ou de módulos por alvo. `cargo check` no alvo Linux continua passando a cada fase.

## 3. Ambiente necessário (na máquina do desenvolvedor, não na nuvem)

A sessão em nuvem usada na preparação não consegue baixar o Rust nem o Android SDK, então **o build e os testes acontecem localmente**.

**Confira o ambiente com `scripts/check-android-env.sh`** (aceita o caminho do repositório como argumento). Ele verifica git, rustup/cargo, a toolchain exata de `rust-toolchain.toml` e os alvos Android, `ANDROID_HOME`, plataformas do SDK, NDK, Java, empacotador (`cargo-apk`, `xbuild` ou `cargo-ndk`), `adb` com dispositivo conectado, espaço em disco e acesso ao crates.io e ao GitHub (as dependências por git). Imprime `[PASS]`, `[WARN]` ou `[FAIL]` com a correção sugerida e sai com código 1 se houver `[FAIL]`. O Claude Code deve rodá-lo no início de toda sessão nova, e de novo se um build falhar por motivo de ambiente.

- Rust **1.98.0** (fixado em `rust-toolchain.toml`) com os alvos `aarch64-linux-android` e `x86_64-linux-android` (emulador).
- Android SDK + **NDK**, `ANDROID_HOME` e `ANDROID_NDK_HOME` definidos, JDK instalado.
- Ferramenta de empacotamento: decidir na Fase 1 entre `cargo-apk`, `xbuild` ou `cargo-ndk` + projeto Gradle mínimo (ver risco R1).
- Para MilkDrop o projeto usa CMake e libclang; no Android o recurso fica **desligado** (`--no-default-features`).
- Um celular com depuração USB ou um emulador. Para testar sem conta: `--features demo -- --demo`.

## 4. Estado atual do código (observado no clone)

- ~117 mil linhas de Rust, edição 2024, `rust-version = 1.98`.
- UI: `eframe`/`egui` 0.36 com backend `glow`, vindos de forks `crmne/egui` e `crmne/winit` fixados por commit em `[patch.crates-io]`.
- Playback/Connect: `librespot-*` 0.8, também de um fork `crmne/librespot`. Áudio local passa por `src/sink.rs` + `fastframe-audio` (cpal 0.18); o backend rodio do librespot é deliberadamente deixado de fora.
- Camada de plataforma: família de crates `fastframe-*` (tag v0.6.0) para tray, barra de título, instância única, controles de mídia, energia, arquivos, fontes, emoji, i18n.
- Credenciais: `keyring-core` com provedores só para macOS, Windows e Linux (`credentials.rs`).
- Módulos claramente de desktop em `src/`: `milkdrop*`, `winamp*`, `ui/winamp/`, `mac_notch.rs`, `notch.rs`, `thumbbar.rs`, `window.rs`, `single_instance.rs`, `opener.rs`, `cast.rs`, `sonos.rs`, `zeroconf.rs`, `appearance.rs`, `power.rs`.
- Arquitetura (do `AGENTS.md`): `src/ui/` desenha e emite `Action`; `src/app.rs` aplica as ações; rede e playback ficam no runtime de `src/backend.rs` e no engine de `src/player.rs`, nunca na thread de UI.

**Leitura obrigatória antes de mexer:** `AGENTS.md`, `CONTRIBUTING.md`, `docs/_reference/how-it-connects.md` (antes de tocar em auth, rede ou credenciais), `docs/_reference/queue.md` (antes de tocar na fila) e `docs/_reference/what-spotify-allows.md`.

## 5. Requisitos

| ID | Requisito |
|----|-----------|
| AND-00 | O ambiente de desenvolvimento passa em `scripts/check-android-env.sh` sem nenhum `[FAIL]`. |
| AND-01 | O projeto compila para `aarch64-linux-android` e gera um APK de debug instalável. |
| AND-02 | O alvo Linux desktop continua compilando e os testes existentes continuam passando. |
| AND-03 | O app abre no Android em modo `--demo` sem conta e mostra Home, Biblioteca, Busca, Fila e a barra do player. |
| AND-04 | A interface é usável com toque: alvos de toque adequados, rolagem por arrasto, layout de coluna única em tela estreita, navegação inferior em vez de barra lateral, teclado virtual nos campos de texto, orientação retrato e paisagem. |
| AND-05 | Login com conta Spotify Premium funciona no Android; a credencial fica em armazenamento seguro da plataforma (Android Keystore ou equivalente), nunca em JSON comum. |
| AND-06 | Playback real: tocar, pausar, avançar, voltar, buscar posição, volume, fila, shuffle e repeat. |
| AND-07 | A música continua com a tela apagada ou o app em segundo plano, via serviço em primeiro plano com notificação. |
| AND-08 | Controles de mídia do sistema (notificação, tela de bloqueio, fones) enviam comandos de volta ao app. |
| AND-09 | Tratamento do ciclo de vida: perda e retorno de rede, troca de saída de áudio, foco de áudio (chamada, outro app), suspensão e retomada. |
| AND-10 | Recursos só de desktop ficam desligados ou removidos no Android sem deixar caminhos mortos na interface. |

## 6. Fases propostas

Cada fase precisa terminar com `cargo check` no desktop verde e a verificação própria abaixo.

**Fase 0 — Ambiente verificado.**
Rodar `scripts/check-android-env.sh`, instalar o que faltar seguindo as sugestões que ele imprime (toolchain 1.98.0, alvos Android, SDK, NDK, JDK, empacotador, `adb`) e rodar de novo até não restar `[FAIL]`. Registrar em `.planning/` as versões encontradas (Rust, NDK, SDK, Java, empacotador) para as próximas fases.
*Verificação:* o script termina com "ambiente OK" e código de saída 0; `cargo check` no host compila o projeto (confirma que as dependências por git e o crates.io estão acessíveis).

**Fase 1 — Build Android mínimo.**
Isolar dependências e módulos só de desktop atrás de `cfg`; adicionar o alvo Android e a ferramenta de empacotamento; gerar um APK que abre uma tela do egui.
*Verificação:* `cargo check --target aarch64-linux-android` sem erros; APK abre no emulador; `cargo check` no host continua verde.

**Fase 2 — Modo demo no Android.**
Rodar o app completo com dados de exemplo (`--features demo`), sem login nem áudio. Resolver fontes, emoji, i18n, persistência e caminhos de arquivo (`paths.rs`) no Android.
*Verificação:* todas as telas principais renderizam no emulador em modo demo, sem panics nos logs.

**Fase 3 — Interface para toque.**
Layout responsivo de coluna única, navegação inferior, mini-player, tela "tocando agora" cheia, rolagem por gesto, teclado virtual, margens seguras (notch e barra de gestos), retrato e paisagem.
*Verificação:* revisão visual em pelo menos duas proporções de tela; sem alvos de toque menores que ~44 dp.

**Fase 4 — Login e credenciais.**
Fluxo de autenticação adequado ao celular e armazenamento seguro de credenciais. Ler `how-it-connects.md` primeiro.
*Verificação:* login, fechar o app, reabrir e continuar logado; nenhuma credencial em log ou arquivo de estado comum.

**Fase 5 — Áudio e playback.**
Sink de áudio funcionando no Android (conferir risco R3), controles de reprodução, fila, foco de áudio.
*Verificação:* tocar uma faixa de ponta a ponta no aparelho real; pausar, retomar, pular e mudar volume.

**Fase 6 — Segundo plano e controles de mídia.**
Serviço em primeiro plano com notificação, sessão de mídia, comandos de fones e tela de bloqueio, tratamento de rede e do ciclo de vida.
*Verificação:* tocar com tela apagada por 10+ minutos; trocar de rede; receber uma chamada simulada e retomar.

**Fase 7 — Estabilização.**
Testes, logs de bug report, consumo de bateria, README do fork com instruções de build Android.
*Verificação:* suíte de testes do projeto verde no host; checklist manual no aparelho.

## 7. Riscos e perguntas que a pesquisa de cada fase deve responder

- **R1 — eframe/egui no Android com os forks do crmne.** Confirmar se o `eframe` 0.36 do fork (backend `glow`) e o `winit` do fork suportam `android-activity`, e qual empacotador (`cargo-apk`, `xbuild`, `cargo-ndk`) funciona melhor com as features atuais. Pode exigir ajustar as features de `eframe` (`wayland`, `x11` não se aplicam).
- **R2 — Crates `fastframe-*`.** Verificar quais compilam no Android (`fastframe-audio`, `-file`, `-fonts`, `-emoji`, `-i18n`, `-log`, `-scroll`, `-power`, `-text`, `-theme`, `-icons`). Tray, titlebar, instance, shell, update e now-playing provavelmente precisam sair no Android. Se algum for necessário e não tiver suporte, abrir como dependência a tratar, sem copiar o código para o repositório (regra do projeto).
- **R3 — Áudio.** O projeto usa `cpal` 0.18 via `fastframe-audio` e evita o backend do librespot. Confirmar o suporte a AAudio/Oboe no Android, latência e comportamento ao pausar.
- **R4 — Credenciais.** `keyring-core` não tem provedor Android no `Cargo.toml` atual. Pesquisar o armazenamento seguro (Keystore) e como expô-lo ao Rust via JNI.
- **R5 — Auth.** Conferir como o fluxo OAuth do librespot funciona num celular (redirecionamento local, navegador do sistema, retorno ao app).
- **R6 — Descoberta de rede.** `mdns-sd` e `zeroconf.rs` exigem *multicast lock* no Android. Se não forem essenciais, desligar no Android.
- **R7 — Integração nativa.** Serviço em primeiro plano, notificação, MediaSession e foco de áudio exigem JNI ou classes Java/Kotlin mínimas. Definir o menor código nativo possível e isolá-lo.
- **R8 — Tamanho e tempo de build.** LTO e dependências pesadas deixam o build lento no NDK; documentar um perfil de build rápido para desenvolvimento.
- **R9 — Dependências por git.** `[patch.crates-io]` aponta para forks fixados; manter esses commits e não trocar por outras fontes.

## 8. Convenções de trabalho

- Um commit atômico por tarefa do GSD, com mensagem clara.
- Não ampliar o escopo nem refatorar de forma geral; preservar o comportamento do desktop.
- Não adicionar configurações novas; preferir bons padrões.
- Código novo de plataforma em módulos por alvo (por exemplo `src/android/`) com `cfg`.
- Cada fase termina com o resumo do que mudou, o que foi verificado e o que ainda depende de teste no aparelho.
