#!/usr/bin/env bash
# Sobe uma partida de 4 jogadores (host + 3 clientes + 1 extra recusado) e confere tudo.
# Uso: tools/run_net_tests.sh [caminho-do-godot] [enet|ws]
G="${1:-godot}"; KIND="${2:-ws}"
cd "$(dirname "$0")/.." || exit 1
T=res://tests/net_integration.tscn
LOG=$(mktemp -d)
timeout 120 "$G" --headless "$T" -- host4 "$KIND" > "$LOG/host.log" 2>&1 &
PIDS=($!)
sleep 4
for i in 0 1 2 3; do
  timeout 120 "$G" --headless "$T" -- crew "$i" "$KIND" > "$LOG/crew$i.log" 2>&1 &
  PIDS+=($!)
done
FAIL=0
for p in "${PIDS[@]}"; do wait "$p" || FAIL=1; done
for f in "$LOG"/*.log; do echo "--- $(basename "$f")"; grep -E "OK$|FALHOU" "$f"; done
[ $FAIL -eq 0 ] && echo "REDE ($KIND): tudo certo" || echo "REDE ($KIND): FALHOU (logs em $LOG)"
exit $FAIL
