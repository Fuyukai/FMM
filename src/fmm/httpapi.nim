import httpclient, json, cgi, strutils
import ./version, ./termhelpers, ./util

const
  MODS_BASE_URL* = "https://mods.factorio.com"
  MODS_API_URL* = MODS_BASE_URL & "/api"
  MODS_LIST_URL* = MODS_API_URL & "/mods"

  MULTIPLAYER_BASE_URL* = "https://multiplayer.factorio.com"
  MULTIPLAYER_GET_GAMES* = MULTIPLAYER_BASE_URL & "/get-games"
  MULTIPLAYER_GAME_INFO* = MULTIPLAYER_BASE_URL & "/get-game-details"

  USER_AGENT* = "FMM (https://github.com/SunDwarf/FMM, " & FMM_VERSION & ") Nim " & NimVersion 

let client = newHttpClient(USER_AGENT)

## Downloads from an address.
proc downloadData*(address: string): string =
  outputPink "Downloading ", address
  let response = client.get(address)
  let body = response.body()
  outputPink "Downloaded ", $body.len, " bytes"
  return body

proc downloadJson*(location: string): JsonNode =
  let data = downloadData(location)
  return data.parseJson()

## Downloads a file to a filepath.
proc downloadFile*(location: string, filepath: string) = client.downloadFile(location, filepath)

## Gets mod information.
## This will download the mod data from the Factorio mod portal, and return it as JSON.
proc getModInfo*(name: string): JsonNode =
  let url = MODS_LIST_URL & "/" & encodeUrl(name).replace("+", "%20")
  return downloadJson(url)

## Gets a list of all servers.
proc getServerList*(): JsonNode =
  let url = MULTIPLAYER_GET_GAMES & "?username=" & encodeUrl(config.username) & "&token=" & encodeUrl(config.token)
  return downloadJson(url)

## Gets information for a paticular server.
proc getServerInfo*(id: int): JsonNode =
  let url = MULTIPLAYER_GAME_INFO & "/" & id.intToStr()
  return downloadJson(url)