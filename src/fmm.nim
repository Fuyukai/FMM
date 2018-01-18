## FMM main file.
import os
import commandeer
import fmm/termhelpers, fmm/version, fmm/util
import fmm/actions/install, fmm/actions/launch

## Initializes FMM, creating directories and data files.
proc initFmm() =
  if not "modpacks".existsOrCreateDir():
    outputPink "Created directory 'modpacks'" 

  if not "downloads".existsOrCreateDir():
    outputPink "Created directory 'downloads'"


const helpText = """
Usage: fmm [command] <options>

Arguments
    --server    Run FMM in server mode.

Commands:
  install (i)   Installs a modpack.
  launch (la)   Launches a modpack.
  lock (lo)     Makes a list of mods from a directory.
  version (v)   Shows version information."""

commandline:
  option server, bool, "server", "s"
  option configLocation, string, "config", "c"

  subcommand cInstall, "install", "i":
    arguments iModpack, string

  subcommand cLaunch, "launch", "la":
    arguments lModpack, string
  
  subcommand cVersion, "version", "v":
    discard

  subcommand cLock, "lock", "lo":
    arguments loDirectory, string, false

  exitoption "help", "h", helpText
  errormsg helpText

initFmm()
try:
  config.loadConfig(configLocation, server)
except IOError:
  echoErr "No valid config file could be found."

  quit(1)

if cVersion:
  echo "FMM (Factorio Modpack Manager) v" & FMM_VERSION & " (Built with: Nim " & NimVersion & ")"
  if server:
    echo "FMM running in server mode."
  echo "Copyright (C) 2017 Laura F. Dickinson."
  echo "This program is licenced under the GPLv3 licence. This program comes with NO WARRANTY."
  echo ""
  echo "Using config from " & config.location
  let factorio = getFactorioBinary()
  if not factorio.isNil:
    echo "Using Factorio at " & factorio
  echo "Factorio is a registered trademark of Wube Software, Ltd."

elif cInstall:
  let success = doInstall(iModpack)
  if not success:
    echoErr "Failed to install."

elif cLaunch:
  doLaunch(lModpack)

else:
  echo "No command was selected. Use fmm --help for help."