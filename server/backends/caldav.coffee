"use strict"

Exc = require "jsDAV/lib/shared/exceptions"
SCCS = require "jsDAV/lib/CalDAV/properties/supportedCalendarComponentSet"
CalendarQueryParser = require('jsDAV/lib/CalDAV/calendarQueryParser')
VObject_Reader = require('jsDAV/lib/VObject/reader')
CalDAV_CQValidator = require('jsDAV/lib/CalDAV/calendarQueryValidator')
WebdavAccount = require '../models/webdavaccount'
async = require "async"
axon = require 'axon'
time  = require "time"
{ICalParser, VCalendar, VTimezone, VEvent, VTodo} = require "cozy-ical"

module.exports = class CozyCalDAVBackend

    constructor: (@Event, @Alarm, @User) ->

        @getLastCtag (err, ctag) =>
            # we suppose something happened while webdav was down
            @ctag = ctag + 1
            @saveLastCtag @ctag

            onChange = =>
                @ctag = @ctag + 1
                @saveLastCtag @ctag

            # keep ctag updated
            socket = axon.socket 'sub-emitter'
            socket.connect 9105
            socket.on 'alarm.*', onChange
            socket.on 'event.*', onChange

    getLastCtag: (callback) ->
        WebdavAccount.first (err, account) ->
            callback err, account?.ctag or 0

    saveLastCtag: (ctag, callback = ->) =>
        WebdavAccount.first (err, account) =>
            return callback err if err or not account
            account.updateAttributes ctag: ctag, ->

    getCalendarsForUser: (principalUri, callback) ->
        @getCalendarsName (err, calendars) =>
            icalCalendars = calendars.map (calendar) =>
                calendar =
                    id: calendar
                    uri: encodeURIComponent calendar
                    principaluri: principalUri
                    "{http://calendarserver.org/ns/}getctag": @ctag
                    "{urn:ietf:params:xml:ns:caldav}supported-calendar-component-set": SCCS.new [ 'VEVENT', 'VTODO' ]
                    "{DAV:}displayname": calendar
            callback null, icalCalendars

    createCalendar: (principalUri, url, properties, callback) ->
        callback null, null

    updateCalendar: (calendarId, mutations, callback) ->
        callback null, false

    deleteCalendar: (calendarId, callback) ->
        callback null, null

    _toICal: (obj, timezone) ->
        cal = new VCalendar organization: 'Cozy', title: 'Cozy Calendar'
        # cal.add new VTimezone new time.Date(obj.trigg or obj.start), timezone
        cal.add obj.toIcal(timezone)
        cal.toString()

    getCalendarObjects: (calendarId, callback) ->
        objects = []
        async.parallel [
            (cb) => @Alarm.byCalendar calendarId, cb
            (cb) => @Event.byCalendar calendarId, cb
            (cb) => @User.getTimezone cb
        ], (err, results) =>
            return callback err if err

            objects = results[0].concat(results[1]).map (obj) =>
                id:           obj.id
                uri:          obj.caldavuri or (obj.id + '.ics')
                calendardata: @_toICal(obj, results[2])
                lastmodified: new Date().getTime()

            callback null, objects

    _findCalendarObject: (calendarId, objectUri, callback) ->
        async.series [
            (cb) => @Alarm.byURI objectUri, cb
            (cb) => @Event.byURI objectUri, cb
        ], (err, results) =>
            object = (results[0]?[0] or results[1]?[0])
            callback err, object

    # take a calendar object from ICalParser, extract VEvent ot VTodo
    _extractCalObject: (calendarobj) =>
        if calendarobj instanceof VEvent or calendarobj instanceof VTodo
            return calendarobj
        else
            for obj in calendarobj.subComponents
                found = @_extractCalObject obj
                return found if found

            return false

    _parseSingleObjICal: (calendarData, callback) ->
        new ICalParser().parseString calendarData, (err, calendar) =>
            return callback err if err
            callback null, @_extractCalObject calendar

    getCalendarObject: (calendarId, objectUri, callback) ->

        @_findCalendarObject calendarId, objectUri, (err, obj) =>
            return callback err if err
            return callback null, null unless obj

            @User.getTimezone (err, timezone) =>
                return callback err if err

                callback null,
                    id:           obj.id
                    uri:          obj.caldavuri or (obj.id + '.ics')
                    calendardata: @_toICal(obj, timezone)
                    lastmodified: new Date().getTime()


    createCalendarObject: (calendarId, objectUri, calendarData, callback) =>
        @_parseSingleObjICal calendarData, (err, obj) =>
            return callback err if err

            if obj.name is 'VEVENT'
                event = @Event.fromIcal obj, calendarId
                event.caldavuri = objectUri
                @Event.create event, (err, event) ->
                    callback err, null

            else if obj.name is 'VTODO'
                alarm = @Alarm.fromIcal obj, calendarId
                alarm.caldavuri = objectUri
                @Alarm.create alarm, (err, alarm) ->
                    callback err, null

            else
                callback Exc.notImplementedYet()


    updateCalendarObject: (calendarId, objectUri, calendarData, callback) ->
        @_findCalendarObject calendarId, objectUri, (err, oldObj) =>
            return callback err if err

            @_parseSingleObjICal calendarData, (err, newObj) =>
                return callback err if err

                if newObj.name is 'VEVENT' and oldObj instanceof @Event
                    event = @Event.fromIcal(newObj, calendarId).toObject()
                    delete event.id

                    oldObj.updateAttributes event, (err, event) ->
                        callback err, null

                else if newObj.name is 'VTODO' and oldObj instanceof @Alarm
                    alarm = @Alarm.fromIcal newObj, calendarId
                    oldObj.updateAttributes alarm, (err, alarm) ->
                        callback err, null

                else
                    callback Exc.notImplementedYet()

    deleteCalendarObject: (calendarId, objectUri, callback) ->
        @_findCalendarObject calendarId, objectUri, (err, obj) ->
            return callback err if err
            obj.destroy callback

    calendarQuery: (calendarId, filters, callback) ->
        objects = []
        reader = VObject_Reader.new()
        validator = CalDAV_CQValidator.new()
        async.parallel [
            (cb) => @Alarm.byCalendar calendarId, cb
            (cb) => @Event.byCalendar calendarId, cb
            (cb) => @User.getTimezone cb
        ], (err, results) =>
            return callback err if err

            [alarms, events, timezone] = results

            try

                for jugglingObj in alarms.concat events
                    # @TODO convert directly from juggling to VObject
                    ical = @_toICal jugglingObj, timezone
                    vobj = reader.read ical

                    if validator.validate vobj, filters
                        uri = jugglingObj.caldavuri or (jugglingObj.id + '.ics')
                        objects.push
                            id:           jugglingObj.id
                            uri:          uri
                            calendardata: ical
                            lastmodified: new Date().getTime()

            catch ex
                console.log ex.stack
                return callback ex, []

            callback null, objects

    getCalendarsName: (callback) ->
        async.series [
            @Event.tags
            @Alarm.tags
        ], (err, results) ->

            if err?
                callback err
            else
                rawCalendars = results[0].calendar.concat results[1].calendar
                calendars = []
                # removes duplicates
                for rawCalendar in rawCalendars \
                when rawCalendar not in calendars
                    calendars.push rawCalendar

                callback null, calendars

