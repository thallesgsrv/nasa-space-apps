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

## Testes
Testes automatizados headless (regras das missões, viagem, reinício, game over, todas as salas, objetos e minigames):

```
godot --headless res://tests/run_tests.tscn
```

Saída `N verificacoes, 0 falhas` e código de saída 0 quando tudo passa. Use Godot 4.6.
Na primeira vez (ou após adicionar assets) rode `godot --headless --import`.
