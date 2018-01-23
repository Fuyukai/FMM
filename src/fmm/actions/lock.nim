import os, strutils, streams, json, algorithm
import zip/zipfiles
import ../termhelpers, ../util

## Creates a list of mods out of a directory.
proc doLock*(location: string = nil) =
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
    var jsonData: string = nil
    for file in archive.walkFiles():
      if file == dName / "info.json":
        archive.extractFile(dName / "info.json", stream)
        stream.setPosition(0)
        jsonData = stream.readAll()
        break

    if jsonData.isNil:
      outputRed "Invalid zip file ", file, " (missing ", dName / "info.json", ")"
      continue

    let node = parseJson(jsonData)
    let modInfo: modType = (name: $node["name"], version: $node["version"])
    mods.add(modInfo)

  if mods.len <= 0:
    echoErr "Could not find any mods."
    return

  mods.sort do (x, y: modType) -> int: cmp(x.name.toLower(), y.name.toLower())

  outputPink "Mod output:\n"
  echo "mods:"
  for iMod in mods:
    echo "    - name: " & iMod.name & "\n      version: " & iMod.version