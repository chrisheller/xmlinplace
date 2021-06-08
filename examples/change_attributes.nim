import ../xmlinplace
import os, streams, strutils

proc multiply_numeric_attrs*(in_stream: Stream, out_stream: Stream) =
  ## Runs the ``in_stream`` through the ``processxml`` iterator
  ## and writes to the ``out_stream`` with any integer attribute values
  ## multiplied by 25

  var ctx = initXmlParseContext()
  for xpi in processxml(in_stream, ctx):
    if xpi.event == xmlAttribute:
      try:
        let intVal = parseInt(xpi.attrValue)
        var newXPI = xpi
        newXPI.attrValue = $(intVal * 25)
        out_stream.write($newXPI)
        continue
      except ValueError:
        discard

    out_stream.write($xpi)

proc multiply_numeric_attrs*(in_file: string, out_file: string) =
  var in_stream = newFileStream(in_file, fmRead)
  if in_stream == nil:
    raise newException(IOError, "cannot read the file " & in_file)

  var out_stream = newFileStream(out_file, fmWrite)
  if out_stream == nil:
    raise newException(IOError, "cannot write to file " & out_file)

  multiply_numeric_attrs(in_stream, out_stream)

when isMainModule:
  if paramCount() < 2:
    quit("Usage: change_attributes input_filename output_filename")

  let
    in_file = paramStr(1)
    out_file = paramStr(2)

  echo "Processing input file ", in_file, " into ", out_file
  multiply_numeric_attrs(in_file, out_file)

