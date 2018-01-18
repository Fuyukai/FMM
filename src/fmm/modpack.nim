import strutils, os, streams
import yaml
import ./httpapi, ./exceptions

# modpack.yaml object structure for NimYAML
type
  ModpackMeta* = object
    ## The name of the modpack.
    name*: string
    ## The author of the modpack.
    author*: string
    ## The URL for the modpack.
    url*: string
    ## The update URL for the modpack.
    update_url*: string
    ## The version for the modpack.
    version*: string

  ModpackFactorio* = object
    ## The factorio version required.
    version*: string
    ## The server to connect to.
    server*: string

  ModpackMod* = object
    ## The name of the mod.
    name*: string
    ## The version of the mod to pin to.
    version*: string

  Modpack* = object
    ## The meta section of the modpack description.
    meta*: ModpackMeta
    ## The factorio section of the modpack description.
    factorio*: ModpackFactorio
    ## The mods section of the modpack description.
    mods*: seq[ModpackMod]

## Set some default values for preventing errors when constructing·
setDefaultValue(ModpackMod, version, nil)
setDefaultValue(ModPackMeta, version, nil)
setDefaultValue(ModpackMeta, url, nil)
setDefaultValue(ModpackMeta, update_url, nil)
setDefaultValue(ModpackFactorio, server, nil)

# Internal implementation functions
proc loadModpackFromData*(data: string): Modpack =
  var modpack = Modpack()
  load(data, modpack)

  return modpack

proc loadModpackFromNetwork(location: string): Modpack =
  let data = downloadData(location)
  return loadModpackFromData(data)

proc loadModpackFromFile(location: string): Modpack =
  var stream = newFileStream(location, fmRead)
  let data = stream.readAll()
  stream.close()
  return loadModpackFromData(data)

proc loadModpackFromInstalled(name: string): Modpack =
  var final: string
  if not name.startsWith("modpacks"):
    final = "modpacks" / name
  else:
    final = name

  let path = final / "modpack.yaml"
  return loadModpackFromFile(path)

## Loads a modpack from a location.
## This location can be either a modpack directory, a YAML file, or an internet location.
proc loadModpackData*(location: string): Modpack =
  if location.startsWith("https://") or location.startsWith("http://"):
    return loadModpackFromNetwork(location)

  if location.existsFile():
    return loadModpackFromFile(location)

  if location.existsDir() or ("modpacks" / location).existsDir():
    return loadModpackFromInstalled(location)

  raise newException(ModpackNotFound, "Could not load modpack from " & location)