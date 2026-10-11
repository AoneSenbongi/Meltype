param([string]$RenderTo)
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $PSScriptRoot 'NativeGuiCommon.ps1')
$context=Get-NativeGuiContext $root
$package=if($context.Installed){$context.State.PackageRoot}else{Join-Path $root 'experimental-build/native-ime-package'}
[Reflection.Assembly]::LoadFrom((Join-Path $package 'Meltype.Core.dll'))|Out-Null
$app=[Reflection.Assembly]::LoadFrom((Join-Path $package 'Meltype.dll'))
Add-Type -AssemblyName System.Windows.Forms
[Windows.Forms.Application]::EnableVisualStyles()
$path=Join-Path $env:LOCALAPPDATA 'Meltype/snippets.json'
$store=[Meltype.Composition.SnippetStore]::new($path)
$type=$app.GetType('Meltype.UI.SnippetsForm',$true)
$form=[Activator]::CreateInstance($type,[Reflection.BindingFlags]'Public,NonPublic,Instance',$null,[object[]]@($store,[Func[string]]{';'}),$null)
# STARTUPINFO hides the first window along with the console. Re-show the form
# after its first display so the registration window remains visible.
$form.Add_Shown({$form.BeginInvoke([Action]{$form.Hide();$form.Show();$form.Activate()})|Out-Null})
try {
    if($RenderTo){
        $form.Show();[Windows.Forms.Application]::DoEvents()
        $bitmap=[Drawing.Bitmap]::new($form.Width,$form.Height)
        try{$form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$form.Width,$form.Height));$bitmap.Save($RenderTo)}finally{$bitmap.Dispose()}
    }else{[Windows.Forms.Application]::Run($form)}
}finally{$form.Dispose()}
