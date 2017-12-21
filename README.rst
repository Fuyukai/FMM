FMM
===

FMM (Factorio Modpack Manager) is a modpack manager for Factorio_.

Building
--------

FMM can be built using the provided Makefile, or via the direct usage of nimble.

You must have Nim 0.17.2 or higher installed. The best way to do this is with 
``choosenim``.

.. code-block:: bash

    # host OS build
    $ make build
    $ nimble build

    # windows 32-bit cross-compile
    $ make build_win32

    # windows 64-bit cross-compile
    $ make build_win64

Usage
-----

FMM requires that Factorio is launched at least once. This is so that it can scan your
factorio data directory to find where you installed it.

Additionally, you must have logged into the mod portal inside Factorio at least once, 
in order to get a mod portal token to use to download mods.

To install a modpack, you can use ``fmm install modpack.yaml`` to install from a local
file, or ``fmm install https://website.com/link.yaml`` to install from a URL.

.. code-block:: bash

    $ ./bin/fmm install mypack.yaml
    $ ./bin/fmm install https://mysite.com/factorio/mypack.yaml

You can launch a modpack with the usage of ``fmm launch``:

.. code-block:: bash

    $ ./bin/fmm launch mypack.yaml

This will automatically locate your Factorio executable and run it with the correct mod
directory. If a server is provided in the file, it will connect automatically.

FAQ
---

**Q:** I get a ``ProtocolError`` when downloading, what do I do?  
**A:** Just re-run the command. This means the mod portal server kicked you off.  

**Q:** How do I uninstall a modpack?  
**A:** Delete it's directory in ``modpacks``.  

**Q:** I got ``could not load: x.dll`` when running on Windows.  
**A:** Grab the dll from https://nim-lang.org/download/dlls.zip and drop it in the same folder.  

**Q:** ``fmm launch`` doesn't do anything / it spawns a steam modal.  
**A:** If the steam modal isn't visible, you probably need to click steam. Just click OK.  

Writing Modpack YAMLs
---------------------

See ``examples/modpack.yaml`` for a full example 