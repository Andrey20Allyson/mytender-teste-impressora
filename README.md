# Teste de impressão — Epson TM-T20X

Diagnóstico para comandas que saem com ~30 cm de papel. Roda em qualquer Windows sem instalar nada: o C# é compilado na hora pelo Windows PowerShell 5.1 (`Add-Type`).

## Como usar

1. Copie `teste-tmt20x.ps1` e `teste-tmt20x.cmd` para a mesma pasta no PC da impressora.
2. Dê duplo clique em `teste-tmt20x.cmd`.
3. Rode os testes do menu e informe quantos cm de papel saíram em cada um.

O resultado fica em `teste-tmt20x-resultado.txt` na Área de Trabalho.

Pelo PowerShell também funciona:

```powershell
.\teste-tmt20x.ps1                                   # menu completo
.\teste-tmt20x.ps1 -Impressora "EPSON TM-T20X Receipt"
.\teste-tmt20x.ps1 -SoDiagnostico                    # só lista driver e papéis, sem imprimir
```

## Testes

| Opção | O que faz |
|---|---|
| 1 | GDI com página de 80x100 mm: o mesmo que o Electron/Chromium faz |
| 2 | GDI com o papel padrão do driver (controle) |
| 3 | ESC/POS direto (RAW) com corte: ignora o tamanho de página do driver |

## Como ler

- **[1] saiu ~10 cm**: o driver respeita a altura pedida; o problema está no app.
- **[1] saiu ~30 cm**: o driver ignora a altura e usa o papel padrão dele (o padrão da Epson é `Roll Paper 80 x 297 mm`).
- **[3] saiu curto**: imprimir ESC/POS direto resolve, sem depender do driver.
