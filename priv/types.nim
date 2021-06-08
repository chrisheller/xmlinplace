import parsexml

export parsexml.XmlEventKind

type
  XmlParseItem* = object
    ## `XmlParseItem` wraps XmlEventKind with additional context data,
    ## such as the current start and finish position of the event, and
    ## any additional data that is useful for reconstructing the
    ## exact XML on the other side of the iteration.
    elementName* : string
    start* : Position
      ## Starting position of the `XmlParseItem`
    finish* : Position
      ## Ending position of the `XmlParseItem`
    case event*: XmlEventKind
    of xmlElementOpen:
      openWhitespace* : string   ## typically a single space, but can be more
    of xmlElementStart:
      isEmptyStart* : bool       ## e.g. <tagname />
      startWhitespace* : string  ## typically empty or a single space, but can be more
    of xmlElementClose:
      isEmptyClose* : bool       ## e.g. <tagname attr="val" />
    of xmlAttribute:
      attrWhitespace* : string   ## typically one leading space
      attrName* : string
      equalsSign* : string       ## typically just one character '='
      attrValue* : string
      isQuoted* : bool           ## typically true for quoted values
      quoteChar* : char          ## typically '"'.  Only meaningful if isQuoted is true
    of xmlCharData, xmlCData, xmlSpecial:
      charData* : string
    of xmlWhitespace:
      whitespace* : string
    of xmlComment:
      comment* : string
    of xmlEntity:
      entityName*: string
    of xmlPI:
      piName* : string
      piRest* : string
    of xmlError, xmlEof, xmlElementEnd:
      discard

  Position* = object
    ## `Position` represents a location in the XML data.
    line* : Positive
      ## Lines are 1-based
    column* : Positive
      ## Columns are also 1-based
    pos* : Natural
      ## The 0-based offset from the beginning of the XML data

