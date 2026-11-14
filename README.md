# Space Mission Design Game (NASA Space Apps 2026)

Jogo em Godot 4 onde você projeta, valida e simula uma missão espacial.
Ande pela estação e sente na **sala de controle** para abrir o console de missão.

## Fluxo
1. **Objetivo científico** (define requisito de dados/dia e vida útil)
2. **Instrumentos** (massa, energia, dados, custo, confiabilidade)
3. **Energia** (painel solar), **Lançador**, **Órbita** e **Estação terrestre**
4. **Revisar projeto**: bloqueios (massa > lançador, custo > orçamento...) e avisos (energia, comunicação, órbita)
5. **Lançar missão**: simulação mensal com falhas e tempestades; relatório explica sucesso ou falha

As relações: massa×lançador×órbita, energia×eclipse×instrumentos, dados×downlink, custo×orçamento (por dificuldade), confiabilidade×vida útil.

**Todos os números são fictícios** (`scripts/mission.gd`). O sistema de sobrevivência da estação (comida, sono, reator) segue como camada de ambientação.

## Controles
WASD/setas andam, F interage, I mochila, 1 alterna astronauta/cientista.

## Referências
Paper CML (JPL) e webinar NASA "Design and Develop Science Missions": segmentos, requisitos, trade space, margens, riscos.
