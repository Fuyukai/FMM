## The FMM utility.
import os, osproc, strutils, json, httpclient, streams, tables, cgi, rdstdin, terminal, re
import commandeer
import yaml
import zip/zipfiles

const
  BASE_URL = "https://mods.factorio.com"
  API_URL = BASE_URL & "/api"
  MODS_URL = API_URL & "/mods"

  FMM_VERSION = "0.2.0"
  USER_AGENT = "FMM (https://github.com/SunDwarf/FMM, " & FMM_VERSION & ") Nim " & NimVersion 

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
  
  let buildLine = lines[0]
  let sp = buildLine.split("(build ")[1].split(",")[1]
  let found = "x" & sp[^2..^0]

  let path = binPath / found / "factorio"
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
  output "Loading modpack data from ", name
  if name.startsWith("http://") or name.startsWith("https://"):
    modpackYAML = downloadData(name)
  else:
    modpackYAML = openData(name)

  var modpack = Modpack()
  load(modpackYAML, modpack)

  # always normalize the name
  modpack.meta.name = modpack.meta.name.toLowerAscii().replace(" ", "_")

  return modpack

## Loads a modpack, either from the modpack YAML or the update URL in the folder.
proc loadModpack(name: string): Modpack =
  # check if it exists as a file, or as a URL
  if name.existsFile() or name.startsWith("https://") or name.startsWith("http://"):
    return loadModpackFromYAML(name)

  # check if the lock file exists
  if ("modpacks" / name).existsDir():
    let lock = openJson("modpacks" / name / "fmm_lock.json")
    var path = lock["url"].getStr()

    if path.isNil or path == "":
      let finalPath = ("modpacks" / name / "modpack.yaml")
      if not finalPath.existsFile():
        echoErr "Modpack does not have an update URL or a modpack.yaml saved. Cannot launch!"
        return

      path = finalPath

    return loadModpackFromYAML(path)

  raise newException(IOError, "Could not find modpack")

## Makes a lock JSON.
proc makeLock(modpack: Modpack) =
  let modpackDir = "modpacks/" & modpack.meta.name.toLowerAscii()

  # simple lock format just gives us the version
  let lock = %*{"version": modpack.meta.version, "url": modpack.meta.update_url}
  let stream = (modpackDir / "fmm_lock.json").newFileStream(fmWrite)
  stream.write($lock)
  stream.close()


# Commands logic

proc doInstall(modpack: Modpack): bool =
  let settings = openJson(getFactorioDir() & "/player-data.json")
  outputBlue "Installing '", modpack.meta.name, "' by '", modpack.meta.author, "'"
  let modpackDir = "modpacks" / modpack.meta.name.toLowerAscii()

  if modpackDir.existsDir():
    modpackDir.removeDir()

  createDir(modpackDir)

  # Enter the download loop.
  outputBlue "Downloading mods...\n"
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

  # output a fmm_lock.json
  outputPink "Locking modpack version at " & modpack.meta.version & "..."
  makeLock modpack

  # copy the modpack.yaml to the directory
  let s = newFileStream(modpackDir / "modpack.yaml", fmWrite)
  dump(modpack, s)
  s.close()

  output "Installed modpack!"
  return true

## Does a modpack installation.
proc doInstallFromName(modpackName: string): bool =
  if modpackName.len <= 0:
    echoErr "Must pass a modpack URL or file path."
    return false
  
  outputCyan "Installing modpack from " & modpackName & "..."

  # load it from YAML
  var modpack: Modpack
  try:
    # NB: We use loadModpackFromYAML because we don't want to install a modpack that already exists
    # if the user specifies one with the same name.
    modpack = loadModpackFromYAML(modpackName)
  except YamlConstructionError:
    echoErr "Invalid YAML provided. Is this definitely a modpack?"
    return false
  except IOError:
    echoErr "Failed reading from file. Does it exist?"
    return false

  return doInstall(modpack)
    
## Launches factorio with the specified modpack.
proc doLaunch(modpackName: string) =
  # load it from YAML
  var modpack: Modpack
  try:
    modpack = loadModpack(modpackName)
  except YamlConstructionError:
    echoErr "Invalid YAML provided. Is this definitely a modpack?"
    return 
  except IOError:
    let e = getCurrentExceptionMsg()
    echoErr "Failed reading from file. Does it exist?"
    echoErr "Error raised: ", e
    return
  
  if modpack.meta.name.isNil:
    echoErr "Cannot launch an empty modpack."
    return

  # ensure it's installed, and if not, install it
  let fullName = getCurrentDir() / "modpacks" / modpack.meta.name
  let dirExists = fullname.existsDir()
  let lockLocation = (fullname / "fmm_lock.json")
  let lockExists = lockLocation.existsFile()

  if not dirExists or not lockExists:
    outputBlue "Modpack is not installed, installing automatically..."
    if not doInstall(modpack):
      echoErr "Failed to install modpack."
      return
  else:
    # check version
    let lock = (fullname / "fmm_lock.json").openJson()

    if lock["version"].getStr != modpack.meta.version:
      outputRed "Installed version is " & lock["version"].getStr & ", latest version is " & modpack.meta.version
      outputPink "Updating modpack...\n"
      if not doInstall(modpack):
        echoErr "Failed to install modpack."
        return

  outputPink "Modpack is up-to-date, version " & modpack.meta.version

  # build the command line
  let executable = getFactorioBinary()
  if executable.isNil:
    echoErr "Cannot launch Factorio."
    return

  var commandLineArgs = @["--mod-directory", fullName]
  if not modpack.factorio.server.isNil:
    commandLineArgs.add("--mp-connect")
    commandLineArgs.add(modpack.factorio.server)

  outputPink "Launching Factorio... (" & executable & " " & commandLineArgs.join(" ") & ")"
  let process = startProcess(executable, args=commandLineArgs, options={poParentStreams})
  let errorCode = waitForExit(process)

  outputPink "Factorio process exited with error code " & $errorCode

## Creates a list of mods out of a directory.
proc doLock(location: string = nil) =
  if not location.existsDir():
    echoErr "This directory does not exist."
    return
  else:
    outputPink "Locking from location " & location

  # make list of mods
  type modType = tuple[name: string, version: string]
  var mods = newSeq[modType]()

  for kind, file in walkDir(location):
    if not file.endsWith(".zip"):
      continue

    let dName = file.splitPath()[1].split(".zip")[0]

    # open the archive for reading
    var archive: ZipArchive
    discard archive.open(file)

    # read info.json into our file
    let stream = newStringStream(newString(65535))
    archive.extractFile(dName / "info.json", stream)
    stream.setPosition(0)
    let jsonData = stream.readAll()

    let node = parseJson(jsonData)
    let modInfo: modType = (name: $node["name"], version: $node["version"])
    mods.add(modInfo)

  if mods.len <= 0:
    echoErr "Could not find any mods."
    return

  outputPink "Mod output:\n"
  echo "mods:"
  for iMod in mods:
    echo "    - name: " & iMod.name & "\n      version: " & iMod.version

# Command-line handling
initFmm()

const helpText = """
Usage: fmm [command] <options>

Commands:
  install (i)   Installs a modpack.
  launch (la)   Launches a modpack.
  lock (lo)     Makes a list of mods from a directory.
  version (v)   Shows version information."""

commandline:
  subcommand install, "install", "i":
    argument iModpack, string

  subcommand launch, "launch", "la":
    argument lModpack, string
  
  subcommand version, "version", "v":
    discard

  subcommand lock, "lock", "lo":
    arguments loDirectory, string, false

  exitoption "help", "h", helpText
  errormsg helpText

if install:
  discard doInstallFromName(iModpack)
elif launch:
  doLaunch(lModpack)
elif lock:
  var directory: string
  if loDirectory.len <= 0:
    directory = getFactorioDir() / "mods"
  else:
    directory = loDirectory[0]
  
  doLock(directory)

elif version:
  echo "FMM (Factorio Modpack Manager) v" & FMM_VERSION & " (Built with: Nim " & NimVersion & ")"
  echo "Copyright (C) 2017 Laura F. Dickinson."
  echo "This program is licenced under the MIT licence. This program comes with NO WARRANTY."
  echo ""
  let factorio = getFactorioBinary()
  if not factorio.isNil:
    echo "Using Factorio at " & factorio
  echo "Factorio is a registered trademark of Wube Software, Ltd."
else:
  echo "No command was selected. Use fmm --help for help."