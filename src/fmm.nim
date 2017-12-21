## The FMM utility.
import os, osproc, strutils, json, httpclient, streams, tables, cgi, rdstdin, terminal
import commandeer
import yaml
import progress

const
  BASE_URL = "https://mods.factorio.com"
  API_URL = BASE_URL & "/api"
  MODS_URL = API_URL & "/mods"
  USER_AGENT = "FactorioModpackManager 0.1.0/Nim " & NimVersion

  FMM_VERSION = "0.1.1"

let client: HttpClient = USER_AGENT.newHttpClient()
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

# Utility functions and templates

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
  stderr.styledWriteLine fgRed, "[!] Error: " & args.join(""), resetStyle

# coloured outputs
template outputPink(args: varargs[string, `$`]) =
  stdout.styledWriteLine fgMagenta, "[!] ", args.join(""), resetStyle

template outputBlue(args: varargs[string, `$`]) =
  stdout.styledWriteLine fgBlue, "[!] ", args.join(""), resetStyle

template outputGreen(args: varargs[string, `$`]) =
  stdout.styledWriteLine fgGreen, "[!] ", args.join(""), resetStyle

template outputCyan(args: varargs[string, `$`]) =
  stdout.styledWriteLine fgCyan, "[!] ", args.join(""), resetStyle

template outputRed(args: varargs[string, `$`]) =
  stdout.styledWriteLine fgRed, "[!] ", args.join(""), resetStyle

# compat
template output(args: varargs[string, `$`]) =
  outputPink args

# Gets the factorio binary.
proc getFactorioBinary(): string =
  let fName = getFactorioDir() / "factorio-current.log"
  let stream = newFileStream(fName, fmRead)
  let lines = stream.readAll().splitLines()

  if lines.len < 5:
    echoErr "Log file is incomplete!"
    return nil

  # example of line 5: 0.037 Binaries path: /media/storage/eyes/.local/share/Steam/steamapps/common/Factorio/bin 
  let argumentLine = lines[5]
  let binPath = argumentLine.split("Binaries path: ")[1]
  
  var arch: string
  when hostCPU == "i386":
    arch = "x86"
  elif hostCPU == "amd64":
    arch = "x64"
  else:
    # fuck it
    arch = "x86"

  let path = binPath / arch / "factorio"

  return path


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

  # always normalize the name
  modpack.meta.name = modpack.meta.name.toLowerAscii().replace(" ", "_")

  return modpack

# Commands logic

## Does a modpack installation.
proc doInstall(modpackName: string): bool =
  let settings = openJson(getFactorioDir() & "/player-data.json")

  if modpackName.len <= 0:
    echoErr "Must pass a modpack URL or file path."
    return false
  
  outputBlue "Installing modpack from " & modpackName & "..."

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

  outputBlue "Installing '", modpack.meta.name, "' by '", modpack.meta.author, "'"
  let modpackDir = "modpacks/" & modpack.meta.name.toLowerAscii()

  if modpackDir.existsDir():
    modpackDir.removeDir()

  createDir(modpackDir)

  # Enter the download loop.
  outputBlue "Downloading mods..."
  for fMod in modpack.mods:
    var constructed = ""
    if fMod.version == nil:
      constructed = fmod.name & " (any)"
    else:
      constructed = fMod.name & " (" & fMod.version & ")"

    outputCyan "Downloading info on '", constructed, "'"
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

            # ensure we don't accidentally select the wrong release
            if not modpack.factorio.version.isNil:
              if modpack.factorio.version != release["factorio_version"].getStr():
                continue

            selectedRelease = release
            currentVersion = release["version"].getStr()
      else:
        if release["version"].getStr() == fMod.version:
          selectedRelease = release
          break
      
    if selectedRelease.isNil:
      var version: string
      if fmod.version.isNil:
        version = "(no version)"
      else:
        version = fmod.version

      echoErr "Could not find a matching release for ", fmod.name, " version ", version, " for this Factorio version"
      return false

    let facVer = selectedRelease["factorio_version"].getStr()
    if not modpack.factorio.version.isNil and facVer != modpack.factorio.version:
      echoErr "This mod is for ", facVer, ", not ", modpack.factorio.version
      return false

    # time to do the download
    # define some variables 
    var downloadUrl = BASE_URL & selectedRelease["download_url"].getStr()
    let filename = downloadURL.split("/")[^1].decodeUrl()
    let filepath = "downloads" / filename
    if filepath.existsFile():
      outputGreen "Skipping downloading mod " & filename & ", mod already downloaded"
    else:
      # copy data onto the download url
      downloadUrl = downloadUrl & "?username=" & settings["service-username"].getStr().encodeUrl()
      downloadUrl = downloadUrl & "&token=" & settings["service-token"].getStr().encodeUrl()

      outputPink "Downloading ", filename, " to '", filepath, "'"
      client.downloadFile(downloadUrl, filepath)
      outputGreen "Downloaded ", filename, " successfully."

    # Symlink mods into the appropriate folder
    outputCyan "Linking into modpack folder..."

    when system.hostOS == "windows":
      createHardlink(filepath.expandFilename(), modpackDir / filename)
    else:
      createSymlink(filepath.expandFilename(), modpackDir / filename)

    outputCyan "Installed mod " & fMod.name & "\n"

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
  let fullName = getCurrentDir() / "modpacks" / modpack.meta.name
  if not fullName.existsDir():
    if not doInstall(modpackName):
      echoErr "Failed to install modpack."
      return

  # build the command line
  let executable = getFactorioBinary()
  if executable.isNil:
    echoErr "Cannot launch Factorio."
    return

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
  install       Installs a modpack.
  launch        Launches a modpack.
  version       Shows version information.
  """

commandline:
  subcommand install, "install", "i":
    argument iModpack, string

  subcommand launch, "launch", "la":
    argument lModpack, string
  
  subcommand version, "version", "v":
    discard

  exitoption "help", "h", helpText
  errormsg helpText

if install:
  discard doInstall(iModpack)
elif launch:
  doLaunch(lModpack)
elif version:
  echo "FMM (Factorio Modpack Manager) v" & FMM_VERSION
  echo "Copyright (C) 2017 Laura F. Dickinson."
  echo "This program is licenced under the MIT licence. This program comes with NO WARRANTY."
  echo ""
  echo "Factorio is a registered trademark of Wube Software, Ltd."
else:
  echo "No command was selected. Use fmm --help for help."