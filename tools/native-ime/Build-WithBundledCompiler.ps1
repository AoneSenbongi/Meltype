# Build in the workspace using the Roslyn compiler and .NET reference assemblies
# already bundled with this Codex host. No global SDK installation is required.
param([string]$TestFilter = 'Google', [switch]$VerifyGoogle, [switch]$VerifyLearning, [switch]$BuildOnly, [string]$JsonGenerator = $env:MELTYPE_JSON_GENERATOR)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$sourceRoot = $workspace
$buildRoot = Join-Path $workspace 'experimental-build'
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
$compiler = [Microsoft.CodeAnalysis.CSharp.CSharpCompilation]
$baseReferences = [System.Collections.Generic.List[Microsoft.CodeAnalysis.MetadataReference]]::new()
foreach ($dll in Get-ChildItem (Join-Path $PSHOME 'ref') -Filter '*.dll') {
    $baseReferences.Add([Microsoft.CodeAnalysis.MetadataReference]::CreateFromFile($dll.FullName))
}
foreach ($name in @('System.Windows.Forms.dll','System.Windows.Forms.Primitives.dll','System.Drawing.Common.dll','System.Private.Windows.Core.dll','System.Private.Windows.GdiPlus.dll','Accessibility.dll')) {
    $file = Join-Path $PSHOME $name
    if (Test-Path $file) { $baseReferences.Add([Microsoft.CodeAnalysis.MetadataReference]::CreateFromFile($file)) }
}
$parseOptions = [Microsoft.CodeAnalysis.CSharp.CSharpParseOptions]::Default.WithLanguageVersion([Microsoft.CodeAnalysis.CSharp.LanguageVersion]::Preview)
function Build-Project([string]$project, [string[]]$dependencies, [string[]]$friends, [bool]$forms, [string]$entry) {
    $trees = [System.Collections.Generic.List[Microsoft.CodeAnalysis.SyntaxTree]]::new()
    $projectDir = Join-Path $sourceRoot "src/$project"
    foreach ($file in Get-ChildItem $projectDir -Filter '*.cs' -Recurse | Where-Object FullName -NotMatch '[\\/](obj|bin)[\\/]') {
        $trees.Add([Microsoft.CodeAnalysis.CSharp.CSharpSyntaxTree]::ParseText([IO.File]::ReadAllText($file.FullName), $parseOptions, $file.FullName))
    }
    $generated = 'global using System; global using System.Collections.Generic; global using System.IO; global using System.Linq; global using System.Net.Http; global using System.Threading; global using System.Threading.Tasks;'
    if ($forms) { $generated += 'global using System.Drawing; global using System.Windows.Forms;' }
    foreach ($friend in $friends) { $generated += "[assembly: System.Runtime.CompilerServices.InternalsVisibleTo(`"$friend`")]" }
    $projectFile = [xml](Get-Content (Join-Path $projectDir ($project + '.csproj')) -Raw)
    $version = @($projectFile.Project.PropertyGroup.Version | Where-Object { $_ })[0]
    if (-not $version) { $version = '1.0.1' }
    $generated += '[assembly: System.Reflection.AssemblyVersion("' + $version + '.0")]'
    if ($project -eq 'Meltype') {
        $generated += 'namespace Meltype { internal static class ApplicationConfiguration { internal static void Initialize() { Application.SetHighDpiMode(HighDpiMode.PerMonitorV2); Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false); } } }'
    }
    $trees.Add([Microsoft.CodeAnalysis.CSharp.CSharpSyntaxTree]::ParseText($generated, $parseOptions))
    $refs = [System.Collections.Generic.List[Microsoft.CodeAnalysis.MetadataReference]]::new($baseReferences)
    foreach ($dependency in $dependencies) { $refs.Add([Microsoft.CodeAnalysis.MetadataReference]::CreateFromFile((Join-Path $buildRoot "$dependency.dll"))) }
    $kind = if ($entry) { [Microsoft.CodeAnalysis.OutputKind]::ConsoleApplication } else { [Microsoft.CodeAnalysis.OutputKind]::DynamicallyLinkedLibrary }
    $options = [Microsoft.CodeAnalysis.CSharp.CSharpCompilationOptions]::new($kind).WithAllowUnsafe($true).WithNullableContextOptions([Microsoft.CodeAnalysis.NullableContextOptions]::Enable)
    if ($entry) { $options = $options.WithMainTypeName($entry) }
    $compilation = $compiler::Create($project, $trees, $refs, $options)
    if ($project -eq 'Meltype.Core') {
        if (-not $JsonGenerator -or -not (Test-Path -LiteralPath $JsonGenerator)) {
            throw 'Set MELTYPE_JSON_GENERATOR to the .NET SDK System.Text.Json.SourceGeneration.dll path.'
        }
        $generatorAssembly = [Reflection.Assembly]::LoadFrom($JsonGenerator)
        $incremental = [Microsoft.CodeAnalysis.IIncrementalGenerator][Activator]::CreateInstance($generatorAssembly.GetType('System.Text.Json.SourceGeneration.JsonSourceGenerator'))
        $generator = [Microsoft.CodeAnalysis.GeneratorExtensions]::AsSourceGenerator($incremental)
        $driver = [Microsoft.CodeAnalysis.CSharp.CSharpGeneratorDriver]::Create([Microsoft.CodeAnalysis.ISourceGenerator[]]@($generator), $null, $parseOptions, $null)
        [Microsoft.CodeAnalysis.Compilation]$updated = $compilation
        $generatorDiagnostics = [System.Collections.Immutable.ImmutableArray[Microsoft.CodeAnalysis.Diagnostic]]::Empty
        $driver = $driver.RunGeneratorsAndUpdateCompilation($compilation, [ref]$updated, [ref]$generatorDiagnostics, [Threading.CancellationToken]::None)
        if (@($generatorDiagnostics | Where-Object Severity -EQ 'Error').Count) { throw ($generatorDiagnostics -join "`n") }
        $compilation = $updated
    }
    $resources = [System.Collections.Generic.List[Microsoft.CodeAnalysis.ResourceDescription]]::new()
    if ($project -eq 'Meltype.Core') {
        foreach ($file in Get-ChildItem (Join-Path $sourceRoot 'dictionaries') -Filter '*.txt') {
            $resourcePath = $file.FullName
            $provider = [Func[IO.Stream]]{ [IO.File]::OpenRead($resourcePath) }.GetNewClosure()
            $resources.Add([Microsoft.CodeAnalysis.ResourceDescription]::new("Meltype.dictionaries.$($file.Name)", $provider, $true))
        }
    }
    $stream = [IO.File]::Create((Join-Path $buildRoot "$project.dll"))
    try { $result = $compilation.Emit($stream, $null, $null, $null, $resources) } finally { $stream.Dispose() }
    if (-not $result.Success) {
        $result.Diagnostics | Where-Object Severity -EQ 'Error' | ForEach-Object ToString
        throw "Compilation failed: $project"
    }
    Write-Output "Build passed: $project"
}
Build-Project 'Meltype.Core' @() @('Meltype','Meltype.Tests','Meltype.Core.Tests') $false ''
Build-Project 'Meltype.Core.Tests' @('Meltype.Core') @('Meltype.Tests') $false 'Meltype.Tests.Program'
Build-Project 'Meltype' @('Meltype.Core') @('Meltype.Tests') $true ''
Build-Project 'Meltype.Tests' @('Meltype.Core','Meltype.Core.Tests','Meltype') @() $true 'Meltype.Tests.TestRunner'
if ($BuildOnly) { return }
foreach ($project in @('Meltype.Core','Meltype.Core.Tests','Meltype','Meltype.Tests')) {
    $loaded = [Reflection.Assembly]::LoadFrom((Join-Path $buildRoot "$project.dll"))
}
$runner = $loaded.GetType('Meltype.Tests.TestRunner').GetMethod('Main')
$arguments = if ($VerifyLearning) { [string[]]@('--google-learning') } elseif ($VerifyGoogle) { [string[]]@('--google-verify') } else { [string[]]@($TestFilter) }
$parameters = [object[]]::new(1)
$parameters[0] = [string[]]$arguments
$exitCode = $runner.Invoke($null, $parameters)
if ($exitCode -ne 0) { throw "Test failure: $exitCode" }
