
$product = Get-WmiObject -Class 'Win32_Product' -Filter 'Name="Microsoft Azure Service Fabric SDK"'
if ($product) {
    Write-Host "Uninstalling '$($env:chocolateyPackageName) $($env:chocolateyPackageVersion)'..."
    $product.Uninstall() | Out-Null
}
