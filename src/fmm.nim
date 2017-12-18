## The FMM utility.
import os, osproc, strutils, json, httpclient, streams, tables, cgi, rdstdin
import commandeer
import yaml
import progress

const
  BASE_URL = "https://mods.factorio.com"
  API_URL = BASE_URL & "/api"
  MODS_URL = API_URL & "/mods"
  USER_AGENT = "FactorioModpackManager 0.1.0/Nim " & NimVersion

let client: HttpClient = USER_AGENT.newHttpClient()
#let headers = newHttpHeaders()
# prevent chunked transfer encoding from happening
#headers["Transfer-Encoding"] = "junk"
#client.headers = headers

## Note: login flow for downloading mods
## 1) POST https://auth.factorio.com/api-login?api_version=2 with username, password, steamid, and require_game_ownership=true
## 2) GET https://mods.factorio.com/api/downloads/data/mods/.../...?username=username&token=token where token is retrieved above
## 3) GET mods-data URL from the redirect

# modpack.yaml object structure for NimYAML
type
  ModpackMeta = object
    ## The name of the modpack.
    name: string
    ## The author of the modpack.
    author: string
    ## The URL for the modpack.
    url: string
    ## The update URL for the modpack.
    update_url: string
    ## The version for the modpack.
    version: string

  ModpackFactorio = object
    ## The factorio version required.
    version: string
    ## The server to connect to.
    server: string

  ModpackMod = object
    ## The name of the mod.
    name: string
    ## The version of the mod to pin to.
    version: string

  Modpack = object
    ## The meta section of the modpack description.
    meta: ModpackMeta
    ## The factorio section of the modpack description.
    factorio: ModpackFactorio
    ## The mods section of the modpack description.
    mods: seq[ModpackMod]

## Set some default values for preventing errors when constructing·
setDefaultValue(ModpackMod, version, nil)
setDefaultValue(ModPackMeta, version, nil)
setDefaultValue(ModpackMeta, url, nil)
setDefaultValue(ModpackMeta, update_url, nil)
setDefaultValue(ModpackFactorio, server, nil)

# Utility functions

## Gets the Factorio directory.
template getFactorioDir(): string =
  when system.hostOS == "windows":
    $getEnv("APPDATA") & "/Factorio"

  elif system.hostOS == "linux":
    $getEnv("HOME") & "/.factorio"

  elif system.hostOS == "macosx":
    $getEnv("HOME") & "~/Library/Application Support/factorio"

  else:
    # panic
    $os.getAppDir()

# utility methods
template echoErr(args: varargs[string, `$`]) =
  stderr.writeLine "[!] Error: " & args.join("")

template output(args: varargs[string, `$`]) =
  stdout.writeLine "[!] " & args.join("")

# Gets the factorio binary.
proc getFactorioBinary(): string =
  let fName = getFactorioDir() & "/factorio-current.log"
  let stream = newFileStream(fName, fmRead)
  let lines = stream.readAll().split("\n")

  if lines.len < 5:
    echoErr "Log file is incomplete!"
    return nil

  # example of line 2: 0.037 Program arguments: "/media/storage/eyes/.local/share/Steam/steamapps/common/Factorio/bin/x64/factorio" 
  return lines[2].split(":")[1].substr(1).split(" ")[0]


## Initializes FMM, creating directories and data files.
proc initFmm() =
  if not "modpacks".existsOrCreateDir():
    output "Created directory 'modpacks'" 

  if not "downloads".existsOrCreateDir():
    output "Created directory 'downloads'"


## Downloads from an address.
proc downloadData(address: string): string =
  output "Downloading ", address
  let response = client.get(address)
  let body = response.body()
  output "Downloaded ", $body.len, " bytes"
  return body
  
## Downloads a JSON document.
proc downloadJSON(address: string): JsonNode =
  return downloadData(address).parseJson()

## Opens from a location.
proc openData(location: string): string =
  if not location.existsFile:
    raise newException(IOError, "File not found")

  var stream = newFileStream(location, fmRead)
  result = stream.readAll()
  stream.close()

## Parses JSON from a file.
proc openJson(location: string): JsonNode =
  var s = location.newFileStream(fmRead)
  result = parseJson(s, location)
  s.close()


## Gets the modpack object from the modpack's YAML.
proc loadModpackFromYAML(name: string): Modpack =
  var modpackYAML: string
  if name.startsWith("http://") or name.startsWith("https://"):
    modpackYAML = downloadData(name)
  else:
    modpackYAML = openData(name)

  var modpack = Modpack()
  load(modpackYAML, modpack)

  # always lowercase the name
  modpack.meta.name = modpack.meta.name.toLowerAscii().replace(" ", "_")

  return modpack

# Commands logic

## Does the login process
proc doLogin(): bool =
  output "Starting auth.factorio.com login flow."
  let hasToken = readLineFromStdin "[!] Do you have a login token? [y/N] " 

  # stored in the login details file
  var
    token: string
    username: string

  if hasToken == "y":
    token = readPasswordFromStdin "[!] Enter your login token: "
    username = readLineFromStdin "[!] Enter your Factorio username: "
  else:
    username = readLineFromStdin "[!] Enter your Factorio username: "
    let password = readPasswordFromStdin "[!] Enter your Factorio password: "
    let steamid = readLineFromStdin "[!] Enter your Factorio steamID (enter nothing if you don't have one): "
    # make the request
    var body = "require_game_ownership=true&username=" & username & "&password=" & encodeUrl(password)
    if steamid != "":
      body = body & "&steam_id=" & steamid

    let tmpClient = newHttpClient()
    let headers = newHttpHeaders()
    headers["Content-Type"] = "application/x-www-form-urlencoded"
    tmpClient.headers = headers
    let response = tmpClient.post(url="https://auth.factorio.com/api-login?api_version=2", body=body)
    if not response.code().is2xx:
      echoErr "Failed to login to Factorio."
      echoErr response.body()
      return false

    let res = response.body().parseJson()
    token = res["token"].getStr()
    username = res["username"].getStr()
  
  let output = $(%*{"token": token, "username": username})
  let fl = open("settings.json", fmWrite)
  fl.write(output)
  fl.close()
  output "Logged in as ", username
  return true

## Does a modpack installation.
proc doInstall(modpackName: string): bool =
  if not "settings.json".existsFile():
    output "No login token detected, starting login process..."
    if not doLogin():
      echoErr "Login failed; cannot do installation."
      return

  var settings = openJson("settings.json")

  if modpackName.len <= 0:
    output "Must pass a modpack URL or file path."
    return false
  
  output "Installing modpack from " & modpackName & "..."

  # load it from YAML
  var modpack: Modpack
  try:
    modpack = loadModpackFromYAML(modpackName)
  except YamlConstructionError:
    echoErr "Invalid YAML provided. Is this definitely a modpack?"
    return false
  except IOError:
    echoErr "Failed reading from file. Does it exist?"
    return false

  output "Installing '", modpack.meta.name, "' by '", modpack.meta.author, "'"
  let modpackDir = "modpacks/" & modpack.meta.name.toLowerAscii()

  if modpackDir.existsDir():
    modpackDir.removeDir()

  createDir(modpackDir)

  # Enter the download loop.
  output "Downloading mods..."
  for fMod in modpack.mods:
    var constructed = ""
    if fMod.version == nil:
      constructed = fmod.name & " (any)"
    else:
      constructed = fMod.name & " (" & fMod.version & ")"

    output "Downloading info on '", constructed, "'"
    let encodedUrl = encodeUrl(fmod.name).replace("+", "%20")
    var modData: JsonNode = downloadJSON(MODS_URL & "/" & encodedUrl)

    if modData.hasKey("detail") and modData["detail"].getStr() == "Not found.":
      echoErr "Mod '", fMod.name, "' not found"
      return false

    var selectedRelease: JsonNode
    var currentVersion: string = ""

    # The bootleggest of bootleg sorting methods
    for release in modData["releases"].elems:
      # special handling in case version is nil
      # in which case, we try and download the latest version
      if fMod.version.isNil:
        if release["version"].getStr() > currentVersion:
          selectedRelease = release
          currentVersion = release["version"].getStr()
      else:
        if release["version"].getStr() == fMod.version:
          selectedRelease = release
          break
      
    if selectedRelease.isNil:
      echoErr "Could not find a matching release for ", fmod.name, " version ", fmod.version
      return false

    let facVer = selectedRelease["factorio_version"].getStr()
    if not modpack.factorio.version.isNil and facVer != modpack.factorio.version:
      echoErr "This mod is for ", facVer, ", not ", modpack.factorio.version
      return false

    # time to do the download
    # define some variables 
    var downloadUrl = BASE_URL & selectedRelease["download_url"].getStr()
    let filename = downloadURL.split("/")[^1].decodeUrl()
    let filepath = "downloads/" & filename
    if filepath.existsFile():
      output "Skipping downloading mod " & filename & ", mod already downloaded"
    else:
      # copy data onto the download url
      downloadUrl = downloadUrl & "?username=" & settings["username"].getStr().encodeUrl()
      downloadUrl = downloadUrl & "&token=" & settings["token"].getStr().encodeUrl()

      output "Downloading ", downloadUrl, " to '", filepath, "'"
      client.downloadFile(downloadUrl, filepath)
      output "Downloaded ", filename, " successfully."

    # Symlink mods into the appropriate folder
    output "Linking into modpack folder..."

    when system.hostOS == "windows":
      createHardlink(filepath.expandFilename(), modpackDir & "/" & filename)
    else:
      createSymlink(filepath.expandFilename(), modpackDir & "/" & filename)

    output "Installed mod " & fMod.name

  output "Installed modpack!"
  return true
    
## Launches factorio with the specified modpack.
proc doLaunch(modpackName: string) =
  # load it from YAML
  var modpack: Modpack
  try:
    modpack = loadModpackFromYAML(modpackName)
  except YamlConstructionError:
    echoErr "Invalid YAML provided. Is this definitely a modpack?"
    return 
  except IOError:
    echoErr "Failed reading from file. Does it exist?"
    return

  # ensure it's installed, and if not, install it
  let fullName = getCurrentDir() & "/modpacks/" & modpack.meta.name
  if not fullName.existsDir():
    if not doInstall(modpackName):
      echoErr "Failed to install modpack."
      return

  # build the command line
  let executable = getFactorioBinary()
  var commandLineArgs = @[executable, "--mod-directory", fullName]
  if not modpack.factorio.server.isNil:
    commandLineArgs.add("--mp-connect")
    commandLineArgs.add(modpack.factorio.server)

  let commandLine = commandLineArgs.join(" ")

  output "Launching Factorio... (" & commandLine & ")"
  let errorCode = execCmd(commandLine)

  output "Factorio process exited with error code " & $errorCode


# Command-line handling
initFmm()

const helpText = """
Usage: fmm [command] <options>

Commands:
  login         Logins into the mod portal. Required to download mods.
  install       Installs a modpack.
  launch        Launches a modpack.
  """

commandline:
  subcommand install, "install", "i":
    argument iModpack, string

  subcommand login, "login", "l": discard

  subcommand launch, "launch", "la":
    argument lModpack, string

  exitoption "help", "h", helpText
  errormsg helpText

if install:
  discard doInstall(iModpack)
elif login:
  discard doLogin()
elif launch:
  doLaunch(lModpack)
else:
  echo "No command was selected. Use fmm --help for help."