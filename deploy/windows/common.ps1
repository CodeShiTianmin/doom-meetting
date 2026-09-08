# 公共函数: 解析 deploy/.env (KEY=VALUE, 忽略空行与 # 注释)
function Read-DotEnv {
    param([Parameter(Mandatory)][string]$Path)
    $result = @{}
    foreach ($line in Get-Content $Path -Encoding UTF8) {
        $trim = $line.Trim()
        if ($trim -eq "" -or $trim.StartsWith("#")) { continue }
        $idx = $trim.IndexOf("=")
        if ($idx -lt 1) { continue }
        $key = $trim.Substring(0, $idx).Trim()
        $val = $trim.Substring($idx + 1).Trim().Trim('"').Trim("'")
        $result[$key] = $val
    }
    return $result
}
