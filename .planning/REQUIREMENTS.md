# Requirements: Spotifast Android

**Defined:** 2026-10-14
**Core Value:** Um APK de debug que abre, faz login, navega pela biblioteca, busca, toca música via streaming (Premium) e continua tocando com a tela apagada — sem quebrar o build desktop existente.

## v1 Requirements

Requisitos para este milestone (port completo para Android). Cada um mapeia para uma fase do roadmap.

### Ambiente (ENV)

- [ ] **AND-00**: O ambiente de desenvolvimento passa em `scripts/check-android-env.sh` sem nenhum `[FAIL]`

### Build (BUILD)

- [ ] **AND-01**: O projeto compila para `aarch64-linux-android` e gera um APK de debug instalável
- [ ] **AND-02**: O alvo Linux desktop continua compilando e os testes existentes continuam passando

### Limpeza de Plataforma (PLATFORM)

- [ ] **AND-10**: Recursos só de desktop ficam desligados ou removidos no Android sem deixar caminhos mortos na interface

### Interface Touch (UI)

- [ ] **AND-03**: O app abre no Android em modo `--demo` sem conta e mostra Home, Biblioteca, Busca, Fila e a barra do player
- [ ] **AND-04**: A interface é usável com toque — alvos de toque adequados, rolagem por arrasto, coluna única em tela estreita, navegação inferior, teclado virtual, retrato e paisagem

### Autenticação (AUTH)

- [ ] **AND-05**: Login com conta Spotify Premium funciona no Android; credencial em armazenamento seguro da plataforma (Android Keystore), nunca em JSON comum

### Playback (PLAY)

- [ ] **AND-06**: Playback real — tocar, pausar, avançar, voltar, buscar posição, volume, fila, shuffle, repeat

### Segundo Plano e Mídia (BG)

- [ ] **AND-07**: A música continua com a tela apagada ou o app em segundo plano, via serviço em primeiro plano com notificação
- [ ] **AND-08**: Controles de mídia do sistema (notificação, tela de bloqueio, fones) enviam comandos de volta ao app
- [ ] **AND-09**: Tratamento do ciclo de vida — perda e retorno de rede, troca de saída de áudio, foco de áudio, suspensão e retomada

## v2 Requirements

Nenhum — o escopo deste milestone é o port completo definido no PRD (`SPOTIFAST-ANDROID.md`). Diferenciais identificados pela pesquisa (ver Out of Scope) ficam fora até uma eventual nova iteração, não como v2 planejado.

## Out of Scope

Exclusões explícitas do PRD e da pesquisa de domínio, para evitar scope creep.

| Feature | Reason |
|---------|--------|
| iOS | Fora do escopo deste fork de estudo |
| Publicação em loja / distribuição a terceiros | Projeto pessoal, nunca publicado |
| Reescrever a interface em Kotlin | Objetivo é manter Rust + egui |
| Download ou cache offline de músicas do Spotify | Contornaria a proteção do serviço; playback é só streaming via librespot |
| Engenharia reversa do Spotify (REA) | Código-fonte já é aberto; REA não se aplica |
| Burlar DRM, Lossless, fontes alternativas de áudio | A capacidade de playback vem só do librespot, nada além |
| Android Auto / Automotive OS | Sem público para um app pessoal nunca publicado; conflita com o objetivo de superfície nativa mínima (risco R7) |
| Widget de tela inicial, App Actions / integração por voz | Diferenciais reais, mas sem usuário além do próprio desenvolvedor |
| Edge-to-edge, predictive back, splash screen, ícone adaptativo | Polimento visual, não necessário para a app não parecer "quebrada" |
| Play Integrity, AAB, Play Billing, Crashlytics/telemetria, formulário Data Safety, ProGuard/R8 | Custos de conformidade de loja — não se aplicam a um debug APK carregado via sideload; telemetria é proibida pelo `AGENTS.md` de qualquer forma |

## Traceability

Fases conforme a estrutura recomendada pela pesquisa de domínio (`.planning/research/SUMMARY.md`), alinhada aos riscos R1-R9 do PRD.

| Requirement | Phase | Status |
|-------------|-------|--------|
| AND-00 | Phase 1 | Pending |
| AND-01 | Phase 1 | Pending |
| AND-02 | Phase 1 | Pending |
| AND-10 | Phase 2 | Pending |
| AND-03 | Phase 3 | Pending |
| AND-04 | Phase 3 | Pending |
| AND-05 | Phase 4 | Pending |
| AND-06 | Phase 5 | Pending |
| AND-07 | Phase 6 | Pending |
| AND-08 | Phase 6 | Pending |
| AND-09 | Phase 6 | Pending |

**Coverage:**
- v1 requirements: 11 total
- Mapeados em fases: 11
- Não mapeados: 0 ✓

(Phase 7 — Estabilização — é verificação cruzada de AND-01 a AND-09 em dispositivo real, sem requisito novo próprio.)

---
*Requirements defined: 2026-10-14*
*Last updated: 2026-10-14 after initial definition*
