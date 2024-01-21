
# Name of directory where SD Card data will be stored
$outputDir = "data"
$debug = $false

### MAIN CODE BELOW -- DO NOT EDIT UNLESS YOU KNOW WHAT YOU'RE DOING ###
#                                                                      #

Add-Type -AssemblyName System.Web;

# Define a function to check if a service is reachable
function servicePing([string]$EZhost, [int]$port=80, [int]$timeout=1) {
  $cnt = 0
  $max = 3
  do {
    $cnt++
    $rtn = $false
    try {
      $socket = New-Object System.Net.Sockets.TcpClient
      $result = $socket.BeginConnect($EZhost, $port, $null, $null)
      $wait = $result.AsyncWaitHandle.WaitOne($timeout * 1000, $false)
      if (-not $wait) {
        $socket.Close()
        $rtn = $false
      }
      else {
        $socket.EndConnect($result) | Out-Null
        $socket.Close()
        $rtn = $true
      }
    }
    catch {
      $rtn = $false
    }
  } while ($cnt -lt $max)

  return $rtn
}

function fetchUrl($url,$outfile=$null,$debug=0) {
    $url = [System.Web.HttpUtility]::UrlDecode($url)

    if ($debug -eq 1) {
      Write-Host "fetchURL: $url"
    }

    if ($outfile -eq $null) {
      $response = Invoke-WebRequest $url
    } else {
      $response = Invoke-WebRequest $url -OutFile $outfile
    }
    return $response.Content
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

            if ($m[5] -match "([^.]+)\.(EDF|edf)") {
                $n = [regex]::Match($m[5], "([^.]+)\.(EDF|edf)").Groups.Value
                $m[5] = $n[1] + ".edf"
            }

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

# Check if the service is reachable
if (-not (servicePing "ezshare.card")) {
    Write-Host "Error: ez Share Card: Connection Failed"
    exit
}

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

Write-Host -NoNewline "Fetching "

# Files to fetch from root
# Note: files are compared (by date) and only pulled if newer
$files = @("Identification.crc", "Identification.json", "STR.edf")

$dst = $outputDir
foreach ($fn in $files) {
    foreach ($r in $list.root) {
        if ($r.name -eq $fn) {
            $out = Join-Path -Path $dst -ChildPath $r.name

            if (-not (Test-Path $out)) {
                $stat = 0
            }
            else {
                $s = Get-Item $out
                $stat = $s.LastWriteTime.Ticks
            }

            if (([datetime]::Parse($r.stat)).Ticks -gt $stat) {
		if ($debug -eq $true) {
                  Write-Host "Fetching: $($r.name)"
		} else {
                  Write-Host -NoNewline "+"
		}
                fetchUrl -url $r.url -outfile $out
            }
            else {
		if ($debug -eq $true) {
                  Write-Host "Skipping: $($r.name)"
		} else {
                  Write-Host -NoNewline "."
		}
            }
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
      Write-Host "Fetching: $out"
    } else {
      Write-Host -NoNewline "+"
    }
    fetchUrl -url $r.url -outfile $out
  }
  else {
    if ($debug -eq $true) {
      Write-Host "Skipping: $out"
    } else {
      Write-Host -NoNewline "."
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

    foreach ($f in $list.$folder) {
        $out = "$outputDir\$folder\" + $f.name

        if (-not (Test-Path $out)) {
	  if ($debug -eq $true) {
            Write-Host "Fetching: $out"
	  } else {
            Write-Host -NoNewline "+"
	  }
          fetchUrl -url $f.url -outfile $out
        }
        else {
	  if ($debug -eq $true) {
            Write-Host "Skipping: $out"
	  } else {
            Write-Host -NoNewline "."
	  }
        }
    }
}

Write-Host " Done"
exit
