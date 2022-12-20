Param([string]$subscriptionId, [string]$workspaceId)

$global:failed=0
$global:subscriptionId="419581d6-4853-49bd-83b6-d94bb8a77887"
$global:workspaceId="059f037c-1b3b-42b1-bb90-e340e8c3142c"
$global:schemas = ("DNS", "WebSession", "NetworkSession", "ProcessEvent")

Class Parser {
    [string] $Name;
    [string] $OriginalQuery;
    [string] $Schema;
    [System.Collections.Generic.List`1[System.Object]] $Parameters
    Parser([string] $Name, [string] $OriginalQuery, [string] $Schema, [System.Collections.Generic.List`1[System.Object]] $Parameters) {
        $this.Name = $Name;
        $this.OriginalQuery = $OriginalQuery;
        $this.Schema = $Schema;
        $this.Parameters = $Parameters;
    }
}

function run ([string]$subscriptionId = "", [string]$workspaceId = "") {
    if ([string]::IsNullOrEmpty($subscriptionId)) {
        $subscriptionId = $global:subscriptionId
    }

    Write-Host workspaceId $workspaceId 
    if ([string]::IsNullOrEmpty($workspaceId)) {
        $workspaceId = $global:workspaceId
    }

    $subscription = Select-AzSubscription -SubscriptionId $subscriptionId
    $modifiedSchemas = & "$($PSScriptRoot)/../../getModifiedASimSchemas.ps1"
    $schemaTesterAsletStatements = getSchemaTesterAsletStatement
    $dataTesterAsletStatements = getDataTesterAsletStatement
    Write-Host modifiedSchemas $modifiedSchemas
    Write-Host modifiedSchemas type- $modifiedSchemas.GetType()
    foreach ($schema in $modifiedSchemas)
    {
        Write-Host "111 schema $($schema)"
        testSchema $workspaceId $schema $schemaTesterAsletStatements $dataTesterAsletStatements
    }
    #$modifiedSchemas | ForEach-Object { testSchema($workspaceId, $_, $schemaTesterAsletStatements, $dataTesterAsletStatements)}
}

function getSchemaTesterAsletStatement {
    $aSimSchemaTester =  Get-Content "$($PSScriptRoot)/../../../ASIM/dev/ASimTester/ASimSchemaTester.json" | ConvertFrom-Json
    $schemaQuery = $aSimSchemaTester.resources.resources.properties.query
    $schemaParameters = $aSimSchemaTester.resources.resources.properties.functionParameters
    return "let generatedASimSchemaTester= ($($schemaParameters)) { $($schemaQuery) };"
}

function getDataTesterAsletStatement {
    $aSimDataTester =  Get-Content "$($PSScriptRoot)/../../../ASIM/dev/ASimTester/ASimDataTester.json" | ConvertFrom-Json
    $dataQuery = $aSimDataTester.resources.resources.properties.query
    $dataParameters = $aSimDataTester.resources.resources.properties.functionParameters
    return "let generatedASimDataTester= ($($dataParameters)) { $($dataQuery) };"
}

function testSchema([string] $workspaceId, [string] $schema, [string] $schemaTesterAsletStatements, [string] $dataTesterAsletStatements) {
    Write-Host "Testing $($workspaceId) workspaceId"
    Write-Host "Testing $($schema) schema"
    $parsersAsObjects = & "$($PSScriptRoot)/convertYamlToObject.ps1"  -Path "$($PSScriptRoot)/../../../Parsers/$($schema)/Parsers"
    Write-Host "$($parsersAsObjects.count) parsers were found"
    $parsersAsObjects | ForEach-Object {
        $functionName = "$($_.EquivalentBuiltInParser)V$($_.Parser.Version.Replace('.',''))"
        if ($_.Parsers) {
            Write-Host "The parser '$($functionName)' is a main parser, ignoring it"
        }
        else {
            testParser $workspaceId ([Parser]::new($functionName, $_.ParserQuery, $schema.replace("ASim", ""), $_.ParserParams)) $schemaTesterAsletStatements $dataTesterAsletStatements
        }
    }
}

function testParser([string] $workspaceId, [Parser] $parser, [string] $schemaTesterAsletStatements, [string] $dataTesterAsletStatements) {
    Write-Host "Testing parser- '$($parser.Name)'"
    $letStatementName = "generated$($parser.Name)"
    $parserAsletStatement = "let $($letStatementName)= ($(getParameters($parser.Parameters))) { $($parser.OriginalQuery) };"

    Write-Host "-- Running schema test for '$($parser.Name)'"
    $schemaTest = "$($schemaTesterAsletStatements)`r`n$($parserAsletStatement)`r`n$($letStatementName) | getschema | invoke generatedASimSchemaTester('$($parser.Schema)')"
    invokeAsimTester $workspaceId $schemaTest $parser.Name "schema"
    Write-Host ""

    Write-Host "-- Running data test for '$($parser.Name)'"
    $dataTest = "$($dataTesterAsletStatements)`r`n$($parserAsletStatement)`r`n$($letStatementName) | invoke generatedASimDataTester('$($parser.Schema)')"
    invokeAsimTester $workspaceId $dataTest $parser.Name "data"
    Write-Host ""
    Write-Host ""
}

function invokeAsimTester([string] $workspaceId, [string] $test, [string] $name, [string] $kind) {
        $query = $test + " | where Result startswith '(0) Error:'"
        try {
            $rawResults = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspaceId -Query $query -ErrorAction Stop
            if ($rawResults.Results) {
                $resultsArray = [System.Linq.Enumerable]::ToArray($rawResults.Results)
                if ($resultsArray.count) {  
                    $errorMessage = "`r`n$($name) $($kind)- test failed with $($resultsArray.count) errors:`r`n"        
                    $resultsArray | ForEach-Object { $errorMessage += "$($_.Result)`r`n" } 
                    Write-Host $errorMessage
                    $global:failed = 1
                }
                else {
                    Write-Host "  -- $($name) $($kind) test done successfully"
                }
            }    
        }
        catch {
            Write-Host "  -- $_"
            Write-Host "     $(((Get-Error -Newest 1)?.Exception)?.Response?.Content)"
            $global:failed = 1
        }
}

function getParameters([System.Collections.Generic.List`1[System.Object]] $parserParams) {
    $paramsArray = @()
    if ($parserParams) {
        $parserParams | ForEach-Object {
            if ($_.Type -eq "string") {
                $_.Default = "'$($_.Default)'"
            }
            $paramsArray += "$($_.Name):$($_.Type)= $($_.Default)"
        }

        return $paramsArray -join ','
    }
    return $paramsString
}

run $subscriptionId $workspaceId
exit $global:failed