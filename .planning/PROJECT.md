# Spotifast Android

## What This Is

Um fork de estudo pessoal do **spotifast** (cliente Spotify nativo em Rust + egui, MIT, de crmne) portado para Android, mantendo Rust e egui. Roda no celular ou emulador do próprio desenvolvedor, usando a conta Spotify Premium pessoal. Não é afiliado ao Spotify, não vai para loja e não é distribuído a terceiros.

## Core Value

Um APK de debug que abre, faz login, navega pela biblioteca, busca, toca música via streaming (Premium) e continua tocando com a tela apagada — sem quebrar o build desktop existente.

## Requirements

### Validated

(Nenhum ainda — são capacidades existentes no desktop, não validadas no Android)

### Active

- [ ] AND-00: Ambiente de desenvolvimento passa em `scripts/check-android-env.sh` sem `[FAIL]`
- [ ] AND-01: Projeto compila para `aarch64-linux-android` e gera APK de debug instalável
- [ ] AND-02: Alvo Linux desktop continua compilando e os testes existentes continuam passando
- [ ] AND-03: App abre no Android em modo `--demo` sem conta, mostrando Home, Biblioteca, Busca, Fila e barra do player
- [ ] AND-04: Interface usável com toque — alvos de toque adequados, rolagem por arrasto, coluna única em tela estreita, navegação inferior, teclado virtual, retrato e paisagem
- [ ] AND-05: Login com conta Spotify Premium funciona no Android; credencial em armazenamento seguro da plataforma (Keystore), nunca em JSON comum
- [ ] AND-06: Playback real — tocar, pausar, avançar, voltar, buscar posição, volume, fila, shuffle, repeat
- [ ] AND-07: Música continua com tela apagada ou app em segundo plano, via serviço em primeiro plano com notificação
- [ ] AND-08: Controles de mídia do sistema (notificação, tela de bloqueio, fones) enviam comandos de volta ao app
- [ ] AND-09: Tratamento de ciclo de vida — perda/retorno de rede, troca de saída de áudio, foco de áudio, suspensão/retomada
- [ ] AND-10: Recursos só de desktop desligados ou removidos no Android sem caminhos mortos na interface

### Out of Scope

- iOS — fora do escopo deste fork de estudo
- Publicação em loja / distribuição a terceiros — é um projeto pessoal
- Reescrever a interface em Kotlin — mantém Rust + egui
- Download ou cache offline de músicas do Spotify — contornaria a proteção do serviço; playback é só streaming via librespot
- Engenharia reversa do Spotify (REA) — código já é aberto, não se aplica
- Burlar DRM, implementar Lossless ou adicionar fontes alternativas de áudio do Spotify — a capacidade de playback vem só do librespot

## Context

- ~117 mil linhas de Rust, edição 2024, `rust-version = 1.98`, fixado em `rust-toolchain.toml`.
- UI: `eframe`/`egui` 0.36 com backend `glow`, de forks `crmne/egui` e `crmne/winit` fixados por commit em `[patch.crates-io]`.
- Playback/Connect: `librespot-*` 0.8, do fork `crmne/librespot`. Áudio local via `src/sink.rs` + `fastframe-audio` (cpal 0.18); o backend rodio do librespot é deliberadamente deixado de fora.
- Camada de plataforma: família de crates `fastframe-*` (tag v0.6.0) para tray, barra de título, instância única, controles de mídia, energia, arquivos, fontes, emoji, i18n.
- Credenciais atuais: `keyring-core` com provedores só para macOS, Windows e Linux (`credentials.rs`) — sem provider Android.
- Módulos claramente de desktop em `src/`: `milkdrop*`, `winamp*`, `ui/winamp/`, `mac_notch.rs`, `notch.rs`, `thumbbar.rs`, `window.rs`, `single_instance.rs`, `opener.rs`, `cast.rs`, `sonos.rs`, `zeroconf.rs`, `appearance.rs`, `power.rs`.
- Arquitetura (do `AGENTS.md` do projeto original): `src/ui/` desenha e emite `Action`; `src/app.rs` aplica as ações; rede e playback ficam no runtime de `src/backend.rs` e no engine de `src/player.rs`, nunca na thread de UI.
- Leitura obrigatória antes de mexer: `AGENTS.md`, `CONTRIBUTING.md`, `docs/_reference/how-it-connects.md` (antes de auth/rede/credenciais), `docs/_reference/queue.md` (antes da fila), `docs/_reference/what-spotify-allows.md`.
- Ambiente local (2026-10-14): Rust 1.98.0 + alvos `aarch64-linux-android`/`x86_64-linux-android` instalados via rustup; Android SDK command-line tools (build 15859902) em `~/Android/Sdk`; platform android-34; NDK 27.0.12077973; Java 25.0.4.1 (OpenJDK). Faltam: empacotador (cargo-apk/xbuild/cargo-ndk, decidir na Fase 1) e dispositivo/emulador conectado.

## Constraints

- **Licença**: manter `LICENSE` MIT e atribuição ao autor original (crmne) — é a condição do fork.
- **Conta**: playback exige Spotify Premium; contas gratuitas só navegam/buscam.
- **Sem backend/telemetria**: do `AGENTS.md` do projeto original, que continua valendo no fork — sem engine de navegador, sem telemetria, sem backend hospedado.
- **Credenciais**: nunca em log nem em JSON comum — usar armazenamento seguro da plataforma.
- **Dependências**: nenhuma nova dependência no `Cargo.toml` sem comentário explicando o motivo.
- **Build desktop**: `cargo check` no alvo Linux precisa continuar passando a cada fase — mudanças Android ficam atrás de `cfg(target_os = "android")` ou módulos por alvo.
- **MilkDrop**: usa CMake/libclang no desktop; fica desligado no Android (`--no-default-features`).
- **Dependências git fixadas (R9)**: `[patch.crates-io]` aponta para forks de crmne fixados por commit; manter esses commits, não trocar de fonte.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Portar mantendo Rust + egui (não reescrever UI em Kotlin) | Preserva o código e a arquitetura existentes; objetivo é estudo, não reescrita | — Pending |
| Nenhum recurso de download/cache offline de áudio do Spotify | Contornaria a proteção do serviço e violaria `AGENTS.md` do projeto original | ✓ Good |
| Ambiente local via Android SDK command-line tools (sem Android Studio) | Mais leve, suficiente para `cargo`/`sdkmanager`/`adb`; evita baixar o Studio completo | ✓ Good |
| Toolchain Rust 1.98.0 pinada via rustup, alvos aarch64/x86_64-linux-android adicionados | Alinhado com `rust-toolchain.toml` do projeto original para builds reprodutíveis | ✓ Good |

## Evolution

Este documento evolui nas transições de fase e nos limites de milestone.

**Após cada transição de fase** (via `/gsd-transition`):
1. Requisitos invalidados? → Mover para Out of Scope com o motivo
2. Requisitos validados? → Mover para Validated com referência à fase
3. Novos requisitos surgiram? → Adicionar em Active
4. Decisões a registrar? → Adicionar em Key Decisions
5. "What This Is" ainda preciso? → Atualizar se houver desvio

**Após cada milestone** (via `/gsd:complete-milestone`):
1. Revisão completa de todas as seções
2. Checar o Core Value — ainda é a prioridade certa?
3. Auditar Out of Scope — motivos ainda válidos?
4. Atualizar Context com o estado atual

---
*Last updated: 2026-10-14 after initialization*
