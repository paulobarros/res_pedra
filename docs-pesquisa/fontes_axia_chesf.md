# Documentos da AXIA Nordeste / antiga CHESF sobre a UHE Pedra

Levantamento de 2026-11-20. Status: **verificado** = documento baixado e lido nesta data.

## Site atual da AXIA

Página: https://axia.com.br/axia-nordeste-gestao-de-recursos-hidricos (**verificado**)

- Hoje só tem a seção **"Comunicados 2026"**, com cartas circulares. **Não há** boletins mensais de vazão, planilhas ou séries históricas, como havia no site da CHESF.
- Cartas sobre a Pedra:
  - **"Programação de vazões do Reservatório da Pedra – Bacia do Rio de Contas"** (OOO.C 005, 009, 011 e 012/2026). Avisos de aumento de defluência com afluência, cota, % do volume útil e **tabela de defluência programada por dia**.
    - Exemplo, 005/2026 de 05/03/2026: afluência de **1.449 m³/s** às 12h, cota 221,31 m, 55,17% V.U.; defluência programada de 60 → 200 m³/s de 06 a 09/03.
  - **"Início do Período Úmido – Ações Preventivas – Bacia do Contas"** (OO|NEGO 021/2026, de 10/11/2026). Pico da estação anterior: **70,6% V.U. em 23/04/2026**. Em 09/11/2026: 54,6% V.U., afluência 0, defluência 11 m³/s.
- Informações operacionais citadas nas cartas:
  - **Vazão de restrição do vale: 800 m³/s**.
  - Aviso por **SMS**: enviar "PEDRA" para **27569**.
- Os PDFs são servidos em `https://axia.com.br/documents/d/guest/<slug>`. Algumas cartas devolvem HTML em vez de PDF (por exemplo, a 012/2026).

**Uso no projeto:** `comunicados_axia.R` verifica a página de hora em hora e repassa as cartas novas sobre a Pedra ou o Rio de Contas ao canal do Telegram, com o resumo e a tabela de defluência extraídos do PDF.

## Arquivo da antiga CHESF (Internet Archive)

Consulta feita pela API CDX do Wayback Machine sobre o domínio `chesf.com.br` (1.559 PDFs arquivados).

| Documento | Captura | Conteúdo | Status |
|---|---|---|---|
| **Boletim Hidrológico Diário da Barragem da Pedra nº 05 – PU 2022/23** (25/12/2022) | 20221225190232 | 92,41% V.U.; afluência média de 6 h ≈ **3.430 m³/s**; defluência 1.530 → **2.400 m³/s**. Na cheia, os boletins eram **diários**, mas só este foi arquivado | verificado |
| **PAE da UHE Pedra** (Plano de Ação de Emergência), rev. 02, emissão em 11/03/2026, 97 páginas | [20260517214034](https://web.archive.org/web/20260517214034/https://www.chesf.com.br/SistemaChesf/Documents/PAE_UHE_PEDRA.pdf) | Zona de Autossalvamento (ZAS), população na ZAS, rotas de fuga e pontos de encontro em Jequié, níveis de resposta (0 a 3), controle de cheias (remete ao *Manual de Operação de Controle de Cheias – Bacia do Rio de Contas*, atualizado todo ano) | verificado |
| PAE externo da UHE Pedra (versão anterior) | 20240421033445 | — | não lido |
| Cartas circulares de 2024 (programação de vazões da Pedra: 002, 004, 006, 007 e 009/2024; período úmido 021/2024) | dez/2025 | eventos de 2024 | não lidos |
| RT DORH 005/2015 e 017/2013 | — | relatórios sobre o São Francisco, **não** sobre a Pedra | verificado |

O endereço antigo do PAE (`chesf.com.br/SistemaChesf/Documents/PAE_UHE_PEDRA.pdf`) hoje redireciona para a página institucional da AXIA Nordeste. O documento **não está publicado** no site atual, e o painel aponta para a cópia arquivada.

## Implicações para a previsão (fase 2)

- Não há série histórica de vazões nos documentos, só **pontos de eventos**. A série de treino vem do balanço hídrico com SAR/ANA + Jequié (`fase2/03_afluencia_reconstruida.R`).
- Os picos documentados servem de **casos de teste**:
  - dez/2022: boletim ≈ 3.430 m³/s; a reconstrução dá 3.100 m³/s (média diária)
  - mar/2026: carta 1.449 m³/s; a reconstrução dá ≈ 1.000 m³/s (média diária)
- Em dez/2022, Lagoa do Tamburi (52405000) marcou no máximo 747 m³/s, enquanto a barragem recebeu ~3.100 m³/s. A maior parte dessa cheia veio **entre Tamburi e a barragem**, ou Tamburi subestima picos extremos. Por isso o alvo do modelo é a afluência da barragem, e não Tamburi × razão de áreas.
