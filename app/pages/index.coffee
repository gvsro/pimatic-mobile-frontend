# index-page
# ----------

$(document).on( "pagebeforecreate", (event) ->
  # Just execute it one time
  if pimatic.pages.index? then return
  ###
    Rule class that are shown in the Rules List
  ###

  class Rule

    @mapping = {
      key: (data) => data.id
      copy: ['id']
    }

    constructor: (data) ->
      ko.mapping.fromJS(data, @constructor.mapping, this)
    update: (data) ->
      ko.mapping.fromJS(data, @constructor.mapping, this)

    afterRender: (elements) ->
      $(elements).find("a").before(
        $('<div class="handle"><div class="ui-btn-icon-notext ui-icon ui-icon-bars ui-alt-icon ui-nodisc-icon"></div></div>')
      )

  # Export the rule class
  pimatic.Rule = Rule

  pimatic.templateClasses = {
    header: pimatic.HeaderItem
    button: pimatic.ButtonItem
    device: pimatic.DeviceItem  
    switch: pimatic.SwitchItem
    dimmer: pimatic.DimmerItem
    temperature: pimatic.TemperatureItem
    presence: pimatic.PresenceItem
  }

  class IndexViewModel
    # static property:
    @mapping = {
      items:
        create: ({data, parent, skip}) =>
          console.log "create"
          itemClass = pimatic.templateClasses[data.template]
          #console.log "creating:", itemClass
          unless itemClass?
            console.warn "Could not find a template class for #{data.template}"
            itemClass = pimatic.Item
          item = new itemClass(data)
          return item
        update: ({data, parent, target}) =>
          target.update(data)
          return target
        key: (data) => data.itemId
      rules:
        create: ({data, parent, skip}) => new pimatic.Rule(data)
        update: ({data, parent, target}) =>
          target.update(data)
          return target
        key: (data) => data.id
    }

    loading: no
    hasData: no
    pageCreated: ko.observable(no)
    items: ko.observableArray([])
    rules: ko.observableArray([])
    errorCount: ko.observable(0)
    enabledEditing: ko.observable(no)
    hasRootCACert: ko.observable(no)
    rememberme: ko.observable(no)

    isSortingItems: ko.observable(no)
    isSortingRules: ko.observable(no)

    constructor: () ->
      @setupStorage()

      @lockButton = ko.computed( => 
        editing = @enabledEditing()
        return {
          icon: (if editing then 'check' else 'gear')
        }
      )

      @itemsListViewRefresh = ko.computed( =>
        @items()
        @isSortingItems()
        if @pageCreated()  
          try
            console.log "refresing items listview"
            $('#items').listview('refresh')
          catch e
            #ignore error refreshing
        return ''
      ).extend(rateLimit: {timeout: 0, method: "notifyWhenChangesStop"})

      @rulesListViewRefresh = ko.computed( =>
        @rules()
        @isSortingRules()
        if @pageCreated()  
          try
            console.log "refresing rules listview"
            $('#rules').listview('refresh')
          catch e
            #ignore error refreshing
        return ''
      ).extend(rateLimit: {timeout: 0, method: "notifyWhenChangesStop"})

      if pimatic.storage.isSet('pimatic.indexPage')
        data = pimatic.storage.get('pimatic.indexPage')
        @updateFromJs(data)

      @autosave = ko.computed( =>
        data = ko.mapping.toJS(this)
        console.log "saving", data
        pimatic.storage.set('pimatic.indexPage', data)
      ).extend(rateLimit: {timeout: 500, method: "notifyWhenChangesStop"})

      sendToServer = yes
      @rememberme.subscribe( (shouldRememberMe) =>
        if sendToServer
          $.get("remember", rememberMe: shouldRememberMe)
            .done(ajaxShowToast)
            .fail( => 
              sendToServer = no
              @rememberme(not shouldRememberMe)
            ).fail(ajaxAlertFail)
        else 
          sendToServer = yes
        # swap storage
        allData = pimatic.storage.get('pimatic')
        pimatic.storage.removeAll()
        if shouldRememberMe
          pimatic.storage = $.localStorage
        else
          pimatic.storage = $.sessionStorage
        pimatic.storage.set('pimatic', allData)
      )

    setupStorage: ->
      allData = $.localStorage.get('pimatic')
      if $.localStorage.isSet('pimatic')
        # Select sessionStorage
        pimatic.storage = $.localStorage
        $.sessionStorage.removeAll()
        @rememberme(no)
      else if $.sessionStorage.isSet('pimatic')
        # Select localStorage
        pimatic.storage = $.sessionStorage
        $.localStorage.removeAll()
        @rememberme(yes)
      else
        # select localStorage as default
        pimatic.storage = $.localStorage
        @rememberme(no)
        pimatic.storage.set('pimatic', {})


    updateFromJs: (data) -> 
      console.log "updating:", data
      ko.mapping.fromJS(data, IndexViewModel.mapping, this)

    getItemTemplate: (item) ->
      console.log "getItemTemplate"
      template = (
        if item.type is 'device'
          if item.template? then "#{item.template}-template"
          else "devie-template"
        else "#{item.type}-template"
      )
      if $('#'+template).length > 0 then return template
      else return 'device-template'

    afterRenderItem: (elements, item) ->
      item.afterRender(elements)

    afterRenderRule: (elements, rule) ->
      rule.afterRender(elements)

    addItemFromJs: (data) ->
      item = IndexViewModel.mapping.items.create({data})
      @items.push(item)


    removeItem: (itemId) ->
      @items.remove( (item) => item.itemId is itemId )

    removeRule: (ruleId) ->
      @rules.remove( (rule) => rule.id is ruleId )

    updateRuleFromJs: (data) ->
      rule = ko.utils.arrayFirst(@rules(), (rule) => rule.id is data.id )
      unless rule?
        rule = IndexViewModel.mapping.rules.create({data})
        @rules.push(rule)
      else 
        rule.update(data)

    updateItemOrder: (order) ->
      # todo order items

    updateRuleOrder: (order) ->
      # todo order items

    updateDeviceAttribute: (deviceId, attrName, attrValue) ->
      for item in @items()
        if item.type is 'device' and item.deviceId is deviceId
          item.updateAttribute(attrName, attrValue)
          break

    toggleEditing: ->
      @enabledEditing(not @enabledEditing())
      $('#items').listview('refresh') if pimatic.pages.index.pageCreated
      pimatic.loading "enableediting", "show", text: __('Saving')
      $.ajax("/enabledEditing/#{@enabledEditing()}",
        global: false # don't show loading indicator
      ).always( ->
        pimatic.loading "enableediting", "hide"
      ).done(ajaxShowToast)

    onItemsSorted: ->
      order = (item.itemId for item in @items())
      pimatic.loading "itemorder", "show", text: __('Saving')
      $.ajax("update-item-order", 
        type: "POST"
        global: false
        data: {order: order}
      ).always( ->
        pimatic.loading "itemorder", "hide"
      ).done(ajaxShowToast)
      .fail(ajaxAlertFail)

    onRulesSorted: ->
      order = (rule.id for rule in @rules())
      pimatic.loading "ruleorder", "show", text: __('Saving')
      $.ajax("update-rule-order",
        type: "POST"
        global: false
        data: {order: order}
      ).always( ->
        pimatic.loading "ruleorder", "hide"
      ).done(ajaxShowToast).fail(ajaxAlertFail)

    onDropItemOnTrash: (ev, ui) ->
      # clear animation
      item = ko.dataFor(ui.draggable[0])
      pimatic.loading "deleteitem", "show", text: __('Saving')
      $.post('remove-item', itemId: item.itemId).done( (data) =>
        if data.success
          if ui.helper.length > 0
            ui.helper.hide(0, => @items.remove(item) )
          else
            @items.remove(item)
      ).always( => 
        pimatic.loading "deleteitem", "hide"
      ).done(ajaxShowToast).fail(ajaxAlertFail)

    onAddRuleClicked: ->
      editRulePage = pimatic.pages.editRule
      editRulePage.resetFields()
      editRulePage.action('add')
      editRulePage.ruleEnabled(yes)
      return true

    onEditRuleClicked: (rule)->
      editRulePage = pimatic.pages.editRule
      editRulePage.action('update')
      editRulePage.ruleId(rule.id)
      editRulePage.ruleCondition(rule.condition())
      editRulePage.ruleActions(rule.action())
      editRulePage.ruleEnabled(rule.active())
      return true

    toLoginPage: ->
      urlEncoded = encodeURIComponent(window.location.href)
      window.location.href = "/login?url=#{urlEncoded}"


  pimatic.pages.index = indexPage = new IndexViewModel()

  pimatic.socket.on("welcome", (data) ->
    indexPage.updateFromJs(data)
  )

  pimatic.socket.on("device-attribute", (attrEvent) -> 
    indexPage.updateDeviceAttribute(attrEvent.id, attrEvent.name, attrEvent.value)
  )

  pimatic.socket.on("item-add", (item) -> indexPage.addItemFromJs(item))
  pimatic.socket.on("item-remove", (itemId) -> indexPage.removeItem(itemId))
  pimatic.socket.on("item-order", (order) -> indexPage.updateItemOrder(order))

  pimatic.socket.on("rule-add", (rule) -> indexPage.updateRuleFromJs(rule))
  pimatic.socket.on("rule-update", (rule) -> indexPage.updateRuleFromJs(rule))
  pimatic.socket.on("rule-remove", (ruleId) -> indexPage.removeRule(ruleId))
  pimatic.socket.on("rule-order", (order) -> indexPage.updateRuleOrder(order))
  return
)

$(document).on("pagecreate", '#index', (event) ->
  indexPage = pimatic.pages.index
  ko.applyBindings(indexPage, $('#index')[0])

  $('#index #items').on("click", ".device-label", (event, ui) ->
    deviceId = $(this).parents(".item").data('item-id')
    device = pimatic.devices[deviceId]
    unless device? then return
    div = $ "#device-info-popup"
    div.find('.info-id .info-val').text device.id
    div.find('.info-name .info-val').text device.name
    div.find(".info-attr").remove()
    for attrName, attr of device.attributes
      attr = $('<li class="info-attr">').text(attr.label)
      div.find("ul").append attr
    div.find('ul').listview('refresh')
    div.popup "open"
    return
  )

  $("#items .handle, #rules .handle").disableSelection()
  indexPage.pageCreated(yes)

  fixScrollOverDraggableRule = ->

    _touchStart = $.ui.mouse.prototype._touchStart
    if _touchStart?
      $.ui.mouse.prototype._touchStart = (event) ->
        # Just alter behavior if the event is triggered on an draggable
        if this._isDragging?
          if this._isDragging is no
            # we are not dragging so allow scrolling
            return
        _touchStart.apply(this, [event]) 

      _touchMove = $.ui.mouse.prototype._touchMove
      $.ui.mouse.prototype._touchMove = (event) ->
        if this._isDragging?
          unless this._isDragging is yes
            # discard the event to not prevent defaults
            return
        _touchMove.apply(this, [event])
        # Sometimes the rule item seems to keep highlighted
        # so clear hover/down state manualy
        $('#rules li.ui-btn-down-c')
          .removeClass("ui-btn-down-c")
          .removeClass('ui-btn-hover-c')
          .addClass("ui-btn-up-c")

      _touchEnd = $.ui.mouse.prototype._touchEnd
      $.ui.mouse.prototype._touchEnd = (event) ->
        if this._isDragging?
          # stop dragging
          this._isDragging = no
        _touchEnd.apply(this, [event]) 
  fixScrollOverDraggableRule()
  return
)









