# Auditoria de contraste WCAG 2.1 — paleta FINAL do index.html
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File tools\contrast.ps1
# Formula oficial: https://www.w3.org/TR/WCAG21/#dfn-contrast-ratio
#
# Rode isto sempre que trocar qualquer cor. Se aparecer REPROVA em uma linha
# marcada como "texto", a nota de Acessibilidade do Lighthouse cai de 100.

function Get-Channel([double]$c){
    $c = $c / 255.0
    if($c -le 0.03928){ return $c / 12.92 }
    return [Math]::Pow((($c + 0.055) / 1.055), 2.4)
}
function Get-Luminance([string]$hex){
    $h = $hex.TrimStart('#')
    0.2126 * (Get-Channel ([Convert]::ToInt32($h.Substring(0,2),16))) +
    0.7152 * (Get-Channel ([Convert]::ToInt32($h.Substring(2,2),16))) +
    0.0722 * (Get-Channel ([Convert]::ToInt32($h.Substring(4,2),16)))
}
function Get-Contrast([string]$fg,[string]$bg){
    $l1 = Get-Luminance $fg; $l2 = Get-Luminance $bg
    if($l2 -gt $l1){ $t=$l1; $l1=$l2; $l2=$t }
    [Math]::Round((($l1 + 0.05) / ($l2 + 0.05)), 2)
}

# --- Tokens finais ---
$T = @{
  'n-0'='#FFFFFF'; 'n-50'='#F9FAFB'; 'n-200'='#DEE2E7'; 'n-300'='#C5CBD3'
  'n-400'='#9AA4B1'; 'n-500'='#6E7D91'; 'n-600'='#4F5E72'; 'n-700'='#384557'
  'n-800'='#1F2937'; 'n-900'='#111827'; 'n-950'='#0A0F1A'
  'teal-100'='#E6F4F4'; 'teal-light'='#E8F4F5'; 'teal-300'='#A1D0D3'
  'teal-400'='#6AB5B9'; 'teal-600'='#3A7D80'; 'teal-700'='#2C6266'; 'teal-800'='#204A4E'
  'wa'='#25D366'; 'wa-hover'='#2EE06E'; 'wa-active'='#1FBF5B'
  'danger'='#B42318'; 'danger-50'='#FEF3F2'; 'star'='#B45309'
}

# frente, fundo, minimo exigido, onde e usado
$pares = @(
  @('n-900','wa',        4.5,'TEXTO do CTA primario (os 4 botoes)'),
  @('n-900','wa-hover',  4.5,'TEXTO do CTA em hover'),
  @('n-900','wa-active', 4.5,'TEXTO do CTA em active'),
  @('n-900','n-0',       4.5,'Titulos h1/h2/h3 sobre branco'),
  @('n-700','n-0',       4.5,'Corpo de texto sobre branco'),
  @('n-600','n-0',       4.5,'Texto secundario, cargo do depoimento'),
  @('n-600','n-50',      4.5,'Texto secundario sobre cinza claro'),
  @('n-600','teal-light',4.5,'Deck na secao Imagine'),
  @('teal-700','n-0',    4.5,'Eyebrow e destaques sobre branco'),
  @('teal-700','n-50',   4.5,'Eyebrow sobre cinza claro'),
  @('teal-700','teal-light',4.5,'Eyebrow na secao Imagine'),
  @('danger','n-0',      4.5,'Texto de alerta sobre branco'),
  @('danger','danger-50',4.5,'Titulo do painel de dor'),
  @('danger','n-50',     4.5,'Kicker vermelho dos cards'),
  @('n-0','n-900',       4.5,'Titulos sobre secao escura'),
  @('n-300','n-900',     4.5,'Corpo sobre secao escura'),
  @('teal-300','n-900',  4.5,'Destaque teal sobre secao escura'),
  @('teal-400','n-900',  4.5,'Stop mais escuro do gradiente de texto'),
  @('n-400','n-900',     4.5,'Notas do bloco de CTA escuro'),
  @('n-400','n-950',     4.5,'Texto do rodape'),
  @('teal-300','n-950',  4.5,'Destaque no rodape'),
  @('teal-800','teal-100',4.5,'Monograma do avatar'),
  @('star','n-0',        3.0,'Estrelas de avaliacao (grafico)'),
  @('n-500','n-0',       3.0,'Borda funcional do botao secundario (1.4.11)'),
  @('teal-700','wa',     3.0,'Anel de foco sobre o botao verde (1.4.11)'),
  @('teal-700','n-0',    3.0,'Anel de foco sobre branco (1.4.11)'),
  @('teal-300','n-900',  3.0,'Anel de foco sobre secao escura (1.4.11)')
)

$falhas = 0
$saida = foreach($p in $pares){
  $r = Get-Contrast $T[$p[0]] $T[$p[1]]
  $passa = $r -ge $p[2]
  if(-not $passa){ $falhas++ }
  [PSCustomObject]@{
    Par     = "{0} / {1}" -f $p[0], $p[1]
    Ratio   = "{0:N2}:1" -f $r
    Minimo  = "{0:N1}" -f $p[2]
    Status  = if($passa){'PASSA'}else{'REPROVA'}
    Uso     = $p[3]
  }
}
$saida | Format-Table -AutoSize
Write-Output ""
if($falhas -eq 0){
  Write-Output ("TODOS OS {0} PARES PASSAM. Acessibilidade do Lighthouse: sem reprovacao de contraste." -f $pares.Count)
} else {
  Write-Output ("ATENCAO: {0} de {1} pares REPROVAM. Corrija antes de publicar." -f $falhas, $pares.Count)
  exit 1
}
