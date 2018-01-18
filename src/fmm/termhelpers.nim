import terminal, os, strutils

proc echoErr*(args: varargs[string, `$`]) =
  stderr.styledWriteLine fgRed, "[!] Error: " & args.join(""), resetStyle

# coloured outputs
proc outputPink*(args: varargs[string, `$`]) =
  stdout.styledWriteLine fgMagenta, "[!] ", args.join(""), resetStyle

proc outputBlue*(args: varargs[string, `$`]) =
  stdout.styledWriteLine fgBlue, "[!] ", args.join(""), resetStyle

proc outputGreen*(args: varargs[string, `$`]) =
  stdout.styledWriteLine fgGreen, "[!] ", args.join(""), resetStyle

proc outputCyan*(args: varargs[string, `$`]) =
  stdout.styledWriteLine fgCyan, "[!] ", args.join(""), resetStyle

proc outputRed*(args: varargs[string, `$`]) =
  stdout.styledWriteLine fgRed, "[!] ", args.join(""), resetStyle