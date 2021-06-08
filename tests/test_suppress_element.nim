import ../xmlinplace
import diff, diffoutput, os, streams, strutils

proc suppress_element*(in_xml: string) : string =
  ## Runs the ``in_xml`` through the ``processxml`` iterator
  ## and outputs XML with `child2` elements removed
  ## This does not take nested elements with the same name
  ## into consideration to keep the example straightforward
  
  var
    ctx = initXmlParseContext()
    in_stream = newStringStream(in_xml)
    out_stream = newStringStream()

    in_elem = false

  for xpi in processxml(in_stream, ctx):
    case xpi.event:
    of xmlElementOpen, xmlElementStart:
      if in_elem:                       # nested element
        continue
      elif xpi.elementName == "child2":
        let is_empty = xpi.event == xmlElementStart and xpi.isEmptyStart
        if not is_empty:    # we don't have to watch for attrs/children
          in_elem = true    # if it is an empty start element
        continue
    of xmlElementClose, xmlElementEnd:
      if in_elem:
        if xpi.elementName == "child2":
          if xpi.event == xmlElementEnd:
            in_elem = false
          elif xpi.isEmptyClose:
            in_elem = false
        continue
    else:
      if in_elem:
        continue

    out_stream.write($xpi)

  out_stream.setPosition(0)
  result = out_stream.readAll()

when isMainModule:
  let
    projectDir = currentSourcePath.parentDir.parentDir
    examplesDir = joinPath(projectDir, "examples")
    in_filename = joinPath(examplesDir, "example4.xml")
    verify_filename = joinPath(examplesDir, "example4_without_child2.xml")

  echo "Processing XML file: ", in_filename
  let
    input_xml = in_filename.readFile()
    output_xml = suppress_element(input_xml)
    verify_xml = verify_filename.readFile()

  if output_xml != verify_xml:
    let d = newDiff(output_xml.split('\n'),
                    verify_xml.split('\n'))
    echo d.outputUnixDiffStr()
    raise newException(Exception, "Did not match")
