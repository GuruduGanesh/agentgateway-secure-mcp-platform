param(
  [string]$BaseUrl = "http://localhost:8080",
  [string]$Realm = "agentgateway",
  [string]$ClientId = "agentgateway-demo",
  [Parameter(Mandatory = $true)][string]$User,
  [Parameter(Mandatory = $true)][string]$Password
)

$body = @{
  grant_type = "password"
  client_id = $ClientId
  username = $User
  password = $Password
}

try {
  $token = Invoke-RestMethod -Method Post -Uri "$BaseUrl/realms/$Realm/protocol/openid-connect/token" -Body $body -ContentType "application/x-www-form-urlencoded"
  $token.access_token
} catch {
  Write-Error "Could not get Keycloak token: $($_.Exception.Message)"
  exit 1
}
