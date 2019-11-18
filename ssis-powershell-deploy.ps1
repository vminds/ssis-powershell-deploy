[CmdletBinding()]
Param(
    [Parameter(Mandatory=$false)] [string]$solutionfile = "MyTestSolution-IS.sln",
    [Parameter(Mandatory=$false)] [string]$rootpath = "C:\dev\IS\MyTestSolution\",
    [Parameter(Mandatory=$false)] [string]$releasefolder = "\bin\Development\",
    [Parameter(Mandatory=$false)] [string]$sqlinstance = ".\sql2017",
    [Parameter(Mandatory=$false)] [string]$ssisfoldername = "MyTestSolution-IS",
    [Parameter(Mandatory=$false)] [string]$ssisfolderdescription = ""
)

Function Write-Log
{
    param([string]$value)
    $str = $env:computername + " " + (Get-Date) + " " + $value
    Write-Host $str
    if ($logfile.Length -gt 1) { Add-Content -Path $logfile -Value $str }
}

Function Get-SlnProjects
{
    param
    (
        [string] $slnFile
    )
    
    $dictProjs = @{}
    Get-Content "$slnFile" |
    Select-String 'Project\(' |
        ForEach-Object {
            $projectParts = $_ -Split '[,=]' | ForEach-Object { $_.Trim('[ "{}]') };
            $dictProjs.add($projectParts[3], $projectParts[1]);
            }

    return $dictProjs
}

Function Get-CatalogFolder
{
    param
    (
        [string] $folderName
    ,   [string] $folderDescription
    ,   [string] $serverName
    )

    $connectionString = [String]::Format("Data Source={0};Initial Catalog=master;Integrated Security=SSPI;", $serverName)

    $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)

    $integrationServices = New-Object Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices($connection)

    $catalog = $integrationServices.Catalogs["SSISDB"]

    $catalogFolder = $catalog.Folders[$folderName]

    if (-not $catalogFolder)
    {
        Write-Debug([System.string]::Format("Creating folder {0}", $folderName))
        $catalogFolder = New-Object Microsoft.SqlServer.Management.IntegrationServices.CatalogFolder($catalog, $folderName, $folderDescription)
        $catalogFolder.Create()
    }
    else
    {
        $catalogFolder.Description = $folderDescription
        $catalogFolder.Alter()
        Write-Debug([System.string]::Format("Existing folder {0}", $folderName))
    }

    return $catalogFolder
}

Write-Log "About to deploy solution $solutionfile"
Write-Log "Loading IS assembly"
# load the IS assembly
$loadStatus = [System.Reflection.Assembly]::Load("Microsoft.SQLServer.Management.IntegrationServices, Version=14.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91, processorArchitecture=MSIL")

# create or get SSIS catalog folder.
Write-Log "Get or create SSIS catalog"
$catalogFolder = Get-CatalogFolder -folderName $ssisfoldername -folderDescription $ssisfolderdescription -serverName $sqlinstance

# get all projects within solution
Write-Log "Get projects from .sln file"
$ssisProjects = Get-SlnProjects -slnFile $rootpath$solutionfile

foreach ($prj in $ssisProjects.GetEnumerator())
{
    # Read the project file and deploy it
    [string] $ispacFile = $rootpath + $prj.Value + $releasefolder + $prj.Value + ".ispac"
    if ((Test-Path $ispacFile) -eq $true)
    {
        Write-Log "Deploying " $prj.Value " project ..."
        [byte[]] $projectFile = [System.IO.File]::ReadAllBytes($ispacFile)
        $catalogFolder.DeployProject($prj.Value, $projectFile)
        Write-Log "Done."   
    }
    else
    {
        Write-Log("File " + $ispacFile + " not found - this project is not deployed") 
    }
}   

