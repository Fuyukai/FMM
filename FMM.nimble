# Package
version       = "0.1.0"
author        = "Laura F. D."
description   = "Factorio Modpack Manager"
license       = "MIT"

# dir configuration
srcDir = "src"
binDir = "bin"

# Binary configuration
# We use the `fmm` file as our main binary entry point
# And skip the `nim` files since we're not a library.
# TODO: Figure out how to switch based on target OS
when system.hostOS == "windows":
    bin = @["fmm"]
else:
    bin = @["fmm"]

skipExt = @["nim"]

# Dependencies
requires "nim >= 0.17.2"
requires "commandeer >= 0.12.0"
requires "zip#head"
requires "yaml >= 0.10.3"
requires "progress"