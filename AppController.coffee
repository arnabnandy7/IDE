class IDEAppController extends AppController

  {
    Stopped, Running, NotInitialized, Terminated, Unknown, Pending,
    Starting, Building, Stopping, Rebooting, Terminating, Updating
  } = Machine.State


  KD.registerAppClass this,
    name         : 'IDE'
    behavior     : 'application'
    multiple     : yes
    preCondition :
      condition  : (options, cb) -> cb KD.isLoggedIn()
      failure    : (options, cb) ->
        KD.getSingleton('appManager').open 'IDE', conditionPassed : yes
        KD.showEnforceLoginModal()
    commands:
      'find file by name'   : 'showFileFinder'
      'search all files'    : 'showContentSearch'
      'split vertically'    : 'splitVertically'
      'split horizontally'  : 'splitHorizontally'
      'merge splitview'     : 'mergeSplitView'
      'preview file'        : 'previewFile'
      'save all files'      : 'saveAllFiles'
      'create new file'     : 'createNewFile'
      'create new terminal' : 'createNewTerminal'
      'create new browser'  : 'createNewBrowser'
      'create new drawing'  : 'createNewDrawing'
      'collapse sidebar'    : 'collapseSidebar'
      'expand sidebar'      : 'expandSidebar'
      'toggle sidebar'      : 'toggleSidebar'
      'close tab'           : 'closeTab'
      'go to left tab'      : 'goToLeftTab'
      'go to right tab'     : 'goToRightTab'
      'go to tab number'    : 'goToTabNumber'
      'fullscren ideview'   : 'toggleFullscreenIDEView'
    keyBindings: [
      { command: 'find file by name',   binding: 'ctrl+alt+o', global: yes }
      { command: 'search all files',    binding: 'ctrl+alt+f', global: yes }
      { command: 'split vertically',    binding: 'ctrl+alt+v', global: yes }
      { command: 'split horizontally',  binding: 'ctrl+alt+h', global: yes }
      { command: 'merge splitview',     binding: 'ctrl+alt+m', global: yes }
      { command: 'preview file',        binding: 'ctrl+alt+p', global: yes }
      { command: 'save all files',      binding: 'ctrl+alt+s', global: yes }
      { command: 'create new file',     binding: 'ctrl+alt+n', global: yes }
      { command: 'create new terminal', binding: 'ctrl+alt+t', global: yes }
      { command: 'create new browser',  binding: 'ctrl+alt+b', global: yes }
      { command: 'create new drawing',  binding: 'ctrl+alt+d', global: yes }
      { command: 'toggle sidebar',      binding: 'ctrl+alt+k', global: yes }
      { command: 'close tab',           binding: 'ctrl+alt+w', global: yes }
      { command: 'go to left tab',      binding: 'ctrl+alt+[', global: yes }
      { command: 'go to right tab',     binding: 'ctrl+alt+]', global: yes }
      { command: 'go to tab number',    binding: 'mod+1',      global: yes }
      { command: 'go to tab number',    binding: 'mod+2',      global: yes }
      { command: 'go to tab number',    binding: 'mod+3',      global: yes }
      { command: 'go to tab number',    binding: 'mod+4',      global: yes }
      { command: 'go to tab number',    binding: 'mod+5',      global: yes }
      { command: 'go to tab number',    binding: 'mod+6',      global: yes }
      { command: 'go to tab number',    binding: 'mod+7',      global: yes }
      { command: 'go to tab number',    binding: 'mod+8',      global: yes }
      { command: 'go to tab number',    binding: 'mod+9',      global: yes }
      { command: 'fullscren ideview',   binding: 'mod+shift+enter', global: yes }
    ]

  constructor: (options = {}, data) ->

    options.appInfo =
      type          : 'application'
      name          : 'IDE'

    super options, data

    layoutOptions     =
      splitOptions    :
        direction     : 'vertical'
        name          : 'BaseSplit'
        sizes         : [ 250, null ]
        maximums      : [ 400, null ]
        views         : [
          {
            type      : 'custom'
            name      : 'filesPane'
            paneClass : IDE.IDEFilesTabView
          },
          {
            type      : 'custom'
            name      : 'editorPane'
            paneClass : IDE.IDEView
          }
        ]

    $('body').addClass 'dark' # for theming

    appView   = @getView()
    workspace = @workspace = new IDE.Workspace { layoutOptions }
    @ideViews = []

    {windowController} = KD.singletons
    windowController.addFocusListener @bound 'setActivePaneFocus'

    workspace.once 'ready', =>
      panel = workspace.getView()
      appView.addSubView panel

      panel.once 'viewAppended', =>
        ideView = panel.getPaneByName 'editorPane'
        @setActiveTabView ideView.tabView
        @registerIDEView  ideView

        splitViewPanel = ideView.parent.parent
        @createStatusBar splitViewPanel
        @createFindAndReplaceView splitViewPanel

        appView.emit 'KeyViewIsSet'

        @createInitialView()
        @bindCollapseEvents()

        {@finderPane} = @workspace.panel.getPaneByName 'filesPane'

        @bindRouteHandler()

    KD.singletons.appManager.on 'AppIsBeingShown', (app) =>

      return  unless app instanceof IDEAppController

      @setActivePaneFocus on

      # Temporary fix for IDE is not shown after
      # opening pages which uses old SplitView.
      # TODO: This needs to be fixed. ~Umut
      KD.singletons.windowController.notifyWindowResizeListeners()


  bindRouteHandler: ->
    {router, mainView} = KD.singletons

    router.on 'RouteInfoHandled', (routeInfo) =>
      if routeInfo.path.indexOf('/IDE') is -1
        if mainView.isSidebarCollapsed
          mainView.toggleSidebar()

  bindCollapseEvents: ->

    { panel } = @workspace

    filesPane = @workspace.panel.getPaneByName 'filesPane'

    # We want double click to work
    # if only the sidebar is collapsed. ~Umut
    expand = (event) =>
      KD.utils.stopDOMEvent event  if event?
      @toggleSidebar()  if @isSidebarCollapsed

    filesPane.on 'TabHandleMousedown', expand

    baseSplit = panel.layout.getSplitViewByName 'BaseSplit'
    baseSplit.resizer.on 'dblclick', @bound 'toggleSidebar'

  setActiveTabView: (tabView) ->
    return  if tabView is @activeTabView
    @setActivePaneFocus off
    @activeTabView = tabView
    @setActivePaneFocus on

  setActivePaneFocus: (state) ->
    return  unless pane = @getActivePaneView()
    KD.utils.defer -> pane.setFocus? state

  splitTabView: (type = 'vertical', ideViewOptions) ->
    ideView        = @activeTabView.parent
    ideParent      = ideView.parent
    newIDEView     = new IDE.IDEView ideViewOptions
    @activeTabView = null

    ideView.detach()

    splitView   = new KDSplitView
      type      : type
      views     : [ null, newIDEView ]

    @registerIDEView newIDEView

    splitView.once 'viewAppended', ->
      splitView.panels.first.attach ideView
      splitView.panels[0] = ideView.parent
      splitView.options.views[0] = ideView

    ideParent.addSubView splitView
    @setActiveTabView newIDEView.tabView

    splitView.on 'ResizeDidStop', KD.utils.throttle 500, @bound 'doResize'

  mergeSplitView: ->
    panel     = @activeTabView.parent.parent
    splitView = panel.parent
    {parent}  = splitView

    return  unless panel instanceof KDSplitViewPanel

    if parent instanceof KDSplitViewPanel
      parentSplitView    = parent.parent
      panelIndexInParent = parentSplitView.panels.indexOf parent

    splitView.once 'SplitIsBeingMerged', (views) =>
      for view in views
        index = @ideViews.indexOf view
        @ideViews.splice index, 1

      @handleSplitMerge views, parent, parentSplitView, panelIndexInParent
      @doResize()

    splitView.merge()

  handleSplitMerge: (views, container, parentSplitView, panelIndexInParent) ->
    ideView = new IDE.IDEView createNewEditor: no
    panes   = []

    for view in views
      {tabView} = view

      for p in tabView.panes by -1
        {pane} = tabView.removePane p, yes, (yes if tabView instanceof AceApplicationTabView)
        panes.push pane

      view.destroy()

    container.addSubView ideView

    for pane in panes
      ideView.tabView.addPane pane

    @setActiveTabView ideView.tabView
    @registerIDEView ideView

    if parentSplitView and panelIndexInParent
      parentSplitView.options.views[panelIndexInParent] = ideView
      parentSplitView.panels[panelIndexInParent]        = ideView.parent

  openFile: (file, contents, callback = noop) ->
    @activeTabView.emit 'FileNeedsToBeOpened', file, contents, callback

  openMachineTerminal: (machineData) ->
    @activeTabView.emit 'MachineTerminalRequested', machineData

  openMachineWebPage: (machineData) ->
    @activeTabView.emit 'MachineWebPageRequested', machineData

  mountMachine: (machineData) ->
    panel        = @workspace.getView()
    filesPane    = panel.getPaneByName 'filesPane'
    rootPath     = @workspaceData?.rootPath or null
    filesPane.emit 'MachineMountRequested', machineData, rootPath

  unmountMachine: (machineData) ->
    panel        = @workspace.getView()
    filesPane    = panel.getPaneByName 'filesPane'
    filesPane.emit 'MachineUnmountRequested', machineData

  createInitialView: ->
    KD.utils.defer =>
      @splitTabView 'horizontal', createNewEditor: no
      @getMountedMachine (err, machine) =>
        return unless machine
        {state} = machine.status

        if state in [ 'Stopped', 'NotInitialized', 'Terminated', 'Starting', 'Building' ]
          nickname     = KD.nick()
          machineLabel = machine.slug or machine.label
          splashs      = IDE.splashMarkups

          @fakeTabView      = @activeTabView
          @fakeTerminalView = new KDCustomHTMLView partial: splashs.getTerminal nickname
          @fakeTerminalPane = @fakeTabView.parent.createPane_ @fakeTerminalView, { name: 'Terminal' }

          @fakeFinderView   = new KDCustomHTMLView partial: splashs.getFileTree nickname, machineLabel
          @finderPane.addSubView @fakeFinderView, '.nfinder .jtreeview-wrapper'

        else
          @createNewTerminal machine
          @setActiveTabView @ideViews.first.tabView

  getMountedMachine: (callback = noop) ->
    KD.getSingleton('computeController').fetchMachines (err, machines) =>
      if err
        KD.showError "Couldn't fetch your VMs"
        return callback err, null

      KD.utils.defer =>
        @mountedMachine = m for m in machines when m.uid is @mountedMachineUId

        callback null, @mountedMachine

  mountMachineByMachineUId: (machineUId) ->
    computeController = KD.getSingleton 'computeController'
    container         = @getView()

    computeController.fetchMachines (err, machines) =>
      return KD.showError 'Something went wrong. Try again.'  if err

      callback = =>
        for machine in machines when machine.uid is machineUId
          machineItem = machine

        if machineItem
          {state} = machineItem.status
          machineId = machineItem._id

          if state is Running
            @mountMachine machineItem
          else

            unless @machineStateModal

              @createMachineStateModal {
                state, container, machineItem, initial: yes
              }

              if state is NotInitialized
                @machineStateModal.once 'MachineTurnOnStarted', =>
                  KD.getSingleton('mainView').activitySidebar.initiateFakeCounter()

          actionRequiredStates = [Pending, Stopping, Stopped, Terminating, Terminated]
          computeController.on "public-#{machineId}", (event) =>

            if event.status in actionRequiredStates

              KodingKontrol.dcNotification?.destroy()
              KodingKontrol.dcNotification = null

              machineItem.getBaseKite( no ).disconnect()

              unless @machineStateModal
                @createMachineStateModal { state, container, machineItem }

              else
                if event.status in actionRequiredStates
                  @machineStateModal.updateStatus event

        else
          @createMachineStateModal { state: 'NotFound', container }


      @appStorage = KD.getSingleton('appStorageController').storage 'IDE', '1.0.0'
      @appStorage.fetchStorage =>

        isOnboardingModalShown = @appStorage.getValue 'isOnboardingModalShown'

        callback()

  createMachineStateModal: (options = {}) ->
    { state, container, machineItem, initial } = options
    modalOptions = { state, container, initial }
    @machineStateModal = new EnvironmentsMachineStateModal modalOptions, machineItem

    @machineStateModal.once 'KDObjectWillBeDestroyed', => @machineStateModal = null
    @machineStateModal.once 'IDEBecameReady',          => @handleIDEBecameReady machineItem

  collapseSidebar: ->
    panel        = @workspace.getView()
    splitView    = panel.layout.getSplitViewByName 'BaseSplit'
    floatedPanel = splitView.panels.first
    filesPane    = panel.getPaneByName 'filesPane'
    {tabView}    = filesPane
    desiredSize  = 250

    splitView.resizePanel 39, 0
    @getView().setClass 'sidebar-collapsed'
    floatedPanel.setClass 'floating'
    tabView.showPaneByName 'Dummy'

    @isSidebarCollapsed = yes

    tabView.on 'PaneDidShow', (pane) ->
      return if pane.options.name is 'Dummy'
      @expandSidebar()  if @isSidebarCollapsed


    # TODO: This will reactivated after release.
    # temporary fix. ~Umut

    # splitView.once 'PanelSetToFloating', =>
    #   floatedPanel._lastSize = desiredSize
    #   @getView().setClass 'sidebar-collapsed'
    #   @isSidebarCollapsed = yes
    #   KD.getSingleton("windowController").notifyWindowResizeListeners()

    # # splitView.setFloatingPanel 0, 39
    # tabView.showPaneByName 'Dummy'

    # tabView.on 'PaneDidShow', (pane) ->
    #   return if pane.options.name is 'Dummy'
    #   splitView.showPanel 0
    #   floatedPanel._lastSize = desiredSize

    # floatedPanel.on 'ReceivedClickElsewhere', ->
    #   KD.utils.defer ->
    #     splitView.setFloatingPanel 0, 39
    #     tabView.showPaneByName 'Dummy'

  expandSidebar: ->
    panel        = @workspace.getView()
    splitView    = panel.layout.getSplitViewByName 'BaseSplit'
    floatedPanel = splitView.panels.first
    filesPane    = panel.getPaneByName 'filesPane'

    splitView.resizePanel 250, 0
    @getView().unsetClass 'sidebar-collapsed'
    floatedPanel.unsetClass 'floating'
    @isSidebarCollapsed = no
    # filesPane.tabView.showPaneByIndex 0

    # floatedPanel._lastSize = 250
    # splitView.unsetFloatingPanel 0
    # filesPane.tabView.showPaneByIndex 0
    # floatedPanel.off 'ReceivedClickElsewhere'
    # @getView().unsetClass 'sidebar-collapsed'
    # @isSidebarCollapsed = no

  toggleSidebar: ->
    if @isSidebarCollapsed then @expandSidebar() else @collapseSidebar()

  splitVertically: ->
    @splitTabView 'vertical'

  splitHorizontally: ->
    @splitTabView 'horizontal'

  createNewFile: do ->
    newFileSeed = 1

    return ->
      path     = "localfile:/Untitled-#{newFileSeed++}.txt"
      file     = FSHelper.createFileInstance { path }
      contents = ''

      @openFile file, contents

  createNewTerminal: (machine, path) ->
    machine = null  unless machine instanceof Machine

    if @workspaceData
      {rootPath} = @workspaceData
      path = rootPath  if rootPath

    @activeTabView.emit 'TerminalPaneRequested', machine, path

  createNewBrowser: (url) ->
    url = ''  unless typeof url is 'string'
    @activeTabView.emit 'PreviewPaneRequested', url

  createNewDrawing: -> @activeTabView.emit 'DrawingPaneRequested'

  goToLeftTab: ->
    index = @activeTabView.getActivePaneIndex()
    return if index is 0

    @activeTabView.showPaneByIndex index - 1

  goToRightTab: ->
    index = @activeTabView.getActivePaneIndex()
    return if index is @activeTabView.length - 1

    @activeTabView.showPaneByIndex index + 1

  goToTabNumber: (keyEvent) ->
    keyEvent.preventDefault()
    keyEvent.stopPropagation()

    keyCodeMap    = [ 49..57 ]
    requiredIndex = keyCodeMap.indexOf keyEvent.keyCode

    @activeTabView.showPaneByIndex requiredIndex

  goToLine: ->
    @activeTabView.emit 'GoToLineRequested'

  closeTab: ->
    @activeTabView.removePane @activeTabView.getActivePane()

  registerIDEView: (ideView) ->
    @ideViews.push ideView

    ideView.on 'PaneRemoved', =>
      ideViewLength  = 0
      ideViewLength += ideView.tabView.panes.length  for ideView in @ideViews

      @statusBar.showInformation()  if ideViewLength is 0

  forEachSubViewInIDEViews_: (callback = noop, paneType) ->
    if typeof callback is 'string'
      [paneType, callback] = [callback, paneType]

    for ideView in @ideViews
      for pane in ideView.tabView.panes
        view = pane.getSubViews().first
        if paneType
          if view.getOptions().paneType is paneType
            callback view
        else
          callback view

  updateSettings: (component, key, value) ->
    # TODO: Refactor this method by passing component type to helper method.
    Class  = if component is 'editor' then IDE.EditorPane else IDE.TerminalPane
    method = "set#{key.capitalize()}"

    @forEachSubViewInIDEViews_ (view) ->
      if view instanceof Class
        if component is 'editor'
          view.aceView.ace[method] value
        else
          view.webtermView.updateSettings()

  showShortcutsView: ->
    @activeTabView.emit 'ShortcutsViewRequested'

  getActivePaneView: ->
    return @activeTabView?.getActivePane()?.getSubViews().first

  saveFile: ->
    @getActivePaneView().emit 'SaveRequested'

  saveAs: ->
    @getActivePaneView().aceView.ace.requestSaveAs()

  saveAllFiles: ->
    @forEachSubViewInIDEViews_ 'editor', (editorPane) ->
      {ace} = editorPane.aceView
      ace.once 'FileContentSynced', ->
        ace.removeModifiedFromTab editorPane.aceView

      editorPane.emit 'SaveRequested'

  previewFile: ->
    view   = @getActivePaneView()
    {file} = view.getOptions()
    return unless file

    if FSHelper.isPublicPath file.path
      # FIXME: Take care of https.
      prefix      = "[#{@mountedMachineUId}]/home/#{KD.nick()}/Web/"
      [temp, src] = file.path.split prefix
      @createNewBrowser "#{@mountedMachine.domain}/#{src}"
    else
      @notify 'File needs to be under ~/Web folder to preview.', 'error'

  updateStatusBar: (component, data) ->
    {status} = @statusBar

    text = if component is 'editor'
      {cursor, file} = data
      """
        <p class="line">#{++cursor.row}:#{++cursor.column}</p>
        <p>#{file.name}</p>
      """

    else if component is 'terminal' then "Terminal on #{data.machineName}"

    else if component is 'searchResult'
    then """Search results for #{data.searchText}"""

    else if typeof data is 'string' then data

    else ''

    status.updatePartial text

  showStatusBarMenu: (ideView, button) ->
    paneView = @getActivePaneView()
    paneType = paneView?.getOptions().paneType or null
    delegate = button
    menu     = new IDE.StatusBarMenu { paneType, paneView, delegate }

    ideView.menu = menu

    menu.on 'viewAppended', ->
      if paneType is 'editor' and paneView
        {syntaxSelector} = menu
        {ace}            = paneView.aceView

        syntaxSelector.select.setValue ace.getSyntax()
        syntaxSelector.on 'SelectionMade', (value) =>
          ace.setSyntax value

  showFileFinder: ->
    return @fileFinder.input.setFocus()  if @fileFinder

    @fileFinder = new IDE.FileFinder
    @fileFinder.once 'KDObjectWillBeDestroyed', => @fileFinder = null

  showContentSearch: ->
    return @contentSearch.findInput.setFocus()  if @contentSearch

    @contentSearch = new IDE.ContentSearch
    @contentSearch.once 'KDObjectWillBeDestroyed', => @contentSearch = null
    @contentSearch.once 'ViewNeedsToBeShown', (view) =>
      @activeTabView.emit 'ViewNeedsToBeShown', view

  createStatusBar: (splitViewPanel) ->
    splitViewPanel.addSubView @statusBar = new IDE.StatusBar

  createFindAndReplaceView: (splitViewPanel) ->
    splitViewPanel.addSubView @findAndReplaceView = new AceFindAndReplaceView
    @findAndReplaceView.hide()
    @findAndReplaceView.on 'FindAndReplaceViewClosed', =>
      @getActivePaneView().aceView?.ace.focus()
      @isFindAndReplaceViewVisible = no

  showFindReplaceView: (withReplaceMode) ->
    view = @findAndReplaceView
    @setFindAndReplaceViewDelegate()
    @isFindAndReplaceViewVisible = yes
    view.setViewHeight withReplaceMode
    view.setTextIntoFindInput '' # FIXME: Set selected text if existss

  hideFindAndReplaceView: ->
    @findAndReplaceView.close no

  setFindAndReplaceViewDelegate: ->
    @findAndReplaceView.setDelegate @getActivePaneView()?.aceView or null

  showFindAndReplaceViewIfNecessary: ->
    if @isFindAndReplaceViewVisible
      @showFindReplaceView @findAndReplaceView.mode is 'replace'

  handleFileDeleted: (file) ->
    for ideView in @ideViews
      ideView.tabView.emit 'TabNeedsToBeClosed', file

  handleIDEBecameReady: (machine) ->
    {finderController} = @finderPane
    if @workspaceData
      finderController.updateMachineRoot @mountedMachine.uid, @workspaceData.rootPath
    else
      finderController.reset()

    @forEachSubViewInIDEViews_ 'terminal', (terminalPane) ->
      terminalPane.resurrect()

    unless @fakeViewsDestroyed
      @fakeFinderView?.destroy()
      @fakeTabView?.removePane_ @fakeTerminalPane
      @createNewTerminal machine
      @setActiveTabView @ideViews.first.tabView
      @fakeViewsDestroyed = yes

  toggleFullscreenIDEView: ->
    @activeTabView.parent.toggleFullscreen()

  doResize: ->
    @forEachSubViewInIDEViews_ (pane) ->
      {paneType} = pane.options
      switch paneType
        when 'terminal'
          {terminal} = pane.webtermView
          terminal.windowDidResize()  if terminal?
        when 'editor'
          height = pane.getHeight()
          {ace}  = pane.aceView

          if ace?.editor?
            ace.setHeight height
            ace.editor.resize()

  notify: (title, cssClass = 'success', type = 'mini', duration = 4000) ->
    return unless title
    new KDNotificationView { title, cssClass, type, duration }
