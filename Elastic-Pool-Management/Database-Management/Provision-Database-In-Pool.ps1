# =====================================================
# Azure SQL Elastic Pool Management Platform (ASEPMP)
# Database Provisioning in Elastic Pool Script
# Production-Ready Enterprise Database Management
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
    [string]$ElasticPoolName,
    
    [Parameter(Mandatory = $true)]
    [string]$DatabaseName,
    
    [Parameter(Mandatory = $false)]
    [string]$Collation = "SQL_Latin1_General_CP1_CI_AS",
    
    [Parameter(Mandatory = $false)]
    [string]$Environment = "Production",
    
    [Parameter(Mandatory = $false)]
    [hashtable]$Tags = @{
        "Environment" = "Production"
        "Project" = "ASEPMP"
        "Owner" = "DatabaseTeam"
        "CostCenter" = "IT-Database"
    },
    
    [Parameter(Mandatory = $false)]
    [switch]$CreateSampleData,
    
    [Parameter(Mandatory = $false)]
    [switch]$EnableBackup = $true,
    
    [Parameter(Mandatory = $false)]
    [switch]$EnableAuditing = $true
)

# =====================================================
# SCRIPT CONFIGURATION
# =====================================================
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

# Logging configuration
$LogFile = "Provision-Database-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
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
# MAIN PROVISIONING SCRIPT
# =====================================================
try {
    Write-Log "Starting Database Provisioning in Elastic Pool"
    Write-Log "Subscription ID: $SubscriptionId"
    Write-Log "Resource Group: $ResourceGroupName"
    Write-Log "SQL Server: $SqlServerName"
    Write-Log "Elastic Pool: $ElasticPoolName"
    Write-Log "Database Name: $DatabaseName"
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
    # VALIDATE PREREQUISITES
    # =====================================================
    Write-Log "Validating prerequisites..."
    
    # Check if Resource Group exists
    $ResourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $ResourceGroup) {
        throw "Resource Group '$ResourceGroupName' does not exist"
    }
    Write-Log "Resource Group validation passed"
    
    # Check if SQL Server exists
    $SqlServer = Get-AzSqlServer -ServerName $SqlServerName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $SqlServer) {
        throw "SQL Server '$SqlServerName' does not exist"
    }
    Write-Log "SQL Server validation passed"
    
    # Check if Elastic Pool exists
    $ElasticPool = Get-AzSqlElasticPool -ElasticPoolName $ElasticPoolName `
                                       -ServerName $SqlServerName `
                                       -ResourceGroupName $ResourceGroupName `
                                       -ErrorAction SilentlyContinue
    if (-not $ElasticPool) {
        throw "Elastic Pool '$ElasticPoolName' does not exist"
    }
    Write-Log "Elastic Pool validation passed"

    # =====================================================
    # DATABASE CREATION
    # =====================================================
    Write-Log "Checking if Database exists: $DatabaseName"
    $Database = Get-AzSqlDatabase -DatabaseName $DatabaseName `
                                 -ServerName $SqlServerName `
                                 -ResourceGroupName $ResourceGroupName `
                                 -ErrorAction SilentlyContinue
    
    if (-not $Database) {
        Write-Log "Creating Database in Elastic Pool: $DatabaseName"
        
        $Database = New-AzSqlDatabase -DatabaseName $DatabaseName `
                                     -ServerName $SqlServerName `
                                     -ResourceGroupName $ResourceGroupName `
                                     -ElasticPoolName $ElasticPoolName `
                                     -Collation $Collation `
                                     -Tag $Tags
        
        Write-LogSuccess "Database created successfully in Elastic Pool"
    } else {
        Write-Log "Database already exists"
        
        # Check if database is in the correct elastic pool
        if ($Database.ElasticPoolName -ne $ElasticPoolName) {
            Write-Log "Moving database to correct Elastic Pool: $ElasticPoolName"
            $Database = Set-AzSqlDatabase -DatabaseName $DatabaseName `
                                         -ServerName $SqlServerName `
                                         -ResourceGroupName $ResourceGroupName `
                                         -ElasticPoolName $ElasticPoolName
            Write-LogSuccess "Database moved to Elastic Pool successfully"
        }
    }

    # =====================================================
    # DATABASE CONFIGURATION
    # =====================================================
    Write-Log "Configuring database settings..."
    
    # Enable backup if requested
    if ($EnableBackup) {
        Write-Log "Configuring database backup settings..."
        # Note: Backup is automatically enabled for Azure SQL Database
        # Additional backup configuration can be added here
        Write-Log "Backup configuration completed"
    }
    
    # Enable auditing if requested
    if ($EnableAuditing) {
        Write-Log "Configuring database auditing..."
        try {
            # Enable database auditing
            Set-AzSqlDatabaseAudit -ResourceGroupName $ResourceGroupName `
                                  -ServerName $SqlServerName `
                                  -DatabaseName $DatabaseName `
                                  -BlobStorageTargetState Enabled `
                                  -StorageAccountResourceId "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/auditlogs$(Get-Random)"
            Write-LogSuccess "Database auditing enabled"
        } catch {
            Write-LogWarning "Could not enable auditing: $($_.Exception.Message)"
        }
    }

    # =====================================================
    # SAMPLE DATA CREATION
    # =====================================================
    if ($CreateSampleData) {
        Write-Log "Creating sample data..."
        
        # Sample SQL commands to create tables and insert data
        $SampleSqlCommands = @"
-- Create sample tables
CREATE TABLE Customers (
    CustomerID int IDENTITY(1,1) PRIMARY KEY,
    CustomerName nvarchar(100) NOT NULL,
    Email nvarchar(100),
    CreatedDate datetime2 DEFAULT GETDATE()
);

CREATE TABLE Orders (
    OrderID int IDENTITY(1,1) PRIMARY KEY,
    CustomerID int FOREIGN KEY REFERENCES Customers(CustomerID),
    OrderDate datetime2 DEFAULT GETDATE(),
    TotalAmount decimal(10,2)
);

-- Insert sample data
INSERT INTO Customers (CustomerName, Email) VALUES 
('John Doe', 'john.doe@example.com'),
('Jane Smith', 'jane.smith@example.com'),
('Bob Johnson', 'bob.johnson@example.com');

INSERT INTO Orders (CustomerID, TotalAmount) VALUES 
(1, 150.00),
(2, 275.50),
(1, 89.99),
(3, 425.00);

-- Create indexes for performance
CREATE INDEX IX_Orders_CustomerID ON Orders(CustomerID);
CREATE INDEX IX_Orders_OrderDate ON Orders(OrderDate);
"@
        
        try {
            # Execute sample SQL commands
            Invoke-Sqlcmd -ServerInstance "$SqlServerName.database.windows.net" `
                         -Database $DatabaseName `
                         -Query $SampleSqlCommands `
                         -AccessToken (Get-AzAccessToken -ResourceUrl "https://database.windows.net/").Token
            
            Write-LogSuccess "Sample data created successfully"
        } catch {
            Write-LogWarning "Could not create sample data: $($_.Exception.Message)"
        }
    }

    # =====================================================
    # DEPLOYMENT VALIDATION
    # =====================================================
    Write-Log "Validating database deployment..."
    
    # Validate database
    $ValidatedDatabase = Get-AzSqlDatabase -DatabaseName $DatabaseName `
                                          -ServerName $SqlServerName `
                                          -ResourceGroupName $ResourceGroupName
    
    if ($ValidatedDatabase -and $ValidatedDatabase.ElasticPoolName -eq $ElasticPoolName) {
        Write-LogSuccess "Database validation passed"
    } else {
        throw "Database validation failed"
    }

    # Get database metrics
    $DatabaseMetrics = Get-AzSqlDatabaseActivity -ResourceGroupName $ResourceGroupName `
                                                -ServerName $SqlServerName `
                                                -DatabaseName $DatabaseName `
                                                -ErrorAction SilentlyContinue

    # =====================================================
    # DEPLOYMENT SUMMARY
    # =====================================================
    Write-LogSuccess "=== DATABASE PROVISIONING COMPLETED SUCCESSFULLY ==="
    Write-Log "Resource Group: $ResourceGroupName"
    Write-Log "SQL Server: $SqlServerName"
    Write-Log "Elastic Pool: $ElasticPoolName"
    Write-Log "Database Name: $($ValidatedDatabase.DatabaseName)"
    Write-Log "Database Status: $($ValidatedDatabase.Status)"
    Write-Log "Database Collation: $($ValidatedDatabase.CollationName)"
    Write-Log "Database Creation Date: $($ValidatedDatabase.CreationDate)"
    Write-Log "Log file: $FullLogPath"
    
    # Return deployment information
    return @{
        ResourceGroup = $ResourceGroupName
        SqlServer = $SqlServerName
        ElasticPool = $ElasticPoolName
        DatabaseName = $ValidatedDatabase.DatabaseName
        DatabaseStatus = $ValidatedDatabase.Status
        Collation = $ValidatedDatabase.CollationName
        CreationDate = $ValidatedDatabase.CreationDate
        Status = "Success"
        LogFile = $FullLogPath
    }

} catch {
    Write-LogError "Database provisioning failed: $($_.Exception.Message)"
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