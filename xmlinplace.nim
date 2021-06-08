## This module is to allow for updating XML in place, but without
## the normalization that the `parsexml module <https://nim-lang.org/docs/parsexml.html>`_
## normally performs.
## 
## This includes things like trimming whitespace, quoting attributes,
## converting line feeds, etc.
## 

import os, parsexml, streams, strutils
import priv/parse_utils, priv/output, priv/types, priv/parsexml_updates

export parse_utils, output, XmlEventKind

template skipElementEnd() =
  ## For empty element tags, we want to suppress the follow on
  ## `xmlElementEnd` event that will happen after we see either
  ## the `xmlElementStart` or `xmlElementClose` events
  if isEmpty:
    ctx.parser.next()
    assert(ctx.parser.kind == xmlElementEnd)
    discard ctx.tagStack.pop()

proc substrContaining(s: string, chars: set[char], start: Natural = 0, last = 0) : string =
  ## Extracts the longest substring possible from `s[start, last]`
  ## where all of the characters are within `chars`
  let last = if last == 0: s.high else: last

  result = ""
  for i in int(start)..last:
    if s[i] notin chars:
      break
    result.add(s[i])

iterator processxml*(s: Stream,
                     ctx: XmlParseCtxRef,
                     filename="") : XmlParseItem =
  ## The `processxml` iterator will yield a series of `XmlParseItem <priv/types.html#XmlParseItem>`_ objects
  ## from the parsing process.
  ## 
  ## Printing the `$`-stringified form of these will give the exact XML
  ## (including whitespace and comments) that was fed into the parser.
  ## 
  ## Callers can examine/modify these before they are re-assembled into an
  ## XML document again. This can include dropping items, adding new ones, etc
  ## 
  ## Modifying items is safe to do; escaping, etc. will be handled 
  ## automatically. When adding or dropping items from this iterator's
  ## output, callers need to take care to not generate invalid XML
  ## though.

  when NEEDS_INIT_PI_CHECK:
    # See comments in parse_utils.nim about initial processing instruction
    var checkedInitialPI = false

  let options: set[XmlParseOption] = {reportComments, reportWhitespace,
                                      allowUnquotedAttribs, allowEmptyAttribs}
  open(ctx.parser, s, filename, options)
  while true:
    ctx.parser.next()

    ctx.currPosition = ctx.parser.getPosition()

    when NEEDS_INIT_PI_CHECK:
      # See comments in parse_utils.nim about initial processing instruction
      if not checkedInitialPI:
        checkedInitialPI = true
        if ctx.parser.kind != xmlPI and ctx.parser.buf.startsWith(initPiCheck):
          # calculate the PI so we can re-issue it
          let
            piRestStart = initPiCheck.len()
            piRestEnd = ctx.parser.buf.find(piEnd, piRestStart, ctx.currPosition.pos)
            piLen = piRestEnd + piEnd.len()
            piPosition = Position(line: 1, column: piLen+1, pos: piLen)
            xpi = XmlParseItem(event: xmlPI,
                               piName: initPiName,
                               piRest: ctx.parser.buf.substr(piRestStart, piRestEnd - 1),
                               start: ctx.prevPosition,
                               finish: piPosition)
          yield xpi
          ctx.prevPosition = piPosition
    
    case ctx.parser.kind
    of xmlElementOpen:
      ctx.tagStack.add(ctx.parser.elementName)
      yield XmlParseItem(event: xmlElementOpen,
                         openWhitespace: ctx.parser.getWhitespace(ctx.parser.bufPos - 1),
                         elementName: ctx.parser.elementName,
                         start: ctx.prevPosition,
                         finish: ctx.currPosition)
    of xmlElementStart:
      ctx.tagStack.add(ctx.parser.elementName)
      let isEmpty = ctx.parser.isEmptyElementTag()
      yield XmlParseItem(event: xmlElementStart,
                         startWhitespace: ctx.parser.getWhitespace(ctx.parser.bufPos - 3),
                         elementName: ctx.parser.elementName,
                         isEmptyStart: isEmpty,
                         start: ctx.prevPosition,
                         finish: ctx.currPosition)
      if isEmpty:
        skipElementEnd()

    of xmlElementClose:
      let isEmpty = ctx.parser.isEmptyElementTag()
      yield XmlParseItem(event: xmlElementClose,
                         elementName: ctx.tagStack[ctx.tagStack.len-1],
                         isEmptyClose: isEmpty,
                         start: ctx.prevPosition,
                         finish: ctx.currPosition)
      if isEmpty:
        skipElementEnd()

    of xmlElementEnd:
      yield XmlParseItem(event: ctx.parser.kind,
                         elementName: ctx.tagStack.pop(),
                         start: ctx.prevPosition,
                         finish: ctx.currPosition)
    of xmlAttribute:
      # We have to handle these whitespace cases:
      # 1) between the key=value part (e.g. key = "value" or key= "value", etc)
      # 2) within the attribute value (if it is a quoted value)
      # 3) any trailing space for the entire attribute

      # For the equals sign, we want to start from right after the attribute name
      # and continue as long as we have whitespace or an equals sign
      const equalsChars = Whitespace + { '=' }
      let
        equalsStart = ctx.prevPosition.pos + ctx.parser.attrKey.len()
        equalsSign = ctx.parser.buf.substrContaining(equalsChars, start=equalsStart)
        # TODO - on a completely empty attribute that just has the attr name
        # and no equals sign, we end up adding an extra space somehow
        # Does that mean that if we don't have an equals sign in here, we 
        # should just set the length to 0?
        equalsFinish = (equalsStart + equalsSign.len()) - 1

      # We can only have leading/trailing whitespace or embedded CR/LF, etc.
      # in the attribute value if the value is quoted
      const quoteChars = { '"', '\'' }
      let startQuotePos = equalsFinish + 1

      var xpi = XmlParseItem(event: xmlAttribute,
                             attrName: ctx.parser.attrKey,
                             elementName: ctx.tagStack[ctx.tagStack.len-1],
                             equalsSign: equalsSign,
                             isQuoted: ctx.parser.buf[startQuotePos] in quoteChars,
                             start: ctx.prevPosition,
                             finish: ctx.currPosition)

      if xpi.isQuoted:
        xpi.quoteChar = ctx.parser.buf[startQuotePos]
        let
          endQuotePos = ctx.parser.buf.find(xpi.quoteChar, startQuotePos+1, ctx.currPosition.pos)
          encodedValue = ctx.parser.buf.substr(startQuotePos+1, endQuotePos-1)
        xpi.attrValue = parseAttrValue(encodedValue)
      else:
        xpi.attrValue = ctx.parser.attrValue

      # Lastly, deal with any whitespace that may be at the end of the attribute
      xpi.attrWhitespace = ctx.parser.getWhitespace(ctx.parser.bufPos - 1)

      yield xpi

    of xmlCharData:
      yield XmlParseItem(event: xmlCharData,
                         charData: ctx.parser.charData,
                         start: ctx.prevPosition,
                         finish: ctx.currPosition)
    of xmlWhitespace:
      let
        lenInBuffer = ctx.currPosition.pos - ctx.prevPosition.pos
        wasModified = lenInBuffer != ctx.parser.charData.len()
        whitespace =  if wasModified:
                        ctx.parser.charData.replace('\L', '\c')
                      else:
                        ctx.parser.charData
      yield XmlParseItem(event: xmlWhitespace,
                         whitespace: whitespace,
                         start: ctx.prevPosition,
                         finish: ctx.currPosition)
    of xmlSpecial:
      yield XmlParseItem(event: xmlSpecial,
                         charData: ctx.parser.charData,
                         start: ctx.prevPosition,
                         finish: ctx.currPosition)
    of xmlCData:
      yield XmlParseItem(event: xmlCData,
                         charData: ctx.parser.charData,
                         start: ctx.prevPosition,
                         finish: ctx.currPosition)
    of xmlComment:
      yield XmlParseItem(event: xmlComment,
                         comment: ctx.parser.charData,
                         start: ctx.prevPosition,
                         finish: ctx.currPosition)
    of xmlPI:
      yield XmlParseItem(event: xmlPI,
                         piName: ctx.parser.piName,
                         piRest: ctx.parser.piRest,
                         start: ctx.prevPosition,
                         finish: ctx.currPosition)
    of xmlEntity:
      yield XmlParseItem(event: xmlEntity,
                         entityName: ctx.parser.entityName,
                         start: ctx.prevPosition,
                         finish: ctx.currPosition)
    of xmlEof:
      break # end of file reached
    of xmlError:
      # TODO - how should we handle XML errors here?
      discard

    ctx.prevPosition = ctx.currPosition

  ctx.parser.close()

iterator processxml*(f: File,
                     ctx: XmlParseCtxRef,
                     filename="") : XmlParseItem =
  var in_stream = newFileStream(f)
  for i in processxml(in_stream, ctx, filename=filename):
    yield i

iterator processxml*(filename: string,
                     ctx: XmlParseCtxRef) : XmlParseItem =
  var in_stream = newFileStream(filename)
  if in_stream == nil:
    raise newException(IOError, "cannot read the file " & filename)

  for i in processxml(in_stream, ctx, filename=filename):
    yield i
