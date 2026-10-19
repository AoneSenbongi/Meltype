$ErrorActionPreference='Stop'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$pipe=[IO.Pipes.NamedPipeClientStream]::new('.',('Meltype.NativeComposition.'+$sid),[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
$timeout=[Threading.CancellationTokenSource]::new(10000)
try {
    $pipe.Connect(3000)
    foreach($flags in @(66,67)) { # private Japanese connection; Shift down/up
        $memory=[IO.MemoryStream]::new();$writer=[IO.BinaryWriter]::new($memory)
        foreach($v in @(1,0,32,0,32,$flags)){$writer.Write([int]$v)}
        $writer.Write([Environment]::TickCount64)
        $bytes=$memory.ToArray();$pipe.Write($bytes,0,$bytes.Length);$writer.Dispose();$memory.Dispose()
        $header=[byte[]]::new(4)
        $null=$pipe.ReadExactlyAsync([Memory[byte]]$header,$timeout.Token).AsTask().GetAwaiter().GetResult()
        $length=[BitConverter]::ToInt32($header)
        if($length -lt 8 -or $length -gt 1048576){throw 'Invalid response length'}
        $payload=[byte[]]::new($length)
        $null=$pipe.ReadExactlyAsync([Memory[byte]]$payload,$timeout.Token).AsTask().GetAwaiter().GetResult()
        $reader=[IO.BinaryReader]::new([IO.MemoryStream]::new($payload))
        try {
            $responseFlags=$reader.ReadInt32();$count=$reader.ReadInt32()
            $commits=@();for($i=0;$i -lt $count;$i++){
                $kind=$reader.ReadInt32();$size=$reader.ReadInt32();$text=[Text.Encoding]::Unicode.GetString($reader.ReadBytes($size))
                if($kind -eq 1){$commits+=$text}
            }
            if($flags -eq 66 -and (($responseFlags -band 1) -ne 0 -or $commits.Count -ne 1 -or $commits[0] -ne [string][char]0x3000)){throw 'Shift+Space did not commit exactly one fullwidth space'}
            if($flags -eq 67 -and $commits.Count -ne 0){throw 'Key up duplicated the space'}
        } finally {$reader.Dispose()}
    }
    Write-Output 'PASS: installed broker commits one U+3000 for idle Shift+Space, with no duplicate on key up; isolated private connection'
} finally {$pipe.Dispose();$timeout.Dispose()}
