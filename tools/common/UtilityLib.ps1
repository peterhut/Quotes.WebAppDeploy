function ReplaceFileParameters() {
    Param(
        [Parameter(Mandatory = $true, Position = 0)] [string] $filePath,
        [Parameter(Mandatory = $true, Position = 1)] [array] $arguments
    )
    $fileContent = Get-Content -Raw $filePath
    for ($i = 0; $i -lt $arguments.Count; $i++) {
        $fileContent = $fileContent.Replace("{$i}", $arguments[$i])
    }
    return $fileContent
}

<#
.SYNOPSIS
    Generates a random string.

 .DESCRIPTION
    Generates a random string of characters, numbers and symbols suitable as passwords.

 .PARAMETER size
    Length of the generated string
    
 .PARAMETER charSets
    Determines which characters/symbols will be used to generate the string. U=Upper case, L=Lower case, N=Numerals, S=Symbols. 
    Upper case means mandator (ULNS)=at least one is used. Lower case (ulns)=may be used.

 .PARAMETER excluse
    Characters to exclude. Use for example to avoid confusing characters like O,o and 0.
#>
Function New-String([Int]$Size = 8, [Char[]]$CharSets = "ULNS", [Char[]]$Exclude) {
    # Source: http://stackoverflow.com/questions/37256154/powershell-password-generator-how-to-always-include-number-in-string
    $Chars = @(); $TokenSet = @()
    If (!$TokenSets) {
        $Global:TokenSets = @{
            U = [Char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZ'                                #Upper case
            L = [Char[]]'abcdefghijklmnopqrstuvwxyz'                                #Lower case
            N = [Char[]]'0123456789'                                                #Numerals
            S = [Char[]]'!#%&()*+-/?@[]^_|~'                         #Symbols - removed <>\
        }
    }
    $CharSets | ForEach {
        $Tokens = $TokenSets."$_" | ForEach {If ($Exclude -cNotContains $_) {$_}}
        If ($Tokens) {
            $TokensSet += $Tokens
            If ($_ -cle [Char]"Z") {$Chars += $Tokens | Get-Random}             #Character sets defined in upper case are mandatory
        }
    }
    While ($Chars.Count -lt $Size) {$Chars += $TokensSet | Get-Random}
    ($Chars | Sort-Object {Get-Random}) -Join ""                                #Mix the (mandatory) characters and output string
}; Set-Alias New-Password New-String -Description "Generate a random string (password)"

<#
.SYNOPSIS
    Replaces placeholders in a file.

 .DESCRIPTION
    Replaces placeholders in a file using a lookup table. The result is the contents of the file, but with the 
	placeholders replaced by the values specified by the lookup table.

 .PARAMETER filePath
    A file containing placeholders. The placeholders should be formatted as @{placeholder}
    
 .PARAMETER lookupTable
	A hashtable of placeholder names and corresponding values that should be inserted instead of the placeholder.
#>
function ReplaceNamedFileParameters() {	
    Param(
        [Parameter(Mandatory = $true, Position = 0)] [string] $FilePath,
        [Parameter(Mandatory = $true, Position = 1)] [hashtable] $PlaceholderValues
    )
    $result = Get-Content -Path $FilePath | ForEach-Object { 
        $line = $_

        $PlaceholderValues.GetEnumerator() | ForEach-Object {
            $placeholder = "@{" + $_.Key + "}"
            if ($line -match $placeholder) {
                $line = $line -replace $placeholder, $_.Value
            }
        }
        $line
    }
    # From: http://stackoverflow.com/questions/36636607/getting-all-placeholders-from-file-with-pattern-using-powershell
    $remainingPlaceholders = $result | % { [regex]::Matches($_, '@\{\w+\}').Value }
    Write-Information "Replaced placeholders in $FilePath Remaining placeholders: $remainingPlaceholders"
	
    # Convert from Array of lines to single string
    return $result | Out-String
}

<#
.SYNOPSIS
    Calculates a hash for files in a folder based on the contents of the files.

 .DESCRIPTION
    Calculates a hash for files in a folder based on the contents of the files. The files names do not influence the hash
    except when the alfabetical order of the full file names (including paths) changes.

 .PARAMETER folder
    The path to the folder for which the hash should be calculated.

 .PARAMETER algorithm
    The algorithm to use for the Hash. Default = SHA1. Allowed values: 	SHA1, SHA256, SHA384, SHA512, MACTripleDES, MD5, RIPEMD160
#>
function Get-FolderHash {
    [cmdletbinding()]
    Param(
        [string]$folder,
        [string]$algorithm = 'SHA1')

    # Sort file list alfabetically on the full path to ensure if the same files are present they are 
    # used in the same order every calculation

    Write-Verbose "Hashing using $algorithm"

    $StopWatch = [system.diagnostics.stopwatch]::StartNew()
    $hashList = (Get-ChildItem $folder -Recurse -File) | sort FullName | Get-FileHash -Algorithm $algorithm    
    
    # Convert all hashes to Byte Arrays
    $hashByteArrays = $hashList | foreach { Convert-HexStringToByteArray $_.Hash }

    # Take first hash as the starting point
    $combinedHash = $hashByteArrays[0].clone()

    # Combine the hashes of all files using the XOR function
    # For an explanation on why XOR is used see https://stackoverflow.com/questions/5889238/why-is-xor-the-default-way-to-combine-hashes

    # Skip first, and xor each next hash with the result of the previous
    for ($i = 1; $i -lt $hashByteArrays.count; $i++) { 
        InPlaceXorByteArrays $combinedHash $hashByteArrays[$i]
    }

    # Convert to a readable Hex String
    [System.BitConverter]::ToString($combinedHash).Replace("-", "")
    $StopWatch.Stop()

    
    Write-Verbose "Duration to calculate $algorithm hash over $($hashList.count) files  [ms]: $($StopWatch.Elapsed.TotalMilliseconds)"
}

<#
.SYNOPSIS
    Apply the -bxor operator to all elements in both arrays and replace the elements in the first array with the result.

 .PARAMETER bytes1
    An array of bytes. Elements in this array are replaced with the result of -bxor on elements in both arrays at the same position.

 .PARAMETER bytes2
    An array of bytes. The other array used in the -bxor.
#>
function InPlaceXorByteArrays($bytes1, $bytes2) {
    if ($bytes1.count -ne $bytes2.count) {
        throw "This function can only be used to Xor two byte arrays of equal lengh. 1: $($bytes1.count) 2: $($bytes2.count)"
    }
    for ($i = 0; $i -lt $bytes1.count; $i++) { 
        $bytes1[$i] = $bytes1[$i] -bxor $bytes2[$i] 
    }
}

<#
.SYNOPSIS
    Convert a String reprenting a Hex value to a Byte array representing the same value as bytes.

 .PARAMETER String
    The value as a Hexadecimal number in a string. Example: "203B2456B99F92B5C97A52413D5D49F3"
#>
function Convert-HexStringToByteArray( [Parameter(Mandatory = $True, ValueFromPipeline = $True)] [String] $String ) { 
    # Clean out whitespaces and any other non-hex characters
    $String = $String.ToLower() -replace '[^a-f0-9]', ''
  
    # The ",@(...)" syntax forces the output into an array even if there is only one element in the output (or none).
    if ($String.Length -eq 0) { 
        , @()
    }
    elseif ($String.Length -eq 1) { 
        , @([System.Convert]::ToByte($String, 16)) 
    }
    elseif ($String.Length % 2 -eq 0) { 
        , @($String -split '([a-f0-9]{2})' | foreach { if ($_) { [System.Convert]::ToByte($_, 16) }}) 
    }
    else {
        throw "Uneven number of characters cannot be converted to a Byte array."
    }
}

<#
.SYNOPSIS
Executes a ScriptBlock and retries it if it fails.

.PARAMETER ScriptBlock
The ScriptBlock to execute. The ScriptBlock will be retried when it fails (Throws an exception or calls Write-Error).

.PARAMETER RetryDelayInSeconds
The number of seconds to wait before retrying.

.PARAMETER MaxTries
The maximum number of times the ScriptBlock should be tried in case of failures.

.PARAMETER FailureIsWarning
Optional, when last try fails write a warning instead of throwing an error. Default: $false
#>
function Start-WithRetry {
    [CmdletBinding()]
    param(    
        [Parameter(ValueFromPipeline, Mandatory)]
        $ScriptBlock,
        [Parameter(Mandatory)]
        [int]
        $RetryDelayInSeconds,
        [Parameter(Mandatory)]
        [int]
        $MaxTries,
        [switch]
        $FailureIsWarning
    )
    
    $tries = 0
    $success = $false
    $cmdText = $ScriptBlock.ToString()
    $cmdTextTruncated = $cmdText.SubString(0, [System.Math]::Min(40, $cmdText.Length)) 

    while (!$success -and $tries -lt $MaxTries) {
        try {
            $result = & $ScriptBlock
            $success = $true
            Write-Verbose "Successfully executed [$cmdTextTruncated]"

            return $result
        }
        catch {
            # Tried ScriptBlock and failed
            $tries++
            
            if ($tries -ge $MaxTries) {
                # Scriptblock has now been given the maximum number of tries and still fails
                if (!$FailureIsWarning) {                
                    throw "Could not execute [$cmdTextTruncated] after #$tries tries. The error: $_"
                }
                else {
                    Write-Warning "Could not execute [$cmdTextTruncated]. The error message: $_"
                }
            }
            else {
                Write-Information "Failed attempt #$tries executing [$cmdTextTruncated]. Waiting $RetryDelayInSeconds second(s) before retrying. Message: $_"
                Start-Sleep -s $RetryDelayInSeconds
            }
        }
    }
}

<#
.SYNOPSIS
 Returns the first parameter that is not $null. If none of the parameters
 has a value an error is thrown.

.PARAMETER a
 Value that is only returned if it is not null or empty ("").

.PARAMETER b
 Value that is returned if a is null this is not null or empty ("").

.PARAMETER c
 Value that is returned if b is null this is not null or empty ("").
#>
function CoalesceRequired($a, $b, $c) { 
    if ($a) { $a } 
    elseif ($b) { $b } 
    elseif ($c) { $c }
    else {
        Throw "No non-null/non-empty value was provided."
    }
}