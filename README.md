# Nasa Space Apps 2026 — Jogo de sobrevivência e missões espaciais

Jogo 2D em **Godot 4.6** (GDScript). Você controla um astronauta numa estação/nave e, ao apertar **1**,
o cientista da base na Terra. Os dois lados precisam cooperar para completar as missões.

## Controles
| Tecla | Ação |
|---|---|
| WASD / setas | andar |
| F / Enter / Espaço | interagir / confirmar |
| I / Tab | mochila |
| M / J | menu de missões |
| V | rever o objetivo atual |
| 1 | alternar astronauta (estação) ↔ cientista (Terra) |
| Esc | cancelar / fechar |

## Multiplayer em LAN (2 jogadores)
No menu inicial: **MULTIPLAYER LAN**. Cooperativo assimétrico, na mesma rede Wi-Fi/cabo:
- **Host = astronauta** (estação). Escolhe **CRIAR SALA**, espera o outro jogador e aperta **INICIAR MISSÃO**.
- **Cliente = base na Terra (cientista)**. Escolhe **PROCURAR SALAS** (a sala aparece sozinha, por broadcast UDP) ou **ENTRAR POR IP**.
- A tecla **1** fica desativada: cada um tem o seu papel. A base vê o que só ela vê (previsão de perigos, análise da amostra, terminal solar) e suas decisões chegam ao astronauta em tempo real.
- O host roda toda a simulação (necessidades, viagem, eventos). O cliente recebe um espelho do estado ~10x/s; as decisões da base
  (`Missions.analyze_sample/verdict`, `Voyage.set_estimate/send_alert`, `Solar.decide`) são executadas no host (`Net.call_host`).
- Portas: **UDP 24565** (jogo, ENet) e **UDP 24566** (descoberta). Libere no firewall se necessário.
- Se o cientista sair, o host continua em modo solo (tecla 1 volta a funcionar). Se o host sair, o cliente volta ao menu.
- Código: `scripts/net.gd` (autoload `Net`), `scripts/lobby.gd`. Teste de integração (dois processos):
  `godot --headless res://tests/net_integration.tscn -- host` e, em outro terminal, `... -- client`.

## Missões
1. **Bionutrientes** — pegar a cultura de fungos, aquecer, centrifugar e enviar pela cápsula; a base analisa a placa de Petri e dá o veredito.
2. **Viagem** — escolher a rota na cadeira de comando. A base prevê perigos (comunicação, asteroide, reator); o astronauta faz as manobras.
3. **CME (tempestade solar)** — a base decide alertar ou ignorar; o astronauta ativa os escudos a tempo.

Em paralelo há a camada de sobrevivência: comida, água, sono, vida e temperatura do núcleo do reator.
Game over: núcleo a 100% por 12 s, falha da viagem (energia, combustível, tempo, colisão) ou vida zerada.

## Estrutura
- `scripts/game_state.gd` (autoload `GameState`): necessidades, inventário, cápsula, entrada.
- `scripts/missions.gd` (`Missions`), `scripts/voyage.gd` (`Voyage`), `scripts/solar.gd` (`Solar`): regras das missões.
- `scripts/interactions.gd` (`Interactions`): o que cada objeto interativo faz (`action` do `interactable.gd`).
- `scripts/ui/ui.gd` (`UI`): HUD, diálogos, menus e telas por cima do jogo; minigames em `scripts/ui/`.
- `scripts/lang.gd` (`Lang`): português (padrão) e inglês. Textos ficam em `tr("português")`; a tabela `EN` traduz.
- `scripts/audio.gd` (`Audio`): música por sala e efeitos. Salas sem arquivo em `assets/audio/music/` ficam em silêncio.
- `scenes/`: menu, cutscene, jogo e as salas (`rooms/`, `baseterrestre/`).

## Missão conectada (planejamento na Terra → voo → retorno → relatório)
- **Planejamento (CML 1 a 9)**: ao começar (depois do tutorial) o host escolhe *Planejar a missão* ou *Missão rápida* (= jogo antigo). Cada CML é uma decisão com custo/efeito e grava em `MissionState.params` (créditos, massa, capacidade do foguete, consumo, combustível, confiabilidade, comunicação, risco, peças, ciência). Código: `scripts/mission_state.gd` (autoload `MissionState`).
- **Consequências no voo**: `Voyage.start` usa massa/combustível/consumo/margem do projeto; o risco muda a chance de evento; os riscos **aceitos** no CML 7 aumentam a chance do evento correspondente; peça reserva (CML 4) amortece o superaquecimento do reator; comunicação (CML 3/5) afeta blecautes e a dica de reentrada.
- **Selos de origem** (REAL / RISCO / FICT): nenhum evento fictício é apresentado como registro da NASA. A tempestade solar usa registros reais de erupções (`data/space_events.json`, intensidade real, direção simulada) ou um feed vivo.
- **Feed NASA** (`scripts/nasa_feed.gd`): o jogo nunca chama `api.nasa.gov` direto. `tools/nasa_feed_proxy.py` (roda no servidor, com `NASA_API_KEY`) gera um JSON a partir do DONKI; sirva-o como arquivo estático e defina `NASA_FEED_URL` (ou a setting `nasa/feed_url`). Sem feed, o arquivo local é usado.
- **Retorno e relatório**: missão final *Retorno à Terra* na cadeira de comando (checklist, janela, reentrada) e relatório pós-missão (também mostrado à base no multiplayer e salvo em `user://last_report.json`).

## Testes
Testes automatizados headless (regras das missões, viagem, reinício, game over, todas as salas, objetos e minigames):

```
godot --headless res://tests/run_tests.tscn
```

Saída `N verificacoes, 0 falhas` e código de saída 0 quando tudo passa. Use Godot 4.6.
Na primeira vez (ou após adicionar assets) rode `godot --headless --import`.
