errors = require '../commons/errors'
wrap = require 'co-express'
database = require '../commons/database'
Clan = require '../models/Clan'
User = require '../models/User'
AnalyticsLogEvent = require '../models/AnalyticsLogEvent'
EarnedAchievement = require '../models/EarnedAchievement'
LevelSession = require '../models/LevelSession'

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
  
  
getMemberSessions = wrap (req, res) ->
  # TODO: restrict information returned based on clan type
  clan = yield database.getDocFromHandle(req, Clan)
  if not clan
    throw new errors.NotFound('Clan not found.')
  
  unless clan.get('dashboardType') is 'premium'
    throw new errors.Forbidden()
    
  memberIDs = _.map clan.get('members') ? [], (memberID) -> memberID.toHexString?() or memberID
  users = yield User.find {_id: {$in: memberIDs}}, 'name', {limit: memberLimit}
  memberIDs = []
  for user in users
    memberIDs.push user.id
    break unless memberIDs.length < memberLimit
  sessions = yield LevelSession.find {creator: {$in: memberIDs}}, 'changed codeLanguage creator creatorName levelID levelName playtime state submittedCodeLanguage'
  cleandocs = (doc.toObject({req}) for doc in sessions)
  res.send(cleandocs)
  
  
getPublicClans = wrap (req, res) ->
  query = [{ $match : {type : 'public'} }]
  query.push {$project : {_id: 1, name: 1, slug: 1, type: 1, description: 1, memberCount: {$size: "$members"}, ownerID: 1}}
  query.push {$sort: { memberCount: -1, _id: -1 }}
  query.push {$limit: 100}
  clans = yield Clan.aggregate(query)
  res.send(clans)


removeMember = wrap (req, res) ->
  clan = yield database.getDocFromHandle(req, Clan)
  if not clan
    throw new errors.NotFound('Clan not found.')

  member = yield database.getDocFromHandle(req, User, {handleName: 'memberHandle'})
  if not member
    throw new errors.NotFound('Member not found.')

  unless req.user?.isAdmin() or clan.get('ownerID')?.equals(req.user._id)
    throw new errors.Forbidden('You must be an admin or owner to remove a member.')

  if clan.get('ownerID').equals member._id
    throw new errors.Forbidden('The owner may not remove themself from their clan.')
  
  yield clan.update({$pull: {members: member._id}})
  yield member.update({$pull: {clans: clan._id}})
  res.send(clan.toObject({req}))
  
  AnalyticsLogEvent.logEvent req.user, 'Clan member removed', clanID: clan._id, type: clan.get('type'), memberID: member._id

  

module.exports = {
  getMemberAchievements
  getMembers
  getMemberSessions
  getPublicClans
  deleteClan
  joinClan
  leaveClan
  removeMember
}
