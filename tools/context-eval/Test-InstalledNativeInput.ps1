param([switch]$Direct,[switch]$Clause,[switch]$Navigation,[switch]$Baseline,[switch]$NoTypedHeader,[string]$Text,[string]$Expected)
$ErrorActionPreference='Stop'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$pipe=[IO.Pipes.NamedPipeClientStream]::new('.',('Meltype.NativeComposition.'+$sid),[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
$timeout=[Threading.CancellationTokenSource]::new(10000)
$script:lastJapanese=''
function Send-ProbeKey([int]$Key,[char]$Character,[int]$Flags,[int]$Operation=0){
    $memory=[IO.MemoryStream]::new()
    $writer=[IO.BinaryWriter]::new($memory)
    try{
        foreach($v in @(1,$Operation,$Key,0,[int]$Character,$Flags)){$writer.Write([int]$v)}
        $writer.Write([Environment]::TickCount64)
        $bytes=$memory.ToArray();$pipe.Write($bytes,0,$bytes.Length)
    }finally{$writer.Dispose();$memory.Dispose()}
    $header=[byte[]]::new(4)
    $null=$pipe.ReadExactlyAsync([Memory[byte]]$header,$timeout.Token).AsTask().GetAwaiter().GetResult()
    $length=[BitConverter]::ToInt32($header)
    if($length -lt 8 -or $length -gt 1048576){throw 'Invalid probe response length'}
    $payload=[byte[]]::new($length)
    $null=$pipe.ReadExactlyAsync([Memory[byte]]$payload,$timeout.Token).AsTask().GetAwaiter().GetResult()
    $reader=[IO.BinaryReader]::new([IO.MemoryStream]::new($payload))
    try{
        $responseFlags=$reader.ReadInt32();$count=$reader.ReadInt32()
        if($Direct -and (($responseFlags -band 1) -eq 0 -or ($responseFlags -band 2) -ne 0)){throw 'English mode did not preserve direct input'}
        for($i=0;$i -lt $count;$i++){
            $kind=$reader.ReadInt32();$size=$reader.ReadInt32()
            $text=[Text.Encoding]::Unicode.GetString($reader.ReadBytes($size))
            if($kind -eq 0){$script:lastJapanese=$text; if($Direct){throw 'English mode started a composition'}}
        }
        if($Navigation -or $NoTypedHeader){
            $null=$reader.ReadInt32();$null=$reader.ReadInt32();$n=$reader.ReadInt32()
            $script:probeCandidates=@(for($i=0;$i -lt $n;$i++){$size=$reader.ReadInt32();[Text.Encoding]::Unicode.GetString($reader.ReadBytes($size))})
            if($NoTypedHeader){$size=$reader.ReadInt32();if($size -ne 0){throw 'Typed romaji header is still visible'}}
        }
    }finally{$reader.Dispose()}
}
try{
    $pipe.Connect(3000)
    $inputText=if($Direct){'hirumakkunisennka test.user+tag@example.com nihongo'}elseif($Clause){'tanniwotoru'}elseif($Navigation){'hirumakkunisennka?'}else{'nihongo'}
    if($Text){$inputText=$Text}
    foreach($c in $inputText.ToCharArray()){
        $key=[int][char]::ToUpperInvariant($c)
        Send-ProbeKey $key $c $(if($Direct){72}elseif($NoTypedHeader){96}else{64})
        Send-ProbeKey $key $c $(if($Direct){73}elseif($NoTypedHeader){97}else{65})
    }
    if($Direct){Write-Output 'PASS: English mode preserves romaji, spaces and email unchanged without Japanese composition';return}
    if($Text){
        Write-Output ('display: '+$script:lastJapanese)
        if($Expected){
            if($script:lastJapanese -ne $Expected){throw 'Immediate display differs from expected text'}
            for($i=0;$i -lt 8;$i++){Start-Sleep -Milliseconds 250;Send-ProbeKey 0 ([char]0) 64 5}
            Write-Output ('after model: '+$script:lastJapanese)
            if($script:lastJapanese -ne $Expected){throw 'Model changed the expected numeric conversion'}
        }
    }
    if($Navigation){
        for($i=0;$i -lt 8;$i++){Start-Sleep -Milliseconds 250;Send-ProbeKey 0 ([char]0) 64 5}
        $visible=$script:lastJapanese
        Write-Output ('live: '+$visible)
        Send-ProbeKey 37 ([char]0) 64; Send-ProbeKey 37 ([char]0) 65
        Write-Output ('left: '+$script:lastJapanese+' candidates: '+($script:probeCandidates -join '|'))
        if(!$Baseline -and $visible -ne $script:lastJapanese){throw 'Arrow navigation changed the live conversion'}
        for($i=0;$i -lt 8;$i++){
            if($script:probeCandidates -contains 'せんか' -or $script:probeCandidates -contains 'せん'){break}
            Send-ProbeKey 37 ([char]0) 64; Send-ProbeKey 37 ([char]0) 65
            Write-Output ('left: '+$script:lastJapanese+' candidates: '+($script:probeCandidates -join '|'))
            if(!$Baseline -and $visible -ne $script:lastJapanese){throw 'Clause movement changed another clause'}
        }
        if(!$Baseline){
            if($script:probeCandidates -notcontains 'せんか'){
                Send-ProbeKey 160 ([char]0) 66
                Send-ProbeKey 39 ([char]0) 66; Send-ProbeKey 39 ([char]0) 67
                Send-ProbeKey 160 ([char]0) 65
                Write-Output ('Shift+right enlarges: '+$script:lastJapanese)
            }
            if($script:probeCandidates -notcontains 'せんか'){throw 'Cannot select senka as one clause'}
            Send-ProbeKey 160 ([char]0) 66
            Send-ProbeKey 37 ([char]0) 66; Send-ProbeKey 37 ([char]0) 67
            Send-ProbeKey 160 ([char]0) 65
            if($script:probeCandidates -notcontains 'せん' -or !$script:lastJapanese.StartsWith('昼マックに')){throw 'Shift+left did not shrink only the target clause'}
            Send-ProbeKey 160 ([char]0) 66
            Send-ProbeKey 39 ([char]0) 66; Send-ProbeKey 39 ([char]0) 67
            Send-ProbeKey 160 ([char]0) 65
            if($script:probeCandidates -notcontains 'せんか' -or !$script:lastJapanese.StartsWith('昼マックに')){throw 'Shift+right did not restore the target clause boundary'}
            $beforeDown=$script:lastJapanese
            $beforeCount=$script:probeCandidates.Count
            Send-ProbeKey 40 ([char]0) 64; Send-ProbeKey 40 ([char]0) 65
            if($beforeDown -eq $script:lastJapanese -or $beforeCount -ne $script:probeCandidates.Count){throw 'Down did not switch candidates with unchanged boundaries'}
            Send-ProbeKey 38 ([char]0) 64; Send-ProbeKey 38 ([char]0) 65
            if($beforeDown -ne $script:lastJapanese){throw 'Up did not restore the previous candidate'}
            for($i=0;$i -lt 256;$i++){
                if($script:lastJapanese -eq '昼マックにせんか？'){break}
                Send-ProbeKey 40 ([char]0) 64; Send-ProbeKey 40 ([char]0) 65
                if(!$script:lastJapanese.StartsWith('昼マックに')){throw 'Down changed the earlier phrase'}
            }
            if($script:lastJapanese -ne '昼マックにせんか？'){throw ('Down did not select hiragana: '+$script:lastJapanese)}
            Write-Output ('PASS: left/right select and up/down choose candidates without Fn or changes to hirumakku; '+$script:lastJapanese)
        }
    }
    if($Clause){
        Send-ProbeKey 37 ([char]0) 64
        Send-ProbeKey 37 ([char]0) 65
        Send-ProbeKey 117 ([char]0) 64
        Send-ProbeKey 117 ([char]0) 65
        if($script:lastJapanese -ne '単位をとる'){throw ('Selected clause F6 changed another clause: '+$script:lastJapanese)}
        Send-ProbeKey 121 ([char]0) 64
        Send-ProbeKey 121 ([char]0) 65
        if($script:lastJapanese -ne '単位をtoru'){throw ('Selected clause F10 changed another clause: '+$script:lastJapanese)}
    }
    if($script:lastJapanese -notmatch '[ぁ-ん一-龯]'){throw 'Installed broker did not produce Japanese text'}
    # Private field flag disables learning; Escape cancels without committing anywhere.
    Send-ProbeKey 27 ([char]0) $(if($NoTypedHeader){96}else{64})
    Send-ProbeKey 27 ([char]0) $(if($NoTypedHeader){97}else{65})
    if($NoTypedHeader){Write-Output 'PASS: installed broker shows Japanese input with no typed romaji header';return}
    Write-Output $(if($Navigation){'PASS: live navigation probe cancelled private input without learning'}elseif($Clause){'PASS: installed broker selected-clause F6/F10 preserves the other clauses; private input cancelled'}else{'PASS: installed native broker converts nihongo to Japanese in a private isolated connection; input cancelled'})
}finally{$pipe.Dispose();$timeout.Dispose()}
