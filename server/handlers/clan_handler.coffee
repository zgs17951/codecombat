async = require 'async'
mongoose = require 'mongoose'
Handler = require '../commons/Handler'
AnalyticsLogEvent = require '../models/AnalyticsLogEvent'
Clan = require './../models/Clan'
EarnedAchievement = require '../models/EarnedAchievement'
EarnedAchievementHandler = require './earned_achievement_handler'
LevelSession = require '../models/LevelSession'
LevelSessionHandler = require './level_session_handler'
User = require '../models/User'
UserHandler = require './user_handler'


ClanHandler = class ClanHandler extends Handler
  modelClass: Clan
  jsonSchema: require '../../app/schemas/models/clan.schema'
  allowedMethods: ['GET', 'POST', 'PUT', 'DELETE']

  hasAccess: (req) ->
    return true if req.method is 'GET'
    return false if req.method is 'POST' and req.body?.type is 'private' and not req.user?.isPremium()
    req.method in @allowedMethods or req.user?.isAdmin()

  hasAccessToDocument: (req, document, method=null) ->
    return false unless document?
    return true if req.user?.isAdmin()
    return true if (method or req.method).toLowerCase() is 'get'
    return true if document.get('ownerID')?.equals req.user?._id
    false

  makeNewInstance: (req) ->
    instance = super(req)
    instance.set 'ownerID', req.user._id
    instance.set 'members', [req.user._id]
    instance.set 'dashboardType', 'premium' if req.body?.type is 'private'
    instance

module.exports = new ClanHandler()
