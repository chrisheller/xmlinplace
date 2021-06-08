import parsexml
import ./types

proc getPosition*(x: XmlParser) : Position =
  ## Returns a `Position` object based on the current state
  ## of the `XmlParser`. This copies the data so that further
  ## changes to the `XmlParser` state will not affect this
  ## 
  
  # Position objects have columns as 1-based, while XmlParser
  # has them as 0-based so we adjust that here
  result = Position(line: x.getLine(),
                    column: x.getColumn()+1,
                    pos: x.bufPos)

type
  TagStack* = seq[string]

  XmlParseCtxRef* = ref XmlParseContext
  XmlParseContext* = object
    ## `XmlParseContext` holds the `XmlParser` object and some
    ## additional parsing context.
    ## 
    prevPosition* : Position
    currPosition* : Position
    tagStack* : TagStack
    parser* : XmlParser

proc initXmlParseContext*(expectDepth=10) : XmlParseCtxRef =
  ## Initializes an `XmlParseCtxRef` value with the expected
  ## parse depth, which defaults to 10. If the actual parsed
  ## depth exceeds this value, no errors will result; the
  ## internal data structure will be re-sized automatically.
  ## 
  result = XmlParseCtxRef(
    prevPosition : Position(line: 1, column: 1, pos: 0),
    currPosition : Position(line: 1, column: 1, pos: 0),
    tagStack : newSeqOfCap[string](expectDepth),
  )

proc depth*(ctx: XmlParseCtxRef) : Natural =
  ## Returns the depth of how many "tags" we are into parsing
  ## 
  ## This will increase by 1 for each `xmlElementOpen` and
  ## `xmlElementStart` event and decrease by 1 for each 
  ## 'xmlElementClose' and `xmlElementEnd` event.
  result = ctx.tagStack.len()

proc tag*(ctx: XmlParseCtxRef, depth: int) : string =
  ## Returns the tag name for the given 0-based depth
  ## 
  ## e.g.  ctx.tag(0) returns the top-most tag being processed
  ##       ctx.tag(1) return the parent tag being processed
  result = ctx.tagStack[depth]

proc elementName*(ctx: XmlParseCtxRef) : string =
  ## Returns the tag name of the current element being processed.
  result = ctx.tag(ctx.depth()-1)

proc parentName*(ctx: XmlParseCtxRef) : string =
  ## Returns the tag name of the parent of the current element
  ## being processed.
  result = ctx.tag(ctx.depth()-2)

proc grandParentName*(ctx: XmlParseCtxRef) : string =
  ## Returns the tag name of the grandparent of the current element
  ## being processed.
  result = ctx.tag(ctx.depth()-3)

proc hasParent*(ctx: XmlParseCtxRef, name: string) : bool =
  ## Returns `true` if `name` is somewhere in the list of
  ## elements being processed, `false` otherwise.
  ## 
  ## This is a case sensitive check.
  result = ctx.tagStack.contains(name)

proc isName*(xpi: XmlParseItem, name: string) : bool {.inline.} =
  result = xpi.elementName == name

proc isNameAttr*(xpi: XmlParseItem, name, attr: string) : bool {.inline.} =
  result = xpi.event == xmlAttribute and xpi.isName(name) and xpi.attrName == attr

proc isNameAttrValue*(xpi: XmlParseItem, name, attr, val: string) : bool {.inline.} =
  result = xpi.isNameAttr(name, attr) and xpi.attrValue == val

const NEEDS_INIT_PI_CHECK* = true
when NEEDS_INIT_PI_CHECK:
  ## The parsexml module  will drop the initial processing instruction
  ## in its streaming parsing, so we add it back in if it was dropped.
  ## 
  ## XML "in the wild" may not have the initial processing instruction
  ## though, so we don't require it to be present though.
  const
    piStart* = "<?"
    piEnd* = "?>"
    initPiName* = "xml"
    initPiCheck* = piStart & initPiName


# --- Helpers for modifying the parse stream

const initialPosition = Position(line: 1, column: 1, pos: 0)

proc makeOpen*(name: string, whitespace=" ") : XmlParseItem =
  ## Creates a new `XmlParseItem` for the `xmlElementOpen` event
  ## for the given element name.
  ## Defaults to using a single whitespace character immediately
  ## after the name.
  result = XmlParseItem(
    event: xmlElementOpen,
    elementName: name,
    openWhitespace: whitespace,
    start : initialPosition,
    finish : initialPosition,
  )

proc makeClose*(name: string, isEmpty=false) : XmlParseItem =
  result = XmlParseItem(
    event: xmlElementClose,
    elementName: name,
    isEmptyClose : isEmpty,
    start : initialPosition,
    finish : initialPosition,
  )

proc makeAttribute*(name: string, value: string) : XmlParseItem =
  result = XmlParseItem(
    event: xmlAttribute,
    attrName: name,
    equalsSign: "=",
    attrValue: value,
    isQuoted: true,
    quoteChar: '"',
    start : initialPosition,
    finish : initialPosition,
  )

proc makeWhitespace*(whitespace = " ") : XmlParseItem =
  result = XmlParseItem(
    event: xmlWhitespace,
    whitespace : whitespace,
    start : initialPosition,
    finish : initialPosition,
  )
