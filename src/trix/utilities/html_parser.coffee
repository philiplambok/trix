{findClosestElementFromNode, walkTree, tagName, makeElement, elementContainsNode} = Trix.DOM
{arraysAreEqual} = Trix.Helpers

class Trix.HTMLParser
  allowedAttributes = "style href src width height class".split(" ")

  @parse: (html, options) ->
    parser = new this html, options
    parser.parse()
    parser

  constructor: (@html) ->
    @blocks = []
    @blockElements = []
    @processedElements = []

  parse: ->
    try
      @createHiddenContainer()
      @container.innerHTML = sanitizeHTML(@html)
      walker = walkTree(@container)
      @processNode(walker.currentNode) while walker.nextNode()
      @translateBlockElementMarginsToNewlines()
    finally
      @removeHiddenContainer()

  createHiddenContainer: ->
    @container = makeElement(tagName: "div", style: { display: "none" })
    document.body.appendChild(@container)

  removeHiddenContainer: ->
    document.body.removeChild(@container)

  processNode: (node) ->
    switch node.nodeType
      when Node.TEXT_NODE
        @processTextNode(node)
      when Node.ELEMENT_NODE
        @appendBlockForElement(node)
        @processElement(node)

  appendBlockForElement: (element) ->
    if @isBlockElement(element) and not @isBlockElement(element.firstChild)
      attributes = getBlockAttributes(element)
      unless elementContainsNode(@currentBlockElement, element) and arraysAreEqual(attributes, @currentBlock.getAttributes())
        @currentBlock = @appendBlockForAttributes(attributes, element)
        @currentBlockElement = element

  isBlockElement: (element) ->
    return unless element?.nodeType is Node.ELEMENT_NODE
    tagName(element) in @getBlockTagNames() or window.getComputedStyle(element).display is "block"

  getBlockTagNames: ->
    @blockTagNames ?= (value.tagName for key, value of Trix.config.blockAttributes)

  processTextNode: (node) ->
    unless node.textContent is Trix.ZERO_WIDTH_SPACE
      @appendStringWithAttributes(node.textContent, getTextAttributes(node.parentNode))

  processElement: (element) ->
    switch tagName(element)
      when "br"
        unless isExtraBR(element)
          @appendStringWithAttributes("\n", getTextAttributes(element))
        @processedElements.push(element)
      when "figure"
        if element.classList.contains("attachment")
          attributes = getAttachmentAttributes(element)
          if Object.keys(attributes).length
            textAttributes = getTextAttributes(element)
            if image = element.querySelector("img")
              textAttributes.width = image.width if image.width?
              textAttributes.height = image.height if image.height?
            @appendAttachmentForAttributes(attributes, textAttributes)
            # We have everything we need so avoid processing inner nodes
            element.innerHTML = ""
          @processedElements.push(element)
      when "img"
        attributes = url: element.src, contentType: "image"
        textAttributes = getTextAttributes(element)
        textAttributes.width = element.width if element.width?
        textAttributes.height = element.height if element.height?
        @appendAttachmentForAttributes(attributes, textAttributes)
        @processedElements.push(element)

  appendBlockForAttributes: (attributes, element) ->
    @text = new Trix.Text
    block = new Trix.Block @text, attributes
    @blocks.push(block)
    @blockElements.push(element)
    block

  appendStringWithAttributes: (string, attributes) ->
    text = Trix.Text.textForStringWithAttributes(string, attributes)
    @appendText(text)

  appendAttachmentForAttributes: (attributes, textAttributes) ->
    attachment = new Trix.Attachment attributes
    text = Trix.Text.textForAttachmentWithAttributes(attachment, textAttributes)
    @appendText(text)

  appendText: (text) ->
    if @blocks.length is 0
      @appendBlockForAttributes({})

    @text = @text.appendText(text)
    index = @blocks.length - 1
    @replaceTextForBlockAtIndex(@text, index)

  replaceTextForBlockAtIndex: (text, index) ->
    block = @blocks[index]
    @blocks[index] = block.copyWithText(text)

  getMarginOfBlockElementAtIndex: (index) ->
    if element = @blockElements[index]
      unless tagName(element) in @getBlockTagNames() or element in @processedElements
        getBlockElementMargin(element)

  getMarginOfDefaultBlockElement: ->
    element = makeElement(Trix.config.blockAttributes.default.tagName)
    @container.appendChild(element)
    getBlockElementMargin(element)

  translateBlockElementMarginsToNewlines: ->
    defaultMargin = @getMarginOfDefaultBlockElement()
    textForNewline = Trix.Text.textForStringWithAttributes("\n")

    for block, index in @blocks when margin = @getMarginOfBlockElementAtIndex(index)
      text = block.getTextWithoutBlockBreak()

      if margin.top > defaultMargin.top * 2
        newText = text.insertTextAtPosition(textForNewline, 0)
        @replaceTextForBlockAtIndex(newText, index)

      if margin.bottom > defaultMargin.bottom * 2
        newText = text.appendText(textForNewline)
        @replaceTextForBlockAtIndex(newText, index)

  getDocument: ->
    new Trix.Document @blocks

  getTextAttributes = (element) ->
    attributes = {}
    for attribute, config of Trix.config.textAttributes
      if config.parser
        if value = config.parser(element)
          attributes[attribute] = value
      else if config.tagName
        if tagName(element) is config.tagName
          attributes[attribute] = true
    attributes

  getBlockAttributes = (element) ->
    attributes = []
    while element
      for attribute, config of Trix.config.blockAttributes when config.parse isnt false
        if tagName(element) is config.tagName
          if config.test?(element) or not config.test
            attributes.push(attribute)
            attributes.push(config.parentAttribute) if config.parentAttribute
      element = element.parentNode
    attributes.reverse()

  getAttachmentAttributes = (element) ->
    JSON.parse(element.dataset.trixAttachment)

  sanitizeHTML = (html) ->
    {body} = document.implementation.createHTMLDocument("")
    body.innerHTML = html

    commentNodes = []
    walker = walkTree(body)

    while walker.nextNode()
      node = walker.currentNode
      switch node.nodeType
        when Node.ELEMENT_NODE
          element = node
          for {name} in [element.attributes...]
            unless name in allowedAttributes or name.indexOf("data-trix") is 0
              element.removeAttribute(name)
        when Node.COMMENT_NODE
          commentNodes.push(node)

    for node in commentNodes
      node.parentNode.removeChild(node)

    body.innerHTML

  isExtraBR = (element) ->
    previousSibling = element.previousElementSibling
    tagName(element) is "br" and
      (not previousSibling? or tagName(element) is tagName(previousSibling)) and
      element is element.parentNode.lastChild and
      window.getComputedStyle(element.parentNode).display is "block"

  getBlockElementMargin = (element) ->
    style = window.getComputedStyle(element)
    if style.display is "block"
      top: parseInt(style.marginTop), bottom: parseInt(style.marginBottom)
