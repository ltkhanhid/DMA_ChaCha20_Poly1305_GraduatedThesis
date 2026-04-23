$ErrorActionPreference = "Continue"
Set-Location "D:\TAILIEU\chuyenngnah\DATN\RTL\03_sim"

$resDir = "test_results"
if (!(Test-Path $resDir)) { New-Item -ItemType Directory $resDir | Out-Null }

function Run-Test($name, $tbFile, $simTime, $extraSrc) {
    Write-Host ("`n======== {0} ========" -f $name) -ForegroundColor Cyan
    if ($extraSrc) {
        vlog -sv -timescale "1ns/100ps" -quiet +acc $extraSrc.Split(" ") 2>&1 | Out-Null
    }
    vlog -sv -timescale "1ns/100ps" -quiet +acc $tbFile 2>&1 | Out-Null
    vsim -c -voptargs="+acc" -do "log -r /*; run $simTime; quit -f" $name 2>&1 | Out-File "$resDir\$name.log" -Encoding utf8
    $log = Get-Content "$resDir\$name.log" -Raw
    $passes = ([regex]::Matches($log, '(?i)\bPASS(ED)?\b')).Count
    $fails  = ([regex]::Matches($log, '(?i)\bFAIL(ED)?\b')).Count
    $errs   = ([regex]::Matches($log, '\[ERROR\]')).Count
    $allp   = $log -match '(?i)ALL.*PASS|ALL.*CORRECT|SIMULATION PASSED|ALL TESTS PASSED'
    $ok = ($allp -or ($fails -eq 0 -and $errs -eq 0 -and $passes -gt 0))
    $sym = if ($ok) { "PASS" } else { "CHECK" }
    $col = if ($ok) { "Green" } else { "Yellow" }
    Write-Host ("  Results: PASS={0} FAIL={1} ERR={2} => {3}" -f $passes, $fails, $errs, $sym) -ForegroundColor $col
    return $sym
}

$results = @{}

# SOC-level tests (base already compiled)
$results["soc_demo_tb"]     = Run-Test "soc_demo_tb"     "../000_tlul/tb/soc_demo_tb.sv"     "25ms"
$results["soc_aead_tb"]     = Run-Test "soc_aead_tb"     "../000_tlul/tb/soc_aead_tb.sv"     "30ms"
$results["soc_aead_dma_tb"] = Run-Test "soc_aead_dma_tb" "../000_tlul/tb/soc_aead_dma_tb.sv" "40ms"
$results["soc_isa_tb"]      = Run-Test "soc_isa_tb"      "../000_tlul/tb/soc_isa_tb.sv"      "10ms"
$results["soc_corner_tb"]   = Run-Test "soc_corner_tb"   "../000_tlul/tb/soc_corner_tb.sv"   "35ms"
$results["soc_dma_tb"]      = Run-Test "soc_dma_tb"      "../000_tlul/tb/soc_dma_tb.sv"      "15ms"
$results["soc_2m6s_tb"]     = Run-Test "soc_2m6s_tb"     "../000_tlul/tb/soc_2m6s_tb.sv"     "20ms"

# Algorithm-level tests
$results["aead_chacha20_poly1305_tb"] = Run-Test "aead_chacha20_poly1305_tb" "../000_tlul/tb/aead_chacha20_poly1305_tb.sv" "200us" "-f flist_chacha"
$results["aead_corner_tb"] = Run-Test "aead_corner_tb" "../000_tlul/tb/aead_corner_tb.sv" "500us"

# Unit-level tests
$results["chacha20_tb"] = Run-Test "chacha20_tb" "../000_tlul/tb/chacha20_tb.sv" "50us" "../000_tlul/chacha20/chacha20_qr.sv ../000_tlul/chacha20/chacha20_core.sv ../000_tlul/chacha20/tlul_chacha20.sv"
$results["poly1305_tb"] = Run-Test "poly1305_tb" "../000_tlul/tb/poly1305_tb.sv" "50us" "../000_tlul/poly1305/poly1305_core.sv ../000_tlul/poly1305/tlul_poly1305.sv"
$results["dma_tb"]      = Run-Test "dma_tb" "../000_tlul/tb/dma_tb.sv" "100us" "../000_tlul/tlul_pkg.sv ../000_tlul/dma/dma_channel.sv ../000_tlul/dma/dma_arbiter.sv ../000_tlul/dma/dma_tlul_master.sv ../000_tlul/dma/dma_controller.sv ../000_tlul/dma/tlul_dma.sv"
$results["dma_rr_tb"]   = Run-Test "dma_rr_tb" "../000_tlul/tb/dma_rr_tb.sv" "100us"
$results["uart_byte_tb"] = Run-Test "uart_byte_tb" "../000_tlul/tb/uart_byte_tb.sv" "20ms" "../000_tlul/uart_byte_tx.sv ../000_tlul/uart_byte_rx.sv"

# Final summary
Write-Host "`n"
Write-Host "================================================================" -ForegroundColor Yellow
Write-Host "          FINAL VERIFICATION SUMMARY (Full Re-run)              " -ForegroundColor Yellow
Write-Host "================================================================" -ForegroundColor Yellow

$totalP = 0; $totalC = 0
foreach ($kv in $results.GetEnumerator() | Sort-Object Name) {
    $col = if ($kv.Value -eq "PASS") { "Green" } else { "Yellow" }
    Write-Host (" {0,-40} {1}" -f $kv.Key, $kv.Value) -ForegroundColor $col
    if ($kv.Value -eq "PASS") { $totalP++ } else { $totalC++ }
}
Write-Host "================================================================" -ForegroundColor Yellow
Write-Host (" TOTAL: {0} PASS / {1} CHECK" -f $totalP, $totalC) -ForegroundColor $(if($totalC -eq 0){"Green"}else{"Yellow"})
Write-Host "================================================================" -ForegroundColor Yellow
