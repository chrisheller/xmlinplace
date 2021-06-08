import ./xmltree_updates
import ./types

proc attrToString(xpi: XmlParseItem) : string =
  assert(xpi.event == xmlAttribute)
  let
    estAttrValSize = xpi.attrValue.countAttrsToEscape() * AttrExpandSize
    estSize = xpi.attrName.len() +
              xpi.equalsSign.len() +
              xpi.attrValue.len() +
              estAttrValSize +
              (if xpi.isQuoted: 2 else: 0)
  result = newStringOfCap(estSize)
  result.add(xpi.attrName)
  result.add(xpi.equalsSign)
  if xpi.isQuoted:
    result.add(xpi.quoteChar)

  result.add(escapeAttr(xpi.attrValue))

  if xpi.isQuoted:
    result.add(xpi.quoteChar)
  result.add(xpi.attrWhitespace)

proc `$`*(xpi: XmlParseItem) : string =
  ## Creates the string representation of an ``XmlParseItem``
  ## This is intended for producing XML and does not output
  ## any debugging information that the ``xpi`` might contain
  ## (such as line, column, etc)
  case xpi.event:
  of xmlElementOpen:
    result = "<" & xpi.elementName & xpi.openWhitespace
  of xmlElementStart:
    let close = if xpi.isEmptyStart: "/>" else: ">"
    result = "<" & xpi.elementName & xpi.startWhitespace & close
  of xmlElementClose:
    result = if xpi.isEmptyClose: "/>" else: ">"
  of xmlElementEnd:
    result = "</" & xpi.elementName & ">"
  of xmlAttribute:
    result = xpi.attrToString()
  of xmlCharData:
    result = xpi.charData
  of xmlCData:
    result = "<![CDATA[" & xpi.charData & "]]>"
  of xmlWhitespace:
    result = xpi.whitespace
  of xmlComment:
    result = "<!--" & xpi.comment & "-->"
  of xmlPI:
    result = "<?" & xpi.piName & xpi.piRest & "?>"
  of xmlEntity:
    result = "&" & xpi.entityName & ";"
  of xmlSpecial:
    result = "<!" & xpi.charData & ">"
  of xmlError, xmlEof:
    discard
