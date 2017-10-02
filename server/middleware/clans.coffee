errors = require '../commons/errors'
wrap = require 'co-express'
database = require '../commons/database'
Clan = require '../models/Clan'
User = require '../models/User'
AnalyticsLogEvent = require '../models/AnalyticsLogEvent'
EarnedAchievement = require '../models/EarnedAchievement'

memberLimit = 200

deleteClan = wrap (req, res) ->
  clan = yield database.getDocFromHandle(req, Clan)
  if not clan
    throw new errors.NotFound('Clan not found.')

  unless req.user?.isAdmin() or clan.get('ownerID')?.equals(req.user._id)
    throw new errors.Forbidden('You must be an admin or owner to delete a clan.')

  memberIDs = clan.get('members')
  yield Clan.remove {_id: clan.get('_id')}

  yield User.update {_id: {$in: memberIDs}}, {$pull: {clans: clan._id}}, {multi: true}

  yield clan.remove()
  res.status(204).end()
  AnalyticsLogEvent.logEvent req.user, 'Clan deleted', clanID: clan.id, type: clan.get('type')


joinClan = wrap (req, res) ->
  clan = yield database.getDocFromHandle(req, Clan)
  if not clan
    throw new errors.NotFound('Clan not found.')

  unless clan.get('type') is 'public' or req.user.isPremium()
    throw new errors.Forbidden('You may not join this clan')

  yield clan.update({$addToSet: {members: req.user._id}})
  yield req.user.update({$addToSet: {clans: clan._id}})
  res.send(clan.toObject({req}))
  AnalyticsLogEvent.logEvent req.user, 'Clan joined', clanID: clan._id, type: clan.get('type')

  
leaveClan = wrap (req, res) ->
  clan = yield database.getDocFromHandle(req, Clan)
  if not clan
    throw new errors.NotFound('Clan not found.')
    
  if clan.get('ownerID')?.equals(req.user._id)
    throw new errors.Forbidden('Owners may not leave their clans.')
  yield clan.update({$pull: {members: req.user._id}})
  yield req.user.update({$pull: {clans: clan._id}})
  res.send(clan.toObject({req}))
  AnalyticsLogEvent.logEvent req.user, 'Clan left', clanID: clan._id, type: clan.get('type')


getMemberAchievements = wrap (req, res) ->
  clan = yield database.getDocFromHandle(req, Clan)
  if not clan
    throw new errors.NotFound('Clan not found.')
    
  memberIDs = _.map clan.get('members') ? [], (memberID) -> memberID.toHexString?() or memberID
  memberIDs = memberIDs.slice(0, memberLimit)
  documents = yield EarnedAchievement.find {user: {$in: memberIDs}}, 'achievementName user'
  cleandocs = (doc.toObject({req}) for doc in documents)
  res.send(cleandocs)


getMembers = wrap (req, res) ->
  clan = yield database.getDocFromHandle(req, Clan)
  if not clan
    throw new errors.NotFound('Clan not found.')
  memberIDs = _.map clan.get('members') ? [], (memberID) -> memberID.toHexString?() or memberID
  users = yield User.find {_id: {$in: memberIDs}}, 'name nameLower points heroConfig.thangType', {limit: memberLimit}
  cleandocs = (user.toObject() for user in users)
  res.send(cleandocs)
  
module.exports = {
  getMemberAchievements
  getMembers
  deleteClan
  joinClan
  leaveClan
}
