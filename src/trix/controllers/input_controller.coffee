#= require trix/observers/device_observer

{defer} = Trix.Helpers
{handleEvent, findClosestElementFromNode, findElementForContainerAtOffset} = Trix.DOM

class Trix.InputController
  pastedFileCount = 0

  @keyNames:
    "8":  "backspace"
    "9":  "tab"
    "13": "return"
    "37": "left"
    "39": "right"
    "68": "d"
    "72": "h"
    "79": "o"

  constructor: (@element) ->
    @deviceObserver = new Trix.DeviceObserver @element
    @deviceObserver.delegate = this

    for eventName of @events
      handleEvent eventName, onElement: @element, withCallback: @handlerFor(eventName), inPhase: "capturing"

  handlerFor: (eventName) ->
    (event) =>
      try
        @events[eventName].call(this, event)
      catch error
        @delegate?.inputControllerDidThrowError?(error, {eventName})
        throw error

  # Device observer delegate

  deviceDidActivateVirtualKeyboard: ->
    @enableMobileInputMode()

  deviceDidDeactivateVirtualKeyboard: ->
    @disableMobileInputMode()

  # Mobile input mode

  enableMobileInputMode: ->
    @mobileInputMode = true

  disableMobileInputMode: ->
    delete @mobileInputMode

  isMobileInputModeEnabled: ->
    @mobileInputMode is true

  # Input handlers

  events:
    keydown: (event) ->
      if keyName = @constructor.keyNames[event.keyCode]
        context = @keys
        for modifier in ["ctrl", "alt", "shift"] when event["#{modifier}Key"]
          modifier = "control" if modifier is "ctrl"
          context = @keys[modifier]
        context[keyName]?.call(this, event)

      if event.ctrlKey or event.metaKey
        if character = String.fromCharCode(event.keyCode).toLowerCase()
          keys = (modifier for modifier in ["alt", "shift"] when event["#{modifier}Key"])
          keys.push(character)
          if @delegate?.inputControllerDidReceiveKeyboardCommand(keys)
            event.preventDefault()

    keypress: (event) ->
      return if @isMobileInputModeEnabled()
      return if (event.metaKey or event.ctrlKey) and not event.altKey
      return if keypressEventIsWebInspectorShortcut(event)

      if event.which is null
        character = String.fromCharCode event.keyCode
      else if event.which isnt 0 and event.charCode isnt 0
        character = String.fromCharCode event.charCode

      if character?
        event.preventDefault()
        @delegate?.inputControllerWillPerformTyping()
        @responder?.insertString(character)

    dragenter: (event) ->
      event.preventDefault()

    dragstart: (event) ->
      target = event.target
      @draggedRange = @responder?.getLocationRange()

    dragover: (event) ->
      if @draggedRange or "Files" in event.dataTransfer?.types
        event.preventDefault()

    dragend: (event) ->
      delete @draggedRange

    drop: (event) ->
      event.preventDefault()
      point = [event.clientX, event.clientY]
      @responder?.setLocationRangeFromPoint(point)

      if @draggedRange
        @delegate?.inputControllerWillMoveText()
        @responder?.moveTextFromLocationRange(@draggedRange)
        delete @draggedRange

      else if files = event.dataTransfer.files
        @delegate?.inputControllerWillAttachFiles()
        for file in files
          if @responder?.insertFile(file)
            file.trixInserted = true

    cut: (event) ->
      @delegate?.inputControllerWillCutText()
      defer => @responder?.deleteBackward()

    paste: (event) ->
      paste = event.clipboardData ? event.testClipboardData
      return if "com.apple.webarchive" in paste.types
      event.preventDefault()

      if html = paste.getData("text/html")
        @delegate?.inputControllerWillPasteText()
        @responder?.insertHTML(html)
      else if string = paste.getData("text/plain")
        @delegate?.inputControllerWillPasteText()
        @responder?.insertString(string)

      if "Files" in paste.types
        if file = paste.items?[0]?.getAsFile?()
          if not file.name and extension = extensionForFile(file)
            file.name = "pasted-file-#{++pastedFileCount}.#{extension}"
          @delegate?.inputControllerWillAttachFiles()
          if @responder?.insertFile(file)
            file.trixInserted = true

    compositionstart: (event) ->
      @delegate?.inputControllerWillStartComposition?()
      @composing = true

    compositionend: (event) ->
      @delegate?.inputControllerWillEndComposition?()
      @composedString = event.data

    input: (event) ->
      if @composing and @composedString?
        @delegate?.inputControllerDidComposeCharacters?(@composedString) if @composedString
        delete @composedString
        delete @composing

  keys:
    backspace: (event) ->
      event.preventDefault()
      @delegate?.inputControllerWillPerformTyping()
      @responder?.deleteBackward()

    return: (event) ->
      event.preventDefault()
      @delegate?.inputControllerWillPerformTyping()
      @responder?.insertLineBreak()

    tab: (event) ->
      if @responder?.canChangeBlockAttributeLevel()
        @responder?.increaseBlockAttributeLevel()
        event.preventDefault()

    left: (event) ->
      if @selectionIsInCursorTarget()
        event.preventDefault()
        @responder?.adjustPositionInDirection("backward")

    right: (event) ->
      if @selectionIsInCursorTarget()
        event.preventDefault()
        @responder?.adjustPositionInDirection("forward")

    control:
      d: (event) ->
        event.preventDefault()
        @delegate?.inputControllerWillPerformTyping()
        @responder?.deleteForward()

      h: (event) ->
        @delegate?.inputControllerWillPerformTyping()
        @backspace(event)

      o: (event) ->
        event.preventDefault()
        @delegate?.inputControllerWillPerformTyping()
        @responder?.insertString("\n", updatePosition: false)

    alt:
      backspace: (event) ->
        event.preventDefault()
        @delegate?.inputControllerWillPerformTyping()
        @responder?.deleteWordBackward()

    shift:
      return: (event) ->
        event.preventDefault()
        @delegate?.inputControllerWillPerformTyping()
        @responder?.insertString("\n")

      left: (event) ->
        if @selectionIsInCursorTarget()
          event.preventDefault()
          @responder?.expandLocationRangeInDirection("backward")

      right: (event) ->
        if @selectionIsInCursorTarget()
          event.preventDefault()
          @responder?.expandLocationRangeInDirection("forward")

  selectionIsInCursorTarget: ->
    @responder?.selectionIsInCursorTarget()

  extensionForFile = (file) ->
    file.type?.match(/\/(\w+)$/)?[1]

keypressEventIsWebInspectorShortcut = (event) ->
  event.metaKey and event.altKey and not event.shiftKey and event.keyCode is 94
