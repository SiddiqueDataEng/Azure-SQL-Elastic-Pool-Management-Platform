# =====================================================
# Azure SQL Elastic Pool Management Platform (ASEPMP)
# Elastic Pool Infrastructure Deployment Script
# Production-Ready Enterprise Elastic Pool Provisioning
# =====================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [string]$Location,
    
    [Parameter(Mandatory = $true)]
    [string]$SqlServerName,
    
    [Parameter(Mandatory = $true)]
    [string]$ElasticPoolName,
    
    [Parameter(Mandatory = $false)]
    [string]$Edition = "Standard",
    
    [Parameter(Mandatory = $false)]
    [int]$Dtu = 100,
    
    [Parameter(Mandatory = $false)]
    [int]$DatabaseDtuMin = 10,
    
    [Parameter(Mandatory = $false)]
    [int]$DatabaseDtuMax = 100,
    
    [Parameter(Mandatory = $false)]
    [string]$AdminUsername = "sqladmin",
    
    [Parameter(Mandatory = $true)]
    [SecureString]$AdminPassword,
    
    [Parameter(Mandatory = $false)]
    [string]$Environment = "Production",
    
    [Parameter(Mandatory = $false)]
    [hashtable]$Tags = @{
        "Environment" = "Production"
        "Project" = "ASEPMP"
        "Owner" = "DatabaseTeam"
        "CostCenter" = "IT-Database"
    }
)

# =====================================================
# SCRIPT CONFIGURATION
# =====================================================
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

# Logging configuration
$LogFile = "Deploy-ElasticPool-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$LogPath = Join-Path -Path $PSScriptRoot -ChildPath "Logs"

if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

$FullLogPath = Join-Path -Path $LogPath -ChildPath $LogFile

# =====================================================
# LOGGING FUNCTIONS
# =====================================================
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    
    Write-Host $LogMessage
    Add-Content -Path $FullLogPath -Value $LogMessage
}

function Write-LogError {
    param([string]$Message)
    Write-Log -Message $Message -Level "ERROR"
}

function Write-LogWarning {
    param([string]$Message)
    Write-Log -Message $Message -Level "WARNING"
}

function Write-LogSuccess {
    param([string]$Message)
    Write-Log -Message $Message -Level "SUCCESS"
}

# =====================================================
# MAIN DEPLOYMENT SCRIPT
# =====================================================
try {
    Write-Log "Starting Azure SQL Elastic Pool Infrastructure Deployment"
    Write-Log "Subscription ID: $SubscriptionId"
    Write-Log "Resource Group: $ResourceGroupName"
    Write-Log "Location: $Location"
    Write-Log "SQL Server: $SqlServerName"
    Write-Log "Elastic Pool: $ElasticPoolName"
    Write-Log "Environment: $Environment"

    # =====================================================
    # AZURE AUTHENTICATION AND CONTEXT
    # =====================================================
    Write-Log "Configuring Azure context..."
    
    # Check if already connected to Azure
    $Context = Get-AzContext
    if (-not $Context) {
        Write-Log "Connecting to Azure..."
        Connect-AzAccount
    }
    
    # Set subscription context
    Write-Log "Setting subscription context to: $SubscriptionId"
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    
    # =====================================================
    # RESOURCE GROUP CREATION
    # =====================================================
    Write-Log "Checking if Resource Group exists: $ResourceGroupName"
    $ResourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    
    if (-not $ResourceGroup) {
        Write-Log "Creating Resource Group: $ResourceGroupName"
        $ResourceGroup = New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Tag $Tags
        Write-LogSuccess "Resource Group created successfully"
    } else {
        Write-Log "Resource Group already exists"
    }

    # =====================================================
    # SQL SERVER CREATION
    # =====================================================
    Write-Log "Checking if SQL Server exists: $SqlServerName"
    $SqlServer = Get-AzSqlServer -ServerName $SqlServerName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    
    if (-not $SqlServer) {
        Write-Log "Creating SQL Server: $SqlServerName"
        
        # Create SQL Server credential
        $SqlCredential = New-Object System.Management.Automation.PSCredential($AdminUsername, $AdminPassword)
        
        # Create SQL Server
        $SqlServer = New-AzSqlServer -ServerName $SqlServerName `
                                   -SqlAdministratorCredentials $SqlCredential `
                                   -Location $Location `
                                   -ResourceGroupName $ResourceGroupName `
                                   -Tag $Tags
        
        Write-LogSuccess "SQL Server created successfully"
        
        # Configure firewall rules
        Write-Log "Configuring SQL Server firewall rules..."
        
        # Allow Azure services
        New-AzSqlServerFirewallRule -ResourceGroupName $ResourceGroupName `
                                   -ServerName $SqlServerName `
                                   -FirewallRuleName "AllowAzureServices" `
                                   -StartIpAddress "0.0.0.0" `
                                   -EndIpAddress "0.0.0.0"
        
        # Get current public IP and add firewall rule
        try {
            $CurrentIP = (Invoke-RestMethod -Uri "https://ipinfo.io/json").ip
            New-AzSqlServerFirewallRule -ResourceGroupName $ResourceGroupName `
                                       -ServerName $SqlServerName `
                                       -FirewallRuleName "ClientAccess" `
                                       -StartIpAddress $CurrentIP `
                                       -EndIpAddress $CurrentIP
            Write-Log "Added firewall rule for current IP: $CurrentIP"
        } catch {
            Write-LogWarning "Could not determine current IP address for firewall rule"
        }
        
    } else {
        Write-Log "SQL Server already exists"
    }

    # =====================================================
    # ELASTIC POOL CREATION
    # =====================================================
    Write-Log "Checking if Elastic Pool exists: $ElasticPoolName"
    $ElasticPool = Get-AzSqlElasticPool -ElasticPoolName $ElasticPoolName `
                                       -ServerName $SqlServerName `
                                       -ResourceGroupName $ResourceGroupName `
                                       -ErrorAction SilentlyContinue
    
    if (-not $ElasticPool) {
        Write-Log "Creating Elastic Pool: $ElasticPoolName"
        Write-Log "Edition: $Edition, DTU: $Dtu, Min DTU: $DatabaseDtuMin, Max DTU: $DatabaseDtuMax"
        
        $ElasticPool = New-AzSqlElasticPool -ElasticPoolName $ElasticPoolName `
                                           -ServerName $SqlServerName `
                                           -ResourceGroupName $ResourceGroupName `
                                           -Edition $Edition `
                                           -Dtu $Dtu `
                                           -DatabaseDtuMin $DatabaseDtuMin `
                                           -DatabaseDtuMax $DatabaseDtuMax `
                                           -Tag $Tags
        
        Write-LogSuccess "Elastic Pool created successfully"
    } else {
        Write-Log "Elastic Pool already exists"
    }

    # =====================================================
    # DEPLOYMENT VALIDATION
    # =====================================================
    Write-Log "Validating deployment..."
    
    # Validate SQL Server
    $ValidatedServer = Get-AzSqlServer -ServerName $SqlServerName -ResourceGroupName $ResourceGroupName
    if ($ValidatedServer) {
        Write-LogSuccess "SQL Server validation passed"
    } else {
        throw "SQL Server validation failed"
    }
    
    # Validate Elastic Pool
    $ValidatedPool = Get-AzSqlElasticPool -ElasticPoolName $ElasticPoolName `
                                         -ServerName $SqlServerName `
                                         -ResourceGroupName $ResourceGroupName
    if ($ValidatedPool) {
        Write-LogSuccess "Elastic Pool validation passed"
    } else {
        throw "Elastic Pool validation failed"
    }

    # =====================================================
    # DEPLOYMENT SUMMARY
    # =====================================================
    Write-LogSuccess "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    Write-Log "Resource Group: $($ResourceGroup.ResourceGroupName)"
    Write-Log "SQL Server: $($ValidatedServer.ServerName)"
    Write-Log "SQL Server FQDN: $($ValidatedServer.FullyQualifiedDomainName)"
    Write-Log "Elastic Pool: $($ValidatedPool.ElasticPoolName)"
    Write-Log "Elastic Pool Edition: $($ValidatedPool.Edition)"
    Write-Log "Elastic Pool DTU: $($ValidatedPool.Dtu)"
    Write-Log "Log file: $FullLogPath"
    
    # Return deployment information
    return @{
        ResourceGroup = $ResourceGroup.ResourceGroupName
        SqlServer = $ValidatedServer.ServerName
        SqlServerFQDN = $ValidatedServer.FullyQualifiedDomainName
        ElasticPool = $ValidatedPool.ElasticPoolName
        Edition = $ValidatedPool.Edition
        DTU = $ValidatedPool.Dtu
        Status = "Success"
        LogFile = $FullLogPath
    }

} catch {
    Write-LogError "Deployment failed: $($_.Exception.Message)"
    Write-LogError "Stack trace: $($_.ScriptStackTrace)"
    
    # Return error information
    return @{
        Status = "Failed"
        Error = $_.Exception.Message
        LogFile = $FullLogPath
    }
    
    throw
}

# =====================================================
# SCRIPT COMPLETION
# =====================================================
Write-Log "Script execution completed"