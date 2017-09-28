errors = require '../commons/errors'
wrap = require 'co-express'
database = require '../commons/database'
Clan = require '../models/Clan'
User = require '../models/User'
AnalyticsLogEvent = require '../models/AnalyticsLogEvent'

deleteClan = wrap (req, res) ->
  clan = yield database.getDocFromHandle(req, Clan)
  if not clan
    throw new errors.NotFound('Clan not found.')

  unless req.user?.isAdmin() or clan.get('ownerID')?.equals(req.user._id)
    throw new errors.Forbidden('You must be an admin or owner to delete a clan.')

  memberIDs = clan.get('members')
  yield Clan.remove {_id: clan.get('_id')}

  yield User.update {_id: {$in: memberIDs}}, {$pull: {clans: clan.get('_id')}}, {multi: true}

  yield clan.remove()
  res.status(204).end()
  AnalyticsLogEvent.logEvent req.user, 'Clan deleted', clanID: clan.id, type: clan.get('type')
  

module.exports = {
  deleteClan
}
