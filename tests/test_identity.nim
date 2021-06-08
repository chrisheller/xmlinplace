import ../xmlinplace

import diff, diffoutput, os, streams, strutils

proc process_unchanged*(in_xml: string) : string =
  ## Runs the ``in_xml`` through the ``processxml`` iterator
  ## and returns the generated XML, which should be byte for byte
  ## identical to what was sent in.
  
  var
    ctx = initXmlParseContext()
    in_stream = newStringStream(in_xml)
    out_stream = newStringStream()

  for xpi in processxml(in_stream, ctx):
    out_stream.write($xpi)

  out_stream.setPosition(0)
  result = out_stream.readAll()

when isMainModule:
  var in_filenames : seq[string] = @[]

  if paramCount() == 0:
    echo "No XML filenames supplied, using examples directory"
    let
      projectDir = currentSourcePath.parentDir.parentDir
      examplesDir = joinPath(projectDir, "examples")
    for filename in walkFiles(joinPath(examplesDir, "*.xml")):
      in_filenames.add(filename)
  else:
    for i in 1 .. paramCount():
      let filename = paramStr(i).string.normalizedPath()
      in_filenames.add(filename)

  for filename in in_filenames:
    echo "Processing XML file: ", filename
    let
      input_xml = filename.readFile()
      output_xml = process_unchanged(input_xml)

    if input_xml != output_xml:
      let d = newDiff(input_xml.split('\n'),
                      output_xml.split('\n'))
      echo d.outputUnixDiffStr()
      raise newException(Exception, "Did not match")
