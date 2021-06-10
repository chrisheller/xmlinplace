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

  for xpi in processxml(in_stream, ctx):
    case xpi.event:
    of xmlElementOpen, xmlElementStart:
      if xpi.elementName == "child2":
        if xpi.event == xmlElementStart and xpi.isEmptyStart:
          continue    # <child2 />

        while true:   # have to check for attrs/child elements
          ctx.next()
          if ctx.kind() in {xmlElementEnd, xmlElementClose}:
            let child_xpi = ctx.item()
            if ctx.kind() == xmlElementClose and not child_xpi.isEmptyClose:
              continue  # was just closing > of opening of element
            if child_xpi.elementName == "child2":
              break

        continue
    else:
      discard

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
    let d = newDiff(verify_xml.split('\n'),
                    output_xml.split('\n'))
    echo d.outputUnixDiffStr()
    raise newException(Exception, "Did not match")
