# =====================================================
# Azure SQL Elastic Pool Management Platform (ASEPMP)
# Complete Platform Deployment Script
# Production-Ready Enterprise Elastic Pool Management
# =====================================================

<#
.SYNOPSIS
    Deploys the complete Azure SQL Elastic Pool Management Platform.

.DESCRIPTION
    This script deploys a comprehensive elastic pool management solution including:
    - Multiple elastic pools across regions
    - Database provisioning and migration
    - Performance monitoring and optimization
    - Cost management and reporting
    - Automated scaling and management

.PARAMETER SubscriptionId
    The Azure subscription ID for deployment.

.PARAMETER PrimaryResourceGroupName
    The name of the primary resource group.

.PARAMETER PrimaryRegion
    The primary Azure region for deployment.

.PARAMETER SecondaryRegion
    The secondary Azure region for multi-region deployment.

.PARAMETER ServerNamePrefix
    The prefix for SQL server names.

.PARAMETER AdminUsername
    The administrator username for SQL servers.

.PARAMETER AdminPassword
    The administrator password for SQL servers.

.PARAMETER NotificationEmails
    Array of email addresses for notifications.

.EXAMPLE
    .\Deploy-Elastic-Pool-Platform.ps1 -SubscriptionId "12345678-1234-1234-1234-123456789012" -PrimaryResourceGroupName "rg-asepmp-prod" -PrimaryRegion "East US" -SecondaryRegion "West US 2" -ServerNamePrefix "sql-asepmp" -AdminUsername "sqladmin" -AdminPassword (ConvertTo-SecureString "SecurePass123!" -AsPlainText -Force) -NotificationEmails @("admin@company.com")
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $true)]
    [string]$PrimaryResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [string]$PrimaryRegion,
    
    [Parameter(Mandatory = $false)]
    [string]$SecondaryRegion = "",
    
    [Parameter(Mandatory = $true)]
    [string]$ServerNamePrefix,
    
    [Parameter(Mandatory = $true)]
    [string]$AdminUsername,
    
    [Parameter(Mandatory = $true)]
    [SecureString]$AdminPassword,
    
    [Parameter(Mandatory = $true)]
    [string[]]$NotificationEmails,
    
    [Parameter(Mandatory = $false)]
    [bool]$DeployMultiRegion = $false,
    
    [Parameter(Mandatory = $false)]
    [bool]$EnableMonitoring = $true,
    
    [Parameter(Mandatory = $false)]
    [bool]$EnableAutomation = $true
)

# Import required modules
Import-Module Az.Sql -Force
Import-Module Az.Resources -Force
Import-Module Az.Monitor -Force
Import-Module Az.Storage -Force
Import-Module Az.Automation -Force

# Set error action preference
$ErrorActionPreference = "Stop"

# Global variables
$deploymentStartTime = Get-Date
$deploymentSteps = @()
$deploymentErrors = @()

function Write-DeploymentStep {
    param(
        [string]$StepName,
        [string]$Status,
        [string]$Details = "",
        [string]$Duration = ""
    )
    
    $step = @{
        StepName = $StepName
        Status = $Status
        Details = $Details
        Duration = $Duration
        Timestamp = Get-Date
    }
    
    $script:deploymentSteps += $step
    
    $color = switch ($Status) {
        "STARTED" { "Yellow" }
        "COMPLETED" { "Green" }
        "FAILED" { "Red" }
        "SKIPPED" { "Gray" }
        default { "White" }
    }
    
    Write-Host "[$($step.Timestamp.ToString('HH:mm:ss'))] $StepName - $Status" -ForegroundColor $color
    if ($Details) {
        Write-Host "  $Details" -ForegroundColor White
    }
}

try {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Azure SQL Elastic Pool Management Platform" -ForegroundColor Cyan
    Write-Host "Complete Platform Deployment" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    Write-Host "Deployment Configuration:" -ForegroundColor White
    Write-Host "  Subscription: $SubscriptionId" -ForegroundColor White
    Write-Host "  Primary Region: $PrimaryRegion" -ForegroundColor White
    Write-Host "  Secondary Region: $SecondaryRegion" -ForegroundColor White
    Write-Host "  Server Prefix: $ServerNamePrefix" -ForegroundColor White
    Write-Host "  Multi-Region: $DeployMultiRegion" -ForegroundColor White
    Write-Host "  Monitoring: $EnableMonitoring" -ForegroundColor White
    Write-Host "  Automation: $EnableAutomation" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Cyan
    
    # Set Azure context
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    
    # Step 1: Create Resource Groups
    Write-DeploymentStep -StepName "Create Resource Groups" -Status "STARTED"
    $stepStartTime = Get-Date
    
    try {
        # Primary resource group
        $primaryRG = Get-AzResourceGroup -Name $PrimaryResourceGroupName -ErrorAction SilentlyContinue
        if (-not $primaryRG) {
            $primaryRG = New-AzResourceGroup -Name $PrimaryResourceGroupName -Location $PrimaryRegion
            Write-Host "  ✓ Primary resource group created: $PrimaryResourceGroupName" -ForegroundColor Green
        }
        else {
            Write-Host "  ✓ Primary resource group exists: $PrimaryResourceGroupName" -ForegroundColor Green
        }
        
        # Secondary resource group (if multi-region)
        if ($DeployMultiRegion -and $SecondaryRegion) {
            $secondaryResourceGroupName = "$PrimaryResourceGroupName-secondary"
            $secondaryRG = Get-AzResourceGroup -Name $secondaryResourceGroupName -ErrorAction SilentlyContinue
            if (-not $secondaryRG) {
                $secondaryRG = New-AzResourceGroup -Name $secondaryResourceGroupName -Location $SecondaryRegion
                Write-Host "  ✓ Secondary resource group created: $secondaryResourceGroupName" -ForegroundColor Green
            }
            else {
                Write-Host "  ✓ Secondary resource group exists: $secondaryResourceGroupName" -ForegroundColor Green
            }
        }
        
        $stepDuration = ((Get-Date) - $stepStartTime).TotalSeconds
        Write-DeploymentStep -StepName "Create Resource Groups" -Status "COMPLETED" -Duration "$stepDuration seconds"
    }
    catch {
        $stepDuration = ((Get-Date) - $stepStartTime).TotalSeconds
        Write-DeploymentStep -StepName "Create Resource Groups" -Status "FAILED" -Details $_.Exception.Message -Duration "$stepDuration seconds"
        $deploymentErrors += "Resource Groups: $($_.Exception.Message)"
        throw
    }
    
    # Step 2: Deploy Primary Elastic Pool Infrastructure
    Write-DeploymentStep -StepName "Deploy Primary Elastic Pool Infrastructure" -Status "STARTED"
    $stepStartTime = Get-Date
    
    try {
        $primaryServerName = "$ServerNamePrefix-primary-001"
        $primaryElasticPoolName = "pool-primary-standard"
        
        # Call the existing deployment script
        $deploymentResult = & "$PSScriptRoot\..\Elastic-Pool-Management\Pool-Provisioning\Deploy-Elastic-Pool-Infrastructure.ps1" `
            -SubscriptionId $SubscriptionId `
            -ResourceGroupName $PrimaryResourceGroupName `
            -Location $PrimaryRegion `
            -SqlServerName $primaryServerName `
            -ElasticPoolName $primaryElasticPoolName `
            -AdminUsername $AdminUsername `
            -AdminPassword $AdminPassword `
            -Edition "Standard" `
            -Dtu 200 `
            -DatabaseDtuMin 10 `
            -DatabaseDtuMax 50
        
        Write-Host "  ✓ Primary elastic pool infrastructure deployed" -ForegroundColor Green
        
        $stepDuration = ((Get-Date) - $stepStartTime).TotalSeconds
        Write-DeploymentStep -StepName "Deploy Primary Elastic Pool Infrastructure" -Status "COMPLETED" -Duration "$stepDuration seconds"
    }
    catch {
        $stepDuration = ((Get-Date) - $stepStartTime).TotalSeconds
        Write-DeploymentStep -StepName "Deploy Primary Elastic Pool Infrastructure" -Status "FAILED" -Details $_.Exception.Message -Duration "$stepDuration seconds"
        $deploymentErrors += "Primary Infrastructure: $($_.Exception.Message)"
        throw
    }
    
    # Step 3: Deploy Secondary Elastic Pool Infrastructure (if multi-region)
    if ($DeployMultiRegion -and $SecondaryRegion) {
        Write-DeploymentStep -StepName "Deploy Secondary Elastic Pool Infrastructure" -Status "STARTED"
        $stepStartTime = Get-Date
        
        try {
            $secondaryServerName = "$ServerNamePrefix-secondary-001"
            $secondaryElasticPoolName = "pool-secondary-standard"
            $secondaryResourceGroupName = "$PrimaryResourceGroupName-secondary"
            
            # Deploy secondary infrastructure
            $secondaryDeploymentResult = & "$PSScriptRoot\..\Elastic-Pool-Management\Pool-Provisioning\Deploy-Elastic-Pool-Infrastructure.ps1" `
                -SubscriptionId $SubscriptionId `
                -ResourceGroupName $secondaryResourceGroupName `
                -Location $SecondaryRegion `
                -SqlServerName $secondaryServerName `
                -ElasticPoolName $secondaryElasticPoolName `
                -AdminUsername $AdminUsername `
                -AdminPassword $AdminPassword `
                -Edition "Standard" `
                -Dtu 200 `
                -DatabaseDtuMin 10 `
                -DatabaseDtuMax 50
            
            Write-Host "  ✓ Secondary elastic pool infrastructure deployed" -ForegroundColor Green
            
            $stepDuration = ((Get-Date) - $stepStartTime).TotalSeconds
            Write-DeploymentStep -StepName "Deploy Secondary Elastic Pool Infrastructure" -Status "COMPLETED" -Duration "$stepDuration seconds"
        }
        catch {
            $stepDuration = ((Get-Date) - $stepStartTime).TotalSeconds
            Write-DeploymentStep -StepName "Deploy Secondary Elastic Pool Infrastructure" -Status "FAILED" -Details $_.Exception.Message -Duration "$stepDuration seconds"
            $deploymentErrors += "Secondary Infrastructure: $($_.Exception.Message)"
        }
    }
    else {
        Write-DeploymentStep -StepName "Deploy Secondary Elastic Pool Infrastructure" -Status "SKIPPED" -Details "Multi-region deployment disabled"
    }
    
    # Step 4: Create Sample Databases
    Write-DeploymentStep -StepName "Create Sample Databases" -Status "STARTED"
    $stepStartTime = Get-Date
    
    try {
        $sampleDatabases = @("SampleDB1", "SampleDB2", "SampleDB3")
        
        foreach ($dbName in $sampleDatabases) {
            # Provision database in primary pool
            & "$PSScriptRoot\..\Elastic-Pool-Management\Database-Management\Provision-Database-In-Pool.ps1" `
                -ResourceGroupName $PrimaryResourceGroupName `
                -ServerName $primaryServerName `
                -DatabaseName $dbName `
                -ElasticPoolName $primaryElasticPoolName
            
            Write-Host "  ✓ Sample database created: $dbName" -ForegroundColor Green
        }
        
        $stepDuration = ((Get-Date) - $stepStartTime).TotalSeconds
        Write-DeploymentStep -StepName "Create Sample Databases" -Status "COMPLETED" -Duration "$stepDuration seconds"
    }
    catch {
        $stepDuration = ((Get-Date) - $stepStartTime).TotalSeconds
        Write-DeploymentStep -StepName "Create Sample Databases" -Status "FAILED" -Details $_.Exception.Message -Duration "$stepDuration seconds"
        $deploymentErrors += "Sample Databases: $($_.Exception.Message)"
    }
    
    # Step 5: Configure Monitoring and Alerts
    if ($EnableMonitoring) {
        Write-DeploymentStep -StepName "Configure Monitoring and Alerts" -Status "STARTED"
        $stepStartTime = Get-Date
        
        try {
            $actionGroupName = "ag-asepmp-alerts"
            
            # Create email receivers
            $emailReceivers = @()
            foreach ($email in $NotificationEmails) {
                $emailReceivers += New-AzActionGroupReceiver -Name ($email.Split('@')[0]) -EmailReceiver -EmailAddress $email
            }
            
            # Create action group
            $actionGroup = Set-AzActionGroup `
                -ResourceGroupName $PrimaryResourceGroupName `
                -Name $actionGroupName `
                -ShortName "asepmp" `
                -Receiver $emailReceivers
            
            Write-Host "  ✓ Action group created: $actionGroupName" -ForegroundColor Green
            
            # Create performance monitoring alerts
            $alertRules = @(
                @{
                    Name = "ElasticPool-HighDTUUtilization"
                    Description = "Alert when elastic pool DTU utilization is high"
                    MetricName = "dtu_consumption_percent"
                    Threshold = 80
                    Operator = "GreaterThan"
                },
                @{
                    Name = "ElasticPool-HighStorageUtilization"
                    Description = "Alert when elastic pool storage utilization is high"
                    MetricName = "storage_percent"
                    Threshold = 85
                    Operator = "GreaterThan"
                }
            )
            
            foreach ($rule in $alertRules) {
                $alertRule = Add-AzMetricAlertRuleV2 `
                    -ResourceGroupName $PrimaryResourceGroupName `
                    -Name $rule.Name `
                    -Description $rule.Description `
                    -Severity 2 `
                    -WindowSize "00:05:00" `
                    -Frequency "00:01:00" `
                    -TargetResourceId "/subscriptions/$SubscriptionId/resourceGroups/$PrimaryResourceGroupName/providers/Microsoft.Sql/servers/$primaryServerName/elasticPools/$primaryElasticPoolName" `
                    -MetricName $rule.MetricName `
                    -Operator $rule.Operator `
                    -Threshold $rule.Threshold `
                    -ActionGroupId $actionGroup.Id
                
                Write-Host "  ✓ Alert rule created: $($rule.Name)" -ForegroundColor Green
            }
            
            $stepDuration = ((Get-Date) - $stepStartTime).TotalSeconds
            Write-DeploymentStep -StepName "Configure Monitoring and Alerts" -Status "COMPLETED" -Duration "$stepDuration seconds"
        }
        catch {
            $stepDuration = ((Get-Date) - $stepStartTime).TotalSeconds
            Write-DeploymentStep -StepName "Configure Monitoring and Alerts" -Status "FAILED" -Details $_.Exception.Message -Duration "$stepDuration seconds"
            $deploymentErrors += "Monitoring and Alerts: $($_.Exception.Message)"
        }
    }
    else {
        Write-DeploymentStep -StepName "Configure Monitoring and Alerts" -Status "SKIPPED" -Details "Monitoring disabled by parameter"
    }
    
    # Step 6: Configure Automation
    if ($EnableAutomation) {
        Write-DeploymentStep -StepName "Configure Automation" -Status "STARTED"
        $stepStartTime = Get-Date
        
        try {
            $automationAccountName = "aa-asepmp-automation"
            
            # Create automation account
            $automationAccount = Get-AzAutomationAccount -ResourceGroupName $PrimaryResourceGroupName -Name $automationAccountName -ErrorAction SilentlyContinue
            
            if (-not $automationAccount) {
                $automationAccount = New-AzAutomationAccount `
                    -ResourceGroupName $PrimaryResourceGroupName `
                    -Name $automationAccountName `
                    -Location $PrimaryRegion `
                    -Plan "Basic"
                
                Write-Host "  ✓ Automation account created: $automationAccountName" -ForegroundColor Green
            }
            else {
                Write-Host "  ✓ Automation account exists: $automationAccountName" -ForegroundColor Green
            }
            
            # Import required modules
            $requiredModules = @("Az.Sql", "Az.Resources", "Az.Monitor")
            
            foreach ($module in $requiredModules) {
                Import-AzAutomationModule `
                    -ResourceGroupName $PrimaryResourceGroupName `
                    -AutomationAccountName $automationAccountName `
                    -Name $module `
                    -ModuleVersion "Latest" `
                    -ErrorAction SilentlyContinue
                
                Write-Host "  ✓ Module imported: $module" -ForegroundColor Green
            }
            
            $stepDuration = ((Get-Date) - $stepStartTime).TotalSeconds
            Write-DeploymentStep -StepName "Configure Automation" -Status "COMPLETED" -Duration "$stepDuration seconds"
        }
        catch {
            $stepDuration = ((Get-Date) - $stepStartTime).TotalSeconds
            Write-DeploymentStep -StepName "Configure Automation" -Status "FAILED" -Details $_.Exception.Message -Duration "$stepDuration seconds"
            $deploymentErrors += "Automation: $($_.Exception.Message)"
        }
    }
    else {
        Write-DeploymentStep -StepName "Configure Automation" -Status "SKIPPED" -Details "Automation disabled by parameter"
    }
    
    # Step 7: Verify Deployment
    Write-DeploymentStep -StepName "Verify Deployment" -Status "STARTED"
    $stepStartTime = Get-Date
    
    try {
        # Verify primary elastic pool
        $verifyPrimaryPool = Get-AzSqlElasticPool -ResourceGroupName $PrimaryResourceGroupName -ServerName $primaryServerName -ElasticPoolName $primaryElasticPoolName
        Write-Host "  ✓ Primary elastic pool verified: $($verifyPrimaryPool.ElasticPoolName)" -ForegroundColor Green
        
        # Verify databases in pool
        $poolDatabases = Get-AzSqlElasticPoolDatabase -ResourceGroupName $PrimaryResourceGroupName -ServerName $primaryServerName -ElasticPoolName $primaryElasticPoolName
        Write-Host "  ✓ Databases in pool: $($poolDatabases.Count)" -ForegroundColor Green
        
        # Verify secondary pool (if multi-region)
        if ($DeployMultiRegion -and $SecondaryRegion) {
            $verifySecondaryPool = Get-AzSqlElasticPool -ResourceGroupName $secondaryResourceGroupName -ServerName $secondaryServerName -ElasticPoolName $secondaryElasticPoolName -ErrorAction SilentlyContinue
            if ($verifySecondaryPool) {
                Write-Host "  ✓ Secondary elastic pool verified: $($verifySecondaryPool.ElasticPoolName)" -ForegroundColor Green
            }
        }
        
        $stepDuration = ((Get-Date) - $stepStartTime).TotalSeconds
        Write-DeploymentStep -StepName "Verify Deployment" -Status "COMPLETED" -Duration "$stepDuration seconds"
    }
    catch {
        $stepDuration = ((Get-Date) - $stepStartTime).TotalSeconds
        Write-DeploymentStep -StepName "Verify Deployment" -Status "FAILED" -Details $_.Exception.Message -Duration "$stepDuration seconds"
        $deploymentErrors += "Deployment Verification: $($_.Exception.Message)"
    }
    
    $deploymentEndTime = Get-Date
    $totalDeploymentDuration = ($deploymentEndTime - $deploymentStartTime).TotalMinutes
    
    # Output comprehensive summary
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Deployment Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Total Duration: $([math]::Round($totalDeploymentDuration, 2)) minutes" -ForegroundColor White
    Write-Host "Start Time: $deploymentStartTime" -ForegroundColor White
    Write-Host "End Time: $deploymentEndTime" -ForegroundColor White
    Write-Host "Total Steps: $($deploymentSteps.Count)" -ForegroundColor White
    Write-Host "Successful Steps: $(($deploymentSteps | Where-Object { $_.Status -eq 'COMPLETED' }).Count)" -ForegroundColor Green
    Write-Host "Failed Steps: $(($deploymentSteps | Where-Object { $_.Status -eq 'FAILED' }).Count)" -ForegroundColor Red
    Write-Host "Skipped Steps: $(($deploymentSteps | Where-Object { $_.Status -eq 'SKIPPED' }).Count)" -ForegroundColor Gray
    
    if ($deploymentErrors.Count -eq 0) {
        Write-Host "Overall Status: SUCCESS" -ForegroundColor Green
    }
    else {
        Write-Host "Overall Status: COMPLETED WITH ERRORS" -ForegroundColor Yellow
    }
    
    Write-Host "`nDeployed Resources:" -ForegroundColor White
    Write-Host "  Primary Server: $primaryServerName" -ForegroundColor Green
    Write-Host "  Primary Elastic Pool: $primaryElasticPoolName" -ForegroundColor Green
    if ($DeployMultiRegion -and $SecondaryRegion) {
        Write-Host "  Secondary Server: $secondaryServerName" -ForegroundColor Green
        Write-Host "  Secondary Elastic Pool: $secondaryElasticPoolName" -ForegroundColor Green
    }
    
    if ($deploymentErrors.Count -gt 0) {
        Write-Host "`nErrors Encountered:" -ForegroundColor Red
        foreach ($error in $deploymentErrors) {
            Write-Host "  ✗ $error" -ForegroundColor Red
        }
    }
    
    Write-Host "`nNext Steps:" -ForegroundColor Yellow
    Write-Host "1. Test database connectivity and performance" -ForegroundColor White
    Write-Host "2. Configure application connection strings" -ForegroundColor White
    Write-Host "3. Set up monitoring dashboards" -ForegroundColor White
    Write-Host "4. Configure automated scaling policies" -ForegroundColor White
    Write-Host "5. Document operational procedures" -ForegroundColor White
    
    Write-Host "========================================" -ForegroundColor Cyan
    
    # Return deployment summary
    return @{
        PrimaryResourceGroupName = $PrimaryResourceGroupName
        PrimaryServerName = $primaryServerName
        PrimaryElasticPoolName = $primaryElasticPoolName
        SecondaryServerName = if ($DeployMultiRegion) { $secondaryServerName } else { $null }
        SecondaryElasticPoolName = if ($DeployMultiRegion) { $secondaryElasticPoolName } else { $null }
        TotalDuration = $totalDeploymentDuration
        StartTime = $deploymentStartTime
        EndTime = $deploymentEndTime
        TotalSteps = $deploymentSteps.Count
        SuccessfulSteps = ($deploymentSteps | Where-Object { $_.Status -eq 'COMPLETED' }).Count
        FailedSteps = ($deploymentSteps | Where-Object { $_.Status -eq 'FAILED' }).Count
        SkippedSteps = ($deploymentSteps | Where-Object { $_.Status -eq 'SKIPPED' }).Count
        DeploymentSteps = $deploymentSteps
        DeploymentErrors = $deploymentErrors
        Status = if ($deploymentErrors.Count -eq 0) { "SUCCESS" } else { "COMPLETED_WITH_ERRORS" }
    }
}
catch {
    $deploymentEndTime = Get-Date
    $totalDeploymentDuration = ($deploymentEndTime - $deploymentStartTime).TotalMinutes
    
    Write-Error "Deployment failed: $($_.Exception.Message)"
    
    # Log failure details
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "Deployment Failed" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Total Duration: $([math]::Round($totalDeploymentDuration, 2)) minutes" -ForegroundColor White
    Write-Host "Failed at: $(Get-Date)" -ForegroundColor White
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Completed Steps: $(($deploymentSteps | Where-Object { $_.Status -eq 'COMPLETED' }).Count)" -ForegroundColor White
    Write-Host "Failed Steps: $(($deploymentSteps | Where-Object { $_.Status -eq 'FAILED' }).Count)" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Red
    
    throw
}