# Configuration Settings:
#   Execute with admin rights to manage wifi adapter and radio state; non-admin will just connect if needed
#   Assumes SSID/profile name match for the ezShare connection
#   ezShare card SSID password stored in wifi profile; user needs to manually connect to ezShare once
#   Restores wifi adapter/radio/connection state post-execution including previous SSID connection
#   Set "ezShareSsid" to "" to omit wifi adapter/radio state/connection logic
$ezShareSsid = ""

# Name of directory where SD Card data will be stored
$outputDir = "data"
$debug = $false

### MAIN CODE BELOW -- DO NOT EDIT UNLESS YOU KNOW WHAT YOU'RE DOING ###
#                                                                      #

Add-Type -AssemblyName System.Web;

function fetchUrl($url,$outfile=$null,$debug=0) {
    $url = [System.Web.HttpUtility]::UrlDecode($url)

    if ($debug -eq 1) {
      Write-Host "fetchURL: $url" | Out-Host
    }

    if ($outfile -eq $null) {
      Try {
        $response = (New-Object System.Net.WebClient).DownloadString($url)
      } Catch [Exception] {
        Write-Host $_.Exception | format-list -force | Out-Host
      }
      return $response
    }

    $outfile = "$PWD\$outfile"
    Try {
      (New-Object System.Net.WebClient).DownloadFile($url, $outfile)
    } Catch [Exception] {
      Write-Host $_.Exception | format-list -force | Out-Host
    }
    return $null
}

function listDir($url, $dir = "root") {
    $output = fetchUrl -url $url
    $rows = $output -split "\n"

    $pattern = "^\s{3}(.{10})\s{3}(.{8})\s+([^\s]+)" +
               '\s+<a href="([^"]+)">(.*)<\/a>'

    $tz = [System.TimeZoneInfo]::Local
    [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, $tz.Id)

    $list = @{}
    $list[$dir] = @()

    foreach ($k in 0..($rows.Length - 1)) {
        $row = $rows[$k]
        if ($row -match $pattern) {
            $m = [regex]::Match($row, $pattern).Groups.Value
            $m[1] = $m[1] -replace " ", "0"
            $m[2] = $m[2] -replace " ", "0"
            $m[5] = $m[5].Trim()

            if ($m[5] -eq "." -or $m[5] -eq "..") { continue }

            $time = [DateTime]::ParseExact("$($m[1]) $($m[2])", "yyyy-MM-dd HH:mm:ss", $null).AddHours($myTimezone)
            $new = @{
                stat = $time.ToString('yyyy-MM-dd HH:mm:ss')
                url = $m[4]
                name = $m[5]
            }
            $list[$dir] += $new
        }
    }

    foreach ($r in $list[$dir]) {
        if ($r['url'] -match "^dir.*") {
            $url = "http://ezshare.card/" + $r['url']
            if ($dir -eq "root") {
                $newdir = $r['name']
            }
            else {
                $newdir = $dir + "\" + $r['name']
            }
	    $newlist = listDir -url $url -dir $newdir
	    $list = $($list; $newlist)
        }
    }

    return $list
}

# Check if the script is running as an administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

# Check if the Wi-Fi adapter is disabled and enable it
$didAdapterEnable = $false
$wifiAdapter = Get-NetAdapter -Name "Wi-Fi"
if ($isAdmin -and $ezShareSsid -ne "" -and $wifiAdapter.Status -eq "Disabled") {
    Enable-NetAdapter -Name "Wi-Fi" -Confirm:$false
    $didAdapterEnable = $true
}

# Check if the Wi-Fi radio is off and turn it on
$didRadioTurnOn = $false
$wifiSoftwareRadioOff = Get-NetAdapterAdvancedProperty -Name "Wi-Fi" -AllProperties -RegistryKeyword "SoftwareRadioOff"
if ($isAdmin -and $ezShareSsid -ne "" -and $wifiSoftwareRadioOff.RegistryValue -eq 1) {
    Set-NetAdapterAdvancedProperty -Name "Wi-Fi" -AllProperties -RegistryKeyword "SoftwareRadioOff" -RegistryValue 0
    $didRadioTurnOn = $true
}

# Check if we are already connected to the desired SSID profile
$didSsidConnect = $false
$connectedSsidProfile = @(netsh wlan show interfaces | Where-Object { $_ -Match '\bSSID\s+:' -or $_ -Match '\bProfile\s+:' } | ForEach-Object { ($_ -split ':')[1].Trim() }) + @("", "")
if ($ezShareSsid -ne "" -and $connectedSsidProfile[0] -ne "$ezShareSsid") {
    # Connect to the SSID/profile
    netsh wlan connect ssid="$ezShareSsid" name="$ezShareSsid" >$null 2>&1
    $didSsidConnect = $true
}

# Wait for the ping response from the specified address
# Note: Can use "192.16.8.4.1" instead of "ezshare.card" if you wish
$ezShareAddress = "ezshare.card"
Write-Host "Waiting for ez Share Site (Ctrl-C to Cancel): " -NoNewline
do {
    Write-Host "." -NoNewline
    $pingResult = Test-Connection -ComputerName "$ezShareAddress" -Count 1 -Quiet
    Start-Sleep -Seconds 2
} while (!$pingResult)
Write-Host ""

$url = "http://ezshare.card/dir?dir=A:"
$list = listDir -url $url;

if (-not $list.root -or -not $list.root.GetType().IsArray) {
    Write-Host "Error: missing root folder on EZ Share Card. Aborting!"
    exit
}

if (-not $list.DATALOG -or -not $list.DATALOG.GetType().IsArray) {
    Write-Host "Error: missing DATALOG folder on EZ Share Card. Aborting!"
    exit
}

if (-not $list.SETTINGS -or -not $list.SETTINGS.GetType().IsArray) {
    Write-Host "Error: missing SETTINGS folder on EZ Share Card. Aborting!"
    exit
}

if (-not (Test-Path $outputDir)) {
    Write-Host "Error: Output folder '$outputDir' doesn't exist. Aborting!"
    exit
}

$dst = $outputDir
Write-Host -NoNewline "Fetching " | Out-Host

# Files to fetch from root

foreach ($r in $list.root) {
  if ($r.name -match "System Volume Information") { continue }
  if ($r.name -match "ezshare.cfg") { continue }
  if ($r.url -match "^dir?.*" ) { continue }

  $out = Join-Path -Path $dst -ChildPath $r.name

  if (-not (Test-Path $out)) {
    $stat = 0
  } else {
    $s = Get-Item $out
    $stat = $s.LastWriteTime.Ticks
  }

  if (([datetime]::Parse($r.stat)).Ticks -gt $stat) {
    if ($debug -eq $true) {
      Write-Host "Fetching: $($r.name)" | Out-Host
    } else {
      Write-Host -NoNewline "+" | Out-Host
    }
    fetchUrl -url $r.url -outfile $out
  } else {
    if ($debug -eq $true) {
      Write-Host "Skipping: $($r.name)" | Out-Host
    } else {
      Write-Host -NoNewline "." | Out-Host
    }
  }
}

# fetch SETTINGS files

if (-not (Test-Path "$outputDir\SETTINGS")) {
    New-Item -ItemType Directory -Path "$outputDir\SETTINGS" | Out-Null
}

if (-not (Test-Path "$outputDir\SETTINGS" -PathType Container)) {
    Write-Host "Error: $outputDir\SETTINGS is not a directory."
    exit
}

foreach ($r in $list.SETTINGS) {
  $out = "$outputDir\SETTINGS\" + $r.name

  if (-not (Test-Path $out)) {
    if ($debug -eq $true) {
      Write-Host "Fetching: $out" | Out-Host
    } else {
      Write-Host -NoNewline "+" | Out-Host
    }
    fetchUrl -url $r.url -outfile $out
  }
  else {
    if ($debug -eq $true) {
      Write-Host "Skipping: $out" | Out-Host
    } else {
      Write-Host -NoNewline "." | Out-Host
    }
  }
}

# fetch DATALOG files

if (-not (Test-Path "$outputDir\DATALOG")) {
    New-Item -ItemType Directory -Path "$outputDir\DATALOG" | Out-Null
}

if (-not (Test-Path "$outputDir\DATALOG" -PathType Container)) {
    Write-Host "Error: $outputDir\DATALOG is not a directory."
    exit
}

foreach ($r in $list.DATALOG) {
    $folder = "DATALOG\" + $r.name

    if (-not (Test-Path "$outputDir\$folder") -or -not (Test-Path "$outputDir\$folder" -PathType Container)) {
        New-Item -ItemType Directory -Path "$outputDir\$folder" | Out-Null
    }

    Write-Host "" | Out-Host
    Write-Host -NoNewline "  $($r.name) " | Out-Host

    foreach ($f in $list.$folder) {
        $out = "$outputDir\$folder\" + $f.name

        if (-not (Test-Path $out)) {
	  if ($debug -eq $true) {
            Write-Host "Fetching: $out" | Out-Host
	  } else {
            Write-Host -NoNewline "+" | Out-Host
	  }
          fetchUrl -url $f.url -outfile $out
        }
        else {
	  if ($debug -eq $true) {
            Write-Host "Skipping: $out" | Out-Host
	  } else {
            Write-Host -NoNewline "." | Out-Host
	  }
        }
    }
}
Write-Host ""

# Restore State: Disconnect from the SSID, turn off radio, disable the adapter only if the script connected to them
if ($didSsidConnect) {
    # Re-connect to the old connected network, or dissconnect if blank
    if ($connectedSsidProfile[0] -eq "") {
        netsh wlan disconnect >$null 2>&1
    } else {
        netsh wlan connect ssid="$connectedSsidProfile[0]" name="$connectedSsidProfile[1]" >$null 2>&1
    }
}
if ($didRadioTurnOn) {
    # Turn off the Wi-Fi radio
    Set-NetAdapterAdvancedProperty -Name "Wi-Fi" -AllProperties -RegistryKeyword "SoftwareRadioOff" -RegistryValue 1
}
if ($didAdapterEnable) {
    # Disable the Wi-Fi adapter
    Disable-NetAdapter -Name "Wi-Fi" -Confirm:$false
}

Write-Host " Done"
exit
