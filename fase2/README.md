# Fase 2: previsão de afluência da UHE Pedra (7 dias)

Status: **experimental**. Publicado no painel (página Previsão) e no boletim do Telegram.

## Dados

| Script | Saída | Conteúdo |
|---|---|---|
| `01_chuva_merge_historico.R` | `data/historico/chuva_bacia_merge_historico.csv` | chuva média diária na bacia (MERGE/CPTEC), 1998 a jun/2026 |
| `02_vazoes_ana_historico.R` | `data/historico/vazoes_diarias_ana.csv` | vazão diária de Lagoa do Tamburi (1984–), Santo Antônio (1935–) e Jequié (1934–), HidroWeb/ANA |
| `03_afluencia_reconstruida.R` | `data/historico/afluencia_pedra_reconstruida.csv` | afluência da barragem por balanço hídrico: Jequié + ΔV do SAR/ANA (2012–) |

A série operacional (chuva MERGE desde jul/2026, afluência da CHESF e telemetria da Montante 1) é atualizada pelo workflow de hora em hora.

## Modelo (`R/modelo_afluencia.R`)

- Floresta aleatória com regressão quantílica (`ranger`, `quantreg = TRUE`), com um modelo para cada horizonte de 1 a 7 dias.
- **Alvo híbrido:** afluência reconstruída da barragem (2012–) e, antes disso, a vazão de Lagoa do Tamburi (1998–2012).
  - De 2012 a 2021, a barragem tem só ~11 dias de cheia (seca prolongada). Treinado só com ela, o modelo não aprende a prever cheias.
- **Preditores:**
  - afluência em t e t−1 e máximo de 7 dias
  - vazão a montante (Tamburi/Montante 1)
  - chuva observada na bacia (dia t e acumulados de 3, 7, 15 e 30 dias)
  - chuva futura de t+1 a t+h (total, últimos 2 dias e máximo)
  - época do ano
- **Na operação** (`previsao_afluencia.R`, a cada previsão de chuva nova):
  - cada um dos ~122 cenários de chuva (ECMWF, GEFS e ICON) gera 19 quantis
  - a faixa final (P10/P50/P90) e a **chance de cheia** (fração de valores acima de 300 m³/s) saem da mistura de todos

## Avaliação (`04_avaliacao_modelo.R`)

Treino até 30/06/2021; teste de 01/07/2021 a 2026, com as cheias de dez/2022 e mar/2026.
**Melhor caso:** no teste, a "chuva futura" é a chuva observada.

| h (dias) | erro médio, modelo (m³/s) | erro médio, persistência | acerto de cheia pela P50 | acerto de cheia pela P90 | falso alarme pela P90 |
|---|---|---|---|---|---|
| 1 | 50,7 | 83,3 | 47% | 69% | 2,1% |
| 3 | 50,0 | 94,5 | 34% | 70% | 2,7% |
| 5 | 52,4 | 93,8 | 20% | 67% | 2,2% |
| 7 | 52,6 | 106,5 | 16% | 71% | 2,7% |

"Cheia" é afluência acima de 300 m³/s. As figuras de cada evento estão em `resultados/`.

**Leitura:**
- O modelo acerta o **momento** das cheias: a P90 passa de 300 m³/s de 1 a 3 dias antes do pico. Ele **subestima o tamanho** dos eventos extremos (dez/2022: P90 de ~1.800 contra 3.100 m³/s observados).
- O produto publicado é, portanto, uma **faixa com chance de cheia**, e não um valor exato.
- O desempenho real será menor que o deste teste, porque a chuva prevista erra. `data/previsao_afluencia_historico.csv` guarda todas as previsões para medir isso.

## Limitações conhecidas

- A afluência reconstruída é ruidosa em vazões baixas (resolução do SAR: 1 hm³ ≈ 11,6 m³/s por dia).
- O dia da chuva MERGE vai das 09h às 09h; o dia da chuva prevista, de 00h a 24h.
- Em dez/2022, a maior parte da cheia veio entre Tamburi e a barragem. Sub-bacias (Gavião, Jacaré, incremental) podem melhorar o modelo.
