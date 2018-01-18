## Launch actions.
import os, osproc, strutils
import ../modpack, ../util, ../termhelpers
import ./install
import yaml

proc doLaunch*(arguments: seq[string]) =
  # load it from YAML
  let modpackName = arguments.join(" ")
  var modpack: Modpack
  try:
    let data = openData("modpacks" / modpackName / "modpack.yaml")
    modpack = loadModpackFromData(data)
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

  # check version
  var updated = false
  if not modpack.meta.update_url.isNil():
    # auto-update if applicable
    var newModpack = loadModpackData(modpack.meta.update_url)
    if newModpack.meta.version > modpack.meta.version:
      outputPink "Updating modpack..."
      let installed = doModpackInstallOnClient(newModpack)
      if not installed:
        echoErr "Failed to update modpack."
        return

  if not updated:
    outputPink "Modpack is up-to-date, version " & modpack.meta.version

  # build the command line
  let executable = getFactorioBinary()
  if executable.isNil:
    echoErr "Cannot launch Factorio."
    return

  let qualifiedName = getCurrentDir() / "modpacks" / modpack.meta.name

  var commandLineArgs = @["--mod-directory", qualifiedName]
  if not modpack.factorio.server.isNil:
    commandLineArgs.add("--mp-connect")
    commandLineArgs.add(modpack.factorio.server)

  outputPink "Launching Factorio... (" & executable & " " & commandLineArgs.join(" ") & ")"
  let process = startProcess(executable, args=commandLineArgs, options={poParentStreams})
  let errorCode = waitForExit(process)

  outputPink "Factorio process exited with error code " & $errorCode