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

## Multiplayer (até 4 jogadores, LAN ou internet)
No menu inicial: **MULTIPLAYER**. Cooperativo assimétrico; os papéis são atribuídos na ordem de entrada e podem ser trocados no lobby:
| Papel | Onde | O que faz |
|---|---|---|
| **Host = astronauta comandante** | estação | joga a missão inteira (mochila, viagem, tasks) e roda toda a simulação |
| **Base (cientista)** — 1º cliente | Terra | prevê perigos, analisa a amostra, dá o veredito, decide o alerta solar |
| **Engenheiro de voo** — 2º cliente | estação | anda na nave; resfria o núcleo e ativa os escudos (pedidos executados no host) |
| **Astronauta 2** — 3º cliente | estação | idem engenheiro |
- Cada jogador vê os outros como "fantasmas" (boneco + nome) quando estão na mesma sala; a posição é replicada ~12x/s.
- Um 5º jogador é recusado. Se um jogador sai, a missão continua; se o host sai, os clientes voltam ao menu.
- **LAN (ENet/UDP)**: host em **CRIAR SALA NA LAN**; os outros em **PROCURAR SALAS NA LAN** (broadcast) ou **ENTRAR POR IP**. Portas: UDP **24565** (jogo) e **24566** (descoberta).
- **Internet / navegador (WebSocket)**: o host (executável desktop) escolhe **CRIAR SALA NA INTERNET**, que abre a porta TCP **24567**; os outros entram em **ENTRAR POR ENDEREÇO** com `ws://IP-DO-HOST:24567` (no navegador só existe esta opção). Para `wss://` coloque um proxy TLS na frente. O host precisa de porta liberada no roteador/firewall (ou um túnel).
- O host roda toda a simulação (necessidades, viagem, eventos). Os clientes recebem um espelho do estado ~10x/s; as decisões saem por `Net.call_host` e só passam se o **papel** do cliente permitir (`Net.CALL_ROLES`): a base decide pela Terra, a tripulação mexe em núcleo/escudos.
- Código: `scripts/net.gd` (autoload `Net`), `scripts/lobby.gd`, `scripts/ghost.gd`.
- Teste de integração com 4 jogadores + 1 recusado: `tools/run_net_tests.sh /caminho/godot ws` (ou `enet`). O teste antigo de 2 jogadores continua em `tests/net_integration.tscn -- host|client`.

### Exportar para o navegador
`export_presets.cfg` traz os presets **Web** (sem threads, não exige cabeçalhos COOP/COEP) e **Linux**. Instale os *export templates* do Godot 4.6 e rode, por exemplo,
`godot --headless --export-release "Web" build/web/index.html`. Sirva a pasta `build/web` por HTTPS. O navegador só consegue **entrar** em salas; o host é um executável desktop.
> Os presets foram escritos à mão e ainda **não foram exportados** (faltam os templates no ambiente onde foram criados): valide o primeiro export e o tamanho do `.pck` (~37 MB de assets).

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
