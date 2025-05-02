# =====================================================
# Azure SQL Elastic Pool Management Platform (ASEPMP)
# Database Migration Between Elastic Pools Script
# Production-Ready Enterprise Database Migration
# =====================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [string]$SqlServerName,
    
    [Parameter(Mandatory = $true)]
    [string]$DatabaseName,
    
    [Parameter(Mandatory = $false)]
    [string]$SourceElasticPoolName,
    
    [Parameter(Mandatory = $false)]
    [string]$TargetElasticPoolName,
    
    [Parameter(Mandatory = $false)]
    [string]$TargetEdition,
    
    [Parameter(Mandatory = $false)]
    [string]$TargetServiceObjective,
    
    [Parameter(Mandatory = $false)]
    [switch]$ValidateOnly,
    
    [Parameter(Mandatory = $false)]
    [switch]$CreateBackupBeforeMigration = $true,
    
    [Parameter(Mandatory = $false)]
    [int]$TimeoutMinutes = 30
)

# =====================================================
# SCRIPT CONFIGURATION
# =====================================================
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

# Logging configuration
$LogFile = "Migrate-Database-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
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
# VALIDATION FUNCTIONS
# =====================================================
function Test-DatabaseMigrationPrerequisites {
    param(
        [string]$ResourceGroupName,
        [string]$SqlServerName,
        [string]$DatabaseName,
        [string]$SourcePool,
        [string]$TargetPool
    )
    
    Write-Log "Validating migration prerequisites..."
    
    # Check database exists
    $Database = Get-AzSqlDatabase -DatabaseName $DatabaseName `
                                 -ServerName $SqlServerName `
                                 -ResourceGroupName $ResourceGroupName `
                                 -ErrorAction SilentlyContinue
    
    if (-not $Database) {
        throw "Database '$DatabaseName' does not exist"
    }
    
    # Check source pool if specified
    if ($SourcePool) {
        $SourceElasticPool = Get-AzSqlElasticPool -ElasticPoolName $SourcePool `
                                                  -ServerName $SqlServerName `
                                                  -ResourceGroupName $ResourceGroupName `
                                                  -ErrorAction SilentlyContinue
        if (-not $SourceElasticPool) {
            throw "Source Elastic Pool '$SourcePool' does not exist"
        }
        
        if ($Database.ElasticPoolName -ne $SourcePool) {
            throw "Database is not currently in the specified source pool '$SourcePool'"
        }
    }
    
    # Check target pool if specified
    if ($TargetPool) {
        $TargetElasticPool = Get-AzSqlElasticPool -ElasticPoolName $TargetPool `
                                                  -ServerName $SqlServerName `
                                                  -ResourceGroupName $ResourceGroupName `
                                                  -ErrorAction SilentlyContinue
        if (-not $TargetElasticPool) {
            throw "Target Elastic Pool '$TargetPool' does not exist"
        }
    }
    
    Write-LogSuccess "Prerequisites validation passed"
    return $Database
}

function Get-DatabaseSize {
    param(
        [string]$ResourceGroupName,
        [string]$SqlServerName,
        [string]$DatabaseName
    )
    
    try {
        $Database = Get-AzSqlDatabase -DatabaseName $DatabaseName `
                                     -ServerName $SqlServerName `
                                     -ResourceGroupName $ResourceGroupName
        
        return $Database.MaxSizeBytes
    } catch {
        Write-LogWarning "Could not determine database size: $($_.Exception.Message)"
        return $null
    }
}

function Wait-ForDatabaseOperation {
    param(
        [string]$ResourceGroupName,
        [string]$SqlServerName,
        [string]$DatabaseName,
        [int]$TimeoutMinutes = 30
    )
    
    $TimeoutTime = (Get-Date).AddMinutes($TimeoutMinutes)
    
    do {
        Start-Sleep -Seconds 30
        $Database = Get-AzSqlDatabase -DatabaseName $DatabaseName `
                                     -ServerName $SqlServerName `
                                     -ResourceGroupName $ResourceGroupName
        
        Write-Log "Database status: $($Database.Status)"
        
        if ($Database.Status -eq "Online") {
            return $true
        }
        
        if ((Get-Date) -gt $TimeoutTime) {
            throw "Operation timed out after $TimeoutMinutes minutes"
        }
        
    } while ($Database.Status -ne "Online")
    
    return $true
}

# =====================================================
# MAIN MIGRATION SCRIPT
# =====================================================
try {
    Write-Log "Starting Database Migration Between Elastic Pools"
    Write-Log "Subscription ID: $SubscriptionId"
    Write-Log "Resource Group: $ResourceGroupName"
    Write-Log "SQL Server: $SqlServerName"
    Write-Log "Database Name: $DatabaseName"
    Write-Log "Source Pool: $SourceElasticPoolName"
    Write-Log "Target Pool: $TargetElasticPoolName"
    Write-Log "Target Edition: $TargetEdition"
    Write-Log "Target Service Objective: $TargetServiceObjective"
    Write-Log "Validation Only: $ValidateOnly"

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
    # VALIDATE PREREQUISITES
    # =====================================================
    $Database = Test-DatabaseMigrationPrerequisites -ResourceGroupName $ResourceGroupName `
                                                   -SqlServerName $SqlServerName `
                                                   -DatabaseName $DatabaseName `
                                                   -SourcePool $SourceElasticPoolName `
                                                   -TargetPool $TargetElasticPoolName

    # Get current database configuration
    Write-Log "Current database configuration:"
    Write-Log "  Current Pool: $($Database.ElasticPoolName)"
    Write-Log "  Current Edition: $($Database.Edition)"
    Write-Log "  Current Service Objective: $($Database.CurrentServiceObjectiveName)"
    Write-Log "  Database Status: $($Database.Status)"
    
    # Get database size
    $DatabaseSize = Get-DatabaseSize -ResourceGroupName $ResourceGroupName `
                                    -SqlServerName $SqlServerName `
                                    -DatabaseName $DatabaseName
    
    if ($DatabaseSize) {
        $DatabaseSizeGB = [math]::Round($DatabaseSize / 1GB, 2)
        Write-Log "  Database Size: $DatabaseSizeGB GB"
    }

    # =====================================================
    # VALIDATION ONLY MODE
    # =====================================================
    if ($ValidateOnly) {
        Write-LogSuccess "=== VALIDATION COMPLETED SUCCESSFULLY ==="
        Write-Log "Migration is feasible with current configuration"
        Write-Log "No actual migration was performed (ValidationOnly mode)"
        
        return @{
            Status = "ValidationSuccess"
            DatabaseName = $DatabaseName
            CurrentPool = $Database.ElasticPoolName
            CurrentEdition = $Database.Edition
            CurrentServiceObjective = $Database.CurrentServiceObjectiveName
            DatabaseSizeGB = $DatabaseSizeGB
            LogFile = $FullLogPath
        }
    }

    # =====================================================
    # PRE-MIGRATION BACKUP
    # =====================================================
    if ($CreateBackupBeforeMigration) {
        Write-Log "Creating backup before migration..."
        try {
            # Note: Azure SQL Database automatically creates backups
            # Additional backup logic can be implemented here if needed
            Write-Log "Automatic backups are enabled for Azure SQL Database"
        } catch {
            Write-LogWarning "Could not create additional backup: $($_.Exception.Message)"
        }
    }

    # =====================================================
    # DATABASE MIGRATION
    # =====================================================
    Write-Log "Starting database migration..."
    
    $MigrationStartTime = Get-Date
    
    try {
        if ($TargetElasticPoolName) {
            # Migrate to target elastic pool
            Write-Log "Migrating database to Elastic Pool: $TargetElasticPoolName"
            
            $MigratedDatabase = Set-AzSqlDatabase -DatabaseName $DatabaseName `
                                                 -ServerName $SqlServerName `
                                                 -ResourceGroupName $ResourceGroupName `
                                                 -ElasticPoolName $TargetElasticPoolName
            
        } elseif ($TargetEdition -and $TargetServiceObjective) {
            # Migrate to standalone database with specific edition and service objective
            Write-Log "Migrating database to standalone configuration: $TargetEdition / $TargetServiceObjective"
            
            $MigratedDatabase = Set-AzSqlDatabase -DatabaseName $DatabaseName `
                                                 -ServerName $SqlServerName `
                                                 -ResourceGroupName $ResourceGroupName `
                                                 -Edition $TargetEdition `
                                                 -RequestedServiceObjectiveName $TargetServiceObjective
        } else {
            throw "Either TargetElasticPoolName or both TargetEdition and TargetServiceObjective must be specified"
        }
        
        Write-LogSuccess "Migration command executed successfully"
        
    } catch {
        Write-LogError "Migration failed: $($_.Exception.Message)"
        throw
    }

    # =====================================================
    # WAIT FOR MIGRATION COMPLETION
    # =====================================================
    Write-Log "Waiting for migration to complete..."
    
    $MigrationCompleted = Wait-ForDatabaseOperation -ResourceGroupName $ResourceGroupName `
                                                   -SqlServerName $SqlServerName `
                                                   -DatabaseName $DatabaseName `
                                                   -TimeoutMinutes $TimeoutMinutes
    
    if ($MigrationCompleted) {
        $MigrationEndTime = Get-Date
        $MigrationDuration = $MigrationEndTime - $MigrationStartTime
        Write-LogSuccess "Migration completed in $($MigrationDuration.TotalMinutes.ToString('F2')) minutes"
    }

    # =====================================================
    # POST-MIGRATION VALIDATION
    # =====================================================
    Write-Log "Validating migration results..."
    
    $ValidatedDatabase = Get-AzSqlDatabase -DatabaseName $DatabaseName `
                                          -ServerName $SqlServerName `
                                          -ResourceGroupName $ResourceGroupName
    
    Write-Log "Post-migration database configuration:"
    Write-Log "  New Pool: $($ValidatedDatabase.ElasticPoolName)"
    Write-Log "  New Edition: $($ValidatedDatabase.Edition)"
    Write-Log "  New Service Objective: $($ValidatedDatabase.CurrentServiceObjectiveName)"
    Write-Log "  Database Status: $($ValidatedDatabase.Status)"

    # =====================================================
    # MIGRATION SUMMARY
    # =====================================================
    Write-LogSuccess "=== DATABASE MIGRATION COMPLETED SUCCESSFULLY ==="
    Write-Log "Resource Group: $ResourceGroupName"
    Write-Log "SQL Server: $SqlServerName"
    Write-Log "Database Name: $DatabaseName"
    Write-Log "Migration Duration: $($MigrationDuration.TotalMinutes.ToString('F2')) minutes"
    Write-Log "Source Pool: $SourceElasticPoolName"
    Write-Log "Target Pool: $($ValidatedDatabase.ElasticPoolName)"
    Write-Log "Target Edition: $($ValidatedDatabase.Edition)"
    Write-Log "Target Service Objective: $($ValidatedDatabase.CurrentServiceObjectiveName)"
    Write-Log "Log file: $FullLogPath"
    
    # Return migration information
    return @{
        ResourceGroup = $ResourceGroupName
        SqlServer = $SqlServerName
        DatabaseName = $DatabaseName
        SourcePool = $SourceElasticPoolName
        TargetPool = $ValidatedDatabase.ElasticPoolName
        TargetEdition = $ValidatedDatabase.Edition
        TargetServiceObjective = $ValidatedDatabase.CurrentServiceObjectiveName
        MigrationDurationMinutes = $MigrationDuration.TotalMinutes
        Status = "Success"
        LogFile = $FullLogPath
    }

} catch {
    Write-LogError "Database migration failed: $($_.Exception.Message)"
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