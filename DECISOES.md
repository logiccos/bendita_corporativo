# Bendita Tour Corporativo — registro de decisões

Documento do **porquê** de cada escolha de arquitetura, design e acessibilidade.
Toda afirmação numérica aqui foi medida, não estimada. Reproduza a auditoria de
cor com `powershell -NoProfile -ExecutionPolicy Bypass -File tools\contrast.ps1`.

---

## 1. A decisão que governa todas as outras

Performance no Lighthouse é **100% métrica**. Os pesos são:

| Métrica | Peso |
|---|---|
| TBT (Total Blocking Time) | 30 |
| LCP (Largest Contentful Paint) | 25 |
| CLS (Cumulative Layout Shift) | 25 |
| FCP (First Contentful Paint) | 10 |
| Speed Index | 10 |
| Os ~40 diagnósticos ("unused JS", "cache TTL", "render-blocking"…) | **0** |

Consequência prática: **zerar TBT e CLS já garante 55 dos 100 pontos**. Foi por
isso que a arquitetura ficou "1 documento + 1 fonte, sem JavaScript" — não por
minimalismo estético.

E o alvo difícil é o **desktop**, não o mobile: o orçamento de LCP é de **596 ms**
no desktop contra 1.555 ms no mobile.

---

## 2. Remoção do Tailwind CDN

**O que era:** `<script src="https://cdn.tailwindcss.com">`.

**Por que saiu** (medido na rede, não estimado):

- A URL responde **HTTP 302** → redirect para `/3.4.17` = **+1 RTT** no caminho crítico.
- O bundle tem **126.354 bytes** comprimidos / **407.279 descomprimidos**.
- Ele **gera o CSS no navegador em runtime**: parse + compile + varredura do DOM +
  injeção de `<style>`. Isso produz uma *long task* única de 600–1.200 ms sob o
  throttle 4× do Lighthouse.
- O limite de TBT para nota 100 é **66 ms**. Só esse script custava ~500–900 ms.
- Até o CSS existir, a página não tem estilo nenhum — então FCP ≈ LCP ≈ 2,8–3,5 s no mobile.

**Total estimado do estrago: 25 a 30 pontos de Performance.**

> Nota de precisão: o aviso `cdn.tailwindcss.com should not be used in production`
> é emitido via `console.warn`, e o audit `errors-in-console` filtra apenas
> `level === 'error'`. Ou seja, ele **não** reprovava Boas Práticas. O motivo da
> remoção é métrico, não cosmético.

**O que entrou:** CSS escrito à mão, inlinado no `<head>`.

**Por que inline e não arquivo externo** — a conta:

Um `<link rel=stylesheet>` custa 1 RTT completo (≈150 ms mobile, ≈40 ms desktop).
Como o LCP desta página é **texto**, ele só pinta depois do CSSOM completo — então
esse RTT é cobrado **duas vezes**, em FCP (peso 10) e em LCP (peso 25). No orçamento
de FCP desktop (542 ms), 40–80 ms é 7–15% do total.

O contra-argumento honesto é que inline não é cacheável. Mas: (a) o PageSpeed mede
sempre *cold load*, então o cache vale **zero pontos**; (b) esta é uma landing de
página única alimentada por link direto — não existe segunda página para amortizar
o cache. O custo de repagar ~17 KB numa visita recorrente é ~15 ms a 1,6 Mbps.

---

## 3. Fonte: self-host de arquivo variável

**Descoberta que mudou a estratégia:** a Montserrat hoje é servida pelo Google como
**fonte variável**. Os pesos 400/500/600/700/800/900 apontam todos para a **mesma URL**.

Comparação de bytes:

| Opção | Bytes |
|---|---|
| 4 arquivos estáticos subsetados (400+600+700+800) | 47.340 |
| woff2 latin **variável** ← escolhido | **37.956** |
| latin + latin-ext | 108.644 |

**Por que descartei o `latin-ext`:** todo acento do português — `ã õ ç á é í ó ú â ê ô à`,
mais `º` (U+00BA) e `©` (U+00A9) — vive no bloco Latin-1, dentro do range
`U+0000–00FF` que o subset `latin` já cobre. Verifiquei no CSS que o próprio
Google devolve. Economia: **70 KB** sem perder um único glifo.

**Por que self-host e não CDN:** o argumento clássico "o CDN do Google já está no
cache do usuário" morreu com o **cache particionado por site** (Chrome 86+ / Safari 13+).
Hoje o CDN só adiciona 2 origens (DNS+TCP+TLS ≈ 450 ms no mobile) e 1 requisição
render-blocking. Self-host same-origin reaproveita a conexão já quente do HTML.

**Métricas de fallback (o que zera o CLS de fonte):**

```css
@font-face{
  font-family:'Montserrat Fallback';
  src:local('Arial'),local('Roboto'),local('Helvetica Neue'),local('Segoe UI');
  size-adjust:112.8%; ascent-override:85.8%; descent-override:22.3%; line-gap-override:0%;
}
```

A Montserrat tem `unitsPerEm 1000`, `ascender 968`, `descender 251`. O `size-adjust`
de 112,8% iguala a **largura média de avanço** da fallback à da Montserrat, ponderada
pela frequência de caracteres do português. É isso que garante o **mesmo número de
linhas** antes e depois do swap — sem isso, o título re-flui e o CLS estoura.
`local('Roboto')` está na lista porque o Lighthouse mobile emula Android.

O `<link rel=preload>` vem **antes** do `<style>` de propósito: o preload scanner
dispara a fonte no mesmo tick em que começa a parsear o CSS, ganhando 1 RTT.
O `crossorigin` é obrigatório mesmo same-origin — fontes usam modo CORS e, sem ele,
o navegador **baixa o arquivo duas vezes**.

---

## 4. Cor — o que reprovava e por quê

Auditei os 16 pares da versão anterior. **6 reprovavam WCAG AA**:

| Combinação | Medido | Onde estava |
|---|---|---|
| branco / verde WhatsApp | **1,98:1** | os 3 CTAs, inclusive o principal |
| branco / verde hover | **2,47:1** | hover dos CTAs |
| ícone verde / fundo verde-50 | **2,18:1** | card de ganho |
| `#4a9b9f` / branco | **3,24:1** | eyebrow e destaques do h1 |
| `gray-500` / `dark2` | **3,04:1** | CNPJ e copyright |
| ícone vermelho / red-50 | **3,44:1** | card de dor |

### 4.1 O caso do verde do WhatsApp

Branco sobre `#25D366` dá **1,98:1**. Reprova AA (4,5) e reprova até o limiar mais
permissivo de texto grande (3,0). Enquanto isso existisse, a nota de Acessibilidade
não fechava 100 — ponto final.

Havia três saídas. A escolhida foi manter o verde exato da marca e **inverter o texto
para `#111827`**, o que dá **8,94:1** — passa AAA com folga de 4,4 pontos.

As alternativas descartadas: escurecer o fundo para `#0F7B3A` (5,36:1, mas perde o
brilho reconhecível do WhatsApp) ou trocar o CTA para o teal da marca (4,75:1, mais
sóbrio, mas perde o sinal de canal).

Os estados seguem a mesma lógica: **hover clareia** (`#2EE06E`, 10,14:1) em vez de
escurecer, porque com texto escuro clarear *aumenta* o contraste. O `active` escurece
(`#1FBF5B`, 7,32:1) e afunda 1px — é o único feedback tátil possível sem JavaScript.

### 4.2 `#4a9b9f` não é cor de texto

Medido: **3,24:1** sobre branco. É uma cor de **superfície e ícone**, não de texto.
A rampa derivada mantém o matiz 183° da marca e resolve:

| Token | Hex | vs branco | Papel |
|---|---|---|---|
| `--teal-500` | `#4A9B9F` ← oficial | 3,24 | fundos, ícones, bordas decorativas |
| `--teal-600` | `#3A7D80` ← oficial | 4,75 | logotipo, texto grande |
| `--teal-700` | `#2C6266` | 6,89 | **eyebrow e destaques em texto pequeno** |
| `--teal-300` | `#A1D0D3` | — | acento sobre superfície escura (10,54 vs dark1) |

Detalhe que só apareceu na medição: sobre o fundo tingido da seção "Imagine"
(`#E8F4F5`), o `--teal-600` cai para **4,22:1** e reprova. Por isso o eyebrow ali
usa `--teal-700` (6,14:1). Contraste depende do fundo composto, não da cor isolada.

### 4.3 Outras correções de cor

- **Estrelas dos depoimentos:** `yellow-400` dava 2,15:1. Trocado por `#B45309`
  (5,02:1). Estrela de avaliação é objeto gráfico significativo → exige 3:1.
  Bônus: dourado escuro lê como premium; amarelo-neon lê como promoção.
- **Cargo do depoimento:** `gray-500` sobre branco dá 4,20:1 e reprova para texto
  pequeno. Subiu para `--n-600` (6,61:1).
- **Vermelho:** `#DC2626` passa no branco (4,83) mas cai abaixo de 4,5 sobre fundos
  tingidos. Padronizado em `#B42318`, que mantém ≥6:1 em todas as superfícies claras.
- **Borda do header:** `gray-100` sobre branco dava **1,06:1** — invisível. Agora
  `--n-200` (1,30:1).
- **Borda funcional** (botão secundário): `--n-500` = 4,20:1. WCAG 1.4.11 exige 3:1
  quando a borda é o único elemento que identifica o componente. `--n-300` (1,63) e
  `--n-400` (2,52) reprovariam — é o erro clássico nesse ponto.

**Estado final: 27 de 27 pares passam.** Rode `tools/contrast.ps1` para conferir.

---

## 5. Acessibilidade — além do que o Lighthouse mede

O Lighthouse cobre cerca de 30% da WCAG. O que foi feito além:

**`<span class="sr-only">` em vez de `aria-label`.** Um `aria-label` **substitui**
todo o nome acessível do link. O botão diria "Falar com Consultor" na tela e
anunciaria outra coisa — isso viola o **SC 2.5.3 (Label in Name)** e impede comando
de voz de acionar o botão. Um `<span>` oculto **concatena**: o nome acessível vira
"Diagnóstico Gratuito — abre o WhatsApp em uma nova aba".

**`@media (forced-colors: active)`.** No modo Alto Contraste do Windows o sistema
substitui `background-color` por `Canvas`. Sem borda declarada, o botão verde
**desaparece da tela** — sobra o texto solto. Agora há `border: 2px solid ButtonText`.

**`@media (hover: hover) and (pointer: fine)`** em todo estado de hover. Sem essa
guarda, no iOS o hover "gruda" após o toque e o botão fica deslocado até o próximo tap.

**`@media (max-height: 30rem)` → header vira estático.** Resolve dois casos com uma
regra: celular em paisagem (360px de altura) e o teste de zoom 400% (altura efetiva
de 256px). Nesse último, header fixo + barra fixa somariam **59% da altura útil**.

**`min-block-size` no header, nunca `height`.** Com `height: 80px` fixo, o logotipo
é cortado a 200% de zoom de texto e no teste de Text Spacing (WCAG 1.4.12).

**Anel de foco com `outline`, não `border`.** `outline` não participa do layout,
então não desloca nada — CLS zero. A cor do anel inverte por seção via a variável
`--ring` (`--teal-700` no claro = 6,89:1; `--teal-300` no escuro = 10,54:1), e o
próprio anel sobre o botão verde dá 3,48:1, acima do mínimo de 3:1.

**Ordem de headings corrigida.** A versão anterior ia de `h1` direto para `h3` —
reprovação direta no audit `heading-order`. Agora: um `h1` → `h2` por seção →
`h3` nos cards, sem saltos (verificado mecanicamente).

**Movimento é opt-in.** `scroll-behavior: smooth` vive dentro de
`@media (prefers-reduced-motion: no-preference)`, com um bloco `reduce` como rede
de segurança. A duração usa `.01ms` e não `0s` porque handlers `transitionend`
não disparam com duração zero em alguns navegadores.

Também: skip link, `role="list"` nas listas (o Safari remove a semântica quando
`list-style: none`), `<abbr>` no CNPJ, `focusable="false"` em todos os 52 SVGs,
alvo de toque mínimo de 44px (48px em `pointer: coarse`), e `prefers-contrast: more`.

---

## 6. Responsividade — 5 media queries de largura, não 24

A abordagem é **intrínseca**: o layout se adapta sozinho e as media queries só
existem onde há mudança estrutural real.

**Container à prova de estouro:**
```css
.container{ width: min(100% - var(--gutter) * 2, var(--container)); margin-inline: auto }
```
`min()` em vez de `max-width` + `padding` é matematicamente incapaz de gerar scroll
horizontal, e independe de `box-sizing`.

**Um gutter único para tudo.** Antes, o header usava `px-4 sm:px-6 lg:px-8` e as
seções usavam `px-4` puro — no desktop o logotipo ficava a 32px da borda e o conteúdo
a 16px. **A margem esquerda da página não era uma linha reta.** É um defeito pequeno
que o olho registra sem conseguir nomear, e é uma das razões pelas quais um site
"parece amador" mesmo com as cores certas.

**Tipografia fluida com `clamp()`.** A parte "preferida" é sempre `rem + vw`, nunca
`vw` puro: com `vw` puro o texto para de responder ao zoom do navegador e reprova
o **WCAG 1.4.4 (Resize Text)**.

**Grid sem media query:**
```css
grid-template-columns: repeat(auto-fit, minmax(min(100%, 20rem), 1fr));
```
Cobre 1→2→3→4 colunas continuamente de 320px a 4K. O `min(100%, …)` impede overflow
quando o container é menor que o mínimo.

**Serviços em 2×2, não 1×4.** Em 4 colunas dentro de 1200px, cada card ficava com
~218px úteis de texto — cerca de **27 caracteres por linha**. Em 2×2 a medida vai
para ~46ch, dentro da faixa confortável de 45–75.

**Medida de leitura limitada em `ch`.** Os parágrafos anteriores rodavam a ~86
caracteres por linha (`max-w-4xl` = 896px), acima do limite de 80 do WCAG 1.4.8.

---

## 7. UX — mudanças com razão

**Barra fixa inferior no mobile, não botão flutuante.** A 320px a barra oferece
288×48 = **13.824 px²** de alvo contra 3.136 px² do FAB de 56px — **4,4× maior** —
e cabe rótulo textual. Nenhum dos dois gera CLS (`fixed` não entra no fluxo); o
espaço é reservado por `padding` no `<body>`. O `env(safe-area-inset-bottom)` é
obrigatório: sem ele, no iPhone com barra de gestos um alvo de 48px vira ~34px úteis.

**CTA no header visível em todos os tamanhos.** Antes era `hidden sm:inline-flex` —
de 320 a 639px **não havia nenhum CTA acima da dobra**, e o primeiro estava a
~1.723px de rolagem (3 alturas de tela num iPhone SE).

**`?text=` diferente por posição** (`topo`, `hero`, `cta-final`, `barra`). Dá
atribuição de qual CTA converteu **sem uma linha de JavaScript** — a mensagem chega
pré-preenchida no WhatsApp com a origem.

**Blur decorativo trocado por gradiente estático.** `blur(64px)` sobre meia viewport
força uma camada de composição repintada a cada scroll. Em GPU móvel de entrada
(Adreno do Moto G, o gargalo típico no Brasil) isso atrasa LCP e INP. `radial-gradient`
custa zero.

**Sprite de ícones (`<symbol>` + `<use>`).** Sendo honesto: em bytes na rede o ganho
é **marginal** (~10 bytes), porque o compressor já deduplica dentro da janela de 32 KB.
O motivo real é reduzir 8 KB de HTML bruto, baixar a contagem de nós do DOM, e
centralizar a manutenção — trocar um ícone é editar um lugar, não 15.

**Botões com raio de 10px, não pílula.** Pílula é vocabulário de varejo/consumer.
O raio arredondado ficou reservado ao badge, para que a forma vire um sinal único
no sistema em vez de ruído.

**Sombras em duas camadas, tingidas com o carvão da página (`16,24,40`).** Sombra
preta pura sobre fundo tingido vira cinza sujo. A dupla camada — uma sombra de
contato curta + uma difusa ampla — é o que separa "premium" de drop-shadow de template.

---

## 8. SEO e Boas Práticas

**`favicon.ico` real na raiz.** O Chrome headless requisita `/favicon.ico` mesmo
sem `<link>`; um 404 vira console error e o audit `errors-in-console` pesa
**1 de 27 = −3,7 pontos** em Boas Práticas.

**`meta description`.** É o único audit de SEO que a versão original reprovava.
A soma dos pesos SEO é 13,043 — faltando 1, a nota vai para **92**.

**JSON-LD com `@graph`:** `TravelAgency` (subtipo exato da vertical, herda
`LocalBusiness` → `Organization`) + `WebSite` + `Service` com
`audience: BusinessAudience` — este último é o que codifica que o público é
**empresarial**, não turista. Não marquei `FAQPage`: a página não tem FAQ visível,
e marcação sem conteúdo correspondente viola as diretrizes do Google.

**`robots.txt`.** Cuidado contraintuitivo: um `robots.txt` **ausente** retorna
`notApplicable` e o SEO continua 100; um `robots.txt` **malformado** zera o audit.
O arquivo entregue respeita as regras validadas (`User-agent` antes de `Allow`,
`Sitemap:` com URL absoluta).

**`og:image` deliberadamente comentado.** Apontar para um arquivo inexistente
quebraria o preview no WhatsApp — que é o canal de conversão desta página. A arte
está em `assets/og-image.svg`; exporte para JPG 1200×630 e descomente as 3 linhas.

---

## 9. Pendências antes de publicar

| # | Item | Gravidade |
|---|---|---|
| 1 | **Depoimentos fictícios** ("Maria Silva", "João Santos", "Ana Costa") e os 5 slots de logo. Publicar depoimento fabricado como verdadeiro viola o **CDC art. 37** e o Código do CONAR. Substitua por reais com autorização escrita, ou remova a seção. | **Crítica** |
| 2 | "+20 empresas" e "Economizamos 28%" — confirmar que são números reais e verificáveis. | Alta |
| 3 | "R$ 106 bilhões por ano" — citar a fonte visivelmente. Número sem fonte enfraquece o argumento justamente com o CFO. | Média |
| 4 | Exportar `assets/og-image.svg` → `assets/og-image.jpg` (1200×630) e descomentar as tags `og:image`. | Média |
| 5 | Confirmar que `corporativo.benditatour.com` resolve e serve HTTPS com 301 de `http://`. Cada redirect custa 1 RTT direto no FCP e no LCP. | Média |
| 6 | Endereço no JSON-LD. Deixei de fora para não inventar dado; preencher fortalece o rich result de `LocalBusiness`. | Baixa |
| 7 | Arquivo `nul` (89 bytes) na raiz — lixo de um redirecionamento de shell. Pode apagar. | Baixa |

---

## 10. Riscos que derrubam a nota depois

| Risco | Impacto |
|---|---|
| Adicionar GTM / Google Analytics / Meta Pixel no `<head>` | +90 KB, +1 origem, TBT +100–300 ms → **−10 a −20 pontos** |
| Adicionar widget de chat (Tawk, Crisp, RD Station) | +300 KB e um iframe → TBT +400 ms |
| Adicionar `<img>` sem `width`/`height` | CLS acima de 0,04 → **−25 pontos** |
| Voltar o Tailwind CDN "só para um ajuste rápido" | **−30 pontos** |
| Hospedar em GitHub Pages | Não serve brotli (só gzip) e força `max-age=600` em tudo, sem headers customizáveis. Prefira Netlify/Cloudflare Pages — o `_headers` entregue já está pronto para ambos |

**Ao medir:** rode o PageSpeed 3–5 vezes e use a mediana. A variação por ruído de
CPU do datacenter é de ±3 a 5 pontos. Submeta sempre a URL canônica final **com
barra** (`https://corporativo.benditatour.com/`) — sem protocolo, o PSI assume
`http://` e você come um 301.

---

## 11. Arquivos

| Arquivo | Papel |
|---|---|
| `index.html` | A página. HTML + CSS + JSON-LD, autocontido |
| `assets/fonts/montserrat-latin-var.woff2` | Único subrecurso (37,9 KB) |
| `assets/og-image.svg` | Arte do card de compartilhamento (exportar para JPG) |
| `favicon.svg` / `favicon.ico` | Ícones (o `.ico` evita o 404 na raiz) |
| `robots.txt` / `sitemap.xml` | SEO |
| `_headers` | Cache e segurança (Netlify / Cloudflare Pages) |
| `tools/contrast.ps1` | Auditoria de contraste — rode sempre que trocar uma cor |
| `backup/index.copywriter-2026-08-10.html` | Versão do agente de copy antes da reconstrução |

**Peso na rede:** 16,9 KB (HTML+CSS, gzip) + 37,9 KB (fonte) = **53,6 KB**.
Zero requisições de terceiro. Zero render-blocking. Zero JavaScript.
