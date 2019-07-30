$ErrorActionPreference = 'Stop'; # stop on all errors

$toolsDir = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$zipfile  = Join-Path $toolsDir "windows.rar"
$libfile = Join-Path $toolsDir "Get-Distrib.ps1"

# Скачивание дистрибутива

Import-Module $libfile

Get-Distrib `
  -username $env:USERS_USERNAME `
  -password $env:USERS_PASSWORD `
  -version $env:ChocolateyPackageVersion `
  -out_file $zipfile

# Параметры архива

$packageZipArgs = @{
  packageName   = $env:ChocolateyPackageName
  unzipLocation = $toolsDir
  File          = $zipfile
  softwareName  = '1c*'
  validExitCodes= @(0, 3010, 1641)
}

# Параметры установщика

$msi_name = '\1CEnterprise 8.msi'
if ($env:ChocolateyPackageVersion.Contains("8.2")) {
  $msi_name = '\1CEnterprise 8.2.msi'    
}

$packageMSIArgs = @{
  packageName   = $env:ChocolateyPackageName
  fileType      = 'MSI'
  softwareName  = '1c*'
  file          = $toolsDir + $msi_name
  silentArgs    = "/qr TRANSFORMS=1049.mst DESIGNERALLCLIENTS=1 THICKCLIENT=1 THINCLIENTFILE=1 THINCLIENT=1 WEBSERVEREXT=0 SERVER=0 CONFREPOSSERVER=0 CONVERTER77=0 SERVERCLIENT=0 LANGUAGES=RU"
  validExitCodes= @(0, 3010, 1641)
}

$path1cconf = "C:\Program Files (x86)\1cv8\" + $env:ChocolateyPackageVersion + "\bin\conf\conf.cfg" 
$cmd_break  = "/c " + "echo.>>" + """" + $path1cconf + """"
$cmd_unsafe = "/c " + "echo DisableUnsafeActionProtection=.*>>" + """" + $path1cconf + """"

Write-Output "Установка 1с"
Install-ChocolateyZipPackage @packageZipArgs
Install-ChocolateyInstallPackage @packageMSIArgs

if (-not $env:ChocolateyPackageVersion.Contains("8.2")) {
  Write-Output "Отключаем защиту от опасных действий"
  Start-ChocolateyProcessAsAdmin $cmd_break cmd
  Start-ChocolateyProcessAsAdmin $cmd_unsafe cmd
}

