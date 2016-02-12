ModalView = require 'views/core/ModalView'
template = require 'templates/core/create-account-modal'
{loginUser, createUser, me} = require 'core/auth'
forms = require 'core/forms'
User = require 'models/User'
application  = require 'core/application'
Classroom = require 'models/Classroom'

module.exports = class AuthModal extends ModalView
  id: 'create-account-modal'
  template: template

  events:
    'click #switch-to-login-btn': 'onClickSwitchToLoginButton'
    'submit form': 'onSubmitForm'
    'keyup #name': 'onNameChange'
    'click #gplus-login-button': 'onClickGPlusLoginButton'
    'click #facebook-login-btn': 'onClickFacebookLoginButton'
    'click #close-modal': 'hide'
    
  subscriptions:
    'auth:facebook-api-loaded': 'onFacebookAPILoaded'
    
    
  # Initialization

  initialize: (options={}) ->
    @onNameChange = _.debounce(_.bind(@checkNameExists, @), 500)
    @previousFormInputs = options.initialValues or {}
    @listenTo application.gplusHandler, 'logged-into-google', @onGPlusHandlerLoggedIntoGoogle
    @listenTo application.gplusHandler, 'person-loaded', @onGPlusPersonLoaded
    @listenTo application.gplusHandler, 'render-login-buttons', @onGPlusRenderLoginButtons
    @listenTo application.facebookHandler, 'logged-into-facebook', @onFacebookHandlerLoggedIntoFacebook
    @listenTo application.facebookHandler, 'person-loaded', @onFacebookPersonLoaded

  afterRender: ->
    super()
    @playSound 'game-menu-open'
    @$('#facebook-login-btn').attr('disabled', true) if not window.FB?
    console.log 'window.FB?', window.FB

  afterInsert: ->
    super()
    _.delay (-> application.router.renderLoginButtons()), 500
    _.delay (=> $('input:visible:first', @$el).focus()), 500

  onGPlusRenderLoginButtons: ->
    @$('#gplus-login-btn').attr('disabled', false)

  onFacebookAPILoaded: ->
    console.log 'facebook api loaded?'
    @$('#facebook-login-btn').attr('disabled', false)

    
  # User creation

  onSubmitForm: (e) ->
    e.preventDefault()
    @playSound 'menu-button-click'

    forms.clearFormAlerts(@$el)
    attrs = forms.formToObject @$el
    attrs.name = @suggestedName if @suggestedName
    _.defaults attrs, me.pick([
      'preferredLanguage', 'testGroupNumber', 'dateCreated', 'wizardColor1',
      'name', 'music', 'volume', 'emails', 'schoolName'
    ])
    attrs.emails ?= {}
    attrs.emails.generalNews ?= {}
    attrs.emails.generalNews.enabled = @$el.find('#subscribe').prop('checked')
    @classCode = attrs.classCode
    delete attrs.classCode
    _.assign attrs, @gplusAttrs if @gplusAttrs
    res = tv4.validateMultiple attrs, User.schema
    if not res.valid
      return forms.applyErrorsToForm(@$el, res.errors)
    if not _.any([attrs.password, @gplusAttrs])
      return forms.setErrorToProperty @$el, 'password', 'Required', true
    if not forms.validateEmail(attrs.email)
      return forms.setErrorToProperty @$el, 'email', 'Please enter a valid email address', true
    
    @$('#signup-button').text($.i18n.t('signup.creating')).attr('disabled', true)
    @newUser = new User(attrs)
    if @classCode
      @signupClassroomPrecheck()
    else
      @createUser()

  signupClassroomPrecheck: ->
    classroom = new Classroom()
    classroom.fetch({ data: { code: @classCode } })
    classroom.once 'sync', @createUser, @
    classroom.once 'error', @onClassroomFetchError, @
    @enableModalInProgress(@$el)

  onClassroomFetchError: ->
    @$('#signup-button').text($.i18n.t('signup.sign_up')).attr('disabled', false)
    forms.setErrorToProperty(@$('form'), 'classCode', 'Classroom code could not be found')
      
  createUser: ->
    options = {}
    if @gplusAttrs
      @newUser.set('_id', me.id)
      options.url = "/db/user?gplusID=#{@gplusAttrs.gplusID}&gplusAccessToken=#{application.gplusHandler.accessToken.access_token}"
      options.type = 'PUT'
    @newUser.save(null, options)
    @newUser.once 'sync', @onUserCreated, @
    @newUser.once 'error', @onUserSaveError, @

  onUserSaveError: (user, jqxhr) ->
    @$('#signup-button').text($.i18n.t('signup.sign_up')).attr('disabled', false)
    if _.isObject(jqxhr.responseJSON) and jqxhr.responseJSON.property
      error = jqxhr.responseJSON
      if jqxhr.status is 409 and error.property is 'name'
        @newUser.unset 'name'
        return @createUser()
      return forms.applyErrorsToForm(@$el, [jqxhr.responseJSON])

    # TODO: Come up with a better way to handle generic errors like this
    noty({
      text: jqxhr.responseText or 'Unknown error'
      layout: 'topCenter'
      type: 'error'
      killer: false,
      dismissQueue: true
    })

  onUserCreated: ->
    Backbone.Mediator.publish "auth:signed-up", {}
    window.tracker?.trackEvent 'Finished Signup', label: 'CodeCombat'

    if @classCode
      url = "/courses?_cc="+@classCode
      application.router.navigate(url)
    window.location.reload()
    
  
  # Google Plus

  onClickGPlusLoginButton: ->
    @clickedGPlusLogin = true

  onGPlusHandlerLoggedIntoGoogle: ->
    return unless @clickedGPlusLogin
    application.gplusHandler.loginCodeCombat()
    @$('#gplus-login-btn .sign-in-blurb').text($.i18n.t('signup.creating')).attr('disabled', true)

  onGPlusPersonLoaded: (@gplusAttrs) ->
    @$('#email-password-row').remove()
    @$('#gplus-logged-in-row').toggleClass('hide')

    
  # Facebook
    
  onClickFacebookLoginButton: ->
    application.facebookHandler.loginThroughFacebook()

  onFacebookHandlerLoggedIntoFacebook: ->
    
    
  onFacebookPersonLoaded: (@facebookAttrs) ->
    @$('#email-password-row').remove()
    @$('#facebook-logged-in-row').toggleClass('hide')

  
  # Misc
  
  onHidden: ->
    super()
    @playSound 'game-menu-close'

  checkNameExists: ->
    name = $('#name', @$el).val()
    return forms.clearFormAlerts(@$el) if name is ''
    User.getUnconflictedName name, (newName) =>
      forms.clearFormAlerts(@$el)
      if name is newName
        @suggestedName = undefined
      else
        @suggestedName = newName
        forms.setErrorToProperty @$el, 'name', "That name is taken! How about #{newName}?", true

  onClickSwitchToLoginButton: (e) ->
    # TODO
    
