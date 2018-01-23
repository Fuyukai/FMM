## Install actions.
import os, strutils, json, cgi, future, streams
import ../httpapi, ../util, ../modpack, ../termhelpers, ../exceptions
import yaml


## Generic installation function, shared between client and server.
proc doModpackInstall(modpack: Modpack): bool =
  let modpackDir = getModpackDirectory() / modpack.meta.name

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
    let modData: JsonNode = getModInfo(fMod.name)

    if modData.hasKey("message") and modData["message"].getStr() == "Mod not found":
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
              let facVer = release["info_json"]["factorio_version"].getStr
              if modpack.factorio.version != facVer:
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

    let facVer = selectedRelease["info_json"]["factorio_version"].getStr()
    if not modpack.factorio.version.isNil and facVer != modpack.factorio.version:
      echoErr "This mod is for ", facVer, ", not ", modpack.factorio.version
      return false

    # time to do the download
    # define some variables 
    var downloadUrl = MODS_BASE_URL & selectedRelease["download_url"].getStr()
    let filename = selectedRelease["file_name"].getStr  # 2018-01-17 thank devs :pray:
    let filepath = getDownloadsDirectory() / filename
    if filepath.existsFile():
      outputGreen "Skipping downloading mod " & filename & ", mod already downloaded"
    else:
      # copy data onto the download url
      downloadUrl = downloadUrl & "?username=" & config.username
      downloadUrl = downloadUrl & "&token=" & config.token

      outputPink "Downloading ", filename, " to '", filepath, "'"
      downloadFile(downloadUrl, filepath)
      outputGreen "Downloaded ", filename, " successfully."

    # Symlink mods into the appropriate folder
    outputCyan "Linking into modpack folder..."

    when system.hostOS == "windows":
      createHardlink(filepath.expandFilename(), modpackDir / filename)
    else:
      createSymlink(filepath.expandFilename(), modpackDir / filename)

    outputCyan "Installed mod " & fMod.name & "\n"

  # copy the modpack.yaml to the directory
  let s = newFileStream(modpackDir / "modpack.yaml", fmWrite)
  dump(modpack, s)
  s.close()

  return true

## A server-specific installation function.
## This updates the server config as appropriate.
proc doModpackInstallOnServer*(modpack: Modpack): bool =
  let installed = doModpackInstall(modpack)
  if not installed:
    return false

  outputPink "Updating server config..."
  var rawConfig = openJson(config.location)
  outputPink "Adding FMM tags..."
  let tags = rawConfig["tags"].getElems()
  var newTags: seq[string] = @[]
  
  # copy over old tags
  for tag in tags:
    let sTag = tag.getStr()
    # don't copy over any old fmm tags, since we replace them
    if sTag.startsWith("_fmm"):
      continue
    newTags.add(sTag)

  # add the new fmm tags
  # this is required for the client to even see the fmm 
  newTags.add("_fmm-indicator")
  # these three are required to build the modpack client-side
  newTags.add("_fmm-modpack=" & modpack.meta.name)
  newTags.add("_fmm-modpack-version=" & modpack.meta.version)
  newTags.add("_fmm-modpack-author=" & modpack.meta.author)
  if not modpack.meta.update_url.isNil():
    newTags.add("_fmm-modpack-update=" & modpack.meta.update_url)

  rawConfig["tags"] = %newTags
  saveJson(config.location, rawConfig)
  outputPink "Successfully updated server config."

  return true


## Does an install from a server name.
proc getModpackFromServer*(serverName: string): Modpack =
  # try and find the specified name in the list of servers
  let servers = getServerList()
  var foundServer: JsonNode = nil

  for server in servers:
    let name = server["name"].getStr().toLowerAscii()
    if name == serverName.toLowerAscii():
      foundServer = server
      break    

  if foundServer.isNil():
    raise newException(InstallError, "Could not find a matching server")

  # download the full data listing
  outputCyan "Found a matching server, checking if we can install from it..."
  let serverData = getServerInfo(foundServer["game_id"].getNum().int)

  # unwrap tags
  let tags = foundServer["tags"].getElems()
  var strTags: seq[string] = @[]
  for tag in tags:
    strTags.add(tag.getStr())

  if not strTags.contains("_fmm-indicator"):
    raise newException(InstallError, "Server does not have an FMM indicator set.")

  outputGreen "Server has an FMM indicator, retrieving data..."

  # begin constructing a modpack
  var modpack = Modpack()
  modpack.meta.name = serverData["name"].getStr()
  # first, update with appropriate tags
  for tag in strTags:
    if tag.startsWith("_fmm-modpack="):
      modpack.meta.name = tag.split("=")[1]
    elif tag.startswith("_fmm-modpack-author="):
      modpack.meta.author = tag.split("=")[1]
    elif tag.startsWith("_fmm-modpack-version="):
      modpack.meta.version = tag.split("=")[1]
    elif tag.startsWith("_fmm-modpack-update"):
      modpack.meta.update_url = tag.split("=")[1]

  # ensure we have some attributes
  if modpack.meta.author.isNil():
    raise newException(InstallError, "Missing author tag.")
  
  if modpack.meta.version.isNil():
    raise newException(InstallError, "Missing version tag.")

  let version = serverData["application_version"]["game_version"].getStr().split(".")[0..1]
  modpack.factorio.version = version.join(".")
  modpack.factorio.server = serverData["host_address"].getStr()
  modpack.mods = @[]

  for sMod in serverData["mods"].getElems():
    var mpMod = ModpackMod()
    
    # don't try to download the base game mod
    let name = sMod["name"].getStr()
    if name == "base":
      continue

    mpMod.name = name
    mpMod.version = sMod["version"].getStr()
    modpack.mods.add(mpMod)

  # we've built as much as we can from this modpack
  return modpack

## Pass-through function.
proc doModpackInstallOnClient*(modpack: Modpack): bool = doModpackInstall(modpack)

proc doInstall*(arguments: seq[string]): bool =
  var modpack: Modpack
  # if the modpack isn't found locally, we can try and get it from the server
  try:
    modpack = loadModpackData(arguments.join(" "))
  except ModpackNotFound:
    outputPink "Could not find a modpack file, trying to install from a server..."
    try:
      modpack = getModpackFromServer(arguments.join(" "))
    except InstallError:
      echoErr "Could not find a modpack or valid server."
      echoErr getCurrentExceptionMsg()
      return

  echo ""
  outputGreen "Installing modpack: " & modpack.meta.name & " version " & modpack.meta.version
  if config.server:
    outputGreen "Doing a server installation..."
    return doModpackInstallOnServer(modpack)
  else:
    outputGreen "Doing a client installation..."
    return doModpackInstallOnClient(modpack)
