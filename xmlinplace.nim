## This module is to allow for updating XML in place, but without
## the normalization that the `parsexml module <https://nim-lang.org/docs/parsexml.html>`_
## normally performs.
## 
## This includes things like trimming whitespace, quoting attributes,
## converting line feeds, etc.
## 

import options, parsexml, streams, strutils, xmlparser
import priv/parse_utils, priv/output, priv/types, priv/parsexml_updates

export parse_utils, output, XmlEventKind

template suppressElementEnd() =
  ## For empty element tags, we want to suppress the follow on
  ## `xmlElementEnd` event that will happen after we see either
  ## the `xmlElementStart` or `xmlElementClose` events
  if ctx.parser.isEmptyElementTag():
    ctx.suppressNextElementEnd = true

proc substrContaining(s: string, chars: set[char], start: Natural = 0, last = 0) : string =
  ## Extracts the longest substring possible from `s[start, last]`
  ## where all of the characters are within `chars`
  let last = if last == 0: s.high else: last

  result = ""
  for i in int(start)..last:
    if s[i] notin chars:
      break
    result.add(s[i])

# The set of options that we use by default to have XmlParser report
# maximal data back to us.
const defaultParseOptions* = {reportComments, reportWhitespace,
                              allowUnquotedAttribs, allowEmptyAttribs}

proc open*(ctx: var XmlParseContext, input: Stream, filename = "",
           options: set[XmlParseOption] = defaultParseOptions, 
           expectDepth = 10) =
  ## Opens the parsing of the input stream and sets up the initial
  ## context values for tracking the parsing activity
  ctx.prevPosition = Position(line: 1, column: 1, pos: 0)
  ctx.currPosition = Position(line: 1, column: 1, pos: 0)
  ctx.tagStack = newSeqOfCap[string](expectDepth)
  ctx.errors = @[]
  open(ctx.parser, input, filename, options)

proc close*(ctx: var XmlParseContext) {.inline.} =
  ## Closes the parser. Call this when finished with parsing.
  ctx.parser.close()

proc kind*(ctx: var XmlParseContext): XmlEventKind {.inline.} =
  ## returns the current event type
  if isSome(ctx.generatedPI):
    return ctx.generatedPI.get().event

  return ctx.parser.kind()

proc next*(ctx: var XmlParseContext) =

  ctx.prevPosition = ctx.currPosition

  when NEEDS_INIT_PI_CHECK:
    if isSome(ctx.generatedPI):
      ctx.generatedPI = none(XmlParseItem)

    # See comments in parse_utils.nim about initial processing instruction
    if not ctx.checkedInitialPI:
      ctx.checkedInitialPI = true
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
        ctx.generatedPI = some(xpi)
        ctx.currPosition = piPosition
        return

  # We may have had an empty element where we want to suppress
  # the follow on `xmlElementEnd` event before we move on
  if ctx.suppressNextElementEnd:
    ctx.suppressNextElementEnd = false
    ctx.parser.next()
    assert(ctx.parser.kind == xmlElementEnd)

  # Clean up any remaining state from previous element ends
  if ctx.parser.kind == xmlElementEnd:
    discard ctx.tagStack.pop()

  ctx.parser.next()

  ctx.currPosition = ctx.parser.getPosition()

  case ctx.parser.kind
  of xmlElementOpen:
    ctx.tagStack.add(ctx.parser.elementName)
  of xmlElementStart:
    ctx.tagStack.add(ctx.parser.elementName)
    suppressElementEnd()
  of xmlElementClose:
    suppressElementEnd()
  of xmlElementEnd, xmlAttribute, xmlCharData, xmlWhitespace,
     xmlSpecial, xmlCData, xmlComment, xmlPI, xmlEntity:
    # No state tracking needed for these event types
    discard
  of xmlEof:
    discard
  of xmlError:
    ctx.errors.add(ctx.parser.errorMsg())

proc item*(ctx: var XmlParseContext) : XmlParseItem =
  if isSome(ctx.generatedPI):
    return ctx.generatedPI.get()

  case ctx.parser.kind()
  of xmlElementOpen:
    result = XmlParseItem(
      event: xmlElementOpen,
      openWhitespace: ctx.parser.getWhitespace(ctx.parser.bufPos - 1),
      elementName: ctx.parser.elementName,
      start: ctx.prevPosition,
      finish: ctx.currPosition
      )
  of xmlElementStart:
    result = XmlParseItem(
      event: xmlElementStart,
      startWhitespace: ctx.parser.getWhitespace(ctx.parser.bufPos - 3),
      elementName: ctx.parser.elementName,
      isEmptyStart: ctx.parser.isEmptyElementTag(),
      start: ctx.prevPosition,
      finish: ctx.currPosition
      )
  of xmlElementClose:
    result = XmlParseItem(
      event: xmlElementClose,
      elementName: ctx.tagStack[ctx.tagStack.len-1],
      isEmptyClose: ctx.parser.isEmptyElementTag(),
      start: ctx.prevPosition,
      finish: ctx.currPosition
      )
  of xmlElementEnd:
    result = XmlParseItem(
      event: xmlElementEnd,
      elementName: ctx.tagStack[ctx.tagStack.len-1],
      start: ctx.prevPosition,
      finish: ctx.currPosition
      )
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

    var xpi = XmlParseItem(
      event: xmlAttribute,
      attrName: ctx.parser.attrKey,
      elementName: ctx.tagStack[ctx.tagStack.len-1],
      equalsSign: equalsSign,
      isQuoted: ctx.parser.buf[startQuotePos] in quoteChars,
      start: ctx.prevPosition,
      finish: ctx.currPosition
      )

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

    result = xpi
  of xmlCharData:
    result = XmlParseItem(
      event: xmlCharData,
      charData: ctx.parser.charData,
      start: ctx.prevPosition,
      finish: ctx.currPosition
      )
  of xmlWhitespace:
    let
      lenInBuffer = ctx.currPosition.pos - ctx.prevPosition.pos
      wasModified = lenInBuffer != ctx.parser.charData.len()
      whitespace =  if wasModified:
                      ctx.parser.charData.replace('\L', '\c')
                    else:
                      ctx.parser.charData
    result = XmlParseItem(
      event: xmlWhitespace,
      whitespace: whitespace,
      start: ctx.prevPosition,
      finish: ctx.currPosition
      )
  of xmlSpecial:
    result = XmlParseItem(
      event: xmlSpecial,
      charData: ctx.parser.charData,
      start: ctx.prevPosition,
      finish: ctx.currPosition
      )
  of xmlCData:
    result = XmlParseItem(
      event: xmlCData,
      charData: ctx.parser.charData,
      start: ctx.prevPosition,
      finish: ctx.currPosition
      )
  of xmlComment:
    result = XmlParseItem(
      event: xmlComment,
      comment: ctx.parser.charData,
      start: ctx.prevPosition,
      finish: ctx.currPosition
      )
  of xmlPI:
    result = XmlParseItem(
      event: xmlPI,
      piName: ctx.parser.piName,
      piRest: ctx.parser.piRest,
      start: ctx.prevPosition,
      finish: ctx.currPosition
      )
  of xmlEntity:
    result = XmlParseItem(
      event: xmlEntity,
      entityName: ctx.parser.entityName,
      start: ctx.prevPosition,
      finish: ctx.currPosition
      )
  of xmlEof:
    raise newException(EofError, "Already at end of XML")
  of xmlError:
    var e: ref XmlError
    new(e)
    e.msg = ctx.errors[0]
    e.errors = ctx.errors
    raise e

iterator processxml*(s: Stream,
                     ctx: var XmlParseContext,
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
  ctx.open(s, filename = "")

  while true:
    ctx.next()
    case ctx.kind():
    of xmlEof:
      break
    else:
      yield ctx.item()

  ctx.close()

iterator processxml*(f: File,
                     ctx: var XmlParseContext,
                     filename="") : XmlParseItem =
  var in_stream = newFileStream(f)
  for i in processxml(in_stream, ctx, filename=filename):
    yield i

iterator processxml*(filename: string,
                     ctx: var XmlParseContext) : XmlParseItem =
  var in_stream = newFileStream(filename)
  if in_stream == nil:
    raise newException(IOError, "cannot read the file " & filename)

  for i in processxml(in_stream, ctx, filename=filename):
    yield i
