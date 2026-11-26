# Teste de impressao para a Epson TM-T20X (MyTender).
#
# Roda no Windows PowerShell 5.1 que ja vem no Windows: o C# abaixo e compilado
# na hora via Add-Type, sem instalar .NET SDK nem nada.
#
# Tres testes, para separar "problema do app" de "problema do driver":
#   [1] GDI com altura customizada (100 mm) -> e o que o Electron/Chromium faz
#   [2] GDI com o papel padrao do driver    -> controle
#   [3] ESC/POS direto (RAW) com corte      -> ignora o tamanho de pagina do driver
#
# Arquivo so com ASCII de proposito: o PowerShell 5.1 le .ps1 sem BOM como ANSI.

param(
    [string]$Impressora,
    [switch]$SoDiagnostico
)

$ErrorActionPreference = 'Stop'

if (-not ('MyTenderTeste.Impressora' -as [type])) {
    $cs = @'
// Escrito em C# 5 para compilar no Windows PowerShell 5.1 (.NET Framework 4.5+).
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Drawing;
using System.Drawing.Printing;
using System.Runtime.InteropServices;
using System.Text;

namespace MyTenderTeste
{
    public static class Impressora
    {
        // PaperSize trabalha em centesimos de polegada.
        static string Mm(double centesimos) { return (centesimos * 0.254).ToString("0.0"); }

        static string Desc(PaperSize p)
        {
            return p.PaperName + "  [" + Mm(p.Width) + " x " + Mm(p.Height) + " mm]  (kind " + p.Kind + ", raw " + p.RawKind + ")";
        }

        public static string[] Listar()
        {
            var lista = new List<string>();
            foreach (string n in PrinterSettings.InstalledPrinters) lista.Add(n);
            return lista.ToArray();
        }

        public static string Diagnostico(string nome)
        {
            var ps = new PrinterSettings();
            ps.PrinterName = nome;
            if (!ps.IsValid) return "Impressora invalida: " + nome;

            var sb = new StringBuilder();
            var pg = ps.DefaultPageSettings;
            sb.AppendLine("Papel padrao do driver : " + Desc(pg.PaperSize));
            sb.AppendLine("Area imprimivel        : " + Mm(pg.PrintableArea.Width) + " x " + Mm(pg.PrintableArea.Height) + " mm");
            sb.AppendLine("Margem fisica (x, y)   : " + Mm(pg.HardMarginX) + ", " + Mm(pg.HardMarginY) + " mm");
            sb.AppendLine("Tamanhos de papel que o driver oferece (" + ps.PaperSizes.Count + "):");
            foreach (PaperSize p in ps.PaperSizes) sb.AppendLine("  - " + Desc(p));
            return sb.ToString();
        }

        // ------------------------------------------------------------ GDI

        // alturaMm <= 0 usa o papel padrao do driver.
        public static string ImprimirGdi(string nome, int alturaMm)
        {
            var log = new StringBuilder();
            var doc = new PrintDocument();
            doc.PrinterSettings.PrinterName = nome;
            if (!doc.PrinterSettings.IsValid) throw new Exception("Impressora invalida: " + nome);

            doc.DocumentName = "MyTender - teste GDI";
            doc.PrintController = new StandardPrintController();   // sem janela de progresso
            doc.OriginAtMargins = false;
            doc.DefaultPageSettings.Margins = new Margins(0, 0, 0, 0);

            string pedido;
            if (alturaMm > 0)
            {
                int largura = (int)Math.Round(80 / 25.4 * 100);
                int altura = (int)Math.Round(alturaMm / 25.4 * 100);
                doc.DefaultPageSettings.PaperSize = new PaperSize("MyTender " + alturaMm + "mm", largura, altura);
                pedido = "80x" + alturaMm + " mm";
            }
            else
            {
                pedido = "padrao do driver";
            }
            log.AppendLine("Pedido ao driver       : " + pedido);

            doc.PrintPage += (s, e) =>
            {
                var papel = e.PageSettings.PaperSize;
                log.AppendLine("Driver usou o papel    : " + Desc(papel));
                log.AppendLine("Limites da pagina      : " + Mm(e.PageBounds.Width) + " x " + Mm(e.PageBounds.Height) + " mm");

                Desenhar(e.Graphics, "TESTE GDI", new string[] {
                    DateTime.Now.ToString("dd/MM/yyyy HH:mm:ss"),
                    "Pedido: " + pedido,
                    "Driver: " + Mm(papel.Width) + "x" + Mm(papel.Height) + " mm",
                    "",
                    "Se o papel passar",
                    "muito da linha FIM,",
                    "o driver ignorou a",
                    "altura pedida."
                });
                e.HasMorePages = false;
            };

            doc.Print();
            return log.ToString();
        }

        static void Desenhar(Graphics g, string titulo, string[] linhas)
        {
            g.PageUnit = GraphicsUnit.Millimeter;

            using (var fonte = new Font("Courier New", 8f))
            using (var negrito = new Font("Courier New", 11f, FontStyle.Bold))
            using (var caneta = new Pen(Color.Black, 0.3f))
            {
                float y = 2f;
                g.DrawString(titulo, negrito, Brushes.Black, 2f, y);
                y += 7f;
                foreach (var l in linhas)
                {
                    g.DrawString(l, fonte, Brushes.Black, 2f, y);
                    y += 4.5f;
                }

                // regua na direita, de 10 em 10 mm, para conferir a escala com uma regua de verdade
                for (int mm = 10; mm <= 90; mm += 10)
                {
                    g.DrawLine(caneta, 61f, mm, 70f, mm);
                    g.DrawString(mm + "mm", fonte, Brushes.Black, 50f, mm - 1.8f);
                }

                g.DrawLine(caneta, 0f, 95f, 70f, 95f);
                g.DrawString("---- FIM (95 mm) ----", fonte, Brushes.Black, 12f, 96f);
            }
        }

        // ------------------------------------------------------------ RAW / ESC-POS

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        class DocInfo
        {
            [MarshalAs(UnmanagedType.LPWStr)] public string pDocName;
            [MarshalAs(UnmanagedType.LPWStr)] public string pOutputFile;
            [MarshalAs(UnmanagedType.LPWStr)] public string pDataType;
        }

        [DllImport("winspool.drv", EntryPoint = "OpenPrinterW", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool OpenPrinter(string nome, out IntPtr h, IntPtr padrao);

        [DllImport("winspool.drv", SetLastError = true)]
        static extern bool ClosePrinter(IntPtr h);

        [DllImport("winspool.drv", EntryPoint = "StartDocPrinterW", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern int StartDocPrinter(IntPtr h, int nivel, [In, MarshalAs(UnmanagedType.LPStruct)] DocInfo di);

        [DllImport("winspool.drv", SetLastError = true)]
        static extern bool EndDocPrinter(IntPtr h);

        [DllImport("winspool.drv", SetLastError = true)]
        static extern bool StartPagePrinter(IntPtr h);

        [DllImport("winspool.drv", SetLastError = true)]
        static extern bool EndPagePrinter(IntPtr h);

        [DllImport("winspool.drv", SetLastError = true)]
        static extern bool WritePrinter(IntPtr h, byte[] dados, int tamanho, out int escritos);

        static Exception Falha(string etapa)
        {
            return new Exception(etapa + ": " + new Win32Exception(Marshal.GetLastWin32Error()).Message);
        }

        public static string ImprimirRaw(string nome)
        {
            var enc = Encoding.GetEncoding(1252);
            var b = new List<byte>();
            Action<byte[]> cmd = x => b.AddRange(x);
            Action<string> txt = s => b.AddRange(enc.GetBytes(s));

            cmd(new byte[] { 0x1B, 0x40 });              // ESC @    inicializa
            cmd(new byte[] { 0x1B, 0x74, 16 });          // ESC t 16 tabela WPC1252
            cmd(new byte[] { 0x1B, 0x61, 1 });           // ESC a 1  centraliza
            cmd(new byte[] { 0x1B, 0x45, 1 });           // ESC E 1  negrito
            cmd(new byte[] { 0x1D, 0x21, 0x11 });        // GS ! 11  altura e largura dupla
            txt("TESTE RAW\n");
            cmd(new byte[] { 0x1D, 0x21, 0x00 });
            cmd(new byte[] { 0x1B, 0x45, 0 });
            txt("ESC/POS direto, sem pagina\n");
            txt(DateTime.Now.ToString("dd/MM/yyyy HH:mm:ss") + "\n\n");
            cmd(new byte[] { 0x1B, 0x61, 0 });           // ESC a 0  alinha a esquerda
            txt("Acentos: áéíóú ãõ âêô ç ÇÃ\n");
            txt("- CENOURA - (1 * R$ 26,00) = R$ 26,00\n");
            txt("- COB. CHOCOLATE - (1 * R$ 18,00) = R$ 18,00\n\n");
            cmd(new byte[] { 0x1B, 0x45, 1 });
            txt("Total: R$ 44,00\n\n");
            cmd(new byte[] { 0x1B, 0x45, 0 });
            txt("Se este papel saiu curto (uns 6-8 cm)\n");
            txt("o corte pelo tamanho do conteudo funciona.\n");
            cmd(new byte[] { 0x1D, 0x56, 66, 3 });       // GS V 66 3  avanca ate a guilhotina e corta

            var dados = b.ToArray();
            IntPtr h;
            if (!OpenPrinter(nome, out h, IntPtr.Zero)) throw Falha("OpenPrinter");
            try
            {
                var di = new DocInfo { pDocName = "MyTender - teste RAW", pDataType = "RAW" };
                if (StartDocPrinter(h, 1, di) == 0) throw Falha("StartDocPrinter");
                try
                {
                    if (!StartPagePrinter(h)) throw Falha("StartPagePrinter");
                    int escritos;
                    bool ok = WritePrinter(h, dados, dados.Length, out escritos);
                    EndPagePrinter(h);
                    if (!ok) throw Falha("WritePrinter");
                    return "Enviados " + escritos + " de " + dados.Length + " bytes em modo RAW.";
                }
                finally { EndDocPrinter(h); }
            }
            finally { ClosePrinter(h); }
        }
    }
}
'@
    Add-Type -TypeDefinition $cs -ReferencedAssemblies System.Drawing -IgnoreWarnings
}

$relatorio = Join-Path ([Environment]::GetFolderPath('Desktop')) 'teste-tmt20x-resultado.txt'

function Write-Relatorio([string]$texto) {
    Write-Host $texto
    Add-Content -LiteralPath $relatorio -Value $texto
}

# ------------------------------------------------------------ escolhe a impressora

$todas = @([MyTenderTeste.Impressora]::Listar())
if ($todas.Count -eq 0) { throw 'Nenhuma impressora instalada.' }

if (-not $Impressora) {
    $candidatas = @($todas | Where-Object { $_ -match 'T20|TM-T|EPSON' })
    if ($candidatas.Count -eq 1) {
        $Impressora = $candidatas[0]
    } else {
        Write-Host 'Impressoras instaladas:'
        for ($i = 0; $i -lt $todas.Count; $i++) { Write-Host ('  [{0}] {1}' -f ($i + 1), $todas[$i]) }
        $n = Read-Host 'Numero da impressora'
        $Impressora = $todas[[int]$n - 1]
    }
}
if ($todas -notcontains $Impressora) { throw "Impressora nao encontrada: $Impressora" }

# ------------------------------------------------------------ diagnostico

Write-Relatorio ''
Write-Relatorio ('==== Teste TM-T20X - {0} ====' -f (Get-Date -Format 'dd/MM/yyyy HH:mm:ss'))
Write-Relatorio "Impressora             : $Impressora"

try {
    $wmi = Get-CimInstance Win32_Printer | Where-Object { $_.Name -eq $Impressora } | Select-Object -First 1
    if ($wmi) {
        Write-Relatorio "Driver                 : $($wmi.DriverName)"
        Write-Relatorio "Porta                  : $($wmi.PortName)"
        Write-Relatorio "Processador            : $($wmi.PrintProcessor)"
    }
} catch {
    Write-Relatorio "Driver                 : (nao consegui ler: $($_.Exception.Message))"
}

Write-Relatorio ([MyTenderTeste.Impressora]::Diagnostico($Impressora))

if ($SoDiagnostico) {
    Write-Host "Relatorio salvo em: $relatorio"
    return
}

# ------------------------------------------------------------ testes

function Invoke-Teste([string]$titulo, [scriptblock]$acao) {
    Write-Relatorio "---- $titulo"
    try {
        Write-Relatorio (& $acao)
        $cm = Read-Host 'Quantos cm de papel sairam? (Enter para pular)'
        if ($cm) { Write-Relatorio "Papel medido           : $cm cm" }
    } catch {
        Write-Relatorio "ERRO: $($_.Exception.Message)"
    }
}

while ($true) {
    Write-Host ''
    Write-Host '[1] GDI com altura de 100 mm  (o que o app faz)'
    Write-Host '[2] GDI com o papel padrao do driver'
    Write-Host '[3] ESC/POS direto (RAW) com corte'
    Write-Host '[0] Sair'
    $op = Read-Host 'Opcao'

    switch ($op) {
        '1' { Invoke-Teste 'GDI 80x100 mm' { [MyTenderTeste.Impressora]::ImprimirGdi($Impressora, 100) } }
        '2' { Invoke-Teste 'GDI padrao do driver' { [MyTenderTeste.Impressora]::ImprimirGdi($Impressora, 0) } }
        '3' { Invoke-Teste 'RAW ESC/POS' { [MyTenderTeste.Impressora]::ImprimirRaw($Impressora) } }
        '0' { break }
        default { Write-Host 'Opcao invalida.' }
    }
    if ($op -eq '0') { break }
}

Write-Host ''
Write-Host 'Como ler:'
Write-Host '  [1] saiu ~10 cm  -> o driver respeita a altura; o problema esta no app.'
Write-Host '  [1] saiu ~30 cm  -> o driver ignora a altura pedida e usa o papel padrao dele.'
Write-Host '  [3] saiu curto   -> imprimir ESC/POS direto resolve, sem depender do driver.'
Write-Host ''
Write-Host "Relatorio salvo em: $relatorio"
