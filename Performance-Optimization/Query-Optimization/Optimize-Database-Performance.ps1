# =====================================================
# Azure SQL Elastic Pool Management Platform (ASEPMP)
# Database Performance Optimization Script
# Production-Ready Enterprise Performance Tuning
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
    [switch]$UpdateStatistics = $true,
    
    [Parameter(Mandatory = $false)]
    [switch]$RebuildIndexes = $true,
    
    [Parameter(Mandatory = $false)]
    [switch]$AnalyzeQueryPerformance = $true,
    
    [Parameter(Mandatory = $false)]
    [switch]$OptimizeIndexes = $true,
    
    [Parameter(Mandatory = $false)]
    [switch]$GeneratePerformanceReport = $true,
    
    [Parameter(Mandatory = $false)]
    [int]$TopSlowQueries = 10,
    
    [Parameter(Mandatory = $false)]
    [int]$IndexFragmentationThreshold = 30
)

# =====================================================
# SCRIPT CONFIGURATION
# =====================================================
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

# Logging configuration
$LogFile = "Optimize-Performance-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
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
# SQL QUERY DEFINITIONS
# =====================================================
$SqlQueries = @{
    UpdateStatistics = @"
-- Update statistics for all tables
DECLARE @sql NVARCHAR(MAX) = ''
SELECT @sql = @sql + 'UPDATE STATISTICS [' + SCHEMA_NAME(schema_id) + '].[' + name + '] WITH FULLSCAN;' + CHAR(13)
FROM sys.tables
EXEC sp_executesql @sql
"@

    GetIndexFragmentation = @"
-- Get index fragmentation information
SELECT 
    OBJECT_SCHEMA_NAME(ips.object_id) AS SchemaName,
    OBJECT_NAME(ips.object_id) AS TableName,
    i.name AS IndexName,
    ips.index_type_desc,
    ips.avg_fragmentation_in_percent,
    ips.page_count,
    CASE 
        WHEN ips.avg_fragmentation_in_percent > 30 THEN 'REBUILD'
        WHEN ips.avg_fragmentation_in_percent > 10 THEN 'REORGANIZE'
        ELSE 'NO ACTION'
    END AS RecommendedAction
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.avg_fragmentation_in_percent > 5
    AND ips.page_count > 1000
ORDER BY ips.avg_fragmentation_in_percent DESC
"@

    GetSlowQueries = @"
-- Get top slow queries
SELECT TOP (@TopSlowQueries)
    qs.sql_handle,
    qs.statement_start_offset,
    qs.statement_end_offset,
    qs.execution_count,
    qs.total_elapsed_time / qs.execution_count AS avg_elapsed_time,
    qs.total_cpu_time / qs.execution_count AS avg_cpu_time,
    qs.total_logical_reads / qs.execution_count AS avg_logical_reads,
    qs.total_physical_reads / qs.execution_count AS avg_physical_reads,
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(st.text)
            ELSE qs.statement_end_offset
        END - qs.statement_start_offset)/2) + 1) AS statement_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
ORDER BY qs.total_elapsed_time / qs.execution_count DESC
"@

    GetMissingIndexes = @"
-- Get missing index recommendations
SELECT 
    migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) AS improvement_measure,
    'CREATE INDEX [IX_' + OBJECT_NAME(mid.object_id) + '_' + REPLACE(REPLACE(REPLACE(ISNULL(mid.equality_columns,''), ', ', '_'), '[', ''), ']', '') + 
    CASE WHEN mid.inequality_columns IS NOT NULL THEN '_' + REPLACE(REPLACE(REPLACE(mid.inequality_columns, ', ', '_'), '[', ''), ']', '') ELSE '' END + ']' +
    ' ON ' + mid.statement + ' (' + ISNULL(mid.equality_columns,'') + 
    CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL THEN ',' ELSE '' END + 
    ISNULL(mid.inequality_columns, '') + ')' + 
    ISNULL(' INCLUDE (' + mid.included_columns + ')', '') AS create_index_statement,
    migs.user_seeks,
    migs.user_scans,
    migs.avg_total_user_cost,
    migs.avg_user_impact
FROM sys.dm_db_missing_index_groups mig
INNER JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
INNER JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
WHERE migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) > 10
ORDER BY improvement_measure DESC
"@

    GetDatabaseSize = @"
-- Get database size information
SELECT 
    DB_NAME() AS DatabaseName,
    SUM(CASE WHEN type = 0 THEN size END) * 8 / 1024 AS DataSizeMB,
    SUM(CASE WHEN type = 1 THEN size END) * 8 / 1024 AS LogSizeMB,
    SUM(size) * 8 / 1024 AS TotalSizeMB
FROM sys.database_files
"@

    GetTableSizes = @"
-- Get table sizes
SELECT 
    SCHEMA_NAME(t.schema_id) AS SchemaName,
    t.name AS TableName,
    SUM(p.rows) AS RowCount,
    SUM(a.total_pages) * 8 / 1024 AS TotalSizeMB,
    SUM(a.used_pages) * 8 / 1024 AS UsedSizeMB,
    (SUM(a.total_pages) - SUM(a.used_pages)) * 8 / 1024 AS UnusedSizeMB
FROM sys.tables t
INNER JOIN sys.indexes i ON t.object_id = i.object_id
INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
WHERE t.is_ms_shipped = 0
GROUP BY t.schema_id, t.name
ORDER BY SUM(a.total_pages) DESC
"@
}

# =====================================================
# PERFORMANCE OPTIMIZATION FUNCTIONS
# =====================================================
function Invoke-DatabaseQuery {
    param(
        [string]$ServerInstance,
        [string]$Database,
        [string]$Query,
        [hashtable]$Parameters = @{}
    )
    
    try {
        $AccessToken = (Get-AzAccessToken -ResourceUrl "https://database.windows.net/").Token
        
        $Result = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                               -Database $Database `
                               -Query $Query `
                               -AccessToken $AccessToken `
                               -QueryTimeout 300 `
                               -ErrorAction Stop
        
        return $Result
    } catch {
        Write-LogError "Query execution failed: $($_.Exception.Message)"
        throw
    }
}

function Update-DatabaseStatistics {
    param(
        [string]$ServerInstance,
        [string]$Database
    )
    
    Write-Log "Updating database statistics..."
    
    try {
        Invoke-DatabaseQuery -ServerInstance $ServerInstance -Database $Database -Query $SqlQueries.UpdateStatistics
        Write-LogSuccess "Database statistics updated successfully"
    } catch {
        Write-LogError "Failed to update statistics: $($_.Exception.Message)"
        throw
    }
}

function Get-IndexFragmentation {
    param(
        [string]$ServerInstance,
        [string]$Database
    )
    
    Write-Log "Analyzing index fragmentation..."
    
    try {
        $FragmentationData = Invoke-DatabaseQuery -ServerInstance $ServerInstance -Database $Database -Query $SqlQueries.GetIndexFragmentation
        
        if ($FragmentationData) {
            Write-Log "Found $($FragmentationData.Count) fragmented indexes"
            return $FragmentationData
        } else {
            Write-Log "No significant index fragmentation found"
            return @()
        }
    } catch {
        Write-LogError "Failed to analyze index fragmentation: $($_.Exception.Message)"
        throw
    }
}

function Optimize-Indexes {
    param(
        [string]$ServerInstance,
        [string]$Database,
        [array]$FragmentationData,
        [int]$FragmentationThreshold = 30
    )
    
    Write-Log "Optimizing indexes based on fragmentation analysis..."
    
    $OptimizedCount = 0
    
    foreach ($Index in $FragmentationData) {
        try {
            $SchemaName = $Index.SchemaName
            $TableName = $Index.TableName
            $IndexName = $Index.IndexName
            $FragmentationPercent = $Index.avg_fragmentation_in_percent
            $RecommendedAction = $Index.RecommendedAction
            
            if ($RecommendedAction -eq "REBUILD" -and $FragmentationPercent -gt $FragmentationThreshold) {
                Write-Log "Rebuilding index [$SchemaName].[$TableName].[$IndexName] (Fragmentation: $($FragmentationPercent.ToString('F2'))%)"
                
                $RebuildQuery = "ALTER INDEX [$IndexName] ON [$SchemaName].[$TableName] REBUILD WITH (ONLINE = ON)"
                Invoke-DatabaseQuery -ServerInstance $ServerInstance -Database $Database -Query $RebuildQuery
                
                $OptimizedCount++
                Write-LogSuccess "Index rebuilt successfully"
                
            } elseif ($RecommendedAction -eq "REORGANIZE") {
                Write-Log "Reorganizing index [$SchemaName].[$TableName].[$IndexName] (Fragmentation: $($FragmentationPercent.ToString('F2'))%)"
                
                $ReorganizeQuery = "ALTER INDEX [$IndexName] ON [$SchemaName].[$TableName] REORGANIZE"
                Invoke-DatabaseQuery -ServerInstance $ServerInstance -Database $Database -Query $ReorganizeQuery
                
                $OptimizedCount++
                Write-LogSuccess "Index reorganized successfully"
            }
            
        } catch {
            Write-LogWarning "Failed to optimize index [$SchemaName].[$TableName].[$IndexName]: $($_.Exception.Message)"
        }
    }
    
    Write-LogSuccess "Optimized $OptimizedCount indexes"
}

function Get-SlowQueries {
    param(
        [string]$ServerInstance,
        [string]$Database,
        [int]$TopCount = 10
    )
    
    Write-Log "Analyzing slow queries (Top $TopCount)..."
    
    try {
        $SlowQueriesQuery = $SqlQueries.GetSlowQueries -replace '@TopSlowQueries', $TopCount
        $SlowQueries = Invoke-DatabaseQuery -ServerInstance $ServerInstance -Database $Database -Query $SlowQueriesQuery
        
        if ($SlowQueries) {
            Write-Log "Found $($SlowQueries.Count) slow queries"
            return $SlowQueries
        } else {
            Write-Log "No slow queries found"
            return @()
        }
    } catch {
        Write-LogError "Failed to analyze slow queries: $($_.Exception.Message)"
        throw
    }
}

function Get-MissingIndexRecommendations {
    param(
        [string]$ServerInstance,
        [string]$Database
    )
    
    Write-Log "Getting missing index recommendations..."
    
    try {
        $MissingIndexes = Invoke-DatabaseQuery -ServerInstance $ServerInstance -Database $Database -Query $SqlQueries.GetMissingIndexes
        
        if ($MissingIndexes) {
            Write-Log "Found $($MissingIndexes.Count) missing index recommendations"
            return $MissingIndexes
        } else {
            Write-Log "No missing index recommendations found"
            return @()
        }
    } catch {
        Write-LogError "Failed to get missing index recommendations: $($_.Exception.Message)"
        throw
    }
}

function Get-DatabaseSizeInfo {
    param(
        [string]$ServerInstance,
        [string]$Database
    )
    
    Write-Log "Getting database size information..."
    
    try {
        $DatabaseSize = Invoke-DatabaseQuery -ServerInstance $ServerInstance -Database $Database -Query $SqlQueries.GetDatabaseSize
        $TableSizes = Invoke-DatabaseQuery -ServerInstance $ServerInstance -Database $Database -Query $SqlQueries.GetTableSizes
        
        return @{
            DatabaseSize = $DatabaseSize
            TableSizes = $TableSizes
        }
    } catch {
        Write-LogError "Failed to get database size information: $($_.Exception.Message)"
        throw
    }
}

function Generate-PerformanceReport {
    param(
        [hashtable]$OptimizationResults,
        [string]$OutputPath
    )
    
    Write-Log "Generating performance optimization report..."
    
    $ReportContent = @"
# Database Performance Optimization Report
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

## Database Information
- **Server**: $($OptimizationResults.ServerInstance)
- **Database**: $($OptimizationResults.Database)
- **Optimization Date**: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

## Database Size Information
"@

    if ($OptimizationResults.SizeInfo.DatabaseSize) {
        $DbSize = $OptimizationResults.SizeInfo.DatabaseSize[0]
        $ReportContent += @"

- **Data Size**: $($DbSize.DataSizeMB) MB
- **Log Size**: $($DbSize.LogSizeMB) MB
- **Total Size**: $($DbSize.TotalSizeMB) MB
"@
    }

    $ReportContent += @"

## Optimization Summary
- **Statistics Updated**: $($OptimizationResults.StatisticsUpdated)
- **Indexes Optimized**: $($OptimizationResults.IndexesOptimized)
- **Fragmented Indexes Found**: $($OptimizationResults.FragmentedIndexes.Count)
- **Slow Queries Analyzed**: $($OptimizationResults.SlowQueries.Count)
- **Missing Index Recommendations**: $($OptimizationResults.MissingIndexes.Count)

"@

    if ($OptimizationResults.FragmentedIndexes.Count -gt 0) {
        $ReportContent += @"
## Index Fragmentation Analysis
| Schema | Table | Index | Fragmentation % | Action Taken |
|--------|-------|-------|----------------|--------------|
"@
        foreach ($Index in $OptimizationResults.FragmentedIndexes) {
            $ReportContent += "| $($Index.SchemaName) | $($Index.TableName) | $($Index.IndexName) | $($Index.avg_fragmentation_in_percent.ToString('F2')) | $($Index.RecommendedAction) |`n"
        }
        $ReportContent += "`n"
    }

    if ($OptimizationResults.SlowQueries.Count -gt 0) {
        $ReportContent += @"
## Top Slow Queries
| Avg Elapsed Time (ms) | Avg CPU Time (ms) | Avg Logical Reads | Execution Count | Query Text (First 100 chars) |
|----------------------|-------------------|-------------------|-----------------|------------------------------|
"@
        foreach ($Query in $OptimizationResults.SlowQueries) {
            $QueryText = $Query.statement_text -replace "`n", " " -replace "`r", ""
            if ($QueryText.Length -gt 100) {
                $QueryText = $QueryText.Substring(0, 100) + "..."
            }
            $ReportContent += "| $($Query.avg_elapsed_time) | $($Query.avg_cpu_time) | $($Query.avg_logical_reads) | $($Query.execution_count) | $QueryText |`n"
        }
        $ReportContent += "`n"
    }

    if ($OptimizationResults.MissingIndexes.Count -gt 0) {
        $ReportContent += @"
## Missing Index Recommendations
| Improvement Measure | User Seeks | User Scans | Avg User Impact | Create Index Statement |
|--------------------|------------|------------|-----------------|------------------------|
"@
        foreach ($Index in $OptimizationResults.MissingIndexes) {
            $CreateStatement = $Index.create_index_statement -replace "`n", " " -replace "`r", ""
            if ($CreateStatement.Length -gt 100) {
                $CreateStatement = $CreateStatement.Substring(0, 100) + "..."
            }
            $ReportContent += "| $($Index.improvement_measure.ToString('F2')) | $($Index.user_seeks) | $($Index.user_scans) | $($Index.avg_user_impact.ToString('F2')) | $CreateStatement |`n"
        }
        $ReportContent += "`n"
    }

    $ReportContent += @"
## Recommendations
1. **Regular Maintenance**: Schedule regular statistics updates and index maintenance
2. **Query Optimization**: Review and optimize slow-performing queries
3. **Index Strategy**: Consider implementing recommended missing indexes
4. **Monitoring**: Set up continuous performance monitoring
5. **Capacity Planning**: Monitor database growth and plan for scaling

---
*Report generated by Azure SQL Elastic Pool Management Platform (ASEPMP)*
"@

    try {
        $ReportFile = Join-Path -Path $OutputPath -ChildPath "Performance-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').md"
        $ReportContent | Out-File -FilePath $ReportFile -Encoding UTF8
        Write-LogSuccess "Performance report generated: $ReportFile"
        return $ReportFile
    } catch {
        Write-LogError "Failed to generate performance report: $($_.Exception.Message)"
        throw
    }
}

# =====================================================
# MAIN OPTIMIZATION SCRIPT
# =====================================================
try {
    Write-Log "Starting Database Performance Optimization"
    Write-Log "Subscription ID: $SubscriptionId"
    Write-Log "Resource Group: $ResourceGroupName"
    Write-Log "SQL Server: $SqlServerName"
    Write-Log "Database Name: $DatabaseName"

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
    # VALIDATE DATABASE EXISTS
    # =====================================================
    Write-Log "Validating database exists..."
    $Database = Get-AzSqlDatabase -DatabaseName $DatabaseName `
                                 -ServerName $SqlServerName `
                                 -ResourceGroupName $ResourceGroupName `
                                 -ErrorAction SilentlyContinue
    
    if (-not $Database) {
        throw "Database '$DatabaseName' does not exist"
    }
    
    Write-LogSuccess "Database validation passed"
    
    $ServerInstance = "$SqlServerName.database.windows.net"
    
    # Initialize results object
    $OptimizationResults = @{
        ServerInstance = $ServerInstance
        Database = $DatabaseName
        StatisticsUpdated = $false
        IndexesOptimized = 0
        FragmentedIndexes = @()
        SlowQueries = @()
        MissingIndexes = @()
        SizeInfo = @{}
    }

    # =====================================================
    # GET DATABASE SIZE INFORMATION
    # =====================================================
    Write-Log "Getting database size information..."
    try {
        $OptimizationResults.SizeInfo = Get-DatabaseSizeInfo -ServerInstance $ServerInstance -Database $DatabaseName
        Write-LogSuccess "Database size information retrieved"
    } catch {
        Write-LogWarning "Could not retrieve database size information: $($_.Exception.Message)"
    }

    # =====================================================
    # UPDATE STATISTICS
    # =====================================================
    if ($UpdateStatistics) {
        try {
            Update-DatabaseStatistics -ServerInstance $ServerInstance -Database $DatabaseName
            $OptimizationResults.StatisticsUpdated = $true
        } catch {
            Write-LogWarning "Statistics update failed: $($_.Exception.Message)"
        }
    }

    # =====================================================
    # ANALYZE INDEX FRAGMENTATION
    # =====================================================
    if ($RebuildIndexes -or $OptimizeIndexes) {
        try {
            $FragmentationData = Get-IndexFragmentation -ServerInstance $ServerInstance -Database $DatabaseName
            $OptimizationResults.FragmentedIndexes = $FragmentationData
            
            if ($OptimizeIndexes -and $FragmentationData.Count -gt 0) {
                Optimize-Indexes -ServerInstance $ServerInstance -Database $DatabaseName -FragmentationData $FragmentationData -FragmentationThreshold $IndexFragmentationThreshold
            }
        } catch {
            Write-LogWarning "Index optimization failed: $($_.Exception.Message)"
        }
    }

    # =====================================================
    # ANALYZE QUERY PERFORMANCE
    # =====================================================
    if ($AnalyzeQueryPerformance) {
        try {
            $SlowQueries = Get-SlowQueries -ServerInstance $ServerInstance -Database $DatabaseName -TopCount $TopSlowQueries
            $OptimizationResults.SlowQueries = $SlowQueries
            
            $MissingIndexes = Get-MissingIndexRecommendations -ServerInstance $ServerInstance -Database $DatabaseName
            $OptimizationResults.MissingIndexes = $MissingIndexes
        } catch {
            Write-LogWarning "Query performance analysis failed: $($_.Exception.Message)"
        }
    }

    # =====================================================
    # GENERATE PERFORMANCE REPORT
    # =====================================================
    if ($GeneratePerformanceReport) {
        try {
            $ReportPath = Join-Path -Path $PSScriptRoot -ChildPath "Reports"
            if (-not (Test-Path $ReportPath)) {
                New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
            }
            
            $ReportFile = Generate-PerformanceReport -OptimizationResults $OptimizationResults -OutputPath $ReportPath
            $OptimizationResults.ReportFile = $ReportFile
        } catch {
            Write-LogWarning "Performance report generation failed: $($_.Exception.Message)"
        }
    }

    # =====================================================
    # OPTIMIZATION SUMMARY
    # =====================================================
    Write-LogSuccess "=== DATABASE PERFORMANCE OPTIMIZATION COMPLETED ==="
    Write-Log "Resource Group: $ResourceGroupName"
    Write-Log "SQL Server: $SqlServerName"
    Write-Log "Database Name: $DatabaseName"
    Write-Log "Statistics Updated: $($OptimizationResults.StatisticsUpdated)"
    Write-Log "Fragmented Indexes Found: $($OptimizationResults.FragmentedIndexes.Count)"
    Write-Log "Slow Queries Analyzed: $($OptimizationResults.SlowQueries.Count)"
    Write-Log "Missing Index Recommendations: $($OptimizationResults.MissingIndexes.Count)"
    if ($OptimizationResults.ReportFile) {
        Write-Log "Performance Report: $($OptimizationResults.ReportFile)"
    }
    Write-Log "Log file: $FullLogPath"
    
    # Return optimization results
    $OptimizationResults.Status = "Success"
    $OptimizationResults.LogFile = $FullLogPath
    return $OptimizationResults

} catch {
    Write-LogError "Database performance optimization failed: $($_.Exception.Message)"
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