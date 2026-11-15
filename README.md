# Terra Chamando

Jogo 2D cooperativo feito em Godot para o NASA Space Apps Challenge 2026, no desafio **Space Mission Design Game**. A equipe planeja uma missão espacial na Terra, executa a viagem dentro da nave e, no fim, recebe um relatório que mostra o que cada decisão do planejamento causou no espaço.

Até 4 jogadores, em LAN ou pela internet. Também dá para jogar sozinho.

**Jogar no navegador:** https://thallesgsrv.github.io/nasa-space-apps/

## O desafio

O Space Mission Design Game pede um jogo em que o usuário planeja e executa a própria missão espacial. Aqui, o planejamento segue os nove níveis de maturidade de conceito (CML) da NASA, e o que a equipe decide neles vira os parâmetros reais do voo, em vez de ficar só como menu de abertura.

## A ideia

Na cutscene de abertura, o cientista da Central da Terra confere reator, propulsão e comunicações com a nave. A tripulação responde que está tudo pronto, e os dois lados combinam o que vale para o jogo inteiro: a nave faz as manobras, a Terra faz as previsões.

Antes disso, porém, a missão precisa existir. O jogo começa pelo planejamento e passa pelos nove níveis de maturidade de conceito (CML), do rabisco no guardanapo até a revisão crítica de projeto. Cada escolha custa créditos e altera a nave. Depois do lançamento, essas escolhas voltam como consequência: o foguete limita a massa, o risco que ninguém pagou para mitigar fica mais provável, a peça reserva salva o reator numa falha térmica e a qualidade da comunicação decide se a base consegue guiar a reentrada.

O ponto central é que tudo isso usa o mesmo estado de missão (`MissionState`). O planejamento grava parâmetros que o voo lê de verdade, o cientista tem trabalho próprio na Terra, e os dados da NASA aparecem nos eventos com um selo dizendo se são reais ou simulados.

## Como a missão acontece

1. **Planejamento.** Depois da cutscene e do tutorial, o jogador escolhe entre planejar a missão (CML 1 a 9) ou seguir com o plano padrão.
2. **Tripulação.** No multiplayer, cada jogador assume um papel no lobby e pode trocar por um papel livre.
3. **Lançamento.** O CDR autoriza, o vídeo de lançamento toca e a tripulação embarca. O cientista fica na Terra.
4. **Operação.** Sobrevivência (comida, água, sono, vida, núcleo do reator), missão dos bionutrientes e viagem até Lua, Marte ou Júpiter.
5. **Eventos.** A cada 30 segundos há um sorteio entre interferência na comunicação, asteroide e falha do reator. Os riscos aceitos no CML 7 pesam no sorteio. Existe ainda a tempestade solar.
6. **Retorno.** Checklist dos sistemas, janela de retorno e ângulo de reentrada.
7. **Relatório.** Nota final, linha do tempo dos eventos e as causas ligadas ao planejamento.

### Os nove CMLs

| CML | Decisão |
|---|---|
| 1 | Objetivo da missão, decidido por voto (bionutrientes, radiação cislunar ou comunicação óptica) |
| 2 | Foguete pequeno, médio ou pesado: custo contra capacidade de massa |
| 3 | Fonte de energia e estrutura da nave |
| 4 | Kit de instrumentos: ciência, peças reserva e banda de comunicação |
| 5 | Política de reserva: folga de cronograma contra créditos |
| 6 | Inconsistências do projeto: corrigir pagando ou assumir o risco |
| 7 | Quais dos três maiores riscos mitigar (12 créditos cada) |
| 8 | PDR: ajustar os requisitos que falharam ou aprovar com dispensa |
| 9 | CDR: autorizar o lançamento |

Os CMLs 2 a 9 são divididos em quatro pares, sorteados entre os jogadores conectados, então cada pessoa decide uma parte do projeto. Os créditos começam em 100 e nunca ficam negativos.

## Papéis

A configuração pensada é dois astronautas, um engenheiro e um cientista na Terra.

| Papel | Onde | O que faz |
|---|---|---|
| Astronauta comandante (host) | Nave | Joga a missão e roda toda a simulação |
| Base / cientista | Terra | Analisa amostras, prevê perigos, decide o alerta solar, calcula o impacto de asteroides |
| Engenheiro de voo | Nave | Resfria o núcleo do reator e ativa os escudos |
| Astronauta 2 | Nave | Mesmas ações do engenheiro |

Jogando sozinho, a tecla `1` alterna entre o astronauta e o cientista.

## Mecânicas

**Sobrevivência.** Comida, água, sono, vida e temperatura do núcleo. Núcleo em 100% por 12 segundos explode a nave. A nave tem cafeteria, impressora de ração e água, armário de 20 espaços, mochila de 6, dormitório e botiquim.

**Missões.**
- *Bionutrientes:* pegar a cultura de fungos, aquecer, centrifugar e mandar para a base pela cápsula. A base analisa a amostra (placa de Petri e microscópio) e dá o veredito, que influencia a missão seguinte.
- *Viagem:* escolher a rota na cadeira de comando. Tempo limite, energia, combustível e massa vêm do projeto.
- *Tempestade solar (CME):* a base lê o terminal (fluxo de raios-X e ângulo), confere o manual de limite seguro e decide alertar ou ignorar. Com alerta, a nave tem 20 segundos para ligar os escudos na sala do reator. Alarme falso gasta energia e tempo. Ignorar uma tempestade real tira vida e inverte os controles por alguns segundos.
- *Retorno à Terra:* verificação dos sistemas, janela de retorno e reentrada.

**Eventos da viagem.**
- *Comunicação:* blecaute cuja duração depende da comunicação do projeto.
- *Asteroide:* a nave só percebe a cerca de 12 segundos do impacto. A base calcula o tempo e a nave decide se faz a manobra, que gasta combustível, energia e tempo.
- *Reator:* puzzle de válvulas para estabilizar. Uma peça reserva amortece o superaquecimento.

**Selos de origem.** Todo evento no relatório é marcado como `REAL` (registro científico real), `RISCO` (fenômeno real com ocorrência simulada) ou `FICT` (desafio criado para o jogo). Nenhum evento fictício é apresentado como dado da NASA.

**Relatório.** A nota (A a E) combina ciência (30%), nave (20%), decisões (15%), eficiência (10%), orçamento (10%) e, no multiplayer, cooperação com a base (15%). O relatório é salvo em `user://last_report.json`.

**Minigames.** Placa de Petri, microscópio, preparo de reagente por proporção, mural de fórmulas, desvio de asteroides com a nave e válvulas do reator.

O jogo está em português e inglês, tem música por sala, tutorial opcional e, na placa de Petri, o nome da cor aparece para quem não distingue cores.

## Dados da NASA

Hoje só a API DONKI (erupções solares) está integrada. Um script Python consulta o DONKI no servidor e gera um JSON estático, que o jogo lê para definir a intensidade da tempestade solar. A intensidade vem do registro real; a direção da ejeção é sempre simulada, e o selo na tela avisa isso.

O jogo procura o feed nesta ordem: `NASA_FEED_URL` (variável de ambiente ou a setting `nasa/feed_url`), o cache em `user://nasa_feed.json` e, por último, `data/space_events.json`. O jogo nunca chama `api.nasa.gov` direto, para a chave não ir junto com o build.

No build para navegador não existem variáveis de ambiente, então o endereço do feed precisa estar na setting `nasa/feed_url` do projeto, e o servidor que entrega o JSON precisa liberar CORS (o GitHub Pages costuma liberar). Enquanto o feed não estiver configurado, o build publicado usa o arquivo local.

```bash
NASA_API_KEY=sua_chave python3 tools/nasa_feed_proxy.py saida/space_events.json 30
```

Sem chave, o script usa `DEMO_KEY`, que tem limite baixo e compartilhado. O arquivo `data/space_events.json` tem só três erupções históricas (2003, 2017 e 2024) preenchidas à mão, então vale conferir datas e classes no DONKI antes de apresentar como dado oficial.

EONET e NeoWs ainda não foram integradas. O evento de asteroide é sorteado e marcado como `RISCO`.

## Tecnologias

- Godot 4 (2D, renderer Forward+) e GDScript, cerca de 11 mil linhas
- Rede com `ENetMultiplayerPeer` (LAN) e `WebSocketMultiplayerPeer` (internet e navegador)
- Python 3, só biblioteca padrão, para o feed do DONKI
- Vídeos em Ogg Theora, áudio em MP3 e WAV, fonte PixelOperator8
- Interface montada por código
- Testes headless do próprio Godot e um script shell para a rede

## Organização do código

O jogo é feito de autoloads que compartilham estado. O host é a autoridade e os clientes recebem um espelho.

```
scripts/
  game_state.gd      necessidades, inventário, cápsula
  mission_state.gd   CML 1-9, parâmetros, riscos, log e relatório
  missions.gd        etapas das missões
  voyage.gd          viagem, eventos, reator, asteroide
  solar.gd           tempestade solar
  nasa_feed.gd       eventos solares com cache e fallback
  interactions.gd    o que cada objeto da nave faz
  net.gd             LAN, WebSocket, papéis e RPCs
  lobby.gd, ghost.gd lobby e "fantasmas" dos outros jogadores
  lang.gd            português e inglês
  audio.gd           música e efeitos
  ui/                HUD, diálogos, telas e minigames
scenes/              menu, cutscene, jogo, salas
data/                fallback offline do feed
tools/               feed da NASA e teste de rede
tests/               testes automatizados
```

Na rede, o host roda a simulação e manda um espelho do estado cerca de 10 vezes por segundo. Pedidos dos clientes passam por `Net.call_host`, que só executa se o papel do jogador permitir (`Net.CALL_ROLES`). Por exemplo, só o cientista chama `Solar.decide`.

O caminho do dado é: `MissionState.params` alimenta `Voyage`, `Solar` e o sorteio de eventos, que escrevem em `MissionState.log`, de onde sai o relatório.

## Como rodar

Use Godot 4.6 ou mais novo, na versão padrão (não a .NET). O `project.godot` está marcado como 4.7 e os testes abaixo foram executados na 4.6.

```bash
git clone https://github.com/thallesgsrv/nasa-space-apps
cd nasa-space-apps
godot --headless --import    # só na primeira vez
godot --path .
```

| Tecla | Ação |
|---|---|
| WASD ou setas | Andar |
| F, Enter ou Espaço | Interagir e confirmar |
| I ou Tab | Mochila |
| M ou J | Menu de missões |
| V | Rever o objetivo atual |
| 1 | Alternar astronauta e cientista |
| Esc | Cancelar ou fechar |

### Exportar

O `export_presets.cfg` tem os presets Web (sem threads, não exige cabeçalhos COOP/COEP) e Linux. Com os export templates instalados:

```bash
mkdir -p build/web build/linux
godot --headless --export-release "Web" build/web/index.html
godot --headless --export-release "Linux (host/servidor)" build/linux/nasa-space-apps.x86_64
```

Para testar o build Web localmente, rode `python -m http.server 8000` dentro de `build/web`. Abrir o `index.html` com duplo clique não funciona.

## Multiplayer e como colocar online

Na LAN o jogo usa ENet: UDP 24565 para o jogo e UDP 24566 para descoberta de salas. Pela internet usa WebSocket na porta TCP 24567. Em qualquer caso o host é o executável desktop, e o navegador só consegue entrar em salas já criadas (por endereço, sem busca automática).

A versão jogável está publicada no GitHub Pages (link no topo). Para publicar de novo, exporte o preset Web e suba a pasta `build/web` no GitHub Pages, itch.io, Netlify ou Cloudflare Pages.

O cuidado é o HTTPS: uma página HTTPS bloqueia conexões `ws://`. O cliente do jogo aceita `wss://`, então há três caminhos:

- Túnel com TLS. O host roda `cloudflared tunnel --url http://localhost:24567` e os outros entram com `wss://endereco-do-tunel`. É o mais simples e não exige abrir porta no roteador.
- Servidor próprio com Caddy ou nginx fazendo o TLS na frente da porta 24567.
- Rede local por HTTP: o host serve `build/web` com `python -m http.server 8000` e os jogadores usam `http://IP:8000` e `ws://IP:24567`. Libere as portas no firewall e confira se o Wi-Fi não isola os clientes.

O modo solo funciona em qualquer hospedagem estática.

## Testes

```bash
godot --headless res://tests/run_tests.tscn
bash tools/run_net_tests.sh /caminho/godot ws
```

Na última execução (Godot 4.6, commit `8c0a0a5`), a suíte de regras terminou com 303 verificações e 0 falhas. O teste de rede, com 4 jogadores e um quinto recusado, e o de planejamento em equipe também passaram. A suíte cobre carregamento de todas as cenas, reinício de estado, game over, fluxo dos bionutrientes, viagem com cada evento, reator, tempestade solar com e sem alerta, feed da NASA e o efeito do planejamento no voo.

No fim da execução o Godot imprime avisos de "RID allocations leaked at exit". Isso acontece no encerramento do modo headless e não indica falha.

## O que já está pronto

- Planejamento com os nove CMLs, com custos, validação de orçamento, inconsistências no CML 6, requisitos no PDR, voto no CML 1 e divisão dos demais entre os jogadores.
- Planejamento que realmente altera o voo (massa, combustível, consumo, tempo, risco, peças e comunicação), verificado por teste.
- Multiplayer em LAN e WebSocket com permissão por papel, espelho de estado e teste de integração.
- Laboratório do cientista com análise de amostra, mural de fórmulas, bancada de reagentes e painel da base (monitor da nave, previsão de perigos, cálculo de asteroide).
- Tempestade solar com seis desfechos possíveis, dependendo do alerta e dos escudos.
- Três eventos de viagem com mecânicas diferentes.
- Retorno à Terra e relatório pós-missão em três páginas.
- Seis salas na nave, mais o laboratório na Terra, cada uma com música.
- Sobrevivência, inventário, armário e cápsula para a Terra.
- Tradução para português e inglês (cerca de 770 textos).

## O que está pela metade

- **Classes.** O lobby deixa trocar de papel, mas o engenheiro de voo e o astronauta 2 têm exatamente as mesmas permissões. Falta uma mecânica de manutenção e diagnóstico só do engenheiro, e uma tela de escolha de classe no começo.
- **Objetivo do CML 1.** O voto é registrado e aparece no relatório, mas não muda a missão. Escolher radiação cislunar ou comunicação óptica não cria nenhum experimento correspondente, e o jogo sempre executa os bionutrientes.
- **Tasks.** Há quatro missões, seis minigames e as tarefas de bordo, o que ainda é pouco para uma partida longa.
- **Eventos.** Só três tipos, sem encadeamento entre eles.
- **NASA.** Só o DONKI, e só alimenta a tempestade solar.
- **Economia e recompensas.** Os créditos existem só no planejamento e viram pontos no relatório. Não há economia durante a operação nem melhorias entre missões.
- **Câmara de propulsão.** O painel responde que o controle está em desenvolvimento.
- **Multiplayer no navegador.** O build Web está publicado, mas entrar numa sala pela página HTTPS (com `wss://`) ainda não foi testado de ponta a ponta.

## Roadmap

1. Fazer o objetivo do CML 1 importar, ou reduzir as opções ao que existe.
2. Dar ao engenheiro ações próprias de manutenção e diagnóstico.
3. Acrescentar tasks e eventos, com encadeamento (um evento mal resolvido piora outro).
4. Testar o multiplayer pelo navegador com `wss://` e configurar o feed da NASA no build Web.
5. Integrar NeoWs no evento de asteroide e EONET em eventos que afetem a base.
6. Economia durante a operação e algum tipo de progressão.
7. Ampliar o fallback do DONKI e atualizar o feed automaticamente com uma GitHub Action.
8. Implementar o painel da câmara de propulsão e salvar partidas.
9. Rebalancear os números, que o próprio código marca como provisórios.

## Pontos de atenção

- O `project.godot` declara Godot 4.7, e o README antigo falava em 4.6. Vale combinar uma versão só.
- O projeto usa Forward+, e o Web do Godot 4 funciona com o renderer de compatibilidade. Confira no primeiro export se abre no navegador.
- Os assets somam cerca de 57 MB, dos quais 24 MB são música. Para Web, vale comprimir os MP3.
- Há assets de template sem nenhuma referência: `knight`, `slime_green`, `slime_purple`, `coin`, `fruit`, `platforms`, `world_tileset`, um PNG com nome em UUID, `time_for_adventure.mp3` e `Laboratorio_futurista_em_pixel_art.webp`.
- A cena `scenes/baseterrestre/saladecontrole.tscn` não é usada por nada.
- O repositório tem um único commit.

## Créditos e licença

A licença ainda não foi definida, e o repositório não tem arquivo `LICENSE`. Faltam também os créditos dos assets (músicas, efeitos, fonte, sprites e interface) e a lista da equipe.

### Uso de IA

- **Código:** usamos o Claude Code para ajudar a escrever o GDScript. O design do jogo, a ideia de ligar planejamento e voo e a arquitetura são nossos.
- **Imagens:** parte das imagens foi gerada com IA e depois editada à mão no PixelStudio e no Pixelorama.
- **Vídeos:** os vídeos usados na cutscene de abertura (`assets/videos/`) foram gerados com IA.
- **Documentação:** este README e o texto da submissão foram redigidos com ajuda do Claude (Anthropic) a partir do nosso código e das nossas anotações, e revisados pela equipe.
- Nenhum logotipo, bandeira ou identificador de missão da NASA foi usado ou gerado.

### Dados e referências

- NASA DONKI, dados de erupções solares (api.nasa.gov).
- Níveis de maturidade de conceito (CML) e revisões PDR e CDR da NASA, como referência para o planejamento.
- Godot Engine 4 (licença MIT), Python 3, Git e GitHub.
- Fonte PixelOperator8.

Projeto desenvolvido para o NASA Space Apps Challenge 2026, no desafio Space Mission Design Game.
