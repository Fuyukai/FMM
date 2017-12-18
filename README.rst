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

Before using FMM, you must login to the mod portal, this is so that FMM can download 
mdos automatically.

.. code-block:: bash

    $ ./bin/fmm login

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

Writing Modpack YAMLs
---------------------

See ``examples/modpack.yaml`` for a full example 