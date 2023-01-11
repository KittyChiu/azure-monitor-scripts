# Set parameters
$metricName = 'Percentage CPU'
$timeGrain = '01:00:00'
$timeRange = -1  # last n day, default is last 1 day, ie -1
$fileName = 'C:\Users\kichiu\Downloads\vms-metric-tags-hourly.csv'

# login into Azure account
# Connect-AzAccount -TenantId '***'
Login-AzAccount


# Loop through all subscriptions to get VMs metrics and tags
Function Get-AllSubscriptionsVmsMetricTags {
    [CmdletBinding()]
    param(
        [Parameter()][string]$tenantId,
        # use Get-AzMetricDefintion to get possible metrics for a resource, e.g. "Percentage CPU"
        [Parameter(Mandatory=$true)][string]$metricName,
        # start time for the metric query
        [Parameter()][DateTime]$startTime,
        # end time for the metric query
        [Parameter()][DateTime]$endTime,
        # time grain for the metric query
        [Parameter(Mandatory=$true)][TimeSpan]$timeGrain

    )
    
    $subscriptions = @()
    if([string]::IsNullOrEmpty(($tenantId))) {
        $subscriptions = Get-AzSubscription
    }
    else {
        $subscriptions = Get-AzSubscription -TenantId $tenantId
    }
    $hasDT = $PSBoundParameters.ContainsKey('startTime') -and $PSBoundParameters.ContainsKey('endTime') 

    # loop through all subscription
    $mtsallsub = @()
    $subscriptions | ForEach-Object {
        $subscriptionId = $_.SubscriptionId
        if($hasDT) {
            $mts = Get-SubscriptionVmsMetricTags -subscriptionId $subscriptionId -metricName $metricName `
                -startTime $startTime -endTime $endTime -timeGrain $timeGrain
        } else {
            $mts = Get-SubscriptionVmsMetricTags -subscriptionId $subscriptionId -metricName $metricName `
                -timeGrain $timeGrain
        } 
        $mtsallsub += $mts
    }

    return $mtsallsub
    
}

# Set required parameters to get specifically VM resource type: required metric, time range (start time & end time)
Function Get-SubscriptionVmsMetricTags {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$subscriptionId,
        # use Get-AzMetricDefintion to get possible metrics for a resource, e.g. "Percentage CPU"
        [Parameter(Mandatory=$true)][string]$metricName,
        # start time for the metric query
        [Parameter()][DateTime]$startTime,
        # end time for the metric query
        [Parameter()][DateTime]$endTime,
        # time grain for the metric query
        [Parameter(Mandatory=$true)][TimeSpan]$timeGrain

    )
    
    Set-AzContext -Subscription $subscriptionId
    $resources = Get-AzResource -ResourceType Microsoft.Compute/virtualMachines
    $hasDT = $PSBoundParameters.ContainsKey('startTime') -and $PSBoundParameters.ContainsKey('endTime') 

    # loop through all resources
    $mtssub = @()
    $resources | ForEach-Object {
        $resourceId = $_.ResourceId
        $rgName = $_.ResourceGroupName
        $vmName = $_.Name

        if ($hasDT) {
            $mts = Get-VmMetricTags -subscriptionId $subscriptionId -rgName $rgName -vmName $vmName -vmId $resourceId `
                -metricName $metricName -startTime $startTime -endTime $endTime -timeGrain $timeGrain
        } else {
            $mts = Get-VmMetricTags -subscriptionId $subscriptionId -rgName $rgName -vmName $vmName -vmId $resourceId `
                -metricName $metricName -timeGrain $timeGrain
        }

        $mtssub += $mts
        
    }

    return $mtssub
    
}


# Get metric and tag metadata for a single VM resource
Function Get-VmMetricTags {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$subscriptionId,
        [Parameter(Mandatory=$true)][string]$rgName,
        [Parameter(Mandatory=$true)][string]$vmName,
        # ResourceId for a VM, use Get-AzVM -ResourceGroup $rgName -Name $vmName
        [Parameter(Mandatory=$true)][string]$vmId,
        # use Get-AzMetricDefintion to get possible metrics for a resource, e.g. "Percentage CPU"
        [Parameter(Mandatory=$true)][string]$metricName,
        # start time for the metric query
        [Parameter()][DateTime]$startTime,
        # end time for the metric query
        [Parameter()][DateTime]$endTime,
        # time grain for the metric query
        [Parameter(Mandatory=$true)][TimeSpan]$timeGrain
    )
    
    # get VM CPU metric
    $hasDT = $PSBoundParameters.ContainsKey('startTime') -and $PSBoundParameters.ContainsKey('endTime') 
    
    if ($hasDT) {
        $metrics = Get-AzMetric -MetricName $metricName -MetricNamespace Microsoft.Compute/virtualMachines -ResourceId $vmId `
            -StartTime $startTime -EndTime $endTime -TimeGrain $timeGrain
    } else {
        $metrics = Get-AzMetric -MetricName $metricName -MetricNamespace Microsoft.Compute/virtualMachines -ResourceId $vmId `
            -TimeGrain $timeGrain
    }

    # get VM tags
    $tags = Get-AzTag -ResourceId $vmId

    # loop through all metrics by time grain
    $mts = @()
    $metrics.Data | ForEach-Object {


        $mt = New-Object PSObject -Property @{
            SubscriptionId = $subscriptionId
            ResourceGroupName = $rgName
            Name = $vmName
            ResourceId = $vmId 
            Maximum = ($_.Maximum | Measure-Object -Maximum).Maximum / 100
            Minimum = ($_.Minimum | Measure-Object -Minimum).Minimum / 100
            Average = ($_.Average | Measure-Object -Average).Average / 100
            DateTime = $_.TimeStamp
            Tags = $tags.Properties.TagsProperty | ConvertTo-Json
            # TagsTable = $tags.PropertiesTable
	    # sometagvalue = $tags.Properties.TagsProperty['<tagkey>']
        }

        $mts += $mt
    }

    return $mts    
}


# Execute the program
$endTime = (Get-Date).AddDays(-1)
$startTime = $endTime.AddDays($timeRange)
$mts = Get-AllSubscriptionsVmsMetricTags -metricName $metricName `
    -startTime $startTime -endTime $endTime -timeGrain $timeGrain 

# Filter element contains the Azure context
$filteredMts = @()
foreach ($mt in $mts)
{
    if (!$mt.GetType().ToString().Contains('PSAzureContext'))
    {
        $filteredMts = $filteredMts + $mt
    }
}

# Export raw data as CSV text file
$filteredMts | Export-Csv $fileName -NoTypeInformation 

