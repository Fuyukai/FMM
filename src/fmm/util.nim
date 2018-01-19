import os, streams, osproc, strutils, json
import ./termhelpers

## Opens from a location.
proc openData*(location: string): string =
  if not location.existsFile():
    raise newException(IOError, "File not found: " & location)

  var stream = newFileStream(location, fmRead)
  result = stream.readAll()
  stream.close()

## Parses JSON from a file.
proc openJson*(location: string): JsonNode =
  var s = location.newFileStream(fmRead)
  result = parseJson(s, location)
  s.close()

## Saves JSON to a file.
proc saveJson*(location: string, json: JsonNode) =
  let stream = location.newFileStream(fmWrite)
  stream.write(json.pretty(4))
  stream.close()
  

## config stuff

type
  FactorioConfig* = object
    ## The location of the settings file.
    location*: string
    ## The directory to use.
    directory: string
    ## The Factorio username used.
    username*: string
    ## The Factorio token used.
    token*: string
    ## If this running server-side.
    server*: bool

var config* = FactorioConfig()

## Gets the Factorio directory on the client.
template getFactorioDirClient*(): string =
  when system.hostOS == "windows":
    $getEnv("APPDATA") & "/Factorio"

  elif system.hostOS == "linux":
    $getEnv("HOME") & "/.factorio"

  elif system.hostOS == "macosx":
    $getEnv("HOME") & "~/Library/Application Support/factorio"

  else:
    # panic
    $os.getAppDir()

## Gets the factory directory on the server.
template getFactorioDirServer*(): string = 
  if config.directory.isNil():
    getCurrentDir()
  else:
    config.directory


## Loads the current factorio config.
## This must be called first; this behaves differently on the server and on the client.
proc loadConfig*(cfg: var FactorioConfig, location: string, server: bool = false, 
                 directory: string = nil) =
  cfg.server = server
  cfg.directory = directory
  let actualLocation = if location.isNil():
      if server:
        getCurrentDir() / "data" / "server-settings.json"
      else:
        getFactorioDirClient() / "player-data.json"
    else:
      location
  
  if not actualLocation.existsFile():
    raise newException(IOError, "No such file: " & actualLocation)
  
  cfg.location = actualLocation
  let data = openJson(actualLocation)

  # server uses raw username/token
  # client uses service- prefix
  if server:
    cfg.username = data["username"].getStr()
    cfg.token = data["token"].getStr()
  else:
    cfg.username = data["service-username"].getStr()
    cfg.token = data["service-token"].getStr()


# Gets the factorio binary.
proc getFactorioBinary*(): string =
  let fName = if config.server:
      getFactorioDirServer() / "factorio-current.log"
    else:
      getFactorioDirClient() / "factorio-current.log"
  let stream = newFileStream(fName, fmRead)
  let lines = stream.readAll().splitLines()

  if lines.len < 5:
    raise newException(IOError, "Log file is incomplete")

  # example of line 5: 0.037 Binaries path: /media/storage/eyes/.local/share/Steam/steamapps/common/Factorio/bin 
  let argumentLine = lines[5]
  let binPath = argumentLine.split("Binaries path: ")[1]
  
  let buildLine = lines[0]
  let sp = buildLine.split("(build ")[1].split(",")[1]
  let found = "x" & sp[^2..^0]

  let path = binPath / found / "factorio"
  return path

## Gets the current modpack directory.
template getModpackDirectory*(): string = config.directory / "modpacks"

## Gets the current downloads directory.
template getDownloadsDirectory*(): string = config.directory / "downloads"