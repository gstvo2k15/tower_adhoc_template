$log = '.\u_ex260706_x.log'

$lines = Get-Content -Path $log

# Obtener la definición real de columnas del log IIS
$fieldsLine = $lines |
    Where-Object { $_ -like '#Fields:*' } |
    Select-Object -First 1

if (-not $fieldsLine) {
    throw "No se encontró la línea #Fields en el log."
}

$fields = ($fieldsLine -replace '^#Fields:\s*', '') -split '\s+'

# Convertir cada línea del log en un objeto usando los nombres de #Fields
$errors = $lines |
    Where-Object {
        $_ -and $_ -notmatch '^#'
    } |
    ForEach-Object {
        $values = $_ -split '\s+'

        if ($values.Count -ne $fields.Count) {
            return
        }

        $row = [ordered]@{}

        for ($i = 0; $i -lt $fields.Count; $i++) {
            $row[$fields[$i]] = $values[$i]
        }

        if ($row['sc-status'] -eq '500') {
            [pscustomobject]@{
                Date     = $row['date']
                Time     = $row['time']
                UriStem  = $row['cs-uri-stem']
                Query    = $row['cs-uri-query']
                ClientIP = $row['c-ip']
                SubSt    = $row['sc-substatus']
                Win32    = $row['sc-win32-status']
            }
        }
    }

# Construir la URI completa y agrupar
$grouped = $errors |
    ForEach-Object {
        $uri = $_.UriStem

        if ($_.Query -and $_.Query -ne '-') {
            $uri = "${uri}?$($_.Query)"
        }

        [pscustomobject]@{
            URI      = $uri
            SubSt    = $_.SubSt
            Win32    = $_.Win32
            ClientIP = $_.ClientIP
            When     = "$($_.Date) $($_.Time)"
        }
    } |
    Group-Object -Property URI |
    Sort-Object Count -Descending

# Mostrar las 20 URI con más errores
$grouped |
    Select-Object -First 20 |
    ForEach-Object {
        $sample = $_.Group[0]

        [pscustomobject]@{
            Count    = $_.Count
            URI      = $_.Name
            SubSt    = $sample.SubSt
            Win32    = $sample.Win32
            ClientIP = $sample.ClientIP
            When     = $sample.When
        }
    } |
    Format-Table -AutoSize