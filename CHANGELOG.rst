Changelog
=========

0.3.0
-----

 - The core of the code has been split out into separate files. This makes maintainability a lot 
   easier.

 - Added the ability to specify the config file FMM uses.

 - Added the ability to specify the base directory. This will affect the location of the modpacks 
   and downloads directory on the client.

 - Added the ability to run FMM on a headless server. This will edit the server tags to ensure 
   clients can install the modpack remotely.

 - Removed launching from a YAML or from a URL.

 - Added the ability to install a modpack directly from a server.

0.2.1
-----

 - Fix FMM for the latest API changes.

0.2.0
-----

 - Add auto-updating from an update URL saved in your modpack folder.

 - Copy the modpack YAML into the modpack folder.

 - Allow launching a modpack from a folder, without using the YAML.


0.1.4
-----

 - Parse the Factorio bittiness from the log file. This prevents issues with x86 builds running on 
   x64.

0.1.3
-----

 - Add version locking. The modpack will automatically update if a newer version is defined by the 
   YAML.

 - Add a locking command, which produces a mod listing from a directory.

 - Fix handling of spaces in directory names by passing arguments to the Factorio client properly.

0.1.2
-----

 - Use the Factorio binaries location from the log file to find the Factorio launcher.
 
0.1.0
-----

 - Initial release.