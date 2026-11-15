#!/usr/bin/env python3
"""Gera o feed de eventos solares do jogo a partir do DONKI (api.nasa.gov).

Rode no SERVIDOR (cron/GitHub Actions) e sirva o JSON como arquivo estatico; configure o jogo com
NASA_FEED_URL ou a setting nasa/feed_url. A chave NUNCA vai para o navegador.

  NASA_API_KEY=sua_chave python3 tools/nasa_feed_proxy.py saida/space_events.json [dias]

Sem chave usa DEMO_KEY (limite baixo e compartilhado). Se a API falhar, o arquivo de saida NAO e
alterado e o script sai com codigo 1 (o jogo continua com o cache/arquivo local).
Endpoint e campos (FLR: flrID, classType, beginTime) seguem a documentacao do DONKI; confira em
https://api.nasa.gov se algo mudar.
"""
import datetime
import json
import os
import sys
import urllib.parse
import urllib.request


def _flare_rank(cls: str) -> float:
    """Ordena por intensidade real: X > M > C > B > A e, dentro da letra, pelo numero."""
    letter = cls[:1].upper()
    try:
        num = float(cls[1:])
    except ValueError:
        num = 0.0
    return "ABCMX".find(letter) * 1000 + num


def main() -> int:
    out = sys.argv[1] if len(sys.argv) > 1 else "space_events.json"
    days = int(sys.argv[2]) if len(sys.argv) > 2 else 30
    end = datetime.date.today()
    start = end - datetime.timedelta(days=days)
    query = urllib.parse.urlencode({
        "startDate": start.isoformat(),
        "endDate": end.isoformat(),
        "api_key": os.environ.get("NASA_API_KEY", "DEMO_KEY"),
    })
    url = "https://api.nasa.gov/DONKI/FLR?" + query
    try:
        with urllib.request.urlopen(url, timeout=20) as resp:
            raw = json.load(resp)
    except Exception as exc:  # rede, 429, 403...
        print("falha ao consultar o DONKI:", exc, file=sys.stderr)
        return 1
    events = []
    for item in raw or []:
        cls = str(item.get("classType", ""))
        begin = str(item.get("beginTime", ""))[:10]
        if len(cls) >= 2 and begin:
            events.append({"id": str(item.get("flrID", "")), "kind": "flare", "class": cls,
                           "date": begin, "title": "Erupção solar " + cls})
    if not events:
        print("nenhuma erupcao no periodo; mantendo o arquivo anterior", file=sys.stderr)
        return 1
    events.sort(key=lambda e: _flare_rank(e["class"]), reverse=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump({"source": "DONKI", "generated": datetime.datetime.utcnow().isoformat() + "Z",
                   "events": events[:20]}, f, ensure_ascii=False, indent=1)
    print("ok:", len(events), "eventos ->", out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
