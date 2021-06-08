import ../xmlinplace
import diff, diffoutput, os, streams, strutils

proc multiply_numeric_attrs*(in_xml: string, mult_by: int) : string =
  ## Runs the ``in_xml`` through the ``processxml`` iterator
  ## and returns XML with any integer attribute values
  ## multiplied by the specified value
  
  var
    ctx = initXmlParseContext()
    in_stream = newStringStream(in_xml)
    out_stream = newStringStream()

  for xpi in processxml(in_stream, ctx):
    case xpi.event:
    of xmlAttribute:
      try:
        let intVal = parseInt(xpi.attrValue)
        var newXPI = xpi
        newXPI.attrValue = $(intVal * mult_by)
        out_stream.write($newXPI)
        continue
      except ValueError:
        discard
    of xmlComment:
      # Update the comment to match the expected file.
      var newXPI = xpi
      newXPI.comment &= "and attributes multiplied by " & $mult_by & " "
      out_stream.write($newXPI)
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
    in_filename = joinPath(examplesDir, "example3.xml")
    verify_filename = joinPath(examplesDir, "example3_changed_attributes.xml")

  echo "Processing XML file: ", in_filename
  let
    input_xml = in_filename.readFile()
    output_xml = multiply_numeric_attrs(input_xml, 25)
    verify_xml = verify_filename.readFile()

  if output_xml != verify_xml:
    let d = newDiff(output_xml.split('\n'),
                    verify_xml.split('\n'))
    echo d.outputUnixDiffStr()
    raise newException(Exception, "Did not match")
