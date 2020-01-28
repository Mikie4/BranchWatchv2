param([switch]$Save, [switch]$NoGUI=$FALSE, [switch]$Logging=$FALSE, [Switch]$debug=$FALSE)
Clear
Write-Host "Starting..."

<#
BUG: If site initializes as 'Down', no last up is ever set. This means, should the site come back up before 'DH",
    the $lastUp time will be 0 resulting in currentTime - 0 = Crazy number. This should be resolve when all times
    are saved into resource file. This is working as intended because I didn't want Downs to results in a new
    $upTime because blips don't mean anything.

Feature: Saveline creates a temp file which is then copied to res after completed. This is to avoid writing an
    incomplete resource file if the script is stopped mid refresh.

    Add [Switch]Save param | Fully Implemented

    Add externalResource param with path command and default

    Add [Switch]Archive for Archiving resource files

    Add [Switch]NoGUI param for showing GUI | Fully Implemented

    Add [Switch]NoLogging for logging Up/DownHard events | Fully Implemented

    Add Line Speed identifier | Not Started

    Add In-Place Upgrade (Ex. look for an upgrade file while writing resources) | Not Started

    Add JSON resource file | Not Started

    Add Address printout/E-mail on Down | Not Started

#>

################################################   
########                                ########
########        Class Definition        ########
########                                ########
################################################

class Branch
{    
    [ValidateNotNullorEmpty()][String]$Gateway
    [ValidateNotNullorEmpty()][String]$Server
    [ValidateNotNullorEmpty()][String]$BSD
    [ValidateNotNullorEmpty()][String]$Name
    [ValidateNotNullorEmpty()][String]$Division
    [ValidateNotNullorEmpty()][String]$Bank
    [ValidateNotNullorEmpty()][DateTime]$lastUp
    [ValidateNotNullorEmpty()][DateTime]$lastDown
    [ValidateNotNullorEmpty()][DateTime]$lastHardDown
    [ValidateNotNullorEmpty()][int]$Status
    [ValidateNotNullorEmpty()][int]$Ping
    [ValidateNotNullorEmpty()][int]$GatewayStatus

    $connectionStatuses = @("Unitialized", "Up", "Down", "DownHard")

    Branch($Gateway,$Server,$BSD,$Name,$Divison,$Bank,$lastUp,$lastDown,$lastHardDown){
        $this.Gateway = $Gateway
        $this.Server = $Server
        $this.BSD = $BSD
        $this.Name = $Name
        $this.Division = $Divison
        $this.Bank = $Bank
        $this.lastUp = [DateTime]::ParseExact($lastup,'yyyyMMddHHmm',$NULL)
        $this.lastDown = [DateTime]::ParseExact($lastDown,'yyyyMMddHHmm',$NULL)
        $this.lastHardDown = [DateTime]::ParseExact($lastHardDown,'yyyyMMddHHmm',$NULL)
        $this.Status = $this.initializeStatus()
        $this.Ping = -99
        $this.GatewayStatus = 1
    }

    Branch(){
        $this.Gateway = "0.0.0.0"
        $this.Server = "1.1.1.1"
        $this.BSD = "DEFAULT"
        $this.Name = "DEFAULT"
        $this.Division = "None"
        $this.Bank = "DEFAULT"
        $this.lastUp = 0
        $this.lastDown = 0
        $this.lastHardDown = 0
        $this.status = 0
        $this.Ping = -99
        $this.GatewayStatus = 1
    }
    
    <# 
    May not use this function. May implement in the future but no need at the moment.

    [String]TestGateway(){
        $this.TestConnection($this.Gateway)
        return $this.connectionStatuses[$this.status]
    }
    #>

    Refresh([string]$path, [string]$logFileName, [bool]$logging){
        $this.TestConnection($this.Server, $path, $logFileName, $logging)
    }

    TestConnection([string]$IP, [string]$path, [string]$logFileName, [bool]$logging){
        $PingSuccess = $FALSE
        
        $results = Test-Connection $IP -Count 1 -ErrorAction SilentlyContinue
        
        If($results -ne $NULL)
        {
            $PingSuccess = $TRUE
        }
        Else
        {
            $PingSuccess = $FALSE
        }

        If($PingSuccess)
        {
            # If it pings, check status

            #########
            ##
            ##  0 : Uninitialized
            ##  1 : Up
            ##  2 : Down
            ##  3 : DownHard
            ##
            #########

            $this.Ping = $results.ResponseTime

            Switch($this.Status)
            {
                0 # Uninitialized => Up
                { 
                    $this.lastUp = Get-Date
                    $this.Status = 1 
                }
                 
                1 # Up => No Change
                { } 

                2 # Down => Up 
                {                     
                    $this.Status = 1 
                } 

                3 # DownHard => Up. May add notifications later
                { 
                    $this.lastUp = Get-Date
                    $this.Status = 1
                    If($Logging)
                    {
                        $this.logLine($path, $logFileName, $this.connectionStatuses[$this.Status])
                    } 
                } 
            }
        }
        Else
        {

            $this.Ping = -1
            Switch($this.Status)
            {
                0 # Uninitialized => Down
                { 
                    $this.lastDown = Get-Date
                    $this.Status = 2 
                } 

                1 # Up => Down. Get Gateway Status.
                { 
                    $this.lastDown = Get-Date
                    $this.Status = 2
                    $this.GatewayStatus = Test-Connection $this.Gateway -Count 1 -Quiet -ErrorAction SilentlyContinue
                } 
                
                2 # Down : Check if time > 5 mins => DownHard, ELSE => No Change. Get Gateway Status. May add notifications later.
                { 
                    If( ($this.lastDown).AddMinutes(5) -lt (Get-Date) )
                    {
                        $this.lastHardDown = $this.lastDown
                        $this.Status = 3
                        If($Logging)
                        {
                            $this.logLine($path, $logFileName, $this.connectionStatuses[$this.Status])
                        }
                    }
                    $this.GatewayStatus = Test-Connection $this.Gateway -Count 1 -Quiet -ErrorAction SilentlyContinue
                } 
                
                3 # Down Hard => No Change. Get Gateway Status.
                { 
                    $this.GatewayStatus = Test-Connection $this.Gateway -Count 1 -Quiet -ErrorAction SilentlyContinue
                } 
            }
        }
    }

    printLine(){
        $pingResult = "??"
        $gwResult = "??"
        $time = [TimeSpan]0
        $nameColor = "Green"
        $pingColor = "White"
        $timeColor = "White"
        $bsdColor = "DarkCyan"
        $gwColor = "White"
        
        Switch($this.status)
        {
            #########
            ##
            ##  0 : Uninitialized
            ##  1 : Up
            ##  2 : Down
            ##  3 : DownHard
            ##
            #########

            0
            {
               $pingResult = "UI"
               $time = [TimeSpan]-1
               $pingColor = "White"
               $timeColor = "White"
            }

            1
            {
                $pingResult = $this.Ping
                $time = ((Get-Date) - $this.lastUp)
                If($this.Ping -gt 249)
                {
                    $pingColor = "Red"
                }
                ElseIf($this.ping -gt 149)
                {
                    $pingColor = "Yellow"
                }
                Else
                {
                    $pingColor = "Green"
                }         
                $timeColor = "Green"
                $gwResult = ""
            }
            
            2
            {
                If($this.GatewayStatus -eq 0) # If GW Down
                {
                    $pingResult = "SVR"
                    $gwResult = "/GW"
                    $gwColor = "Yellow"
                }
                else
                {
                    $pingResult = "SVR"
                    $gwResult = "/GW"
                    $gwColor = "Green"
                }
                
                $time = ((Get-Date) - $this.lastDown)
                $pingColor = "Yellow"
                $timeColor = "Yellow"
            }
            
            3
            {
                If($this.GatewayStatus -eq 0) # If GW Down
                {
                    $pingResult = "SVR"
                    $gwResult = "/GW"
                    $gwColor = "Red"
                }
                else
                {
                    $pingResult = "SVR"                                   
                    $gwResult = "/GW"
                    $gwColor = "Green"
                }
                
                $time = ((Get-Date) - $this.lastHardDown)
                $pingColor = "Red"
                $timeColor = "Red"
            }
        }
        
        Write-Host ("{0,-21}" -f $this.name) -ForeGroundColor $nameColor -NoNewLine
        #Write-Host ("{0,-8}" -f $pingResult) -ForeGroundColor $pingColor -NoNewLine
        Write-Host ("{0,-4}" -f $pingResult) -ForeGroundColor $pingColor -NoNewLine
        Write-Host ("{0,-4}" -f $gwResult) -ForeGroundColor $gwColor -NoNewLine
        
        If($this.Status -eq 2)
        {
            Write-Host ("{0,0}:{1,0}:{2,-6}" -f $time.Hours.toString().PadLeft(3,"0"), $time.minutes.toString().PadLeft(2,"0"), $time.seconds.toString().PadLeft(2,"0") ) -ForeGroundColor $timeColor -NoNewLine
        }
        else
        {
            Write-Host ("{0,0}:{1,0}:{2,-6}" -f $time.Days.toString().PadLeft(3,"0"), $time.Hours.toString().PadLeft(2,"0"), $time.minutes.toString().PadLeft(2,"0") ) -ForeGroundColor $timeColor -NoNewLine
        }
        

        Write-Host ("{0,0}" -f $this.bsd) -ForeGroundColor $bsdColor
    }

    saveLine([string]$path, [string]$tempFileName){        
        #$fileIn = Get-Content -Path "$path\resSaved.txt"

        ("{0,0}:{1,0}:{2,0}:{3,0}:{4,0}:{5,0}:{6,0}:{7,0}:{8,0}" -f $this.Name,$this.Server,$this.Gateway,$this.BSD,$this.Division,$this.Bank,($this.lastUp).toString("yyyyMMddHHmm"),($this.lastDown).toString("yyyyMMddHHmm"),($this.lastHardDown).toString("yyyyMMddHHmm")) | Add-Content "$path\$tempFileName" -Encoding Ascii        
    }

    logLine([string]$path, [string]$logFileName, [string]$status){
        $date = Get-Date
        ("{0,0}:{1,0}:{2,0}:{3,0}:{4,0}:{5,0}" -f $status,$this.Name,$this.Server,$this.Division,$this.Bank,$date.toString("yyyyMMddHHmm")) | Add-Content "$path\$logFileName" -Encoding Ascii
    }

    [int]initializeStatus(){
        $initStatus = 0
        If($this.lastUp -gt $this.lastDown)
        {
            If($this.lastUp -gt $this.lastHardDown)
            {
                $initStatus = 1
            }
            else
            {
                $initStatus = 3
            }
        }
        else
        {
            If($this.lastDown -gt $this.lastHardDown)
            {
                $initStatus = 2
            }
            else
            {
                $initStatus = 3
            }
        }
        return $initStatus
    }
}

################################################   
########                                ########
########      Function Definitions      ########
########                                ########
################################################

Function printTitle
{
    param()
    Process
    {
        $titleColor = "White"
        Write-Host ("{0,-21}" -f "Branch") -ForegroundColor $titleColor -noNewLine
        Write-Host ("{0,-8}" -f "Server") -ForegroundColor $titleColor -noNewLine        
        Write-Host ("{0,-13}" -f "Time") -ForegroundColor $titleColor -noNewLine
        Write-Host ("{0,0}" -f "BSD") -ForegroundColor $titleColor  
    }
}


################################################   
########                                ########
########         Initialization         ########
########                                ########
################################################

### Variables ###
#$resPath = Split-Path $MyInvocation.MyCommand.Path
$resPath = ".\"

$random = Get-Random -Minimum 1000 -Maximum 9999
$tempFileName = "resTemp$random.txt"
$resFileName = "res.txt"
$resBackupName = "resBackup.txt"
$logFileName = "upDownLog.txt"
$fileIn = Get-Content -Path "$resPath\$resfileName"

If($fileIn -eq $NULL -OR $fileIn -eq ""){
    $fileIn = Get-Content -Path "$resPath\$resBackupName"
}

$AllBranches = @()
$firstLoad = $TRUE


###  File read and object creation ###
ForEach($line in $fileIn)
{ 
    #$line
    $Gateway = ($line.Split(':') )[2].Trim()
    $Server = ($line.Split(':') )[1].Trim()
    $BSD = ($line.Split(':') )[3].Trim()
    $Name = ($line.Split(':') )[0].Trim()
    $Division = ($line.Split(':') )[4].Trim()
    $Bank = ($line.Split(':') )[5].Trim() 
    $LastUp = ($line.Split(':') )[6].Trim()
    $LastDown = ($line.Split(':') )[7].Trim()
    $LastHardDown = ($line.Split(':') )[8].Trim()

    New-Variable -Name ($line.Split(':') )[0].Trim() -Value (New-Object `
        Branch(`
            $Gateway,` 
            $Server,`
            $BSD,`
            $Name,`
            $Division,`
            $Bank,`
            $lastUp,`
            $lastDown,`
            $lastHardDown`
        )`
    )
    
    $temp = Get-Variable "$name" -ValueOnly

    $AllBranches = $AllBranches + $temp
    
    #$temp.Name 
}

################################################   
########                                ########
########           Main Loop            ########
########                                ########
################################################
While($true){
    $count = 0

    ### Refresh ###
    ForEach($branch in $AllBranches)
    {
        $branch.Refresh($resPath, $logFileName, $logging)

        If(-Not $NoGUI)
        {
            If($firstLoad)
            {
                [int]$loading = ($count / $allBranches.Count)*100
                If(-Not $debug)
                {
                    Clear
                }
            
                Write-Host "Loading... $loading"
            
                $count = $count + 1
            }
        }

        If($Save)
        {
            $branch.saveLine($resPath,$tempFileName)        
        }
    }
    $firstLoad = $FALSE
    
    If(-Not $NoGUI)
    {
        ### Display Title ###
        If(-Not $debug)
        {
            Clear
        }
        printTitle

        ### Display Results ###
        ForEach($branch in $AllBranches)
        {
            $branch.PrintLine()
        }
    }

    If($Save)
    {
        Copy-Item "$resPath\$resFileName" "$resPath\$resBackupName"
        Remove-Item "$resPath\$resFileName"
        Copy-Item "$resPath\$tempFileName" "$resPath\$resFileName"
        Remove-Item "$resPath\$tempFileName"
    }

    If($NoGUI)
    {     
        Clear
        Write-Host "Running..."
    }
    Sleep -s 1
}